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

/// A `BufferState` where key input on both Normal and Insert modes are handled
/// by Nvim.
///
/// Nvim et UI buffers alternate being the source of truth cooperatively thanks
/// to a shared `EditionToken`.
struct NvimDrivenBufferState: BufferState {
    /// Indicates which buffer is the current source of truth for the content.
    private(set) var token: EditionToken

    /// State of the Nvim buffer.
    private(set) var nvim: NvimState

    /// State of the UI buffer.
    private(set) var ui: UIState

    /// Indicates whether the keys passthrough is switched on.
    private(set) var isKeysPassthroughEnabled: Bool

    /// Indicates whether the left mouse button is pressed.
    private(set) var isLeftMouseButtonDown: Bool

    /// Indicates whether the user is currently selecting text with the mouse.
    private(set) var isSelecting: Bool

    init(
        token: EditionToken = .free,
        nvim: NvimState = NvimState(),
        ui: UIState = UIState(),
        isKeysPassthroughEnabled: Bool = false,
        isLeftMouseButtonDown: Bool = false,
        isSelecting: Bool = false
    ) {
        self.token = token
        self.nvim = nvim
        self.ui = ui
        self.isKeysPassthroughEnabled = isKeysPassthroughEnabled
        self.isLeftMouseButtonDown = isLeftMouseButtonDown
        self.isSelecting = isSelecting
    }

    /// Represents the current state of the Nvim buffer.
    struct NvimState: Equatable {
        var mode: Mode = .normal
        var cursorPosition: BufferPosition = .init()
        var visualPosition: BufferPosition = .init()

        /// Buffer content lines.
        var lines: [String] = []

        var pendingMode: Mode? = nil
        var pendingCursorPosition: BufferPosition? = nil
        var pendingVisualPosition: BufferPosition? = nil
        var pendingLines: [String]? = nil

        mutating func flush() {
            mode = pendingMode ?? mode
            cursorPosition = pendingCursorPosition ?? cursorPosition
            visualPosition = pendingVisualPosition ?? visualPosition
            lines = pendingLines ?? lines

            pendingMode = nil
            pendingCursorPosition = nil
            pendingVisualPosition = nil
            pendingLines = nil
        }

        /// Converts the current cursor position and visual selection as a
        /// list of selection ranges in the UI buffer.
        func uiSelections() -> [UISelection] {
            .init(mode: mode, cursor: cursorPosition, visual: visualPosition)
        }
    }

    /// Represents the current state of the UI buffer, accessed through the
    /// accessibility APIs (AX).
    struct UIState: Equatable {
        /// Current text selection in the buffer view.
        var selection: UISelection = .init()

        /// Buffer content lines.
        var lines: [String] = []
    }

