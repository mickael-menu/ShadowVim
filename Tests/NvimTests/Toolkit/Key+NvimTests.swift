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

@testable import Nvim
import Toolkit
import XCTest

final class KeyNvimTests: XCTestCase {
    func testNotationOfSingleCharacter() {
        let key = KeyCombo(.a)
        XCTAssertEqual(key.nvimNotation, "a")
    }

    func testNotationOfKeysWithoutModifiers() {
        XCTAssertEqual(KeyCombo(.escape).nvimNotation, "<Esc>")
        XCTAssertEqual(KeyCombo(.return).nvimNotation, "<CR>")
        XCTAssertEqual(KeyCombo(.tab).nvimNotation, "<Tab>")
        XCTAssertEqual(KeyCombo(.space).nvimNotation, "<Space>")
        XCTAssertEqual(KeyCombo(.backspace).nvimNotation, "<BS>")
        XCTAssertEqual(KeyCombo(.forwardDelete).nvimNotation, "<Del>")
        XCTAssertEqual(KeyCombo(.upArrow).nvimNotation, "<Up>")
        XCTAssertEqual(KeyCombo(.downArrow).nvimNotation, "<Down>")
        XCTAssertEqual(KeyCombo(.leftArrow).nvimNotation, "<Left>")
        XCTAssertEqual(KeyCombo(.rightArrow).nvimNotation, "<Right>")
        XCTAssertEqual(KeyCombo(.pageUp).nvimNotation, "<PageUp>")
        XCTAssertEqual(KeyCombo(.pageDown).nvimNotation, "<PageDown>")
        XCTAssertEqual(KeyCombo(.home).nvimNotation, "<Home>")
        XCTAssertEqual(KeyCombo(.end).nvimNotation, "<End>")
        XCTAssertEqual(KeyCombo(.help).nvimNotation, "<Help>")
        XCTAssertEqual(KeyCombo(.a).nvimNotation, "a")
        XCTAssertEqual(KeyCombo(.b).nvimNotation, "b")
        XCTAssertEqual(KeyCombo(.c).nvimNotation, "c")
        XCTAssertEqual(KeyCombo(.d).nvimNotation, "d")
        XCTAssertEqual(KeyCombo(.e).nvimNotation, "e")
        XCTAssertEqual(KeyCombo(.f).nvimNotation, "f")
        XCTAssertEqual(KeyCombo(.g).nvimNotation, "g")
        XCTAssertEqual(KeyCombo(.h).nvimNotation, "h")
        XCTAssertEqual(KeyCombo(.i).nvimNotation, "i")
        XCTAssertEqual(KeyCombo(.j).nvimNotation, "j")
        XCTAssertEqual(KeyCombo(.k).nvimNotation, "k")
        XCTAssertEqual(KeyCombo(.l).nvimNotation, "l")
        XCTAssertEqual(KeyCombo(.m).nvimNotation, "m")
        XCTAssertEqual(KeyCombo(.n).nvimNotation, "n")
        XCTAssertEqual(KeyCombo(.o).nvimNotation, "o")
        XCTAssertEqual(KeyCombo(.p).nvimNotation, "p")
        XCTAssertEqual(KeyCombo(.q).nvimNotation, "q")
        XCTAssertEqual(KeyCombo(.r).nvimNotation, "r")
        XCTAssertEqual(KeyCombo(.s).nvimNotation, "s")
        XCTAssertEqual(KeyCombo(.t).nvimNotation, "t")
        XCTAssertEqual(KeyCombo(.u).nvimNotation, "u")
        XCTAssertEqual(KeyCombo(.v).nvimNotation, "v")
        XCTAssertEqual(KeyCombo(.w).nvimNotation, "w")
        XCTAssertEqual(KeyCombo(.x).nvimNotation, "x")
        XCTAssertEqual(KeyCombo(.y).nvimNotation, "y")
        XCTAssertEqual(KeyCombo(.z).nvimNotation, "z")
        XCTAssertEqual(KeyCombo(.zero).nvimNotation, "0")
        XCTAssertEqual(KeyCombo(.one).nvimNotation, "1")
        XCTAssertEqual(KeyCombo(.two).nvimNotation, "2")
        XCTAssertEqual(KeyCombo(.three).nvimNotation, "3")
        XCTAssertEqual(KeyCombo(.four).nvimNotation, "4")
        XCTAssertEqual(KeyCombo(.five).nvimNotation, "5")
        XCTAssertEqual(KeyCombo(.six).nvimNotation, "6")
        XCTAssertEqual(KeyCombo(.seven).nvimNotation, "7")
        XCTAssertEqual(KeyCombo(.eight).nvimNotation, "8")
        XCTAssertEqual(KeyCombo(.nine).nvimNotation, "9")
        XCTAssertEqual(KeyCombo(.f1).nvimNotation, "<F1>")
        XCTAssertEqual(KeyCombo(.f2).nvimNotation, "<F2>")
        XCTAssertEqual(KeyCombo(.f3).nvimNotation, "<F3>")
        XCTAssertEqual(KeyCombo(.f4).nvimNotation, "<F4>")
        XCTAssertEqual(KeyCombo(.f5).nvimNotation, "<F5>")
        XCTAssertEqual(KeyCombo(.f6).nvimNotation, "<F6>")
        XCTAssertEqual(KeyCombo(.f7).nvimNotation, "<F7>")
        XCTAssertEqual(KeyCombo(.f8).nvimNotation, "<F8>")
        XCTAssertEqual(KeyCombo(.f9).nvimNotation, "<F9>")
        XCTAssertEqual(KeyCombo(.f10).nvimNotation, "<F10>")
        XCTAssertEqual(KeyCombo(.f11).nvimNotation, "<F11>")
        XCTAssertEqual(KeyCombo(.f12).nvimNotation, "<F12>")
        XCTAssertEqual(KeyCombo(.minus).nvimNotation, "-")
        XCTAssertEqual(KeyCombo(.equal).nvimNotation, "=")
        XCTAssertEqual(KeyCombo(.leftBracket).nvimNotation, "[")
        XCTAssertEqual(KeyCombo(.rightBracket).nvimNotation, "]")
        XCTAssertEqual(KeyCombo(.semicolon).nvimNotation, ";")
        XCTAssertEqual(KeyCombo(.quote).nvimNotation, "'")
        XCTAssertEqual(KeyCombo(.backslash).nvimNotation, "\\")
        XCTAssertEqual(KeyCombo(.comma).nvimNotation, ",")
        XCTAssertEqual(KeyCombo(.period).nvimNotation, ".")
        XCTAssertEqual(KeyCombo(.slash).nvimNotation, "/")
        XCTAssertEqual(KeyCombo(.grave).nvimNotation, "`")
        XCTAssertEqual(KeyCombo(.keypadZero).nvimNotation, "<k0>")
        XCTAssertEqual(KeyCombo(.keypadOne).nvimNotation, "<k1>")
        XCTAssertEqual(KeyCombo(.keypadTwo).nvimNotation, "<k2>")
        XCTAssertEqual(KeyCombo(.keypadThree).nvimNotation, "<k3>")
        XCTAssertEqual(KeyCombo(.keypadFour).nvimNotation, "<k4>")
        XCTAssertEqual(KeyCombo(.keypadFive).nvimNotation, "<k5>")
        XCTAssertEqual(KeyCombo(.keypadSix).nvimNotation, "<k6>")
        XCTAssertEqual(KeyCombo(.keypadSeven).nvimNotation, "<k7>")
        XCTAssertEqual(KeyCombo(.keypadEight).nvimNotation, "<k8>")
        XCTAssertEqual(KeyCombo(.keypadNine).nvimNotation, "<k9>")
        XCTAssertEqual(KeyCombo(.keypadDecimal).nvimNotation, "<kComma>")
        XCTAssertEqual(KeyCombo(.keypadMinus).nvimNotation, "<kMinus>")
        XCTAssertEqual(KeyCombo(.keypadPlus).nvimNotation, "<kPlus>")
        XCTAssertEqual(KeyCombo(.keypadMultiply).nvimNotation, "<kMultiply>")
        XCTAssertEqual(KeyCombo(.keypadDivide).nvimNotation, "<kDivide>")
        XCTAssertEqual(KeyCombo(.keypadEnter).nvimNotation, "<kEnter>")
        XCTAssertEqual(KeyCombo(.keypadEquals).nvimNotation, "<kEqual>")
        XCTAssertEqual(KeyCombo(.leftMouse).nvimNotation, "<LeftMouse>")
        XCTAssertEqual(KeyCombo(.rightMouse).nvimNotation, "<RightMouse>")
    }

