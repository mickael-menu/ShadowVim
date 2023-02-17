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
import XCTest

final class KeystrokeTests: XCTestCase {
    func testNotationOfSingleCharacter() {
        let keystroke = Keystroke(.ascii("a"))
        XCTAssertEqual(keystroke.notation, "a")
    }

    func testNotationOfSingleHyphen() {
        let keystroke = Keystroke(.ascii("-"))
        XCTAssertEqual(keystroke.notation, "-")
    }

    func testNotationOfLessThan() {
        // Note: notations like <CR> are translated, so "<" is special.
        // To input a literal "<", send <LT>.
        let keystroke = Keystroke(.ascii("<"))
        XCTAssertEqual(keystroke.notation, "<LT>")
    }

    func testNotationOfSingleKey() {
        let keystroke = Keystroke(.key(.tab))
        XCTAssertEqual(keystroke.notation, "<Tab>")
    }

    func testNotationOfCharacterWithModifiers() {
        let keystroke = Keystroke(.ascii("a"), modifiers: [.control, .shift])
        XCTAssertEqual(keystroke.notation, "<S-C-a>")
    }

    func testNotationOfHyphenWithModifiers() {
        let keystroke = Keystroke(.ascii("-"), modifiers: .control)
        XCTAssertEqual(keystroke.notation, "<C-\\->")
    }

    func testNotationOfLessThanWithModifiers() {
        let keystroke = Keystroke(.ascii("<"), modifiers: .control)
        XCTAssertEqual(keystroke.notation, "<C-LT>")
    }

    func testNotationOfKeyWithModifiers() {
        let keystroke = Keystroke(.key(.tab), modifiers: [.control, .shift])
        XCTAssertEqual(keystroke.notation, "<S-C-Tab>")
    }

    func testNotationWithASingleModifier() {
        let keystroke = Keystroke(.ascii("a"), modifiers: [.shift])
        XCTAssertEqual(keystroke.notation, "<S-a>")
    }

    func testNotationWithAllModifiers() {
        let keystroke = Keystroke(.ascii("a"), modifiers: [.shift, .control, .option, .command])
        XCTAssertEqual(keystroke.notation, "<S-C-M-D-a>")
    }

    func testKeystrokeFromNotationOfSingleCharacter() {
        let keystroke = Keystroke(notation: "a")
        XCTAssertEqual(keystroke, Keystroke(.ascii("a")))
    }

    func testKeystrokeFromNotationWithSeveralCharacters() {
        let keystroke = Keystroke(notation: "abc")
        XCTAssertEqual(keystroke, Keystroke(.ascii("abc")))
    }

    func testKeystrokeFromNotationOfLessThan() {
        let keystroke = Keystroke(notation: "<LT>")
        XCTAssertEqual(keystroke, Keystroke(.key(.lt)))
    }

    func testKeystrokeFromNotationOfSingleKey() {
        let keystroke = Keystroke(notation: "<Tab>")
        XCTAssertEqual(keystroke, Keystroke(.key(.tab)))
    }

    func testKeystrokeFromNotationOfCharacterWithModifiers() {
        let keystroke = Keystroke(notation: "<S-C-a>")
        XCTAssertEqual(keystroke, Keystroke(.ascii("a"), modifiers: [.control, .shift]))
    }

    func testKeystrokeFromNotationOfHyphenWithModifiers() {
        let keystroke = Keystroke(notation: "<C-\\->")
        XCTAssertEqual(keystroke, Keystroke(.ascii("-"), modifiers: .control))
    }

    func testKeystrokeFromNotationOfLessThanWithModifiers() {
        let keystroke = Keystroke(notation: "<C-<>")
        XCTAssertEqual(keystroke, Keystroke(.ascii("<"), modifiers: .control))
    }

    func testKeystrokeFromNotationOfKeyWithModifiers() {
        let keystroke = Keystroke(notation: "<S-C-Tab>")
        XCTAssertEqual(keystroke, Keystroke(.key(.tab), modifiers: [.control, .shift]))
    }

    func testKeystrokeFromNotationWithASingleModifier() {
        let keystroke = Keystroke(notation: "<S-a>")
        XCTAssertEqual(keystroke, Keystroke(.ascii("a"), modifiers: [.shift]))
    }

    func testKeystrokeFromNotationWithAllModifiers() {
        let keystroke = Keystroke(notation: "<S-C-M-D-a>")
        XCTAssertEqual(keystroke, Keystroke(.ascii("a"), modifiers: [.shift, .control, .option, .command]))
    }

    func testKeystrokeFromNotationIsCaseInsensitive() {
        let keystroke = Keystroke(notation: "<s-c-m-d-tab>")
        XCTAssertEqual(keystroke, Keystroke(.key(.tab), modifiers: [.shift, .control, .option, .command]))
    }

    func testKeystrokeFromEmptyNotation() {
        XCTAssertNil(Keystroke(notation: ""))
    }

    func testKeystrokeFromInvalidNotation() {
        XCTAssertNil(Keystroke(notation: "<>"))
        XCTAssertNil(Keystroke(notation: "<S-"))
        XCTAssertNil(Keystroke(notation: "<S-C-Tab"))
    }
}
