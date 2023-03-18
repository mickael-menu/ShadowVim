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
            case .acquired(let owner):
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
                if lines.indices.contains(end.line) {
                    end.column = lines[end.line].count + 1
                }
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
        case uiDidFocus(lines: [String], selection: UISelection?)

        /// The UI buffer changed with the given new `lines`.
        case uiBufferDidChange(lines: [String])

        /// The UI selection changed.
        case uiSelectionDidChange(UISelection)

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
        /// Update the content of the Nvim buffer with the new `lines`.
        ///
        /// The `diff` contains the changes from the current Nvim `lines`.
        case updateNvimLines(lines: [String], diff: CollectionDifference<String>)

        /// Update the position of the Nvim cursor.
        case moveNvimCursor(BufferPosition)

        /// Create a new visual selection in the Nvim buffer.
        case startNvimVisual(start: BufferPosition, end: BufferPosition)

        /// Exits the Neovim Visual mode.
        case stopNvimVisual

        /// Update the content of the UI buffer with the new `lines`.
        ///
        /// The `diff` contains the changes from the current UI `lines`.
        case updateUILines(lines: [String], diff: CollectionDifference<String>)

        /// Update a portion of the UI buffer using the given `BufLinesEvent`
        /// from Nvim.
        case updateUIPartialLines(event: BufLinesEvent)

        /// Update the current selections in the UI buffer.
        case updateUISelections([UISelection])

        /// Scrolls the UI to make the given selection visible.
        case scrollUI(visibleSelection: UISelection)

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
                setToken(.free)
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
            updateUIPartialLines(from: event)
            updateUISelections()

        case let .nvimCursorDidChange(cursor):
            nvim.cursor = cursor
            updateUISelections()
            ensureNvimSelectionCursorVisible()

        case let .uiDidFocus(lines: lines, selection: selection):
            if ui.lines != lines {
                ui.lines = lines
                updateNvimLines()
            }

            let selection = selection ?? .init()
            if ui.selection != selection {
                ui.selection = selection

                adjustUISelection(to: nvim.cursor.mode)
                updateNvimCursor()
            }

        case let .uiBufferDidChange(lines: lines):
            guard ui.lines != lines else {
                break
            }

            ui.lines = lines
            updateNvimLines()

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
                adjustUISelection(to: nvim.cursor.mode)
                updateNvimCursor()
            }

        case let .uiDidReceiveMouseEvent(.down(.left), bufferPoint: bufferPoint):
            guard bufferPoint != nil else { break }

            isLeftMouseButtonDown = true

            // Simulate the default behavior of `LeftMouse` in Nvim, which is:
            // > If Visual mode is active it is stopped.
            // > :help LeftMouse
            stopNvimVisual()

        case .uiDidReceiveMouseEvent(.up(.left), bufferPoint: _):
            isLeftMouseButtonDown = false

            if isSelecting {
                isSelecting = false

                if ui.selection.isCollapsed {
                    adjustUISelection(to: nvim.cursor.mode)
                    updateNvimCursor()
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
                perform(.stopNvimVisual)
            }

            let selection = ui.selection.adjust(
                to: enabled ? .insert : nvim.cursor.mode,
                lines: ui.lines
            )
            perform(.updateUISelections([selection]))

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
                token = .acquired(owner: host)

                if !actions.contains(.startTokenTimeout) {
                    perform(.startTokenTimeout)
                }
                return true
            default:
                return false
            }
        }

        /// Synchronizes the whole buffer using the given `source` of truth.
        func synchronize(source: BufferHost) {
            var synchronizing = false

            switch source {
            case .nvim:
                synchronizing = updateUILines() || synchronizing
                synchronizing = updateUISelections() || synchronizing
            case .ui:
                synchronizing = updateNvimLines() || synchronizing
                synchronizing = updateNvimCursor() || synchronizing
            }

            setToken(synchronizing ? .synchronizing : .free)
        }

        func setToken(_ token: EditionToken) {
            self.token = token

            if token != .free, !actions.contains(.startTokenTimeout) {
                perform(.startTokenTimeout)
            }
        }

        func areLinesDifferent() -> Bool {
            // Some apps (like Xcode) systematically add an empty line at
            // the end of a document. To make sure the comparison won't
            // fail in this case, we add an empty line in the Nvim buffer
            // as well.
            var nvimLines = nvim.lines
            if ui.lines.last == "", nvimLines.last != "" {
                nvimLines.append("")
            }
            return ui.lines != nvimLines
        }

        @discardableResult
        func updateNvimLines() -> Bool {
            guard areLinesDifferent(), tryEdition(from: .ui) else {
                return false
            }

            perform(.updateNvimLines(
                lines: ui.lines,
                diff: ui.lines.difference(from: nvim.lines)
            ))
            return true
        }

        /// Moves the Nvim cursor to match the current UI selection.
        @discardableResult
        func updateNvimCursor() -> Bool {
            let start = BufferPosition(ui.selection.start)
            guard start != nvim.cursor.position, tryEdition(from: .ui) else {
                return false
            }
            perform(.moveNvimCursor(start))
            return true
        }

        @discardableResult
        func updateUILines() -> Bool {
            guard areLinesDifferent(), tryEdition(from: .nvim) else {
                return false
            }

            perform(.updateUILines(
                lines: nvim.lines,
                diff: nvim.lines.difference(from: ui.lines)
            ))
            return true
        }

        func updateUIPartialLines(from event: BufLinesEvent) {
            guard tryEdition(from: .nvim) else {
                return
            }
            perform(.updateUIPartialLines(event: event))
        }

        @discardableResult
        func updateUISelections() -> Bool {
            let nvimUISelections = nvim.uiSelections()
            guard [ui.selection] != nvimUISelections, tryEdition(from: .nvim) else {
                return false
            }
            perform(.updateUISelections(nvimUISelections))
            return true
        }

        /// Adjusts the current UI selection to match the given Nvim `mode`.
        func adjustUISelection(to mode: Mode) {
            let adjustedSelection = {
                guard !isKeysPassthroughEnabled else {
                    return ui.selection
                }
                return ui.selection.adjust(to: mode, lines: ui.lines)
            }()

            if ui.selection != adjustedSelection, tryEdition(from: .ui) {
                ui.selection = adjustedSelection
                perform(.updateUISelections([ui.selection]))
            }
        }

        /// Requests Nvim to start the Visual mode using the given `selection`.
        func startNvimVisual(using selection: UISelection) {
            guard tryEdition(from: .ui) else {
                return
            }

            perform(.startNvimVisual(
                start: BufferPosition(selection.start),
                // In Visual mode the end character is included in
                // the selection, so we need to shift it.
                end: BufferPosition(selection.end.moving(column: -1))
            ))
        }

        func stopNvimVisual() {
            guard tryEdition(from: .ui) else {
                return
            }
            perform(.stopNvimVisual)
        }

        /// Ensure the cursor is always visible during a visual selection by
        /// scrolling the UI.
        func ensureNvimSelectionCursorVisible() {
            guard
                // If it's not a selection, we don't need to scroll the UI as
                // the cursor will already be visible.
                nvim.cursor.position.line != nvim.cursor.visual.line,
                tryEdition(from: .nvim)
            else {
                return
            }
            let cursorPosition = UIPosition(nvim.cursor.position)
            let visibleSelection = UISelection(start: cursorPosition, end: cursorPosition)
            perform(.scrollUI(visibleSelection: visibleSelection))
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
        case .didRequestRefresh(source: let source):
            return source.rawValue
        case .nvimBufferDidChange(lines: _, event: let event):
            return "\(event.firstLine)-\(event.lastLine) (\(event.lineData.count) lines)"
        case .nvimCursorDidChange(let cursor):
            return "\(cursor.mode.rawValue) .\(cursor.position.line):\(cursor.position.column) v\(cursor.position.line):\(cursor.position.column)"
        case .uiSelectionDidChange(let selection):
            return "\(selection.start.line):\(selection.end.line)...\(selection.end.line):\(selection.end.column)"
        case .uiDidReceiveMouseEvent(let kind, bufferPoint: let bufferPoint):
            if let bufferPoint = bufferPoint {
                return "\(kind) @\(bufferPoint.x),\(bufferPoint.y)"
            } else {
                return "\(kind) outside buffer"
            }
        case .didToggleKeysPassthrough(enabled: let enabled):
            return "\(enabled)"
        case .didFail(let error):
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
        case let .updateNvimLines(lines: lines, diff: diff):
            return [.name: "updateNvimLines", "lines": lines, "diff": diff]
        case let .moveNvimCursor(cursor):
            return [.name: "moveNvimCursor", "cursor": cursor]
        case let .startNvimVisual(start: start, end: end):
            return [.name: "startNvimVisual", "start": start, "end": end]
        case .stopNvimVisual:
            return [.name: "stopNvimVisual"]
        case let .updateUILines(lines: lines, diff: diff):
            return [.name: "updateUILines", "lines": lines, "diff": diff]
        case let .updateUIPartialLines(event: event):
            return [.name: "updateUIPartialLines", "event": event]
        case let .updateUISelections(selections):
            return [.name: "updateUISelection", "selections": selections]
        case let .scrollUI(visibleSelection: visibleSelection):
            return [.name: "scrollUI", "visibleSelection": visibleSelection]
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
