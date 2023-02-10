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

enum AppState {
    case stopped
    case idle(passthrough: Bool)
    case focused(buffer: BufferMediator, passthrough: Bool)

    enum Event {
        case start
        case stop
        case focus(buffer: BufferMediator)
        case unfocus
        case togglePassthrough
    }

    enum Action {
        case start
        case stop
        case playSound(name: String)
    }

    mutating func on(_ event: Event) -> [Action] {
        var actions: [Action] = []

        switch (self, event) {
        case (.stopped, .start):
            self = .idle(passthrough: false)
            perform(.start)

        case let (.idle(passthrough: passthrough), .focus(buffer: buffer)):
            self = .focused(buffer: buffer, passthrough: passthrough)

        case let (.idle(passthrough: passthrough), .togglePassthrough):
            self = .idle(passthrough: !passthrough)
            perform(.playSound(name: "Pop"))

        case let (.focused(buffer: _, passthrough: passthrough), .unfocus):
            self = .idle(passthrough: passthrough)

        case let (.focused(buffer: buffer, passthrough: passthrough), .togglePassthrough):
            self = .focused(buffer: buffer, passthrough: !passthrough)
            perform(.playSound(name: "Pop"))

        case (_, .stop):
            self = .stopped
            perform(.stop)

        default:
            break
        }

        func perform(_ action: Action...) {
            actions.append(contentsOf: action)
        }

        return actions
    }
}
