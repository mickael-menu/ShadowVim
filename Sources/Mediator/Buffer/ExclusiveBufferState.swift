//
//  Copyright © 2023 Mickaël Menu
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import Nvim
import Toolkit

/// A `BufferState` where key input is handled:
/// - by Nvim on Normal mode
/// - by the UI on Insert mode, for better performance
struct ExclusiveBufferState: BufferState {
    private(set) var nvim: NvimState
    private(set) var ui: UIState

    /// Indicates which buffer host receives input events.
    private(set) var input: BufferHost

    /// Indicates which buffer is the current source of truth for the content.
    private(set) var token: EditionToken
    private let tokenTimeoutId: Int = 0
    private let tokenTimeoutDuration: Double = 0.2 // seconds

    /// Indicates whether the keys passthrough is switched on.
    private(set) var isKeysPassthroughEnabled: Bool

    /// Indicates whether the left mouse button is pressed.
    private(set) var isLeftMouseButtonDown: Bool

    /// Indicates whether the user is currently selecting text with the mouse.
    private(set) var isSelecting: Bool

    init(
        nvim: NvimState = NvimState(),
        ui: UIState = UIState(),
        input: BufferHost = .nvim,
        token: EditionToken = .free,
        isKeysPassthroughEnabled: Bool = false,
        isLeftMouseButtonDown: Bool = false,
        isSelecting: Bool = false
    ) {
        self.nvim = nvim
        self.ui = ui
        self.input = input
        self.token = token
        self.isKeysPassthroughEnabled = isKeysPassthroughEnabled
        self.isLeftMouseButtonDown = isLeftMouseButtonDown
        self.isSelecting = isSelecting
    }

    /// Represents the current state of the Nvim buffer.
    struct NvimState: Equatable {
        var mode: Mode = .normal
        var lines: [String] = []
        var cursorPosition: BufferPosition = .init()
        var visualPosition: BufferPosition = .init()

        var pendingMode: Mode? = nil
        var pendingLines: [String]? = nil
        var pendingCursorPosition: BufferPosition? = nil
        var pendingVisualPosition: BufferPosition? = nil

        mutating func flush() {
            mode = pendingMode ?? mode
            lines = pendingLines ?? lines
            cursorPosition = pendingCursorPosition ?? cursorPosition
            visualPosition = pendingVisualPosition ?? visualPosition

            pendingMode = nil
            pendingLines = nil
            pendingCursorPosition = nil
            pendingVisualPosition = nil
        }

        func uiSelections() -> [UISelection] {
            .init(mode: mode, cursor: cursorPosition, visual: visualPosition)
        }
    }

    /// Represents the current state of the UI buffer, accessed through the
    /// accessibility APIs (AX).
    struct UIState: Equatable {
        var lines: [String] = []
        var selection: UISelection = .init()

        /// A new UI selection change was requested.
        /// When true, the next `uiSelectionDidChange` will be ignored.
        var hasPendingSelection: Bool = false
    }

    /// Some apps (like Xcode) systematically add an empty line at the end of a
    /// document. To make sure the comparison won't fail in this case, we add an
    /// empty line in the Nvim buffer as well.
    private var areLinesSynchronized: Bool {
        var nvimLines = nvim.lines
        if ui.lines.last == "", nvimLines.last != "" {
            nvimLines.append("")
        }
        return ui.lines == nvimLines
    }

