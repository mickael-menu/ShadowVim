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

final class BufferStateTests: XCTestCase {
    let nvimLines = [
        "func hello() {",
        "    print(\"Hello world\")",
        "}",
    ]

    let uiLines = [
        "func helloWorld() -> Bool {",
        "    print(\"Hello, world\")",
        "    return true",
        "}",
    ]

    let nvimCursor = Cursor(
        position: BufferPosition(line: 1, column: 20),
        mode: .normal
    )

    let uiSelection = BufferSelection(
        start: BufferPosition(line: 1, column: 5),
        end: BufferPosition(line: 2, column: 8)
    )

    lazy var initialState = BufferState(
        token: .free,
        nvim: .init(cursor: nvimCursor, lines: nvimLines),
        ui: .init(selection: uiSelection, lines: uiLines)
    )

    let bufLinesEvent = BufLinesEvent(changedTick: 42, firstLine: 0, lastLine: 1, lineData: [])

    // MARK: - Token timeout

    // The timeout is ignored when the token is free.
    func testTokenDidTimeoutWhileFree() {
        let state = initialState.copy(token: .free)
        assert(
            initial: state,
            on: .tokenDidTimeout,
            expected: state,
            actions: []
        )
    }

    // The token is released when timed out while synchronizing.
    func testTokenDidTimeoutWhileSynchronizing() {
        assert(
            initial: initialState.copy(token: .synchronizing),
            on: .tokenDidTimeout,
            expected: initialState.copy(token: .free),
            actions: []
        )
    }

    // The buffers are synchronized when timed out while acquired.
    func testTokenDidTimeoutWhileAcquired() {
        assert(
            initial: initialState.copy(token: .acquired(owner: .nvim)),
            on: .tokenDidTimeout,
            expected: initialState.copy(token: .synchronizing),
            actions: [
                .updateUI(
                    lines: nvimLines,
                    diff: nvimLines.difference(from: uiLines),
                    selection: BufferSelection(
                        start: nvimCursor.position,
                        end: nvimCursor.position.moving(column: +1)
                    )
                ),
                .startTokenTimeout,
            ]
        )

        assert(
            initial: initialState.copy(token: .acquired(owner: .ui)),
            on: .tokenDidTimeout,
            expected: initialState.copy(token: .synchronizing),
            actions: [
                .updateNvim(
                    lines: uiLines,
                    diff: uiLines.difference(from: nvimLines),
                    cursorPosition: uiSelection.start
                ),
                .startTokenTimeout,
            ]
        )
    }

    // The buffers are not resynchronized when already synchronized.
    func testTokenDidTimeoutIgnoredWhenAlreadySynchronized() {
        let state = initialState.copy(
            token: .acquired(owner: .nvim),
            nvimLines: uiLines
        )

        assert(
            initial: state,
            on: .tokenDidTimeout,
            expected: state.copy(token: .free),
            actions: []
        )
    }

    // An empty last line in the UI buffer is ignored to compare if the
    // synchronization is needed.
    // Some apps (like Xcode) systematically add an empty line at the end of a
    // document. To make sure the comparison won't fail in this case, it is
    // ignored.
    func testFinalEOLInUIBufferIsIgnored() {
        let state = initialState.copy(
            token: .acquired(owner: .nvim),
            nvimLines: uiLines,
            uiLines: uiLines + [""]
        )

        assert(
            initial: state,
            on: .tokenDidTimeout,
            expected: state.copy(token: .free),
            actions: []
        )
    }

    // MARK: - User refresh request

    // Authorized while the edition token is free (from UI).
    func testRefreshRequestWhileFree() {
        assert(
            initial: initialState,
            on: .userDidRequestRefresh(source: .nvim),
            expected: initialState.copy(token: .synchronizing),
            actions: [
                .updateUI(
                    lines: nvimLines,
                    diff: nvimLines.difference(from: uiLines),
                    selection: BufferSelection(
                        start: nvimCursor.position,
                        end: nvimCursor.position.moving(column: +1)
                    )
                ),
                .startTokenTimeout,
            ]
        )

        assert(
            initial: initialState,
            on: .userDidRequestRefresh(source: .ui),
            expected: initialState.copy(token: .synchronizing),
            actions: [
                .updateNvim(
                    lines: uiLines,
                    diff: uiLines.difference(from: nvimLines),
                    cursorPosition: uiSelection.start
                ),
                .startTokenTimeout,
            ]
        )
    }

