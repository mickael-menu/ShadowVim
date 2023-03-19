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

/// Identifiers the owner of a live buffer.
enum BufferHost: String, Equatable {
    case nvim
    case ui
}

/// State machine handling the state of a single buffer synchronized between the
/// UI and Nvim.
///
/// It is owned and executed by a `BufferMediator` which binds to the events of
/// the actual Nvim and UI buffers.
struct BufferState: Equatable {
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

    /// Events handled by the state machine.
    enum Event: Equatable {
        /// The edition token timed out and needs to be reset.
        case tokenDidTimeout

        /// The user requested to resynchronize the buffers using the given
        /// `source` host for the source of truth of the content.
        case didRequestRefresh(source: BufferHost)

        /// The Nvim buffer changed and sent a `BufLinesEvent`.
        case nvimBufferDidChange(lines: [String], event: BufLinesEvent)

        /// The Nvim cursor moved or changed its mode.
        case nvimCursorDidChange(Cursor)

        case nvimDidFlush

        /// The UI buffer regained focus.
        ///
        /// The current `lines` and `selection` are given in case they were
        /// changed by a third party.
        case uiDidFocus(lines: [String], selection: UISelection)

        /// The UI buffer changed with the given new `lines`.
        case uiBufferDidChange(lines: [String])

        /// The UI selection changed.
        case uiSelectionDidChange(UISelection)

        /// The user pressed keyboard keys.
        case uiDidReceiveKeyEvent(KeyCombo, character: String?)

        /// The user interacted with the mouse.
        ///
        /// `bufferPoint` is the event location in the UI buffer coordinates.
        /// When `nil`, the event happened outside the bounds of the UI buffer.
        case uiDidReceiveMouseEvent(MouseEvent.Kind, bufferPoint: CGPoint?)

        /// The keys passthrough was toggled.
        case didToggleKeysPassthrough(enabled: Bool)

        /// An error occurred.
        case didFail(EquatableError)
    }

    /// Actions produced by the state machine when receiving an event. They
    /// are executed by the `BufferMediator`.
    enum Action: Equatable {
        /// Update the content of the Nvim buffer with the new `lines` and
        /// cursor position.
        ///
        /// The `diff` contains the changes from the current Nvim `lines`.
        case nvimUpdate(lines: [String], diff: CollectionDifference<String>, cursorPosition: BufferPosition)

        /// Update the position of the Nvim cursor.
        case nvimMoveCursor(BufferPosition)

        /// Create a new visual selection in the Nvim buffer.
        case nvimStartVisual(start: BufferPosition, end: BufferPosition)

        /// Exit the Nvim Visual mode.
        case nvimStopVisual

        /// Undo one Nvim change.
        case nvimUndo

        /// Redo last undone Nvim change.
        case nvimRedo

        /// Paste the content of the system clipboard in the Nvim buffer.
        case nvimPaste

        /// Send input keys to Nvim.
        case nvimInput(String)

        /// Update the content of the UI buffer with the new `lines` and text
        /// `selection`.
        ///
        /// The `diff` contains the changes from the current UI `lines`.
        case uiUpdate(lines: [String], diff: CollectionDifference<String>, selections: [UISelection])

        /// Update a portion of the UI buffer using the given `BufLinesEvent`
        /// from Nvim.
        case uiUpdatePartialLines(event: BufLinesEvent)

        /// Update the current selections in the UI buffer.
        case uiUpdateSelections([UISelection])

        /// Scrolls the UI to make the given selection visible.
        case uiScroll(visibleSelection: UISelection)

        /// Start a new timeout for the edition token. Any on-going timeout
        /// should be cancelled.
        case startTokenTimeout

        /// Emit a bell sound to the user.
        case bell

        /// Present the given error to the user.
        case alert(EquatableError)
    }

    mutating func on(_ event: Event, logger: Logger? = nil) -> [Action] {
        let oldState = self
        var actions: [Action] = []

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
        func perform(_ action: Action) {
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

        let newState = self

        logger?.t("on \(event.name) \(event.shortArg ?? "")", [
            "event": event,
            "oldState": oldState,
            "newState": newState,
            "actions": actions,
        ])

        if oldState.token != newState.token {
            logger?.t("token changed: \(newState.token)")
        }

        return actions
    }
}

private extension KeyCombo {
    static let cmdZ = KeyCombo(.z, modifiers: .command)
    static let cmdShiftZ = KeyCombo(.z, modifiers: [.command, .shift])
    static let cmdV = KeyCombo(.v, modifiers: [.command])
}

// MARK: - Logging

extension BufferState.EditionToken: LogValueConvertible {
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

extension BufferState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["token": token, "nvim": nvim, "ui": ui]
    }
}

extension BufferState.NvimState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["lines": lines, "cursor": cursor]
    }
}

extension BufferState.UIState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["lines": lines, "selection": selection]
    }
}

