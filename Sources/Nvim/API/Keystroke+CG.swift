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

import CoreGraphics
import Foundation
import Toolkit

public extension Keystroke {
    /// Creates an Nvim-compatible keystroke from a CoreGraphics event.
    init?(event: CGEvent) {
        guard
            event.type == .keyUp || event.type == .keyDown,
            let key = KeyOrASCII(event: event)
        else {
            return nil
        }

        self.init(key, modifiers: KeyModifiers(event: event))
    }
}

private extension KeyModifiers {
    init(event: CGEvent) {
        self = .none
        if event.flags.contains(.maskControl) {
            insert(.control)
        }
        if event.flags.contains(.maskAlternate) {
            insert(.option)
        }
        if event.flags.contains(.maskCommand) {
            insert(.command)
        }
        if event.flags.contains(.maskShift) {
            insert(.shift)
        }
    }
}

private extension KeyOrASCII {
    init?(event: CGEvent) {
        if let key = Key(event: event) {
            self = .key(key)
        } else {
            guard
                let char = event.key,
                !char.isEmpty
            else {
                return nil
            }
            self = .ascii(char)
        }
    }
}

private extension Key {
    init?(event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch code {
        case 0x33: self = .bs
        case 0x30: self = .tab
        case 0x24: self = .cr
        case 0x35: self = .esc
        case 0x31: self = .space
        case 0x2A: self = .bslash
        case 0x7E: self = .up
        case 0x7D: self = .down
        case 0x7B: self = .left
        case 0x7C: self = .right
        case 0x7A: self = .f1
        case 0x78: self = .f2
        case 0x63: self = .f3
        case 0x76: self = .f4
        case 0x60: self = .f5
        case 0x61: self = .f6
        case 0x62: self = .f7
        case 0x64: self = .f8
        case 0x65: self = .f9
        case 0x6D: self = .f10
        case 0x67: self = .f11
        case 0x6F: self = .f12
        case 0x72: self = .help
        case 0x73: self = .home
        case 0x77: self = .end
        case 0x74: self = .pageUp
        case 0x79: self = .pageDown
        case 0x52: self = .k0
        case 0x53: self = .k1
        case 0x54: self = .k2
        case 0x55: self = .k3
        case 0x56: self = .k4
        case 0x57: self = .k5
        case 0x58: self = .k6
        case 0x59: self = .k7
        case 0x5B: self = .k8
        case 0x5C: self = .k9
        default: return nil
        }
    }
}