    // Rejected if the token is busy (acquired).
    func testRefreshRequestWhileAcquired() {
        let state = initialState.copy(token: .acquired(owner: .nvim))
        assert(
            initial: state,
            on: .userDidRequestRefresh(source: .ui),
            expected: state,
            actions: [.bell]
        )
    }

    // Rejected if the token is busy (synchronizing).
    func testRefreshRequestWhileSynchronizing() {
        let state = initialState.copy(token: .synchronizing)
        assert(
            initial: state,
            on: .userDidRequestRefresh(source: .ui),
            expected: state,
            actions: [.bell]
        )
    }

    // The refresh is ignored when the buffers are already synchronized.
    func testRefreshRequestIgnoredWhenSynchronized() {
        let state = initialState.copy(nvimLines: uiLines)

        assert(
            initial: state,
            on: .userDidRequestRefresh(source: .nvim),
            expected: state,
            actions: []
        )
    }

    // MARK: - Nvim buffer changes

    // The token is acquired when free and the update sent to the UI buffer.
    func testNvimBufferDidChangeWhileFree() {
        let newLines = nvimLines + ["An addition"]

        assert(
            initial: initialState.copy(token: .free),
            on: .nvimBufferDidChange(lines: newLines, event: bufLinesEvent),
            expected: initialState.copy(
                token: .acquired(owner: .nvim),
                nvimLines: newLines
            ),
            actions: [
                .startTokenTimeout,
                .updateUIPartialLines(event: bufLinesEvent),
                .updateUISelection(BufferSelection(
                    start: nvimCursor.position,
                    end: nvimCursor.position.moving(column: +1)
                )),
            ]
        )
    }

    // The update is sent to the UI buffer when the token is already acquired for Nvim.
    func testNvimBufferDidChangeWhileAlreadyAcquired() {
        let newLines = nvimLines + ["An addition"]

        assert(
            initial: initialState.copy(token: .acquired(owner: .nvim)),
            on: .nvimBufferDidChange(lines: newLines, event: bufLinesEvent),
            expected: initialState.copy(
                token: .acquired(owner: .nvim),
                nvimLines: newLines
            ),
            actions: [
                .startTokenTimeout,
                .updateUIPartialLines(event: bufLinesEvent),
                .updateUISelection(BufferSelection(
                    start: nvimCursor.position,
                    end: nvimCursor.position.moving(column: +1)
                )),
            ]
        )
    }

    // Changes are not sent back to the UI if the token is acquired by it.
    func testNvimBufferDidChangeIgnoredWhileAcquiredByUI() {
        let newLines = nvimLines + ["An addition"]
        let state = initialState.copy(token: .acquired(owner: .ui))

        assert(
            initial: state,
            on: .nvimBufferDidChange(lines: newLines, event: bufLinesEvent),
            expected: state.copy(nvimLines: newLines),
            actions: []
        )
    }

    // MARK: - Nvim cursor changes

    // The token is acquired when free and the update sent to the UI buffer.
    func testNvimCursorDidChangeWhileFree() {
        let cursor = Cursor(
            position: BufferPosition(line: 4, column: 2),
            mode: .insert
        )

        assert(
            initial: initialState.copy(token: .free),
            on: .nvimCursorDidChange(cursor),
            expected: initialState.copy(
                token: .acquired(owner: .nvim),
                nvimCursor: cursor
            ),
            actions: [
                .startTokenTimeout,
                .updateUISelection(BufferSelection(
                    start: cursor.position,
                    end: cursor.position
                )),
            ]
        )
    }

    // The update is sent to the UI buffer when the token is already acquired for Nvim.
    func testNvimCursorDidChangeWhileAlreadyAcquired() {
        let cursor = Cursor(
            position: BufferPosition(line: 4, column: 2),
            mode: .insert
        )

        assert(
            initial: initialState.copy(token: .acquired(owner: .nvim)),
            on: .nvimCursorDidChange(cursor),
            expected: initialState.copy(
                token: .acquired(owner: .nvim),
                nvimCursor: cursor
            ),
            actions: [
                .startTokenTimeout,
                .updateUISelection(BufferSelection(
                    start: cursor.position,
                    end: cursor.position
                )),
            ]
        )
    }

