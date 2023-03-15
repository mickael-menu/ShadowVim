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
    case starting
    case idle
    case focused(buffer: BufferMediator)

    enum Event {
        case willStart
        case didStart
        case didStop
        case focus(buffer: BufferMediator)
        case unfocus
    }

    mutating func on(_ event: Event, logger: Logger? = nil) {
        let oldState = self

        switch (self, event) {
        case (.stopped, .willStart):
            self = .starting

        case (.starting, .didStart):
            self = .idle

        case (_, .didStop):
            self = .stopped

        case let (.idle, .focus(buffer: buffer)):
            self = .focused(buffer: buffer)

        case let (.focused, .focus(buffer: buffer)):
            self = .focused(buffer: buffer)

        case (.focused, .unfocus):
            self = .idle

        default:
            break
        }

        let newState = self
        logger?.t("on \(event.name)", [
            "event": event,
            "oldState": oldState,
            "newState": newState,
        ])
    }
}

// MARK: - Logging

extension AppState: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case .stopped:
            return [.name: "stopped"]
        case .starting:
            return [.name: "starting"]
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
        case .willStart:
            return "willStart"
        case .didStart:
            return "didStart"
        case .didStop:
            return "didStop"
        case .focus:
            return "focus"
        case .unfocus:
            return "unfocus"
        }
    }

    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case .willStart, .didStart, .didStop, .unfocus:
            return [.name: name]
        case let .focus(buffer: buffer):
            return [.name: name, .buffer: buffer]
        }
    }
}

private extension LogKey {
    static var name: LogKey { "@name" }
    static var buffer: LogKey { "buffer" }
}