    func testNotationOfCharacterWithModifiers() {
        let key = KeyCombo(.a, modifiers: [.control, .shift])
        XCTAssertEqual(key.nvimNotation, "<S-C-a>")
    }

    func testNotationOfSpecialKeyWithModifiers() {
        let key = KeyCombo(.tab, modifiers: [.control, .shift])
        XCTAssertEqual(key.nvimNotation, "<S-C-Tab>")
    }

    func testNotationWithASingleModifier() {
        let key = KeyCombo(.a, modifiers: [.shift])
        XCTAssertEqual(key.nvimNotation, "<S-a>")
    }

    func testNotationWithAllModifiers() {
        let key = KeyCombo(.a, modifiers: [.shift, .control, .option, .command])
        XCTAssertEqual(key.nvimNotation, "<S-C-M-D-a>")
    }

    func testKeyComboFromNotationOfKeyWithoutModifiers() {
        XCTAssertEqual(KeyCombo(nvimNotation: "<Esc>"), KeyCombo(.escape))
        XCTAssertEqual(KeyCombo(nvimNotation: "<CR>"), KeyCombo(.return))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Return>"), KeyCombo(.return))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Enter>"), KeyCombo(.return))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Tab>"), KeyCombo(.tab))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Space>"), KeyCombo(.space))
        XCTAssertEqual(KeyCombo(nvimNotation: "<BS>"), KeyCombo(.backspace))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Del>"), KeyCombo(.forwardDelete))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Up>"), KeyCombo(.upArrow))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Down>"), KeyCombo(.downArrow))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Left>"), KeyCombo(.leftArrow))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Right>"), KeyCombo(.rightArrow))
        XCTAssertEqual(KeyCombo(nvimNotation: "<PageUp>"), KeyCombo(.pageUp))
        XCTAssertEqual(KeyCombo(nvimNotation: "<PageDown>"), KeyCombo(.pageDown))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Home>"), KeyCombo(.home))
        XCTAssertEqual(KeyCombo(nvimNotation: "<End>"), KeyCombo(.end))
        XCTAssertEqual(KeyCombo(nvimNotation: "<Help>"), KeyCombo(.help))
        XCTAssertEqual(KeyCombo(nvimNotation: "a"), KeyCombo(.a))
        XCTAssertEqual(KeyCombo(nvimNotation: "b"), KeyCombo(.b))
        XCTAssertEqual(KeyCombo(nvimNotation: "c"), KeyCombo(.c))
        XCTAssertEqual(KeyCombo(nvimNotation: "d"), KeyCombo(.d))
        XCTAssertEqual(KeyCombo(nvimNotation: "e"), KeyCombo(.e))
        XCTAssertEqual(KeyCombo(nvimNotation: "f"), KeyCombo(.f))
        XCTAssertEqual(KeyCombo(nvimNotation: "g"), KeyCombo(.g))
        XCTAssertEqual(KeyCombo(nvimNotation: "h"), KeyCombo(.h))
        XCTAssertEqual(KeyCombo(nvimNotation: "i"), KeyCombo(.i))
        XCTAssertEqual(KeyCombo(nvimNotation: "j"), KeyCombo(.j))
        XCTAssertEqual(KeyCombo(nvimNotation: "k"), KeyCombo(.k))
        XCTAssertEqual(KeyCombo(nvimNotation: "l"), KeyCombo(.l))
        XCTAssertEqual(KeyCombo(nvimNotation: "m"), KeyCombo(.m))
        XCTAssertEqual(KeyCombo(nvimNotation: "n"), KeyCombo(.n))
        XCTAssertEqual(KeyCombo(nvimNotation: "o"), KeyCombo(.o))
        XCTAssertEqual(KeyCombo(nvimNotation: "p"), KeyCombo(.p))
        XCTAssertEqual(KeyCombo(nvimNotation: "q"), KeyCombo(.q))
        XCTAssertEqual(KeyCombo(nvimNotation: "r"), KeyCombo(.r))
        XCTAssertEqual(KeyCombo(nvimNotation: "s"), KeyCombo(.s))
        XCTAssertEqual(KeyCombo(nvimNotation: "t"), KeyCombo(.t))
        XCTAssertEqual(KeyCombo(nvimNotation: "u"), KeyCombo(.u))
        XCTAssertEqual(KeyCombo(nvimNotation: "v"), KeyCombo(.v))
        XCTAssertEqual(KeyCombo(nvimNotation: "w"), KeyCombo(.w))
        XCTAssertEqual(KeyCombo(nvimNotation: "x"), KeyCombo(.x))
        XCTAssertEqual(KeyCombo(nvimNotation: "y"), KeyCombo(.y))
        XCTAssertEqual(KeyCombo(nvimNotation: "z"), KeyCombo(.z))
        XCTAssertEqual(KeyCombo(nvimNotation: "0"), KeyCombo(.zero))
        XCTAssertEqual(KeyCombo(nvimNotation: "1"), KeyCombo(.one))
        XCTAssertEqual(KeyCombo(nvimNotation: "2"), KeyCombo(.two))
        XCTAssertEqual(KeyCombo(nvimNotation: "3"), KeyCombo(.three))
        XCTAssertEqual(KeyCombo(nvimNotation: "4"), KeyCombo(.four))
        XCTAssertEqual(KeyCombo(nvimNotation: "5"), KeyCombo(.five))
        XCTAssertEqual(KeyCombo(nvimNotation: "6"), KeyCombo(.six))
        XCTAssertEqual(KeyCombo(nvimNotation: "7"), KeyCombo(.seven))
        XCTAssertEqual(KeyCombo(nvimNotation: "8"), KeyCombo(.eight))
        XCTAssertEqual(KeyCombo(nvimNotation: "9"), KeyCombo(.nine))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F1>"), KeyCombo(.f1))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F2>"), KeyCombo(.f2))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F3>"), KeyCombo(.f3))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F4>"), KeyCombo(.f4))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F5>"), KeyCombo(.f5))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F6>"), KeyCombo(.f6))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F7>"), KeyCombo(.f7))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F8>"), KeyCombo(.f8))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F9>"), KeyCombo(.f9))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F10>"), KeyCombo(.f10))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F11>"), KeyCombo(.f11))
        XCTAssertEqual(KeyCombo(nvimNotation: "<F12>"), KeyCombo(.f12))
        XCTAssertEqual(KeyCombo(nvimNotation: "-"), KeyCombo(.minus))
        XCTAssertEqual(KeyCombo(nvimNotation: "="), KeyCombo(.equal))
        XCTAssertEqual(KeyCombo(nvimNotation: "["), KeyCombo(.leftBracket))
        XCTAssertEqual(KeyCombo(nvimNotation: "]"), KeyCombo(.rightBracket))
        XCTAssertEqual(KeyCombo(nvimNotation: ";"), KeyCombo(.semicolon))
        XCTAssertEqual(KeyCombo(nvimNotation: "'"), KeyCombo(.quote))
        XCTAssertEqual(KeyCombo(nvimNotation: "\\"), KeyCombo(.backslash))
        XCTAssertEqual(KeyCombo(nvimNotation: ","), KeyCombo(.comma))
        XCTAssertEqual(KeyCombo(nvimNotation: "."), KeyCombo(.period))
        XCTAssertEqual(KeyCombo(nvimNotation: "/"), KeyCombo(.slash))
        XCTAssertEqual(KeyCombo(nvimNotation: "`"), KeyCombo(.grave))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k0>"), KeyCombo(.keypadZero))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k1>"), KeyCombo(.keypadOne))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k2>"), KeyCombo(.keypadTwo))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k3>"), KeyCombo(.keypadThree))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k4>"), KeyCombo(.keypadFour))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k5>"), KeyCombo(.keypadFive))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k6>"), KeyCombo(.keypadSix))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k7>"), KeyCombo(.keypadSeven))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k8>"), KeyCombo(.keypadEight))
        XCTAssertEqual(KeyCombo(nvimNotation: "<k9>"), KeyCombo(.keypadNine))
        XCTAssertEqual(KeyCombo(nvimNotation: "<kComma>"), KeyCombo(.keypadDecimal))
        XCTAssertEqual(KeyCombo(nvimNotation: "<kMinus>"), KeyCombo(.keypadMinus))
        XCTAssertEqual(KeyCombo(nvimNotation: "<kPlus>"), KeyCombo(.keypadPlus))
        XCTAssertEqual(KeyCombo(nvimNotation: "<kMultiply>"), KeyCombo(.keypadMultiply))
        XCTAssertEqual(KeyCombo(nvimNotation: "<kDivide>"), KeyCombo(.keypadDivide))
        XCTAssertEqual(KeyCombo(nvimNotation: "<kEnter>"), KeyCombo(.keypadEnter))
        XCTAssertEqual(KeyCombo(nvimNotation: "<kEqual>"), KeyCombo(.keypadEquals))
        XCTAssertEqual(KeyCombo(nvimNotation: "<LeftMouse>"), KeyCombo(.leftMouse))
        XCTAssertEqual(KeyCombo(nvimNotation: "<RightMouse>"), KeyCombo(.rightMouse))
    }

    func testKeyComboFromNotationOfCharacterWithModifiers() {
        let key = KeyCombo(nvimNotation: "<S-C-a>")
        XCTAssertEqual(key, KeyCombo(.a, modifiers: [.control, .shift]))
    }

    func testKeyComboFromNotationOfSpecialKeyWithModifiers() {
        let key = KeyCombo(nvimNotation: "<S-C-Tab>")
        XCTAssertEqual(key, KeyCombo(.tab, modifiers: [.control, .shift]))
    }

    func testKeyComboFromNotationWithASingleModifier() {
        let key = KeyCombo(nvimNotation: "<S-a>")
        XCTAssertEqual(key, KeyCombo(.a, modifiers: [.shift]))
    }

    func testKeyComboFromNotationWithAllModifiers() {
        let key = KeyCombo(nvimNotation: "<S-C-M-D-a>")
        XCTAssertEqual(key, KeyCombo(.a, modifiers: [.shift, .control, .option, .command]))
    }

    func testKeyComboFromNotationIsCaseInsensitive() {
        XCTAssertEqual(
            KeyCombo(nvimNotation: "<c-A>"),
            KeyCombo(.a, modifiers: .control)
        )
        XCTAssertEqual(
            KeyCombo(nvimNotation: "<s-c-m-d-tab>"),
            KeyCombo(.tab, modifiers: [.shift, .control, .option, .command])
        )
    }

    func testKeyComboFromEmptyNotation() {
        XCTAssertNil(KeyCombo(nvimNotation: ""))
    }

    func testKeyComboFromInvalidNotation() {
        XCTAssertNil(KeyCombo(nvimNotation: "<>"))
        XCTAssertNil(KeyCombo(nvimNotation: "<S-"))
        XCTAssertNil(KeyCombo(nvimNotation: "<S-C-Tab"))
    }
}
