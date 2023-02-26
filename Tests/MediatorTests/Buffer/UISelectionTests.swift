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
import XCTest

final class UISelectionTests: XCTestCase {
    let lines = [
        "func helloWorld() {",
        "    print(\"Hello world\")",
        "}",
        "",
    ]

    // MARK: - Adjust to Insert mode

    // Does nothing when the selection is already of length 0.
    func testAdjustInsertAlreadyLength0() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 5)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    // Collapses a selection of length 1.
    func testAdjustInsertCollapsesLength1() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 6)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel.copy(endColumn: 5)
        )
    }

    // Keeps a selection of length >1, because otherwise it prevents the user
    // from selecting with the mouse (e.g. with a right click on a symbol).
    func testAdjustInsertIgnoresLengthMoreThan1() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 7)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    func testAdjustInsertIgnoresLengthMoreThan1TwoLines() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 1, col: 2)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    // Adjusts on an empty line.
    func testAdjustInsertEmptyLine() {
        let sel = UISelection(startLine: 3, col: 0, endLine: 3, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .insert, lines: lines),
            sel
        )
    }

    // MARK: - Adjust to Replace mode

    // Does nothing when the selection is already of length 0.
    func testAdjustReplaceAlreadyLength0() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 5)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    // Collapses a selection of length 1.
    func testAdjustReplaceCollapsesLength1() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 6)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel.copy(endColumn: 5)
        )
    }

    // Keeps a selection of length >1, because otherwise it prevents the user
    // from selecting with the mouse (e.g. with a right click on a symbol).
    func testAdjustReplaceIgnoresLengthMoreThan1() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 7)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    func testAdjustReplaceIgnoresLengthMoreThan1TwoLines() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 1, col: 2)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    // Adjusts on an empty line.
    func testAdjustReplaceEmptyLine() {
        let sel = UISelection(startLine: 3, col: 0, endLine: 3, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .replace, lines: lines),
            sel
        )
    }

    // MARK: - Adjust to Normal mode

    // Does nothing when the selection is already of length 1.
    func testAdjustNormalAlreadyLength1() {
        var sel = UISelection(startLine: 0, col: 0, endLine: 0, col: 1)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )

        sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 6)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )

        sel = UISelection(startLine: 0, col: 18, endLine: 0, col: 19)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )
    }

    // Expands a selection of length 0, at the beginning of the line.
    func testAdjustNormalExpandLength0StartOfLine() {
        let sel = UISelection(startLine: 0, col: 0, endLine: 0, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(endColumn: 1)
        )
    }

    // Expands a selection of length 0, in the middle of the line.
    func testAdjustNormalExpandLength0MiddleOfLine() {
        let sel = UISelection(startLine: 0, col: 4, endLine: 0, col: 4)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(endColumn: 5)
        )
    }

    // Expands a selection of length 0, at the end of the line.
    func testAdjustNormalExpandLength0EndOfLine() {
        let sel = UISelection(startLine: 0, col: 19, endLine: 0, col: 19)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(startColumn: 18)
        )
    }

    // Expands a selection of length 0, past the end of the line
    func testAdjustNormalExpandLength0PastEndOfLine() {
        let sel = UISelection(startLine: 0, col: 25, endLine: 0, col: 25)
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
        let sel = UISelection(startLine: 0, col: 5, endLine: 0, col: 7)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )
    }

    func testAdjustNormalIgnoresLengthMoreThan1TwoLines() {
        let sel = UISelection(startLine: 0, col: 5, endLine: 1, col: 2)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel
        )
    }

    // Adjusts on an empty line.
    func testAdjustNormalEmptyLine() {
        let sel = UISelection(startLine: 3, col: 0, endLine: 3, col: 0)
        XCTAssertEqual(
            sel.adjust(to: .normal, lines: lines),
            sel.copy(endColumn: 1)
        )
    }

    // MARK: - Join selections

    func testJoin0Selections() {
        let selections = [UISelection]()
        XCTAssertNil(selections.joined())
    }

    func testJoin1Selection() {
        let selection = UISelection(startLine: 1, col: 5, endLine: 2, col: 7)
        XCTAssertEqual([selection].joined(), selection)
    }

    func testJoinMultipleSelections() {
        let selections = [
            UISelection(startLine: 2, col: 7, endLine: 3, col: 9),
            UISelection(startLine: 3, col: 9, endLine: 4, col: 11),
            UISelection(startLine: 1, col: 5, endLine: 2, col: 7),
        ]
        XCTAssertEqual(
            selections.joined(),
            UISelection(startLine: 1, col: 5, endLine: 4, col: 11)
        )
    }

    func testJoinOverlappingSelections() {
        let selections = [
            UISelection(startLine: 2, col: 6, endLine: 3, col: 9),
            UISelection(startLine: 1, col: 5, endLine: 2, col: 7),
            UISelection(startLine: 3, col: 9, endLine: 4, col: 11),
        ]
        XCTAssertEqual(
            selections.joined(),
            UISelection(startLine: 1, col: 5, endLine: 4, col: 11)
        )
    }
}

extension UISelection {
    init(
        startLine: LineIndex,
        col startColumn: ColumnIndex,
        endLine: LineIndex,
        col endColumn: ColumnIndex
    ) {
        self.init(
            start: UIPosition(line: startLine, column: startColumn),
            end: UIPosition(line: endLine, column: endColumn)
        )
    }
}
