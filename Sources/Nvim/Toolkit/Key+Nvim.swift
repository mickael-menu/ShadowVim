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
import Toolkit

public typealias Notation = String

public extension KeyCombo {
    /// Creates a key combo from an Nvim string notation.
    ///
    /// See https://neovim.io/doc/user/intro.html#key-notation
    init?(nvimNotation notation: Notation) {
        guard !notation.isEmpty, notation != "<>" else {
            return nil
        }

        let notation = notation.lowercased()
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
                guard let key = lookupTo[components[0]] else {
                    return nil
                }
                self.init(key)

            } else {
                let keyComponent = components.removeLast()
                guard
                    let modifiers = InputModifiers(notations: components),
                    let key = lookupTo[keyComponent]
                else {
                    return nil
                }
                self.init(key, modifiers: modifiers)
            }

        } else if let key = lookupTo[notation] {
            self.init(key)

        } else {
            return nil
        }
    }

    /// Returns the string notation of the keystroke.
    ///
    /// See https://neovim.io/doc/user/intro.html#key-notation
    var nvimNotation: Notation? {
        modifiers.notation(with: key)
    }
}

public extension InputModifiers {
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

    func notation(with key: Key) -> String? {
        guard let (keyNotation, needsBracket) = lookupFrom[key] else {
            return nil
        }

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

        notation += keyNotation

        if needsBracket || !isEmpty {
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

private let lookupTo: [Notation: Toolkit.Key] = [
    "esc": .escape,
    "cr": .return,
    "return": .return,
    "enter": .return,
    "tab": .tab,
    "space": .space,
    "bs": .backspace,
    "del": .forwardDelete,
    "up": .upArrow,
    "down": .downArrow,
    "left": .leftArrow,
    "right": .rightArrow,
    "pageup": .pageUp,
    "pagedown": .pageDown,
    "home": .home,
    "end": .end,
    "help": .help,

    "a": .a,
    "b": .b,
    "c": .c,
    "d": .d,
    "e": .e,
    "f": .f,
    "g": .g,
    "h": .h,
    "i": .i,
    "j": .j,
    "k": .k,
    "l": .l,
    "m": .m,
    "n": .n,
    "o": .o,
    "p": .p,
    "q": .q,
    "r": .r,
    "s": .s,
    "t": .t,
    "u": .u,
    "v": .v,
    "w": .w,
    "x": .x,
    "y": .y,
    "z": .z,

    "0": .zero,
    "1": .one,
    "2": .two,
    "3": .three,
    "4": .four,
    "5": .five,
    "6": .six,
    "7": .seven,
    "8": .eight,
    "9": .nine,

    "f1": .f1,
    "f2": .f2,
    "f3": .f3,
    "f4": .f4,
    "f5": .f5,
    "f6": .f6,
    "f7": .f7,
    "f8": .f8,
    "f9": .f9,
    "f10": .f10,
    "f11": .f11,
    "f12": .f12,

    "-": .minus,
    "=": .equal,
    "[": .leftBracket,
    "]": .rightBracket,
    ";": .semicolon,
    "'": .quote,
    "\\": .backslash,
    ",": .comma,
    ".": .period,
    "/": .slash,
    "`": .grave,

    "k0": .keypadZero,
    "k1": .keypadOne,
    "k2": .keypadTwo,
    "k3": .keypadThree,
    "k4": .keypadFour,
    "k5": .keypadFive,
    "k6": .keypadSix,
    "k7": .keypadSeven,
    "k8": .keypadEight,
    "k9": .keypadNine,
    "kcomma": .keypadDecimal,
    "kminus": .keypadMinus,
    "kplus": .keypadPlus,
    "kmultiply": .keypadMultiply,
    "kdivide": .keypadDivide,
    "kenter": .keypadEnter,
    "kequal": .keypadEquals,

    "leftmouse": .leftMouse,
    "rightmouse": .rightMouse,
]

private let lookupFrom: [Toolkit.Key: (Notation, bracketed: Bool)] = [
    .escape: ("Esc", bracketed: true),
    .return: ("CR", bracketed: true),
    .tab: ("Tab", bracketed: true),
    .space: ("Space", bracketed: true),
    .backspace: ("BS", bracketed: true),
    .forwardDelete: ("Del", bracketed: true),
    .upArrow: ("Up", bracketed: true),
    .downArrow: ("Down", bracketed: true),
    .leftArrow: ("Left", bracketed: true),
    .rightArrow: ("Right", bracketed: true),
    .pageUp: ("PageUp", bracketed: true),
    .pageDown: ("PageDown", bracketed: true),
    .home: ("Home", bracketed: true),
    .end: ("End", bracketed: true),
    .help: ("Help", bracketed: true),

    .a: ("a", bracketed: false),
    .b: ("b", bracketed: false),
    .c: ("c", bracketed: false),
    .d: ("d", bracketed: false),
    .e: ("e", bracketed: false),
    .f: ("f", bracketed: false),
    .g: ("g", bracketed: false),
    .h: ("h", bracketed: false),
    .i: ("i", bracketed: false),
    .j: ("j", bracketed: false),
    .k: ("k", bracketed: false),
    .l: ("l", bracketed: false),
    .m: ("m", bracketed: false),
    .n: ("n", bracketed: false),
    .o: ("o", bracketed: false),
    .p: ("p", bracketed: false),
    .q: ("q", bracketed: false),
    .r: ("r", bracketed: false),
    .s: ("s", bracketed: false),
    .t: ("t", bracketed: false),
    .u: ("u", bracketed: false),
    .v: ("v", bracketed: false),
    .w: ("w", bracketed: false),
    .x: ("x", bracketed: false),
    .y: ("y", bracketed: false),
    .z: ("z", bracketed: false),

    .zero: ("0", bracketed: false),
    .one: ("1", bracketed: false),
    .two: ("2", bracketed: false),
    .three: ("3", bracketed: false),
    .four: ("4", bracketed: false),
    .five: ("5", bracketed: false),
    .six: ("6", bracketed: false),
    .seven: ("7", bracketed: false),
    .eight: ("8", bracketed: false),
    .nine: ("9", bracketed: false),

    .f1: ("F1", bracketed: true),
    .f2: ("F2", bracketed: true),
    .f3: ("F3", bracketed: true),
    .f4: ("F4", bracketed: true),
    .f5: ("F5", bracketed: true),
    .f6: ("F6", bracketed: true),
    .f7: ("F7", bracketed: true),
    .f8: ("F8", bracketed: true),
    .f9: ("F9", bracketed: true),
    .f10: ("F10", bracketed: true),
    .f11: ("F11", bracketed: true),
    .f12: ("F12", bracketed: true),

    .minus: ("-", bracketed: false),
    .equal: ("=", bracketed: false),
    .leftBracket: ("[", bracketed: false),
    .rightBracket: ("]", bracketed: false),
    .semicolon: (";", bracketed: false),
    .quote: ("'", bracketed: false),
    .backslash: ("\\", bracketed: false),
    .comma: (",", bracketed: false),
    .period: (".", bracketed: false),
    .slash: ("/", bracketed: false),
    .grave: ("`", bracketed: false),

    .keypadZero: ("k0", bracketed: true),
    .keypadOne: ("k1", bracketed: true),
    .keypadTwo: ("k2", bracketed: true),
    .keypadThree: ("k3", bracketed: true),
    .keypadFour: ("k4", bracketed: true),
    .keypadFive: ("k5", bracketed: true),
    .keypadSix: ("k6", bracketed: true),
    .keypadSeven: ("k7", bracketed: true),
    .keypadEight: ("k8", bracketed: true),
    .keypadNine: ("k9", bracketed: true),
    .keypadDecimal: ("kComma", bracketed: true),
    .keypadMinus: ("kMinus", bracketed: true),
    .keypadPlus: ("kPlus", bracketed: true),
    .keypadMultiply: ("kMultiply", bracketed: true),
    .keypadDivide: ("kDivide", bracketed: true),
    .keypadEnter: ("kEnter", bracketed: true),
    .keypadEquals: ("kEqual", bracketed: true),

    .leftMouse: ("LeftMouse", bracketed: true),
    .rightMouse: ("RightMouse", bracketed: true),
]
