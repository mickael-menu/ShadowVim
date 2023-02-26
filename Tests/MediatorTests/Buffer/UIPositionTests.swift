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

final class UIPositionTests: XCTestCase {
    // Buffer positions are 1-indexed.
    func testCreateFromBufferPosition() {
        XCTAssertEqual(
            UIPosition(BufferPosition(line: 2, column: 3)),
            UIPosition(line: 1, column: 2)
        )
        XCTAssertEqual(
            UIPosition(BufferPosition(line: 1, column: 1)),
            UIPosition(line: 0, column: 0)
        )
        // Invalid
        XCTAssertEqual(
            UIPosition(BufferPosition(line: 0, column: 0)),
            UIPosition(line: 0, column: 0)
        )
    }

    // UI positions are 0-indexed.
    func testCreateBufferPosition() {
        XCTAssertEqual(
            BufferPosition(UIPosition(line: 1, column: 2)),
            BufferPosition(line: 2, column: 3)
        )
        XCTAssertEqual(
            BufferPosition(UIPosition(line: 0, column: 0)),
            BufferPosition(line: 1, column: 1)
        )
    }

    func testMoving() {
        XCTAssertEqual(pos(1, 2).moving(line: 3), pos(4, 2))
        XCTAssertEqual(pos(1, 2).moving(column: 3), pos(1, 5))
        XCTAssertEqual(pos(1, 2).moving(line: 3, column: 4), pos(4, 6))

        XCTAssertEqual(pos(4, 3).moving(line: -2), pos(2, 3))
        XCTAssertEqual(pos(4, 3).moving(column: -2), pos(4, 1))
        XCTAssertEqual(pos(4, 3).moving(line: -2, column: -1), pos(2, 2))
    }

    func testMovingOutOfBounds() {
        XCTAssertEqual(pos(1, 2).moving(line: -2), pos(0, 2))
        XCTAssertEqual(pos(1, 2).moving(column: -3), pos(1, 0))
        XCTAssertEqual(pos(1, 2).moving(line: -2, column: -3), pos(0, 0))
    }

    func testCompare() {
        XCTAssertTrue(pos(1, 2) == pos(1, 2))

        XCTAssertTrue(pos(1, 2) < pos(2, 1))
        XCTAssertFalse(pos(2, 1) < pos(1, 2))

        XCTAssertTrue(pos(1, 1) < pos(1, 2))
        XCTAssertFalse(pos(1, 2) < pos(1, 1))
    }

    func testCopy() {
        XCTAssertEqual(pos(1, 2).copy(line: 3), pos(3, 2))
        XCTAssertEqual(pos(1, 2).copy(column: 3), pos(1, 3))
        XCTAssertEqual(pos(1, 2).copy(line: 2, column: 3), pos(2, 3))
    }

    private func pos(_ line: LineIndex, _ column: ColumnIndex) -> UIPosition {
        UIPosition(line: line, column: column)
    }
}
