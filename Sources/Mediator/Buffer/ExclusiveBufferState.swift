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
    private(set) var source: BufferHost
    private(set) var nvim: NvimState
    private(set) var ui: UIState

    /// Indicates whether the keys passthrough is switched on.
    private(set) var isKeysPassthroughEnabled: Bool

    /// Indicates whether the left mouse button is pressed.
    private(set) var isLeftMouseButtonDown: Bool

    /// Indicates whether the user is currently selecting text with the mouse.
    private(set) var isSelecting: Bool

    init(
        source: BufferHost = .nvim,
        nvim: NvimState = NvimState(),
        ui: UIState = UIState(),
        isKeysPassthroughEnabled: Bool = false,
        isLeftMouseButtonDown: Bool = false,
        isSelecting: Bool = false
    ) {
        self.source = source
        self.nvim = nvim
        self.ui = ui
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
        var pendingSelection: UISelection? = nil
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
        case let .nvimLinesDidChange(event):
            nvim.pendingLines = event.applyChanges(in: nvim.pendingLines ?? nvim.lines)

        case let .nvimCursorDidChange(cursor):
            nvim.pendingMode = cursor.mode
            nvim.pendingCursorPosition = cursor.position
            nvim.pendingVisualPosition = cursor.visual

        case .nvimDidFlush:
            let hadPendingLines = nvim.pendingLines != nil
            let hadPendingPositions =
                nvim.pendingCursorPosition != nil ||
                nvim.pendingVisualPosition != nil

            nvim.flush()

            if source == .nvim {
                if hadPendingLines {
                    perform(.uiUpdateLines(nvim.lines))
                }

                if hadPendingPositions {
                    let selections = nvim.uiSelections()
                    ui.pendingSelection = selections.first
                    perform(.uiUpdateSelections(selections))
                }
            }

            switch nvim.mode {
            case .insert, .replace:
                source = .ui
            default:
                source = .nvim
            }

        case let .uiDidFocus(lines: lines, selection: selection):
            let selection = selection.adjusted(to: nvim.mode, lines: lines)

            if ui.lines != lines {
                perform(.nvimUpdateLines(lines))
            }
            if ui.selection != selection {
                perform(.nvimMoveCursor(BufferPosition(selection.start)))
            }

            ui.lines = lines
            ui.selection = selection

        case let .uiBufferDidChange(lines: lines):
            if source == .ui || areLinesSynchronized {
                perform(.nvimUpdateLines(lines))
            }

            ui.lines = lines

        case let .uiSelectionDidChange(selection):
            guard ui.pendingSelection != selection else {
                ui.pendingSelection = nil
                ui.selection = selection
                break
            }
            guard ui.selection != selection else {
                break
            }

            if isLeftMouseButtonDown {
                isSelecting = true
            } else {
                let adjustedSelection = selection.adjusted(to: nvim.mode, lines: ui.lines)
                if ui.selection != adjustedSelection {
                    ui.pendingSelection = adjustedSelection
                    perform(.uiUpdateSelections([adjustedSelection]))
                }

                let start = BufferPosition(adjustedSelection.start)
                if nvim.cursorPosition != start {
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
                perform(.nvimPaste)

            default:
                guard source == .nvim else {
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
            perform(.nvimStopVisual)

        case .uiDidReceiveMouseEvent(.up(.left), bufferPoint: _):
            isLeftMouseButtonDown = false

            if isSelecting {
                isSelecting = false

                if ui.selection.isCollapsed {
                    ui.selection.adjust(to: nvim.mode, lines: ui.lines)

                    let start = BufferPosition(ui.selection.start)
                    if nvim.cursorPosition != start {
                        perform(.nvimMoveCursor(start))
                    }

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
            if ui.selection != selection {
                ui.pendingSelection = selection
                perform(.uiUpdateSelections([selection]))
            }

        case let .didFail(error):
            perform(.alert(error))

        default:
            break
        }

        // Syntactic sugar.
        func perform(_ action: BufferAction) {
            actions.append(action)
        }

        /// Synchronizes the whole buffer using the given `source` of truth.
        /// Requests Nvim to start the Visual mode using the given `selection`.
        func startNvimVisual(using selection: UISelection) {
            perform(.nvimStartVisual(
                start: BufferPosition(selection.start),
                // In Visual mode the end character is included in
                // the selection, so we need to shift it.
                end: BufferPosition(selection.end.moving(column: -1))
            ))
        }

        return actions
    }
}

// MARK: Logging

extension ExclusiveBufferState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["@source": source, "nvim": nvim, "ui": ui]
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
            "pendingSelection": pendingSelection,
        ]
    }
}
