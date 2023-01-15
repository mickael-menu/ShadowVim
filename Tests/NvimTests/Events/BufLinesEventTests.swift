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
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

@testable import Nvim
import XCTest

final class BufLinesEventTests: XCTestCase {
    let emptyLines = [""]
    lazy var emptyContent = emptyLines[0]

    let singleLines = ["Just a flesh wound."]
    lazy var singleContent = singleLines[0]

    let nLines = [
        "We dine well here in Camelot.",
        "We eat ham and jam and spam a lot.",
        "",
        "- Knights of Camelot",
    ]
    lazy var nContent = nLines.joined(separator: "\n")

    // To test diacritics and such.
    let frenchPoemLines = [
       "Ce cœur où plus rien ne pénètre,",
       "D'où plus rien désormais ne sort ;",
       "Je t'aime avec ce que mon être",
       "A de plus fort contre la mort ;",
    ]
    lazy var frenchPoemContent = frenchPoemLines.joined(separator: "\n")
    
    func testInitialEmptyContent() throws {
        let expected = emptyContent

        func test(in buffer: String) throws {
            let event = initialEvent(data: [expected])
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(in: emptyContent)
        try test(in: singleContent)
        try test(in: nContent)
        try test(in: frenchPoemContent)
    }

    func testInitialSingleLineContent() throws {
        let expected = singleContent

        func test(in buffer: String) throws {
            let event = initialEvent(data: [expected])
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(in: emptyContent)
        try test(in: singleContent)
        try test(in: nContent)
        try test(in: frenchPoemContent)
    }

    func testInitialMulilineContent() throws {
        let expected = nContent

        func test(in buffer: String) throws {
            let event = initialEvent(data: [expected])
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(in: emptyContent)
        try test(in: singleContent)
        try test(in: nContent)
        try test(in: frenchPoemContent)
    }

    /// Creates an event for the initial notification containing the whole buffer (`lastLine = -1`).
    private func initialEvent(data: [String]) -> BufLinesEvent {
        BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: -1, lineData: data)
    }

    func testPrependLinesToEmptyBuffer() throws {
        let buffer = emptyContent

        func test(prepending lines: [String], expected: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 0, lineData: lines)
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(prepending: emptyLines, expected: "\n")
        try test(prepending: singleLines, expected: singleContent + "\n")
        try test(prepending: nLines, expected: nContent + "\n")
        try test(prepending: frenchPoemLines, expected: frenchPoemContent + "\n")
    }

    func testPrependLinesToSingleLineBuffer() throws {
        let buffer = singleContent

        func test(prepending lines: [String], expected: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 0, lineData: lines)
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(prepending: emptyLines, expected: "\n" + singleContent)
        try test(prepending: singleLines, expected: singleContent + "\n" + singleContent)
        try test(prepending: nLines, expected: nContent + "\n" + singleContent)
        try test(prepending: frenchPoemLines, expected: frenchPoemContent + "\n" + singleContent)
    }

    func testPrependLinesToMultilineBuffer() throws {
        let buffer = nContent

        func test(prepending lines: [String], expected: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 0, lineData: lines)
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(prepending: emptyLines, expected: "\n" + nContent)
        try test(prepending: singleLines, expected: singleContent + "\n" + nContent)
        try test(prepending: nLines, expected: nContent + "\n" + nContent)
        try test(prepending: frenchPoemLines, expected: frenchPoemContent + "\n" + nContent)
    }

    func testAppendLinesToEmptyBuffer() throws {
        let buffer = emptyContent

        func test(appending lines: [String], expected: String) throws {
            let event = BufLinesEvent(
                changedTick: 1,
                firstLine: 0,
                lastLine: 1,
                lineData: lines
            )
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(appending: emptyLines, expected: emptyContent)
        try test(appending: singleLines, expected: singleContent)
        try test(appending: nLines, expected: nContent)
        try test(appending: frenchPoemLines, expected: frenchPoemContent)
    }

    func testAppendLinesToSingleLineBuffer() throws {
        let buffer = singleContent

        func test(appending lines: [String], expected: String) throws {
            let event = BufLinesEvent(
                changedTick: 1,
                firstLine: 1,
                lastLine: 1,
                lineData: lines
            )
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(appending: emptyLines, expected: singleContent + "\n")
        try test(appending: singleLines, expected: singleContent + "\n" + singleContent)
        try test(appending: nLines, expected: singleContent + "\n" + nContent)
        try test(appending: frenchPoemLines, expected: singleContent + "\n" + frenchPoemContent)
    }

    func testAppendLinesToMultilineBuffer() throws {
        let buffer = nContent

        func test(appending lines: [String], expected: String) throws {
            let event = BufLinesEvent(
                changedTick: 1,
                firstLine: nLines.count,
                lastLine: nLines.count,
                lineData: lines
            )
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(appending: emptyLines, expected: nContent + "\n")
        try test(appending: singleLines, expected: nContent + "\n" + singleContent)
        try test(appending: nLines, expected: nContent + "\n" + nContent)
        try test(appending: frenchPoemLines, expected: nContent + "\n" + frenchPoemContent)
    }

    func testModifyEmptyBuffer() throws {
        let buffer = emptyContent

        func test(set line: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 1, lineData: [line])
            try assertChanges(from: event, in: buffer, expects: line)
        }

        try test(set: "")
        try test(set: "one")
        try test(set: "one\ntwo")
    }

    func testModifySingleLineBuffer() throws {
        let buffer = singleContent

        func test(set line: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 1, lineData: [line])
            try assertChanges(from: event, in: buffer, expects: line)
        }

        try test(set: "")
        try test(set: "one")
        try test(set: "one\ntwo")
    }

    func testModifyFirstLineOfMultilineBuffer() throws {
        let buffer = nContent
        let bufferFromSecondLine = nLines[1...]
            .joined(separator: "\n")

        func test(set line: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 1, lineData: [line])
            let expected = line + "\n" + bufferFromSecondLine
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(set: "")
        try test(set: "one")
        try test(set: "one\ntwo")
    }

    func testModifySecondLineOfMultilineBuffer() throws {
        let buffer = nContent
        let bufferFirstLine = nLines[0]
        let bufferFromThirdLine = nLines[2...]
            .joined(separator: "\n")

        func test(set line: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 1, lastLine: 2, lineData: [line])
            let expected = bufferFirstLine + "\n" + line + "\n" + bufferFromThirdLine
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(set: "")
        try test(set: "one")
        try test(set: "one\ntwo")
    }

    func testModifyLastLineOfMultilineBuffer() throws {
        let buffer = nContent
        let bufferLastLine = nLines.count - 1
        let bufferUntilLastLine = nLines[..<bufferLastLine]
            .joined(separator: "\n")

        func test(set line: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: bufferLastLine, lastLine: bufferLastLine + 1, lineData: [line])
            let expected = bufferUntilLastLine + "\n" + line
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(set: "")
        try test(set: "one")
        try test(set: "one\ntwo")
    }

    func testModifySecondLineOfDiacriticsBuffer() throws {
        let buffer = frenchPoemContent
        let bufferFirstLine = frenchPoemLines[0]
        let bufferFromThirdLine = frenchPoemLines[2...]
            .joined(separator: "\n")

        func test(set line: String) throws {
            let event = BufLinesEvent(changedTick: 1, firstLine: 1, lastLine: 2, lineData: [line])
            let expected = bufferFirstLine + "\n" + line + "\n" + bufferFromThirdLine
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(set: "")
        try test(set: "l'école")
        try test(set: "l'école\nla forêt")
    }

    func testDeleteEmptyBuffer() throws {
        let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 1, lineData: [])
        try assertChanges(from: event, in: emptyContent, expects: "")
    }

    func testDeleteSingleLineBuffer() throws {
        let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 1, lineData: [])
        try assertChanges(from: event, in: singleContent, expects: "")
    }

    func testDeleteFirstLineOfMultilineBuffer() throws {
        let expected = nLines[1...].joined(separator: "\n")
        let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 1, lineData: [])
        try assertChanges(from: event, in: nContent, expects: expected)
    }

    func testDeleteSecondLineOfMultilineBuffer() throws {
        var lines = nLines
        lines.remove(at: 1)
        let expected = lines.joined(separator: "\n")

        let event = BufLinesEvent(changedTick: 1, firstLine: 1, lastLine: 2, lineData: [])
        try assertChanges(from: event, in: nContent, expects: expected)
    }

    func testDeleteLastLineOfMultilineBuffer() throws {
        let lastLineIndex = nLines.count - 1
        let expected = nLines[0 ..< lastLineIndex]
            .joined(separator: "\n")

        let event = BufLinesEvent(changedTick: 1, firstLine: lastLineIndex, lastLine: lastLineIndex + 1, lineData: [])
        try assertChanges(from: event, in: nContent, expects: expected)
    }
        
    func testDeleteMultipleLinesOfMultilineBuffer() throws {
        let buffer = nContent

        func test(removing indices: Range<Int>) throws {
            var lines = nLines
            lines.removeSubrange(indices)
            let expected = lines.joined(separator: "\n")
            
            let event = BufLinesEvent(
                changedTick: 1,
                firstLine: indices.startIndex,
                lastLine: indices.endIndex,
                lineData: []
            )
            try assertChanges(from: event, in: buffer, expects: expected)
        }

        try test(removing: 0..<2)
        try test(removing: 1..<3)
        try test(removing: 0..<4)
    }

    func testDeleteSecondLineOfDiacriticsBuffer() throws {
        var lines = frenchPoemLines
        lines.remove(at: 1)
        let expected = lines.joined(separator: "\n")

        let event = BufLinesEvent(changedTick: 1, firstLine: 1, lastLine: 2, lineData: [])
        try assertChanges(from: event, in: frenchPoemContent, expects: expected)
    }

    /// Sometimes Nvim sends events with no content (same `firstLine` and `lastLine` with
    /// empty `lineData`). As we don't know what to do with it, they should be ignored.
    func testNullEventIsIgnored() {
        func test(in buffer: String) {
            let event = BufLinesEvent(changedTick: 1, firstLine: 0, lastLine: 0, lineData: [])
            XCTAssertNil(event.changes(in: buffer))
        }

        test(in: emptyContent)
        test(in: singleContent)
        test(in: nContent)
    }

    private func assertChanges(from event: BufLinesEvent, in buffer: String, expects: String) throws {
        let (range, replacement) = try XCTUnwrap(event.changes(in: buffer))
        XCTAssertEqual(
            buffer.replacingCharacters(in: range, with: replacement),
            expects
        )
    }
}
