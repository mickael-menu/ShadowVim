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

/// Represents a keystroke which can be triggered in Nvim.
public struct Keystroke: Hashable, CustomStringConvertible {
    /// Pressed key.
    public var key: KeyOrASCII

    /// Additional pressed key modifiers.
    public var modifiers: KeyModifiers

    public init(_ key: KeyOrASCII, modifiers: KeyModifiers = .none) {
        self.key = key
        self.modifiers = modifiers
    }

    public init(_ ascii: String, modifiers: KeyModifiers = .none) {
        key = .ascii(ascii)
        self.modifiers = modifiers
    }

    public init(key: Key, modifiers: KeyModifiers = .none) {
        self.key = .key(key)
        self.modifiers = modifiers
    }

    /// Creates a keystroke from an Nvim string notation.
    ///
    /// See https://neovim.io/doc/user/intro.html#key-notation
    public init?(notation: String) {
        guard !notation.isEmpty, notation != "<>" else {
            return nil
        }

        if notation.first == "<" {
            guard notation.last == ">" else {
                return nil
            }
            var notation = notation
            notation.removeFirst()
            notation.removeLast()

            var components = notation.splitByHyphen()
            guard !components.isEmpty else {
                return nil
            }

            if components.count == 1 {
                guard let key = KeyOrASCII(notation: components[0]) else {
                    return nil
                }
                self.init(key)

            } else {
                let keyComponent = components.removeLast()
                guard
                    let modifiers = KeyModifiers(notations: components),
                    let key = KeyOrASCII(notation: keyComponent)
                else {
                    return nil
                }
                self.init(key, modifiers: modifiers)
            }

        } else {
            self.init(.ascii(notation))
        }
    }

    /// Returns the string notation of the keystroke.
    ///
    /// See https://neovim.io/doc/user/intro.html#key-notation
    public var notation: String {
        modifiers.notation(with: key)
    }

    public var description: String { notation }
}

public enum KeyOrASCII: Hashable {
    case key(Key)
    case ascii(String)

    init?<S: StringProtocol>(notation: S) {
        guard !notation.isEmpty else {
            return nil
        }
        if let key = Key(notation: notation) {
            self = .key(key)
        } else {
            self = .ascii(String(notation))
        }
    }
}

public enum Key: String, Hashable {
    /// Backspace
    case bs = "BS"
    /// Tab
    case tab = "Tab"
    /// Linefeed
    case nl = "NL"
    /// Carriage return
    case cr = "CR"
    /// Same as `<CR>`
    case `return` = "Return"
    /// Same as `<CR>`
    case enter = "Enter"
    /// Escape
    case esc = "Esc"
    /// Space
    case space = "Space"
    /// Less-than
    case lt
    /// Backslash
    case bslash = "Bslash"
    /// Vertical bar
    case bar = "Bar"
    /// Delete
    case del = "Del"
    /// Cursor-up
    case up = "Up"
    /// Cursor-down
    case down = "Down"
    /// Cursor-left
    case left = "Left"
    /// Cursor-right
    case right = "Right"
    /// Function key 1
    case f1 = "F1"
    /// Function key 2
    case f2 = "F2"
    /// Function key 3
    case f3 = "F3"
    /// Function key 4
    case f4 = "F4"
    /// Function key 5
    case f5 = "F5"
    /// Function key 6
    case f6 = "F6"
    /// Function key 7
    case f7 = "F7"
    /// Function key 8
    case f8 = "F8"
    /// Function key 9
    case f9 = "F9"
    /// Function key 10
    case f10 = "F10"
    /// Function key 11
    case f11 = "F11"
    /// Function key 12
    case f12 = "F12"
    /// Help key
    case help = "Help"
    /// Undo key
    case undo = "Undo"
    /// Insert key
    case insert = "Insert"
    /// Home
    case home = "Home"
    /// End
    case end = "End"
    /// Page-up
    case pageUp = "PageUp"
    /// Page-down
    case pageDown = "PageDown"
    /// Keypad cursor-up
    case kUp
    /// Keypad cursor-down
    case kDown
    /// Keypad cursor-left
    case kLeft
    /// Keypad cursor-right
    case kRight
    /// Keypad home (upper left)
    case kHome
    /// Keypad end (lower left)
    case kEnd
    /// Keypad origin (middle)
    case kOrigin
    /// Keypad page-up (upper right)
    case kPageUp
    /// Keypad page-down (lower right)
    case kPageDown
    /// Keypad delete
    case kDel
    /// Keypad +
    case kPlus
    /// Keypad -
    case kMinus
    /// Keypad *
    case kMultiply
    /// Keypad /
    case kDivide
    /// Keypad .
    case kPoint
    /// Keypad ,
    case kComma
    /// Keypad =
    case kEqual
    /// Keypad Enter
    case kEnter
    /// Keypad 0
    case k0
    /// Keypad 1
    case k1
    /// Keypad 2
    case k2
    /// Keypad 3
    case k3
    /// Keypad 4
    case k4
    /// Keypad 5
    case k5
    /// Keypad 6
    case k6
    /// Keypad 7
    case k7
    /// Keypad 8
    case k8
    /// Keypad 9
    case k9

