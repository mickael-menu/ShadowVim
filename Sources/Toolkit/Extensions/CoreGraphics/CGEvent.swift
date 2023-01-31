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

public struct KeyModifiers: OptionSet {
    public static let none = KeyModifiers([])
    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let command = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    public static let capsLock = KeyModifiers(rawValue: 1 << 4)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(flags: CGEventFlags) {
        self = .none

        if flags.contains(.maskControl) {
            insert(.control)
        }
        if flags.contains(.maskAlternate) {
            insert(.option)
        }
        if flags.contains(.maskCommand) {
            insert(.command)
        }
        if flags.contains(.maskShift) {
            insert(.shift)
        }
        if flags.contains(.maskAlphaShift) {
            insert(.capsLock)
        }
    }
}

public enum KeyCode: Int64 {
    case escape = 0x35
    case backspace = 0x33
    case enter = 0x24
    case leftArrow = 0x7B
    case rightArrow = 0x7C
    case downArrow = 0x7D
    case upArrow = 0x7E
    case period = 0x2F
}

public extension CGEvent {
    /// Returns the keyboard key code for this keyboard event.
    var keyCode: KeyCode? {
        KeyCode(rawValue: getIntegerValueField(.keyboardEventKeycode))
    }

    /// Returns the keyboard modifiers for this event.
    var modifiers: KeyModifiers {
        KeyModifiers(flags: flags)
    }

    /// Returns the unicode character for this keyboard event.
    var character: String {
        let maxStringLength = 4
        var actualStringLength = 0
        var unicodeString = [UniChar](repeating: 0, count: Int(maxStringLength))
        keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
        return String(utf16CodeUnits: &unicodeString, count: Int(actualStringLength))
    }
}

public extension CGEventFlags {
    static var none: CGEventFlags {
        CGEventFlags()
    }
}