extension BufferState.Event: LogPayloadConvertible {
    var name: String {
        switch self {
        case .tokenDidTimeout:
            return "tokenDidTimeout"
        case .didRequestRefresh:
            return "userDidRequestRefresh"
        case .nvimBufferDidChange:
            return "nvimBufferDidChange"
        case .nvimCursorDidChange:
            return "nvimCursorDidChange"
        case .nvimDidFlush:
            return "nvimDidFlush"
        case .uiDidFocus:
            return "uiDidFocus"
        case .uiBufferDidChange:
            return "uiBufferDidChange"
        case .uiSelectionDidChange:
            return "uiSelectionDidChange"
        case .uiDidReceiveKeyEvent:
            return "uiDidReceiveKeyEvent"
        case .uiDidReceiveMouseEvent:
            return "uiDidReceiveMouseEvent"
        case .didToggleKeysPassthrough:
            return "didToggleKeysPassthrough"
        case .didFail:
            return "didFail"
        }
    }

    var shortArg: String? {
        switch self {
        case let .didRequestRefresh(source: source):
            return source.rawValue
        case .nvimBufferDidChange(lines: _, event: let event):
            return "\(event.firstLine)-\(event.lastLine) (\(event.lineData.count) lines)"
        case let .nvimCursorDidChange(cursor):
            return "\(cursor.mode.rawValue) .\(cursor.position.line):\(cursor.position.column) v\(cursor.visual.line):\(cursor.visual.column)"
        case let .uiSelectionDidChange(selection):
            return "\(selection.start.line):\(selection.start.column)...\(selection.end.line):\(selection.end.column)"
        case let .uiDidReceiveKeyEvent(kc, character: _):
            return "\(kc)"
        case let .uiDidReceiveMouseEvent(kind, bufferPoint: bufferPoint):
            if let bufferPoint = bufferPoint {
                return "\(kind) @\(bufferPoint.x),\(bufferPoint.y)"
            } else {
                return "\(kind) outside buffer"
            }
        case let .didToggleKeysPassthrough(enabled: enabled):
            return "\(enabled)"
        case let .didFail(error):
            return error.error.localizedDescription
        default:
            return nil
        }
    }

    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case .tokenDidTimeout, .nvimDidFlush:
            return [.name: name]
        case let .didRequestRefresh(source: source):
            return [.name: name, "source": source.rawValue]
        case let .nvimBufferDidChange(lines: newLines, event: event):
            return [.name: name, "newLines": newLines, "event": event]
        case let .nvimCursorDidChange(cursor):
            return [.name: name, "cursor": cursor]
        case let .uiDidFocus(lines: lines, selection: selection):
            return [.name: name, "lines": lines, "selection": selection]
        case let .uiBufferDidChange(lines: lines):
            return [.name: name, "lines": lines]
        case let .uiSelectionDidChange(selection):
            return [.name: name, "selection": selection]
        case let .uiDidReceiveKeyEvent(kc, character: character):
            return [.name: name, "keyCombo": kc.description, "character": character]
        case let .uiDidReceiveMouseEvent(kind, bufferPoint: bufferPoint):
            return [.name: name, "kind": String(reflecting: kind), "bufferPoint": bufferPoint]
        case let .didToggleKeysPassthrough(enabled: enabled):
            return [.name: name, "enabled": enabled]
        case let .didFail(error):
            return [.name: name, "error": error]
        }
    }
}

extension BufferState.Action: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case let .nvimUpdate(lines: lines, diff: diff, cursorPosition: cursorPosition):
            return [.name: "nvimUpdate", "lines": lines, "diff": diff, "cursorPosition": cursorPosition]
        case let .nvimMoveCursor(cursor):
            return [.name: "nvimMoveCursor", "cursor": cursor]
        case let .nvimStartVisual(start: start, end: end):
            return [.name: "nvimStartVisual", "start": start, "end": end]
        case .nvimStopVisual:
            return [.name: "nvimStopVisual"]
        case .nvimUndo:
            return [.name: "nvimUndo"]
        case .nvimRedo:
            return [.name: "nvimRedo"]
        case .nvimPaste:
            return [.name: "nvimPaste"]
        case let .nvimInput(keys):
            return [.name: "nvimInput", "keys": keys]
        case let .uiUpdate(lines: lines, diff: diff, selections: selections):
            return [.name: "uiUpdate", "lines": lines, "diff": diff, "selections": selections]
        case let .uiUpdatePartialLines(event: event):
            return [.name: "uiUpdatePartialLines", "event": event]
        case let .uiUpdateSelections(selections):
            return [.name: "uiUpdateSelection", "selections": selections]
        case let .uiScroll(visibleSelection: visibleSelection):
            return [.name: "uiScroll", "visibleSelection": visibleSelection]
        case .startTokenTimeout:
            return [.name: "startTokenTimeout"]
        case .bell:
            return [.name: "bell"]
        case let .alert(error):
            return [.name: "alert", "error": error]
        }
    }
}

private extension LogKey {
    static var name: LogKey { "@name" }
}
