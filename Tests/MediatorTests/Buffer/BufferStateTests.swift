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
        mode: .normal,
        position: BufferPosition(line: 1, column: 20),
        visual: BufferPosition(line: 1, column: 20)
    )

    let uiSelection = UISelection(
        start: UIPosition(line: 1, column: 5),
        end: UIPosition(line: 2, column: 8)
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
                    selections: [UISelection(
                        start: UIPosition(nvimCursor.position),
                        end: UIPosition(nvimCursor.position.moving(column: +1))
                    )]
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
                    cursorPosition: BufferPosition(uiSelection.start)
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
            on: .didRequestRefresh(source: .nvim),
            expected: initialState.copy(token: .synchronizing),
            actions: [
                .updateUI(
                    lines: nvimLines,
                    diff: nvimLines.difference(from: uiLines),
                    selections: [UISelection(
                        start: UIPosition(nvimCursor.position),
                        end: UIPosition(nvimCursor.position.moving(column: +1))
                    )]
                ),
                .startTokenTimeout,
            ]
        )

        assert(
            initial: initialState,
            on: .didRequestRefresh(source: .ui),
            expected: initialState.copy(token: .synchronizing),
            actions: [
                .updateNvim(
                    lines: uiLines,
                    diff: uiLines.difference(from: nvimLines),
                    cursorPosition: BufferPosition(uiSelection.start)
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
            on: .didRequestRefresh(source: .ui),
            expected: state,
            actions: [.bell]
        )
    }

    // Rejected if the token is busy (synchronizing).
    func testRefreshRequestWhileSynchronizing() {
        let state = initialState.copy(token: .synchronizing)
        assert(
            initial: state,
            on: .didRequestRefresh(source: .ui),
            expected: state,
            actions: [.bell]
        )
    }

    // The refresh is ignored when the buffers are already synchronized.
    func testRefreshRequestIgnoredWhenSynchronized() {
        let state = initialState.copy(nvimLines: uiLines)

        assert(
            initial: state,
            on: .didRequestRefresh(source: .nvim),
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
                .updateUISelections([UISelection(
                    start: UIPosition(nvimCursor.position),
                    end: UIPosition(nvimCursor.position.moving(column: +1))
                )]),
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
                .updateUISelections([UISelection(
                    start: UIPosition(nvimCursor.position),
                    end: UIPosition(nvimCursor.position.moving(column: +1))
                )]),
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
            mode: .insert,
            position: BufferPosition(line: 4, column: 2),
            visual: BufferPosition(line: 4, column: 2)
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
                .updateUISelections([UISelection(
                    start: UIPosition(cursor.position),
                    end: UIPosition(cursor.position)
                )]),
            ]
        )
    }

    // The update is sent to the UI buffer when the token is already acquired for Nvim.
    func testNvimCursorDidChangeWhileAlreadyAcquired() {
        let cursor = Cursor(
            mode: .insert,
            position: BufferPosition(line: 4, column: 2),
            visual: BufferPosition(line: 4, column: 2)
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
                .updateUISelections([UISelection(
                    start: UIPosition(cursor.position),
                    end: UIPosition(cursor.position)
                )]),
            ]
        )
    }

    // Changes are not sent back to the UI if the token is acquired by it.
    func testNvimCursorDidChangeIgnoredWhileAcquiredByUI() {
        let cursor = Cursor(
            mode: .insert,
            position: BufferPosition(line: 4, column: 2),
            visual: BufferPosition(line: 4, column: 2)
        )
        let state = initialState.copy(token: .acquired(owner: .ui))

        assert(
            initial: state,
            on: .nvimCursorDidChange(cursor),
            expected: state.copy(nvimCursor: cursor),
            actions: []
        )
    }

    // When a UI selection is generated from the Nvim cursor, the UI
    // will be requested to scroll to the cursor position.
    func testNvimCursorDidChangeScrollsUIWithSelection() {
        let position = BufferPosition(line: 4, column: 2)

        func test(visual: BufferPosition, expected: UISelection?) {
            let cursor = Cursor(
                mode: .visual,
                position: position,
                visual: visual
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
                    .updateUISelections([UISelection(
                        start: UIPosition(cursor.position),
                        end: UIPosition(visual.moving(column: +1))
                    )]),
                    expected.map { .scrollUI(visibleSelection: $0) },
                ].compactMap { $0 }
            )
        }

        // No scroll when the visual position is on the same line as the cursor.
        test(visual: position, expected: nil)
        test(visual: position.moving(column: 5), expected: nil)

        // Scroll to the cursor when the visual is on a different line.
        let expected = UISelection(start: UIPosition(position), end: UIPosition(position))
        test(visual: position.moving(line: +5), expected: expected)
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
                    cursorPosition: BufferPosition(newSelection.start)
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
                    cursorPosition: BufferPosition(newSelection.start)
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
                    cursorPosition: BufferPosition(uiSelection.start)
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
                    cursorPosition: BufferPosition(uiSelection.start)
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
        let selection = UISelection(
            startLine: 1, col: 2,
            endLine: 1, col: 3
        )

        assert(
            initial: initialState.copy(token: .free),
            on: .uiSelectionDidChange(selection),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiSelection: selection
            ),
            actions: [
                .startTokenTimeout,
                .moveNvimCursor(BufferPosition(selection.start)),
            ]
        )
    }

    // The update is sent to the Nvim buffer when the token is already acquired by the UI.
    func testUISelectionDidChangeWhileAlreadyAcquired() {
        let selection = UISelection(
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
                .moveNvimCursor(BufferPosition(selection.start)),
            ]
        )
    }

    // Changes are not sent back to Nvim if the token is acquired by it.
    func testUISelectionDidChangeIgnoredWhileAcquiredByNvim() {
        let selection = UISelection(
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
            nvimCursor: Cursor(
                mode: .normal,
                position: BufferPosition(line: 42, column: 32),
                visual: BufferPosition(line: 42, column: 32)
            )
        )
        let selection = UISelection(
            startLine: 41, col: 31,
            endLine: 41, col: 32
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

    // Changes are ignored if identical with the UI selection, to avoid
    // adjusting the selection several times in a row.
    func testUISelectionDidChangeIgnoredWhenEqualToUISelection() {
        let selection = UISelection(
            startLine: 41, col: 31,
            endLine: 41, col: 32
        )

        let state = initialState.copy(
            token: .free,
            nvimCursor: Cursor(mode: .normal),
            uiSelection: selection
        )

        assert(
            initial: state,
            on: .uiSelectionDidChange(selection),
            expected: state,
            actions: []
        )
    }

    // The selection is adjusted to match the Nvim mode, when needed.
    func testUISelectionDidChangeAdjustsToNvimMode() {
        let selection = UISelection(
            startLine: 1, col: 2,
            endLine: 1, col: 2
        )

        assert(
            initial: initialState.copy(token: .free),
            on: .uiSelectionDidChange(selection),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiSelection: selection.copy(endColumn: 3)
            ),
            actions: [
                .startTokenTimeout,
                .updateUISelections([selection.copy(endColumn: 3)]),
                .moveNvimCursor(BufferPosition(selection.start)),
            ]
        )
    }

    // If the UI selection already matches the Nvim mode, only the Nvim cursor
    // is updated, not the UI selection.
    func testUISelectionDidChangeAlreadyAdjustedToNvimMode() {
        let selection = UISelection(
            startLine: 1, col: 2,
            endLine: 1, col: 3
        )

        assert(
            initial: initialState.copy(token: .free),
            on: .uiSelectionDidChange(selection),
            expected: initialState.copy(
                token: .acquired(owner: .ui),
                uiSelection: selection.copy(endColumn: 3)
            ),
            actions: [
                .startTokenTimeout,
                .moveNvimCursor(BufferPosition(selection.start)),
            ]
        )
    }

    // The selection is NOT adjusted to match the Nvim mode, if the keys
    // passthrough is enabled.
    func testUISelectionDidChangeDontAdjustToNvimModeWhenKeysPassthrough() {
        let selection = UISelection(
            startLine: 1, col: 2,
            endLine: 1, col: 2
        )

        let state = initialState.copy(token: .free, keysPassthrough: true)

        assert(
            initial: state,
            on: .uiSelectionDidChange(selection),
            expected: state.copy(
                token: .acquired(owner: .ui),
                uiSelection: selection
            ),
            actions: [
                .startTokenTimeout,
                .moveNvimCursor(BufferPosition(selection.start)),
            ]
        )
    }

    // The selection change is ignored when the left mouse button is down.
    // The state is put into "selecting" mode.
    func testUISelectionDidChangeWhileLeftMouseDownStartsSelectingMode() {
        let selection = UISelection(
            startLine: 1, col: 2,
            endLine: 1, col: 3
        )

        let state = initialState.copy(
            token: .free,
            isLeftMouseButtonDown: true
        )

        assert(
            initial: state,
            on: .uiSelectionDidChange(selection),
            expected: state.copy(
                uiSelection: selection,
                isSelecting: true
            ),
            actions: []
        )
    }

    // MARK: - UI mouse event
    
    // Left mouse down is ignored if outside the buffer.
    func testUIDidReceiveMouseEventDownLeftIgnoredWhenOutsideBuffer() {
        let state = initialState.copy(
            token: .free,
            isLeftMouseButtonDown: false
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.down(.left), bufferPoint: nil),
            expected: state,
            actions: []
        )
    }
    
    // Left mouse down inside the buffer is memorized, and the visual mode is
    // requested to stop.
    //
    // This simulates the default behavior of `LeftMouse` in Nvim, which is:
    // > If Visual mode is active it is stopped.
    // > :help LeftMouse
    func testUIDidReceiveMouseEventDownLeftRequestsStopVisualModeWhenTokenFree() {
        let state = initialState.copy(
            token: .free,
            isLeftMouseButtonDown: false
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.down(.left), bufferPoint: .zero),
            expected: state.copy(
                token: .acquired(owner: .ui),
                isLeftMouseButtonDown: true
            ),
            actions: [
                .startTokenTimeout,
                .stopNvimVisual
            ]
        )
    }

    func testUIDidReceiveMouseEventDownLeftStopsVisualModeWhenTokenBusy() {
        let state = initialState.copy(
            token: .acquired(owner: .nvim),
            isLeftMouseButtonDown: false
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.down(.left), bufferPoint: .zero),
            expected: state.copy(
                isLeftMouseButtonDown: true
            ),
            actions: []
        )
    }

    // Left mouse up is ignored unless we were in "selecting mode".
    func testUIDidReceiveMouseEventUpLeftIgnoredWhenNotSelecting() {
        let state = initialState.copy(
            token: .free,
            isLeftMouseButtonDown: true
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.up(.left), bufferPoint: .zero),
            expected: state.copy(
                isLeftMouseButtonDown: false
            ),
            actions: []
        )
    }

    // Left mouse up interrupts "selecting mode" and requests Nvim to start
    // a visual selection.
    func testUIDidReceiveMouseEventUpLeftStartsNvimVisualMode() {
        let state = initialState.copy(
            token: .free,
            uiSelection: UISelection(
                startLine: 1, col: 2,
                endLine: 2, col: 5
            ),
            isLeftMouseButtonDown: true,
            isSelecting: true
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.up(.left), bufferPoint: .zero),
            expected: state.copy(
                token: .acquired(owner: .ui),
                isLeftMouseButtonDown: false,
                isSelecting: false
            ),
            actions: [
                .startTokenTimeout,
                .startNvimVisual(
                    start: BufferPosition(line: 2, column: 3),
                    // "column - 1" because in visual mode the end character is
                    // included in the selection.
                    end: BufferPosition(line: 3, column: 5)
                )
            ]
        )
    }

    // Left mouse up interrupts "selecting mode" and adjusts a collapsed UI
    // selection.
    func testUIDidReceiveMouseEventUpLeftAdjustsCollapsedSelection() {
        let state = initialState.copy(
            token: .free,
            uiSelection: UISelection(
                startLine: 1, col: 2,
                endLine: 1, col: 2
            ),
            isLeftMouseButtonDown: true,
            isSelecting: true
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.up(.left), bufferPoint: .zero),
            expected: state.copy(
                token: .acquired(owner: .ui),
                uiSelection: UISelection(
                    startLine: 1, col: 2,
                    endLine: 1, col: 3
                ),
                isLeftMouseButtonDown: false,
                isSelecting: false
            ),
            actions: [
                .startTokenTimeout,
                .updateUISelections([UISelection(
                    startLine: 1, col: 2,
                    endLine: 1, col: 3
                )]),
                .moveNvimCursor(BufferPosition(line: 2, column: 3))
            ]
        )
    }

    // No adjustement is done when the Nvim token is buzy, with a collapsed
    // selection.
    func testUIDidReceiveMouseEventUpLeftWithCollapsedSelectionWhenTokenBusy() {
        let state = initialState.copy(
            token: .acquired(owner: .nvim),
            uiSelection: UISelection(
                startLine: 1, col: 2,
                endLine: 1, col: 2
            ),
            isLeftMouseButtonDown: true,
            isSelecting: true
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.up(.left), bufferPoint: .zero),
            expected: state.copy(
                isLeftMouseButtonDown: false,
                isSelecting: false
            ),
            actions: []
        )
    }

    // No adjustement is done when the Nvim token is buzy, with an actual
    // selection.
    func testUIDidReceiveMouseEventUpLeftWithFullSelectionWhenTokenBusy() {
        let state = initialState.copy(
            token: .acquired(owner: .nvim),
            uiSelection: UISelection(
                startLine: 1, col: 2,
                endLine: 2, col: 4
            ),
            isLeftMouseButtonDown: true,
            isSelecting: true
        )

        assert(
            initial: state,
            on: .uiDidReceiveMouseEvent(.up(.left), bufferPoint: .zero),
            expected: state.copy(
                isLeftMouseButtonDown: false,
                isSelecting: false
            ),
            actions: []
        )
    }

    // MARK: - Toggle keys passthrough

    func testDidToggleKeysPassthroughOn() {
        let state = initialState.copy(
            uiSelection: UISelection(
                startLine: 1, col: 3,
                endLine: 1, col: 4
            ),
            keysPassthrough: false
        )

        assert(
            initial: state,
            on: .didToggleKeysPassthrough(enabled: true),
            expected: state.copy(keysPassthrough: true),
            actions: [
                // The visual mode is stopped in Neovim when enabling keys passthrough.
                .stopNvimVisual,
                .updateUISelections([UISelection(
                    startLine: 1, col: 3,
                    endLine: 1, col: 3
                )]),
            ]
        )
    }

    func testDidToggleKeysPassthroughOff() {
        let state = initialState.copy(
            uiSelection: UISelection(
                startLine: 1, col: 3,
                endLine: 1, col: 3
            ),
            keysPassthrough: true
        )

        assert(
            initial: state,
            on: .didToggleKeysPassthrough(enabled: false),
            expected: state.copy(keysPassthrough: false),
            actions: [
                .updateUISelections([UISelection(
                    startLine: 1, col: 3,
                    endLine: 1, col: 4
                )]),
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
        uiSelection: UISelection? = nil,
        keysPassthrough: Bool? = nil,
        isLeftMouseButtonDown: Bool? = nil,
        isSelecting: Bool? = nil
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
            ),
            isKeysPassthroughEnabled: keysPassthrough ?? isKeysPassthroughEnabled,
            isLeftMouseButtonDown: isLeftMouseButtonDown ?? self.isLeftMouseButtonDown,
            isSelecting: isSelecting ?? self.isSelecting
        )
    }
}
