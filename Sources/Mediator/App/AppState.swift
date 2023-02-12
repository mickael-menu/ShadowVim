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

import AX
import Foundation
import Nvim
import Toolkit

enum AppState {
    case stopped
    case idle
    case focused(buffer: BufferMediator)

    enum Event {
        case start
        case stop
        case focus(buffer: BufferMediator)
        case unfocus
    }

    enum Action {
        case start
        case stop
    }

    mutating func on(_ event: Event, logger: Logger? = nil) -> [Action] {
        let oldState = self
        var actions: [Action] = []

        switch (self, event) {
        case (.stopped, .start):
            self = .idle
            perform(.start)

        case let (.idle, .focus(buffer: buffer)):
            self = .focused(buffer: buffer)

        case let (.focused, .focus(buffer: buffer)):
            self = .focused(buffer: buffer)

        case (.focused, .unfocus):
            self = .idle

        case (_, .stop):
            self = .stopped
            perform(.stop)

        default:
            break
        }

        func perform(_ action: Action...) {
            actions.append(contentsOf: action)
        }

        let newState = self
        logger?.t("on \(event.name)", [
            "event": event,
            "oldState": oldState,
            "newState": newState,
            "actions": actions,
        ])
        return actions
    }
}

// MARK: - Logging

extension AppState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case .stopped:
            return [.name: "stopped"]
        case .idle:
            return [.name: "idle"]
        case let .focused(buffer: buffer):
            return [.name: "focused", .buffer: buffer]
        }
    }
}

extension AppState.Event: LogPayloadConvertible {
    var name: String {
        switch self {
        case .start:
            return "start"
        case .stop:
            return "stop"
        case .focus:
            return "focus"
        case .unfocus:
            return "unfocus"
        }
    }

    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case .start:
            return [.name: name]
        case .stop:
            return [.name: name]
        case let .focus(buffer: buffer):
            return [.name: name, .buffer: buffer]
        case .unfocus:
            return [.name: name]
        }
    }
}

extension AppState.Action: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case .start:
            return [.name: "start"]
        case .stop:
            return [.name: "stop"]
        }
    }
}

private extension LogKey {
    static var name: LogKey { "@name" }
    static var buffer: LogKey { "buffer" }
}
