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

/// State machine handling the state of a single buffer synchronized between the
/// UI and Nvim.
///
/// It is owned and executed by a `BufferMediator` which binds to the events of
/// the actual Nvim and UI buffers.
struct LegacyBufferState: BufferState {
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

    /// Indicates whether an automatic keys passthrough is enabled in insert
    /// mode. This helps improve performance.
    private let keysPassthroughOnInsert: Bool

    init(
        token: EditionToken = .free,
        nvim: NvimState = NvimState(),
        ui: UIState = UIState(),
        isKeysPassthroughEnabled: Bool = false,
        isLeftMouseButtonDown: Bool = false,
        isSelecting: Bool = false,
        keysPassthroughOnInsert: Bool = true
    ) {
        self.token = token
        self.nvim = nvim
        self.ui = ui
        self.isKeysPassthroughEnabled = isKeysPassthroughEnabled
        self.isLeftMouseButtonDown = isLeftMouseButtonDown
        self.isSelecting = isSelecting
        self.keysPassthroughOnInsert = keysPassthroughOnInsert
    }

    /// The edition token indicates which buffer is the current source of truth
    /// for the content.
    ///
    /// While there are two actual live buffers for any buffer (Nvim and UI),
    /// there is no natural "source of truth" for the buffer content. Changes
    /// mostly come from Nvim, but in some cases we want to synchronize changes
    /// from the UI back to Nvim:
    /// * Auto-completion of symbols and snippets.
    /// * Paste using macOS clipboard through Cmd-V or "Paste" menu.
    /// * Undo/redo using the UI instead of u and ^R.
    ///
    /// To address this, `BufferState` uses a shared "edition token" whose
    /// owner temporarily becomes the source of truth.
    ///
    /// The edition token is automatically reset (released) after a short
    /// timeout without any editing events.
    enum EditionToken: Equatable, CustomDebugStringConvertible {
        /// UI and Nvim are idle.
        case free

        /// One buffer acquired the token and became the source of truth for
        /// the content.
        case acquired(owner: BufferHost)

        /// The main buffer released the token and is now synchronizing the full
        /// content with the subalternate buffer.
        ///
        /// The token will revert to `free` when receiving the next token
        /// timeout.
        case synchronizing

        var debugDescription: String {
            switch self {
            case .free:
                return "free"
            case let .acquired(owner):
                return "acquired(by: \(owner.rawValue))"
            case .synchronizing:
                return "synchronizing"
            }
        }
    }

    /// Represents the current state of the Nvim buffer.
    struct NvimState: Equatable {
        /// Current cursor position and mode.
        var cursor: Cursor = .init(mode: .normal, position: .init(), visual: .init())

        /// Buffer content lines.
        var lines: [String] = []

        /// Converts the current cursor position and visual selection as a
        /// list of selection ranges in the UI buffer.
        func uiSelections() -> [UISelection] {
            switch cursor.mode {
            case .normal:
                let end = BufferPosition(line: cursor.position.line, column: cursor.position.column + 1)
                return [UISelection(start: UIPosition(cursor.position), end: UIPosition(end))]

            case .insert, .replace:
                let position = UIPosition(cursor.position)
                return [UISelection(start: position, end: position)]

            case .visualBlock, .selectBlock:
                // Block selections could be implemented using AX's
                // `selectedTextRanges` (plural). Unfortunately it doesn't seem
                // to be writable in Xcode... For now blocks are handled as
                // regular character selection, to see where the blocks start
                // and end.
                fallthrough

            case .visual, .select:
                // FIXME: Only the default `selection` option of `inclusive` is currently supported for the selection feedback. (https://neovim.io/doc/user/options.html#'selection')
                let start: UIPosition
                let end: UIPosition

                let position = UIPosition(cursor.position)
                let visual = UIPosition(cursor.visual)
                if position >= visual {
                    start = visual
                    end = position.moving(column: +1)
                } else {
                    start = position
                    end = visual.moving(column: +1)
                }
                return [UISelection(start: start, end: end)]

            case .visualLine, .selectLine:
                let position = UIPosition(cursor.position)
                let visual = UIPosition(cursor.visual)
                var start = min(position, visual)
                var end = max(position, visual)
                start.column = 0
                end.line += 1
                end.column = 0
                return [UISelection(start: start, end: end)]

            case .cmdline, .hitEnterPrompt, .shell, .terminal:
                return []
            }
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
        case .tokenDidTimeout:
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

        case let .nvimBufferDidChange(lines: lines, event: event):
            nvim.lines = lines

            if tryEdition(from: .nvim) {
                perform(.uiUpdatePartialLines(event: event))
                perform(.uiUpdateSelections(nvim.uiSelections()))
            }

        case let .nvimCursorDidChange(cursor):
            nvim.cursor = cursor

            if tryEdition(from: .nvim) {
                perform(.uiUpdateSelections(nvim.uiSelections()))
                // Ensures the cursor is always visible by scrolling the UI.
                if cursor.position.line != cursor.visual.line {
                    let cursorPosition = UIPosition(cursor.position)
                    let visibleSelection = UISelection(start: cursorPosition, end: cursorPosition)
                    perform(.uiScroll(visibleSelection: visibleSelection))
                }
            }

        case let .uiDidFocus(lines: lines, selection: selection):
            ui.lines = lines
            ui.selection = selection

            if tryEdition(from: .ui) {
                adjustUISelection(to: nvim.cursor.mode)
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
                adjustUISelection(to: nvim.cursor.mode)
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
                // Passthrough in insert mode, for improved performance.
                guard !keysPassthroughOnInsert || nvim.cursor.mode != .insert else {
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
                    adjustUISelection(to: nvim.cursor.mode)
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

            let selection = ui.selection.adjust(
                to: enabled ? .insert : nvim.cursor.mode,
                lines: ui.lines
            )
            perform(.uiUpdateSelections([selection]))

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
            perform(.uiUpdate(
                lines: nvim.lines,
                diff: nvim.lines.difference(from: ui.lines),
                selections: nvim.uiSelections()
            ))
        }

        func synchronizeNvim() {
            perform(.nvimUpdate(
                lines: ui.lines,
                diff: ui.lines.difference(from: nvim.lines),
                cursorPosition: BufferPosition(ui.selection.start)
            ))
        }

        /// Moves the Nvim cursor to match the current UI selection.
        func synchronizeNvimCursor() {
            precondition(token == .acquired(owner: .ui))

            let start = BufferPosition(ui.selection.start)
            if nvim.cursor.position != start {
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
                return ui.selection.adjust(to: mode, lines: ui.lines)
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

            if token != .free, !actions.contains(.startTokenTimeout) {
                perform(.startTokenTimeout)
            }
        }

        return actions
    }
}

private extension KeyCombo {
    static let escape = KeyCombo(.escape)
    static let cmdZ = KeyCombo(.z, modifiers: .command)
    static let cmdShiftZ = KeyCombo(.z, modifiers: [.command, .shift])
    static let cmdV = KeyCombo(.v, modifiers: [.command])
}

// MARK: Logging

extension LegacyBufferState.EditionToken: LogValueConvertible {
    var logValue: LogValue {
        switch self {
        case .free:
            return .string("free")
        case let .acquired(owner: owner):
            return .string("acquired by \(owner.rawValue)")
        case .synchronizing:
            return .string("synchronizing")
        }
    }
}

extension LegacyBufferState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["token": token, "nvim": nvim, "ui": ui]
    }
}

extension LegacyBufferState.NvimState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["lines": lines, "cursor": cursor]
    }
}

extension LegacyBufferState.UIState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["lines": lines, "selection": selection]
    }
}
