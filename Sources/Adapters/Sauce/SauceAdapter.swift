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
import Sauce
import Toolkit

public final class SauceCGKeyResolver: CGKeyResolver {
    public init() {}

    public func key(for code: CGKeyCode) -> Toolkit.Key? {
        guard let key = Sauce.shared.key(for: Int(code)) else {
            switch code {
            case 179:
                // The 179/fn key is not handled by Sauce
                return .fn
            default:
                return nil
            }
        }
        return lookupTo[key]
    }

    public func code(for key: Toolkit.Key) -> CGKeyCode? {
        guard let key = lookupFrom[key] else {
            switch key {
            case .fn:
                return 179
            default:
                return nil
            }
        }
        return Sauce.shared.keyCode(for: key)
    }
}

private let lookupTo: [SauceKey: Toolkit.Key] = [
    .escape: .escape,
    .return: .return,
    .tab: .tab,
    .space: .space,
    .delete: .backspace,
    .forwardDelete: .forwardDelete,
    .upArrow: .upArrow,
    .downArrow: .downArrow,
    .leftArrow: .leftArrow,
    .rightArrow: .rightArrow,
    .pageUp: .pageUp,
    .pageDown: .pageDown,
    .home: .home,
    .end: .end,
    .help: .help,

    .a: .a,
    .b: .b,
    .c: .c,
    .d: .d,
    .e: .e,
    .f: .f,
    .g: .g,
    .h: .h,
    .i: .i,
    .j: .j,
    .k: .k,
    .l: .l,
    .m: .m,
    .n: .n,
    .o: .o,
    .p: .p,
    .q: .q,
    .r: .r,
    .s: .s,
    .t: .t,
    .u: .u,
    .v: .v,
    .w: .w,
    .x: .x,
    .y: .y,
    .z: .z,

    .zero: .zero,
    .one: .one,
    .two: .two,
    .three: .three,
    .four: .four,
    .five: .five,
    .six: .six,
    .seven: .seven,
    .eight: .eight,
    .nine: .nine,

    .f1: .f1,
    .f2: .f2,
    .f3: .f3,
    .f4: .f4,
    .f5: .f5,
    .f6: .f6,
    .f7: .f7,
    .f8: .f8,
    .f9: .f9,
    .f10: .f10,
    .f11: .f11,
    .f12: .f12,

    .minus: .minus,
    .equal: .equal,
    .leftBracket: .leftBracket,
    .rightBracket: .rightBracket,
    .semicolon: .semicolon,
    .quote: .quote,
    .backslash: .backslash,
    .comma: .comma,
    .period: .period,
    .slash: .slash,
    .grave: .grave,

    .keypadZero: .keypadZero,
    .keypadOne: .keypadOne,
    .keypadTwo: .keypadTwo,
    .keypadThree: .keypadThree,
    .keypadFour: .keypadFour,
    .keypadFive: .keypadFive,
    .keypadSix: .keypadSix,
    .keypadSeven: .keypadSeven,
    .keypadEight: .keypadEight,
    .keypadNine: .keypadNine,
    .keypadDecimal: .keypadDecimal,
    .keypadMinus: .keypadMinus,
    .keypadPlus: .keypadPlus,
    .keypadMultiply: .keypadMultiply,
    .keypadDivide: .keypadDivide,
    .keypadClear: .keypadClear,
    .keypadEnter: .keypadEnter,
    .keypadEquals: .keypadEquals,

    .yen: .yen,
    .underscore: .underscore,
    .keypadComma: .keypadComma,
    .eisu: .eisu,
    .kana: .kana,
    .atSign: .atSign,
    .caret: .caret,
    .colon: .colon,

    .section: .section,
]

private let lookupFrom: [Toolkit.Key: SauceKey] = [
    .escape: .escape,
    .return: .return,
    .tab: .tab,
    .space: .space,
    .backspace: .delete,
    .forwardDelete: .forwardDelete,
    .upArrow: .upArrow,
    .downArrow: .downArrow,
    .leftArrow: .leftArrow,
    .rightArrow: .rightArrow,
    .pageUp: .pageUp,
    .pageDown: .pageDown,
    .home: .home,
    .end: .end,
    .help: .help,

    .a: .a,
    .b: .b,
    .c: .c,
    .d: .d,
    .e: .e,
    .f: .f,
    .g: .g,
    .h: .h,
    .i: .i,
    .j: .j,
    .k: .k,
    .l: .l,
    .m: .m,
    .n: .n,
    .o: .o,
    .p: .p,
    .q: .q,
    .r: .r,
    .s: .s,
    .t: .t,
    .u: .u,
    .v: .v,
    .w: .w,
    .x: .x,
    .y: .y,
    .z: .z,

    .zero: .zero,
    .one: .one,
    .two: .two,
    .three: .three,
    .four: .four,
    .five: .five,
    .six: .six,
    .seven: .seven,
    .eight: .eight,
    .nine: .nine,

    .f1: .f1,
    .f2: .f2,
    .f3: .f3,
    .f4: .f4,
    .f5: .f5,
    .f6: .f6,
    .f7: .f7,
    .f8: .f8,
    .f9: .f9,
    .f10: .f10,
    .f11: .f11,
    .f12: .f12,

    .minus: .minus,
    .equal: .equal,
    .leftBracket: .leftBracket,
    .rightBracket: .rightBracket,
    .semicolon: .semicolon,
    .quote: .quote,
    .backslash: .backslash,
    .comma: .comma,
    .period: .period,
    .slash: .slash,
    .grave: .grave,

    .keypadZero: .keypadZero,
    .keypadOne: .keypadOne,
    .keypadTwo: .keypadTwo,
    .keypadThree: .keypadThree,
    .keypadFour: .keypadFour,
    .keypadFive: .keypadFive,
    .keypadSix: .keypadSix,
    .keypadSeven: .keypadSeven,
    .keypadEight: .keypadEight,
    .keypadNine: .keypadNine,
    .keypadDecimal: .keypadDecimal,
    .keypadMinus: .keypadMinus,
    .keypadPlus: .keypadPlus,
    .keypadMultiply: .keypadMultiply,
    .keypadDivide: .keypadDivide,
    .keypadClear: .keypadClear,
    .keypadEnter: .keypadEnter,
    .keypadEquals: .keypadEquals,

    .yen: .yen,
    .underscore: .underscore,
    .keypadComma: .keypadComma,
    .eisu: .eisu,
    .kana: .kana,
    .atSign: .atSign,
    .caret: .caret,
    .colon: .colon,

    .section: .section,
]
