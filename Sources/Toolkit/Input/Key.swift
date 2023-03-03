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

/// A key combined with optional modifiers.
public struct KeyCombo: Hashable {
    public let key: Key
    public let modifiers: InputModifiers

    public init(_ key: Key, modifiers: InputModifiers = .none) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Virtual keyboard keys.
///
/// This is largely inspired by Sauce.
public enum Key: Hashable {
    case escape
    case `return`
    case tab
    case space
    case backspace
    case forwardDelete
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
    case pageUp
    case pageDown
    case home
    case end
    case help

    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine

    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12

    case minus
    case equal
    case leftBracket
    case rightBracket
    case semicolon
    case quote
    case backslash
    case comma
    case period
    case slash
    case grave

    case keypadZero
    case keypadOne
    case keypadTwo
    case keypadThree
    case keypadFour
    case keypadFive
    case keypadSix
    case keypadSeven
    case keypadEight
    case keypadNine
    case keypadDecimal
    case keypadMinus
    case keypadPlus
    case keypadMultiply
    case keypadDivide
    case keypadClear
    case keypadEnter
    case keypadEquals

    // Keycodes for JIS keyboard only
    case yen
    case underscore
    case keypadComma
    case eisu
    case kana
    case atSign
    case caret
    case colon

    // Keycodes for ISO keyboard only
    case section

    public var isNonPrintableCharacter: Bool {
        Key.nonPrintableKeys.contains(self)
    }

    private static let nonPrintableKeys: [Key] = [
        .escape, .return, .backspace, .forwardDelete,
        .upArrow, .downArrow, .leftArrow, .rightArrow,
        .pageUp, .pageDown, .home, .end, .help,
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
        .keypadClear, .keypadEnter,
    ]
}