    // Changes are not sent back to the UI if the token is acquired by it.
    func testNvimCursorDidChangeIgnoredWhileAcquiredByUI() {
        let cursor = Cursor(
            position: BufferPosition(line: 4, column: 2),
            mode: .insert
        )
        let state = initialState.copy(token: .acquired(owner: .ui))

        assert(
            initial: state,
            on: .nvimCursorDidChange(cursor),
            expected: state.copy(nvimCursor: cursor),
            actions: []
        )
    }

    // MARK: UI focus

    // The UI state is updated with the given data, then synchronized back to Nvim.
    func testUIDidFocusWhileFree() {
        let newLines = uiLines + ["An addition"]
        let newSelection = uiSelection.copy(startLine: 42)

        assert(
            initial: initialState.copy(token: .free),
            on: .uiDidFocus(lines: newLines, selection: newSelection),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiLines: newLines,
                uiSelection: newSelection
            ),
            actions: [
                .startTokenTimeout,
                .updateNvim(
                    lines: newLines,
                    diff: newLines.difference(from: nvimLines),
                    cursorPosition: newSelection.start
                ),
            ]
        )
    }

    // The UI state is updated with the given data, then synchronized back to Nvim when already acquired by the UI.
    func testUIDidFocusWhileAcquiredByUI() {
        let newLines = uiLines + ["An addition"]
        let newSelection = uiSelection.copy(startLine: 42)

        assert(
            initial: initialState.copy(token: .acquired(owner: .ui)),
            on: .uiDidFocus(lines: newLines, selection: newSelection),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiLines: newLines,
                uiSelection: newSelection
            ),
            actions: [
                .startTokenTimeout,
                .updateNvim(
                    lines: newLines,
                    diff: newLines.difference(from: nvimLines),
                    cursorPosition: newSelection.start
                ),
            ]
        )
    }

    // The UI state is updated but not synchronized back to Nvim when busy (acquired by Nvim).
    func testUIDidFocusWhileAcquiredByNvim() {
        let newLines = uiLines + ["An addition"]
        let newSelection = uiSelection.copy(startLine: 42)

        assert(
            initial: initialState.copy(token: .acquired(owner: .nvim)),
            on: .uiDidFocus(lines: newLines, selection: newSelection),
            expected: initialState.copy(
                token: .acquired(owner: .nvim),
                uiLines: newLines,
                uiSelection: newSelection
            ),
            actions: []
        )
    }

    // The UI state is updated but not synchronized back to Nvim when busy (synchronizing).
    func testUIDidFocusWhileSynchronizing() {
        let newLines = uiLines + ["An addition"]
        let newSelection = uiSelection.copy(startLine: 42)

        assert(
            initial: initialState.copy(token: .synchronizing),
            on: .uiDidFocus(lines: newLines, selection: newSelection),
            expected: initialState.copy(
                token: .synchronizing,
                uiLines: newLines,
                uiSelection: newSelection
            ),
            actions: []
        )
    }

    // MARK: - UI buffer changes

    // The token is acquired when free and the update sent to the Nvim buffer.
    func testUIBufferDidChangeWhileFree() {
        let newLines = uiLines + ["An addition"]

        assert(
            initial: initialState.copy(token: .free),
            on: .uiBufferDidChange(lines: newLines),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiLines: newLines
            ),
            actions: [
                .startTokenTimeout,
                .updateNvim(
                    lines: newLines,
                    diff: newLines.difference(from: nvimLines),
                    cursorPosition: uiSelection.start
                ),
            ]
        )
    }

    // The update is sent to the Nvim buffer when the token is already acquired for the UI.
    func testUIBufferDidChangeWhileAlreadyAcquired() {
        let newLines = uiLines + ["An addition"]

        assert(
            initial: initialState.copy(token: .acquired(owner: .ui)),
            on: .uiBufferDidChange(lines: newLines),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiLines: newLines
            ),
            actions: [
                .startTokenTimeout,
                .updateNvim(
                    lines: newLines,
                    diff: newLines.difference(from: nvimLines),
                    cursorPosition: uiSelection.start
                ),
            ]
        )
    }

    // Changes are not sent back to Nvim if the token is acquired by it.
    func testUIBufferDidChangeIgnoredWhileAcquiredByNvim() {
        let newLines = uiLines + ["An addition"]
        let state = initialState.copy(token: .acquired(owner: .nvim))

        assert(
            initial: state,
            on: .uiBufferDidChange(lines: newLines),
            expected: state.copy(uiLines: newLines),
            actions: []
        )
    }

    // MARK: - UI selection changes

    // The token is acquired when free and the update sent to the Nvim buffer.
    func testUISelectionDidChangeWhileFree() {
        let selection = BufferSelection(
            startLine: 1, col: 2,
            endLine: 1, col: 3
        )

        assert(
            initial: initialState.copy(token: .free),
            on: .uiSelectionDidChange(selection),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiSelection: selection.copy(
                    endLine: selection.start.line,
                    endColumn: selection.start.column + 1
                )
            ),
            actions: [
                .startTokenTimeout,
                .updateNvimCursor(selection.start),
            ]
        )
    }

    // The update is sent to the Nvim buffer when the token is already acquired by the UI.
    func testUISelectionDidChangeWhileAlreadyAcquired() {
        let selection = BufferSelection(
            startLine: 1, col: 2,
            endLine: 1, col: 3
        )

        assert(
            initial: initialState.copy(token: .acquired(owner: .ui)),
            on: .uiSelectionDidChange(selection),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiSelection: selection
            ),
            actions: [
                .startTokenTimeout,
                .updateNvimCursor(selection.start),
            ]
        )
    }

    // Changes are not sent back to Nvim if the token is acquired by it.
    func testUISelectionDidChangeIgnoredWhileAcquiredByNvim() {
        let selection = BufferSelection(
            startLine: 1, col: 2,
            endLine: 1, col: 3
        )
        let state = initialState.copy(token: .acquired(owner: .nvim))

        assert(
            initial: state,
            on: .uiSelectionDidChange(selection),
            expected: state.copy(uiSelection: selection),
            actions: []
        )
    }

    // Changes are ignored if identical with the Nvim cursor.
    func testUISelectionDidChangeIgnoredWhenEqualToNvimCursor() {
        let state = initialState.copy(
            token: .free,
            nvimCursor: Cursor(position: BufferPosition(line: 42, column: 32), mode: .normal)
        )
        let selection = BufferSelection(
            startLine: 42, col: 32,
            endLine: 42, col: 33
        )

        assert(
            initial: state,
            on: .uiSelectionDidChange(selection),
            expected: state.copy(
                token: .acquired(owner: .ui),
                uiSelection: selection
            ),
            actions: [
                .startTokenTimeout,
            ]
        )
    }

    // MARK: - Failure

    enum Err: Error {
        case failed(Int)
    }

    // The error is forwarded to the user.
    func testDidFail() {
        let error = Err.failed(1).equatable()

        assert(
            initial: initialState,
            on: .didFail(error),
            expected: initialState,
            actions: [.alert(error)]
        )
    }

    // MARK: - Utilities

    private func assert(
        initial state: BufferState,
        on event: BufferState.Event,
        expected expectedState: BufferState,
        actions expectedActions: [BufferState.Action],
        file: StaticString = #file, line: UInt = #line
    ) {
        var state = state
        XCTAssertEqual(state.on(event), expectedActions, file: file, line: line)
        XCTAssertEqual(state, expectedState, file: file, line: line)
    }
}

extension BufferState {
    func copy(
        token: EditionToken? = nil,
        nvimLines: [String]? = nil,
        nvimCursor: Cursor? = nil,
        uiLines: [String]? = nil,
        uiSelection: BufferSelection? = nil
    ) -> BufferState {
        BufferState(
            token: token ?? self.token,
            nvim: NvimState(
                cursor: nvimCursor ?? nvim.cursor,
                lines: nvimLines ?? nvim.lines
            ),
            ui: UIState(
                selection: uiSelection ?? ui.selection,
                lines: uiLines ?? ui.lines
            )
        )
    }
}
