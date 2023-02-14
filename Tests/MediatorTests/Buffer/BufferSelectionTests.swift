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

@testable import Mediator
import Nvim
import XCTest

final class BufferSelectionTests: XCTestCase {
    let lines = [
        "func helloWorld() {",
        "    print(\"Hello world\")",
        "}",
        "",
    ]

    // MARK: - Insert mode

    // Does nothing when the selection is already of length 0.
    func testAdjustInsertAlreadyLength0() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 5)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    // Collapses a selection of length 1.
    func testAdjustInsertCollapsesLength1() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 6)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel.copy(endColumn: 5)
        )
    }

    // Keeps a selection of length >1, because otherwise it prevents the user
    // from selecting with the mouse (e.g. with a right click on a symbol).
    func testAdjustInsertIgnoresLengthMoreThan1() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 7)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    func testAdjustInsertIgnoresLengthMoreThan1TwoLines() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 1, col: 2)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    // Adjusts on an empty line.
    func testAdjustInsertEmptyLine() {
        let sel = BufferSelection(startLine: 3, col: 0, endLine: 3, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    // MARK: - Replace mode

    // Does nothing when the selection is already of length 0.
    func testAdjustReplaceAlreadyLength0() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 5)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    // Collapses a selection of length 1.
    func testAdjustReplaceCollapsesLength1() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 6)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel.copy(endColumn: 5)
        )
    }

    // Keeps a selection of length >1, because otherwise it prevents the user
    // from selecting with the mouse (e.g. with a right click on a symbol).
    func testAdjustReplaceIgnoresLengthMoreThan1() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 7)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    func testAdjustReplaceIgnoresLengthMoreThan1TwoLines() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 1, col: 2)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    // Adjusts on an empty line.
    func testAdjustReplaceEmptyLine() {
        let sel = BufferSelection(startLine: 3, col: 0, endLine: 3, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    // MARK: - Normal mode

    // Does nothing when the selection is already of length 1.
    func testAdjustNormalAlreadyLength1() {
        var sel = BufferSelection(startLine: 0, col: 0, endLine: 0, col: 1)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )

        sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 6)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )

        sel = BufferSelection(startLine: 0, col: 18, endLine: 0, col: 19)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )
    }

    // Expands a selection of length 0, at the beginning of the line.
    func testAdjustNormalExpandLength0StartOfLine() {
        let sel = BufferSelection(startLine: 0, col: 0, endLine: 0, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(endColumn: 1)
        )
    }

    // Expands a selection of length 0, in the middle of the line.
    func testAdjustNormalExpandLength0MiddleOfLine() {
        let sel = BufferSelection(startLine: 0, col: 4, endLine: 0, col: 4)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(endColumn: 5)
        )
    }

    // Expands a selection of length 0, at the end of the line.
    func testAdjustNormalExpandLength0EndOfLine() {
        let sel = BufferSelection(startLine: 0, col: 19, endLine: 0, col: 19)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(startColumn: 18)
        )
    }

    // Expands a selection of length 0, past the end of the line
    func testAdjustNormalExpandLength0PastEndOfLine() {
        let sel = BufferSelection(startLine: 0, col: 25, endLine: 0, col: 25)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(
                startColumn: 18,
                endColumn: 19
            )
        )
    }

    // Keeps a selection of length >1, because otherwise it prevents the user
    // from selecting with the mouse (e.g. with a right click on a symbol).
    func testAdjustNormalIgnoresLengthMoreThan1() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 0, col: 7)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )
    }

    func testAdjustNormalIgnoresLengthMoreThan1TwoLines() {
        let sel = BufferSelection(startLine: 0, col: 5, endLine: 1, col: 2)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )
    }

    // Adjusts on an empty line.
    func testAdjustNormalEmptyLine() {
        let sel = BufferSelection(startLine: 3, col: 0, endLine: 3, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(endColumn: 1)
        )
    }
}
