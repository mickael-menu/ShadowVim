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

final class NvimStateTests: XCTestCase {
    let lines = [
        "func helloWorld() -> Bool {",
        "    print(\"Hello, world\")",
        "    return true",
        "}",
    ]

    private func state(mode: Mode, position: BufferPosition, visual: BufferPosition) -> BufferState.NvimState {
        BufferState.NvimState(
            cursor: Cursor(mode: mode, position: position, visual: visual),
            lines: lines
        )
    }

    // MARK: - UI selections from Nvim state

    // In Normal mode, only the cursor position is used and a padding is added
    // to form a 1-character block.
    func testSelectionsForNormalMode() {
        let state = state(
            mode: .normal,
            position: BufferPosition(line: 2, column: 3),
            visual: BufferPosition(line: 2, column: 3)
        )
        XCTAssertEqual(
            state.uiSelections(),
            [
                UISelection(
                    start: UIPosition(line: 1, column: 2),
                    end: UIPosition(line: 1, column: 3)
                ),
            ]
        )
    }

    // In Insert or Replace modes, only the cursor position is used for the
    // selection.
    func testSelectionsForInsertOrReplaceModes() {
        func test(_ mode: Mode) {
            let state = state(
                mode: mode,
                position: BufferPosition(line: 2, column: 3),
                visual: BufferPosition(line: 3, column: 5)
            )
            XCTAssertEqual(
                state.uiSelections(),
                [
                    UISelection(
                        start: UIPosition(line: 1, column: 2),
                        end: UIPosition(line: 1, column: 2)
                    ),
                ]
            )
        }

        test(.insert)
        test(.replace)
    }

    // In Visual or Select modes, the cursor and visual positions are sorted
    // and a padding is added to always have a selection of at least one
    // character.
    func testSelectionsForVisualOrSelectModes() {
        func test(_ mode: Mode) {
            var state = state(
                mode: mode,
                position: BufferPosition(line: 2, column: 3),
                visual: BufferPosition(line: 2, column: 3)
            )

            // Equal cursor and visual positions.
            XCTAssertEqual(
                state.uiSelections(),
                [
                    UISelection(
                        start: UIPosition(line: 1, column: 2),
                        end: UIPosition(line: 1, column: 3)
                    ),
                ]
            )

            // Cursor before visual.
            state.cursor.position = BufferPosition(line: 1, column: 5)
            XCTAssertEqual(
                state.uiSelections(),
                [
                    UISelection(
                        start: UIPosition(line: 0, column: 4),
                        end: UIPosition(line: 1, column: 3)
                    ),
                ]
            )

            // Cursor after visual.
            state.cursor.position = BufferPosition(line: 3, column: 2)
            XCTAssertEqual(
                state.uiSelections(),
                [
                    UISelection(
                        start: UIPosition(line: 1, column: 2),
                        end: UIPosition(line: 2, column: 2)
                    ),
                ]
            )
        }

        test(.visual)
        test(.select)
        test(.visualBlock)
        test(.selectBlock)
    }

    /// In Visual or Select Line Modes, the visual and cursor positions are
    /// sorted and extended to fit their line contents.
    func testSelectionsForVisualOrSelectLineModes() {
        func test(_ mode: Mode) {
            var state = state(
                mode: mode,
                position: BufferPosition(line: 2, column: 3),
                visual: BufferPosition(line: 2, column: 3)
            )

            // Equal cursor and visual positions.
            XCTAssertEqual(
                state.uiSelections(),
                [
                    UISelection(
                        start: UIPosition(line: 1, column: 0),
                        end: UIPosition(line: 1, column: 26)
                    ),
                ]
            )

            // Cursor before visual.
            state.cursor.position = BufferPosition(line: 1, column: 5)
            XCTAssertEqual(
                state.uiSelections(),
                [
                    UISelection(
                        start: UIPosition(line: 0, column: 0),
                        end: UIPosition(line: 1, column: 26)
                    ),
                ]
            )

            // Cursor after visual.
            state.cursor.position = BufferPosition(line: 3, column: 2)
            XCTAssertEqual(
                state.uiSelections(),
                [
                    UISelection(
                        start: UIPosition(line: 1, column: 0),
                        end: UIPosition(line: 2, column: 16)
                    ),
                ]
            )
        }

        test(.visualLine)
        test(.selectLine)
    }

    /// With other modes, no selections is generated.
    func testOtherModes() {
        func test(_ mode: Mode) {
            let state = state(
                mode: mode,
                position: BufferPosition(line: 2, column: 3),
                visual: BufferPosition(line: 2, column: 3)
            )
            XCTAssertEqual(state.uiSelections(), [])
        }

        test(.cmdline)
        test(.hitEnterPrompt)
        test(.shell)
        test(.terminal)
    }
}
