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
protocol BufferState: Equatable, LogPayloadConvertible {
    mutating func on(_ event: BufferEvent, logger: Logger?) -> [BufferAction]
}

/// Identifiers the owner of a live buffer.
enum BufferHost: String, Equatable {
    case nvim
    case ui
}

/// Events handled by the Buffer state machine.
enum BufferEvent: Equatable {
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

/// Actions produced by the Buffer state machine when receiving an event. They
/// are executed by the `BufferMediator`.
enum BufferAction: Equatable {
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

// MARK: - Logging

struct LoggableBufferState<S: BufferState>: BufferState {
    static func == (lhs: LoggableBufferState, rhs: LoggableBufferState) -> Bool {
        lhs.state == rhs.state
    }

    func logPayload() -> [LogKey: LogValueConvertible] {
        state.logPayload()
    }

    private var state: S
    private let logger: Logger?

    init(state: S, logger: Logger?) {
        self.state = state
        self.logger = logger
    }

    mutating func on(_ event: BufferEvent, logger: Logger?) -> [BufferAction] {
        let logger = logger ?? self.logger
        let oldState = state
        let actions = state.on(event, logger: logger)
        let newState = state

        logger?.t("on \(event.name) \(event.shortArg ?? "")", [
            "event": event,
            "oldState": oldState,
            "newState": newState,
            "actions": actions,
        ])

        return actions
    }
}

extension BufferState {
    func loggable(_ logger: Logger?) -> some BufferState {
        LoggableBufferState(state: self, logger: logger)
    }
}

extension BufferHost: LogValueConvertible {
    var logValue: LogValue {
        .string(rawValue)
    }
}

extension BufferEvent: LogPayloadConvertible {
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

extension BufferAction: LogPayloadConvertible {
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