    init?<S: StringProtocol>(notation: S) {
        switch notation.lowercased() {
        case "bs":
            self = .bs
        case "tab":
            self = .tab
        case "nl":
            self = .nl
        case "cr":
            self = .cr
        case "return":
            self = .return
        case "enter":
            self = .enter
        case "esc":
            self = .esc
        case "space":
            self = .space
        case "lt":
            self = .lt
        case "bslash":
            self = .bslash
        case "bar":
            self = .bar
        case "del":
            self = .del
        case "up":
            self = .up
        case "down":
            self = .down
        case "left":
            self = .left
        case "right":
            self = .right
        case "f1":
            self = .f1
        case "f2":
            self = .f2
        case "f3":
            self = .f3
        case "f4":
            self = .f4
        case "f5":
            self = .f5
        case "f6":
            self = .f6
        case "f7":
            self = .f7
        case "f8":
            self = .f8
        case "f9":
            self = .f9
        case "f10":
            self = .f10
        case "f11":
            self = .f11
        case "f12":
            self = .f12
        case "help":
            self = .help
        case "undo":
            self = .undo
        case "insert":
            self = .insert
        case "home":
            self = .home
        case "end":
            self = .end
        case "pageup":
            self = .pageUp
        case "pagedown":
            self = .pageDown
        case "kup":
            self = .kUp
        case "kdown":
            self = .kDown
        case "kleft":
            self = .kLeft
        case "kright":
            self = .kRight
        case "khome":
            self = .kHome
        case "kend":
            self = .kEnd
        case "korigin":
            self = .kOrigin
        case "kpageup":
            self = .kPageUp
        case "kpagedown":
            self = .kPageDown
        case "kdel":
            self = .kDel
        case "kplus":
            self = .kPlus
        case "kminus":
            self = .kMinus
        case "kmultiply":
            self = .kMultiply
        case "kdivide":
            self = .kDivide
        case "kpoint":
            self = .kPoint
        case "kcomma":
            self = .kComma
        case "kequal":
            self = .kEqual
        case "kenter":
            self = .kEnter
        case "k0":
            self = .k0
        case "k1":
            self = .k1
        case "k2":
            self = .k2
        case "k3":
            self = .k3
        case "k4":
            self = .k4
        case "k5":
            self = .k5
        case "k6":
            self = .k6
        case "k7":
            self = .k7
        case "k8":
            self = .k8
        case "k9":
            self = .k9
        default:
            return nil
        }
    }
}

public struct KeyModifiers: OptionSet, Hashable {
    public static let none = KeyModifiers([])
    /// S-
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    /// C-
    public static let control = KeyModifiers(rawValue: 1 << 0)
    /// M- or A-
    public static let option = KeyModifiers(rawValue: 1 << 1)
    /// D-
    public static let command = KeyModifiers(rawValue: 1 << 2)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init?<S: StringProtocol>(notations: [S]) {
        self = .none
        for notation in notations {
            switch notation.lowercased() {
            case "s":
                insert(.shift)
            case "c":
                insert(.control)
            case "m", "a":
                insert(.option)
            case "d":
                insert(.command)
            default:
                return nil
            }
        }
    }

    func notation(with key: KeyOrASCII) -> String {
        var notation = ""
        if contains(.shift) {
            notation += "S-"
        }
        if contains(.control) {
            notation += "C-"
        }
        if contains(.option) {
            notation += "M-"
        }
        if contains(.command) {
            notation += "D-"
        }

        var needsBracket = (self != .none)

        switch key {
        case let .key(key):
            notation += key.rawValue
            needsBracket = true
        case .ascii("-") where needsBracket:
            notation += "\\-"
        case .ascii("<"):
            notation += "LT"
            needsBracket = true
        case let .ascii(ascii):
            notation += ascii
        }

        if needsBracket {
            notation = "<\(notation)>"
        }
        return notation
    }
}

private extension String {
    /// Splits the string by hyphens, except if they are escaped with a
    /// backslash.
    func splitByHyphen() -> [String] {
        var components: [String] = []
        var currentComponent = ""
        var isEscaped = false
        for char in self {
            if char == "-", !isEscaped {
                components.append(currentComponent)
                currentComponent = ""
            } else if char == "\\" {
                isEscaped = true
            } else {
                isEscaped = false
                currentComponent.append(char)
            }
        }
        components.append(currentComponent)
        return components
    }
}