    mutating func on(_ event: BufferEvent, logger: Logger?) -> [BufferAction] {
        var actions: [BufferAction] = []

        switch event {
        case .didTimeout:
            switch token {
            case .free:
                break
            case .synchronizing:
                token = .free
            case let .acquired(owner: owner):
                synchronize(source: owner)
            }

        case let .didRequestRefresh(source: source):
            switch token {
            case .synchronizing, .acquired:
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
            let hadPendingLines = nvim.pendingLines != nil
            let hadPendingCursor =
                nvim.pendingCursorPosition != nil ||
                nvim.pendingVisualPosition != nil

            nvim.flush()

            if tryEdition(from: .nvim) {
                if hadPendingLines {
                    perform(.uiUpdateLines(nvim.lines))
                }

                if hadPendingCursor {
                    perform(.uiUpdateSelections(nvim.uiSelections()))

                    // Ensures the cursor is always visible by scrolling the UI.
                    if nvim.cursorPosition.line != nvim.visualPosition.line {
                        let cursorPosition = UIPosition(nvim.cursorPosition)
                        let visibleSelection = UISelection(start: cursorPosition, end: cursorPosition)
                        perform(.uiScroll(visibleSelection))
                    }
                }
            }

        case let .uiDidFocus(lines: lines, selection: selection):
            ui.lines = lines
            ui.selection = selection

            if tryEdition(from: .ui) {
                adjustUISelection(to: nvim.mode)
                synchronizeNvim()
            }

        case let .uiBufferDidChange(lines: lines):
            guard ui.lines != lines else {
                break
            }

            ui.lines = lines

            if tryEdition(from: .ui) {
                synchronizeNvim()
            }

        case let .uiSelectionDidChange(selection):
            // Ignore the selection change if it's identical, to avoid adjusting
            // the selection several times in a row.
            guard ui.selection != selection else {
                break
            }
            ui.selection = selection
            if isLeftMouseButtonDown {
                isSelecting = true
            } else {
                guard tryEdition(from: .ui) else {
                    break
                }
                adjustUISelection(to: nvim.mode)
                synchronizeNvimCursor()
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
                perform(.nvimPaste)

            default:
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
            if tryEdition(from: .ui) {
                perform(.nvimStopVisual)
            }

        case .uiDidReceiveMouseEvent(.up(.left), bufferPoint: _):
            isLeftMouseButtonDown = false

            if isSelecting {
                isSelecting = false

                guard tryEdition(from: .ui) else {
                    break
                }

                if ui.selection.isCollapsed {
                    adjustUISelection(to: nvim.mode)
                    synchronizeNvimCursor()
                } else {
                    startNvimVisual(using: ui.selection)
                }
            }

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
            perform(.uiUpdateSelections([selection]))

        case let .didFail(error):
            perform(.alert(error))
        }

        // Syntactic sugar.
        func perform(_ action: BufferAction) {
            actions.append(action)
        }

        /// Try to acquire the edition token for the given `host` to modify the
        /// shared virtual buffer.
        func tryEdition(from host: BufferHost) -> Bool {
            switch token {
            case .free, .acquired(owner: host):
                setToken(.acquired(owner: host))
                return true
            default:
                return false
            }
        }

        /// Synchronizes the whole buffer using the given `source` of truth.
        func synchronize(source: BufferHost) {
            // Some apps (like Xcode) systematically add an empty line at
            // the end of a document. To make sure the comparison won't
            // fail in this case, we add an empty line in the Nvim buffer
            // as well.
            var nvimLines = nvim.lines
            if ui.lines.last == "", nvimLines.last != "" {
                nvimLines.append("")
            }
            guard ui.lines != nvimLines else {
                setToken(.free)
                return
            }

            switch source {
            case .nvim:
                synchronizeUI()
            case .ui:
                synchronizeNvim()
            }

            setToken(.synchronizing)
        }

        func synchronizeUI() {
            perform(.uiUpdateLines(nvim.lines))
            perform(.uiUpdateSelections(nvim.uiSelections()))
        }

        func synchronizeNvim() {
            perform(.nvimUpdateLines(ui.lines))
            perform(.nvimMoveCursor(BufferPosition(ui.selection.start)))
        }

        /// Moves the Nvim cursor to match the current UI selection.
        func synchronizeNvimCursor() {
            precondition(token == .acquired(owner: .ui))

            let start = BufferPosition(ui.selection.start)
            if nvim.cursorPosition != start {
                perform(.nvimMoveCursor(start))
            }
        }

        /// Adjusts the current UI selection to match the given Nvim `mode`.
        func adjustUISelection(to mode: Mode) {
            precondition(token == .acquired(owner: .ui))

            let adjustedSelection = {
                guard !isKeysPassthroughEnabled else {
                    return ui.selection
                }
                return ui.selection.adjusted(to: mode, lines: ui.lines)
            }()

            if ui.selection != adjustedSelection {
                ui.selection = adjustedSelection
                perform(.uiUpdateSelections([ui.selection]))
            }
        }

        /// Requests Nvim to start the Visual mode using the given `selection`.
        func startNvimVisual(using selection: UISelection) {
            precondition(token == .acquired(owner: .ui))

            perform(.nvimStartVisual(
                start: BufferPosition(selection.start),
                // In Visual mode the end character is included in
                // the selection, so we need to shift it.
                end: BufferPosition(selection.end.moving(column: -1))
            ))
        }

        func setToken(_ token: EditionToken) {
            self.token = token

            if token != .free, !actions.contains(.startTimeout(id: 0, durationInSeconds: 0.2)) {
                perform(.startTimeout(id: 0, durationInSeconds: 0.2))
            }
        }

        return actions
    }
}

// MARK: Logging

extension NvimDrivenBufferState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["token": token, "nvim": nvim, "ui": ui]
    }
}

extension NvimDrivenBufferState.NvimState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["lines": lines, "mode": mode, "cursor": cursorPosition, "visual": visualPosition]
    }
}

extension NvimDrivenBufferState.UIState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["lines": lines, "selection": selection]
    }
}