    mutating func on(_ event: BufferEvent, logger: Logger?) -> [BufferAction] {
        var actions: [BufferAction] = []

        switch event {
        case .didTokenTimeout:
            switch token {
            case .free:
                break
            case .synchronizing:
                setToken(.free)
            case let .acquired(owner: owner):
                synchronize(source: owner)
            }

        case let .didRequestRefresh(source: source):
            switch token {
            case .acquired, .synchronizing:
                logger?.w("Token busy, cannot refresh")
                perform(.bell)
            case .free:
                synchronize(source: source)
            }

        case let .nvimLinesDidChange(event):
            nvim.pendingLines = event.applyChanges(in: nvim.pendingLines ?? nvim.lines)

        case let .nvimModeDidChange(mode):
            guard nvim.mode != mode else {
                break
            }
            nvim.pendingMode = mode

        case let .nvimCursorDidChange(cursor):
            nvim.pendingCursorPosition = cursor.cursor
            nvim.pendingVisualPosition = cursor.visual

        case .nvimDidFlush:
            let hadPendingMode = nvim.pendingMode != nil
            let hadPendingLines = nvim.pendingLines != nil
            let hadPendingPositions =
                nvim.pendingCursorPosition != nil ||
                nvim.pendingVisualPosition != nil

            let oldMode = nvim.mode
            nvim.flush()

            var needsUpdateUISelections = false

            if requestEdition(from: .nvim) {
                needsUpdateUISelections = hadPendingPositions

                if hadPendingLines {
                    perform(.uiUpdateLines(nvim.lines))
                }
            }

            if hadPendingMode {
                needsUpdateUISelections = true

                switch nvim.mode {
                case .insert, .replace:
                    // When the Insert mode started from an Operator-pending
                    // mode, then we let Nvim handle the Insert commands.
                    // This is a workaround for an issue with Dot-repeat, see
                    // https://github.com/vscode-neovim/vscode-neovim/issues/76#issuecomment-562902179
                    input = (oldMode == .operatorPending) ? .nvim : .ui

                default:
                    input = .nvim
                }
            }

            if needsUpdateUISelections {
                uiUpdateSelections(nvim.uiSelections())

                // Ensures the cursor is always visible by scrolling the UI.
                let cursorPosition = UIPosition(nvim.cursorPosition)
                let visibleSelection = UISelection(start: cursorPosition, end: cursorPosition)
                perform(.uiScroll(visibleSelection))
            }

        case let .uiDidFocus(lines: lines, selection: selection):
            ui.lines = lines
            ui.selection = selection.adjusted(to: nvim.mode, lines: lines)

            if requestEdition(from: .ui) {
                nvimSynchronize()
            }

        case let .uiBufferDidChange(lines: lines):
            guard ui.lines != lines else {
                break
            }

            ui.lines = lines

            if requestEdition(from: .ui) {
                nvimSynchronize()
            }

        case let .uiSelectionDidChange(selection):
            guard !ui.hasPendingSelection else {
                ui.hasPendingSelection = false
                ui.selection = selection
                break
            }
            guard ui.selection != selection else {
                break
            }

            ui.selection = selection

            if isLeftMouseButtonDown {
                isSelecting = true

            } else {
                let adjustedSelection = selection.adjusted(to: nvim.mode, lines: ui.lines)
                uiUpdateSelections([adjustedSelection])

                let start = BufferPosition(adjustedSelection.start)
                if requestEdition(from: .ui), nvim.cursorPosition != start {
                    perform(.nvimMoveCursor(start))
                }
            }

        case let .uiDidReceiveKeyEvent(kc, character: character):
            switch kc {
            case .escape:
                perform(.nvimInput("<Esc>"))

            case .cmdZ:
                perform(.nvimUndo)
            case .cmdShiftZ:
                perform(.nvimRedo)

            case .cmdV:
                // We override the system paste behavior to improve performance
                // and nvim's undo history.
                if input == .nvim {
                    perform(.nvimPaste)
                }

            default:
                guard input == .nvim || kc.modifiers == .control else {
                    break
                }

                let mods = kc.modifiers
                // Passthrough for ⌘-based keyboard shortcuts.
                guard !mods.contains(.command) else {
                    break
                }

                // If the user pressed control, we send the key combo as is to
                // be able to remap this keyboard shortcut in Nvim.
                // Otherwise, we send the unicode character for this event.
                // See Documentation/Research/Keyboard.md.
                if
                    !mods.contains(.control),
                    !kc.key.isNonPrintableCharacter,
                    let character = character
                {
                    perform(.nvimInput(character))
                } else if let notation = kc.nvimNotation {
                    perform(.nvimInput(notation))
                }
            }

        case let .uiDidReceiveMouseEvent(.down(.left), bufferPoint: bufferPoint):
            guard bufferPoint != nil else { break }

            isLeftMouseButtonDown = true

            // Simulate the default behavior of `LeftMouse` in Nvim, which is:
            // > If Visual mode is active it is stopped.
            // > :help LeftMouse
            if requestEdition(from: .ui) {
                perform(.nvimStopVisual)
            }

        case .uiDidReceiveMouseEvent(.up(.left), bufferPoint: _):
            isLeftMouseButtonDown = false
            uiEndSelection()

        case .uiDidReceiveMouseEvent:
            // Other mouse events are ignored.
            break

        case let .didToggleKeysPassthrough(enabled: enabled):
            isKeysPassthroughEnabled = enabled

            if enabled {
                perform(.nvimStopVisual)
            }

            let selection = ui.selection.adjusted(
                to: enabled ? .insert : nvim.mode,
                lines: ui.lines
            )
            uiUpdateSelections([selection])

        case let .didFail(error):
            perform(.alert(error))

        default:
            break
        }

        // Syntactic sugar.
        func perform(_ action: BufferAction) {
            actions.append(action)
        }

        /// Try to acquire the edition token for the given `host` to modify the
        /// shared virtual buffer.
        func requestEdition(from host: BufferHost) -> Bool {
            switch token {
            case .free, .acquired(owner: host):
                setToken(.acquired(owner: host))
                return true
            default:
                return false
            }
        }

        /// Force-synchronizes the whole buffer using the given `source` of truth.
        func synchronize(source: BufferHost) {
            setToken(.free)

            guard areLinesSynchronized else {
                return
            }

            switch source {
            case .nvim:
                uiSynchronize()
            case .ui:
                nvimSynchronize()
            }
        }

        func nvimSynchronize() {
            perform(.nvimUpdateLines(ui.lines))
            perform(.nvimMoveCursor(BufferPosition(ui.selection.start)))
        }

        /// Moves the Nvim cursor to match the current UI selection.
        func nvimSynchronizeCursor() {
            precondition(token == .acquired(owner: .ui))

            let start = BufferPosition(ui.selection.start)
            if nvim.cursorPosition != start {
                perform(.nvimMoveCursor(start))
            }
        }

        /// Synchronizes the whole buffer using the given `source` of truth.
        /// Requests Nvim to start the Visual mode using the given `selection`.
        func nvimStartVisual(using selection: UISelection) {
            perform(.nvimStartVisual(
                start: BufferPosition(selection.start),
                // In Visual mode the end character is included in
                // the selection, so we need to shift it.
                end: BufferPosition(selection.end.moving(column: -1))
            ))
        }

        func uiSynchronize() {
            perform(.uiUpdateLines(nvim.lines))
            uiUpdateSelections(nvim.uiSelections())
        }

        /// Called when the user releases the left mouse button. The UI
        /// selection will be sent to Nvim.
        func uiEndSelection() {
            guard isSelecting else {
                return
            }
            isSelecting = false

            guard requestEdition(from: .ui) else {
                return
            }

            if ui.selection.isCollapsed {
                uiAdjustSelection(to: nvim.mode)
                nvimSynchronizeCursor()
            } else {
                nvimStartVisual(using: ui.selection)
            }
        }

        /// Adjusts the current UI selection to match the given Nvim `mode`.
        func uiAdjustSelection(to mode: Mode) {
            precondition(token == .acquired(owner: .ui))
            guard !isKeysPassthroughEnabled else {
                return
            }

            let adjustedSelection = ui.selection.adjusted(to: mode, lines: ui.lines)
            uiUpdateSelections([adjustedSelection])
        }

        func uiUpdateSelections(_ selections: [UISelection]) {
            guard ui.selection != selections.first else {
                return
            }

            ui.hasPendingSelection = true
            perform(.uiUpdateSelections(selections))
        }

        func setToken(_ token: EditionToken) {
            self.token = token

            // Request a token timeout if the token is acquired.
            if
                token != .free,
                !actions.contains(.startTokenTimeout)
            {
                perform(.startTokenTimeout)
            }
        }

        return actions
    }
}

extension BufferEvent {
    static let didTokenTimeout: BufferEvent = .didTimeout(id: 0)
}

extension BufferAction {
    static let startTokenTimeout: BufferAction = .startTimeout(id: 0, durationInSeconds: 0.2)
}

// MARK: Logging

extension ExclusiveBufferState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["@source": input, "nvim": nvim, "ui": ui]
    }
}

extension ExclusiveBufferState.NvimState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        [
            "lines": lines,
            "linesPending": pendingLines,
            "mode": mode,
            "modePending": pendingMode,
            "cursor": cursorPosition,
            "cursorPending": pendingCursorPosition,
            "visual": visualPosition,
            "visualPending": pendingVisualPosition,
        ]
    }
}

extension ExclusiveBufferState.UIState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        [
            "lines": lines,
            "selection": selection,
            "hasPendingSelection": hasPendingSelection,
        ]
    }
}
