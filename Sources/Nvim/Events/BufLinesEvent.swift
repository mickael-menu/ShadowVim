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

import Combine
import Foundation

extension EventDispatcher {
    /// Subscribes a new handler for the `nvim_buf_lines_event` event of the given `buffer`.
    func subscribeToBufLines(
        of buffer: BufferHandle
    ) -> AnyPublisher<BufLinesEvent, APIError> {
        subscribe(to: "nvim_buf_lines_event")
            .compactMap { data in
                guard
                    let eventBuffer = data.first?.bufferValue,
                    eventBuffer == buffer,
                    let event = BufLinesEvent(params: data)
                else {
                    return nil
                }
                return event
            }
            .eraseToAnyPublisher()
    }
}

/// Event broadcasted when the buffer text between `firstline` and `lastline` (end-exclusive,
/// zero-indexed) were changed to the new text in the `linedata` list.
///
/// The granularity is a line, i.e. if a single character is changed in the editor, the entire line is sent.
///
/// When `changedtick` is nil this means the screen lines (display) changed but not the buffer
/// contents. `linedata` contains the changed screen lines. This happens when 'inccommand'
/// shows a buffer preview.
public struct BufLinesEvent {
    /// API buffer handle (buffer number).
    public let buf: BufferHandle

    /// Value of `b:changedtick` for the buffer.
    ///
    /// If you send an API command back to nvim you can check the value of `b:changedtick`
    /// as part of your request to ensure that no other changes have been made.
    public let changedTick: Int?

    /// Integer line number of the first line that was replaced.
    ///
    /// Zero-indexed: if line 1 was replaced then `firstLine` will be 0, not 1. `firstLine` is
    /// always less than or equal to the number of lines that were in the buffer before the lines
    /// were replaced.
    public let firstLine: LineIndex

    /// Integer line number of the first line that was not replaced (i.e. the range `firstline`,
    /// `lastline` is end-exclusive).
    ///
    /// Zero-indexed: if line numbers 2 to 5 were replaced, this will be 5 instead of 6. `lastLine`
    /// is always less than or equal to the number of lines that were in the buffer before the lines
    /// were replaced. `lastLine` will be -1 if the event is part of the initial update after
    /// attaching.
    public let lastLine: LineIndex

    /// List of strings containing the contents of the new buffer lines.
    ///
    /// Newline characters are omitted; empty lines are sent as empty strings.
    public let lineData: [String]

    /// True for a "multipart" change notification: the current change was chunked into multiple
    /// `nvim_buf_lines_event` notifications (e.g. because it was too big).
    public let more: Bool

    init(
        buf: BufferHandle = 0,
        changedTick: Int?,
        firstLine: LineIndex,
        lastLine: LineIndex,
        lineData: [String],
        more: Bool = false
    ) {
        self.buf = buf
        self.changedTick = changedTick
        self.firstLine = firstLine
        self.lastLine = lastLine
        self.lineData = lineData
        self.more = more
    }

    /// Initializes the `BufLinesEvent` from the RPC notification params.
    init?(params: [Value]) {
        guard
            params.count == 6,
            let buf = params[0].bufferValue,
            let firstLine = params[2].intValue,
            let lastLine = params[3].intValue,
            let lineData = params[4].arrayValue,
            let more = params[5].boolValue
        else {
            return nil
        }

        var changedTick: Int?
        switch params[1] {
        case .nil:
            changedTick = nil
        case let .int(tick):
            changedTick = tick
        default:
            return nil
        }

        self.init(
            buf: buf,
            changedTick: changedTick,
            firstLine: LineIndex(firstLine),
            lastLine: LineIndex(lastLine),
            lineData: lineData
                .compactMap {
                    guard case let .string(data) = $0 else {
                        return nil
                    }
                    return data
                },
            more: more
        )
    }

    public typealias Changes = (range: Range<String.Index>, replacement: String)

    /// Applies the changes in `lines` for this `BufLinesEvent`.
    public func applyChanges(in lines: [String]) -> [String] {
        var lines = lines
        let lastLine = (lastLine > -1) ? lastLine : firstLine + lineData.count - 1
        lines.replaceSubrange(firstLine ..< lastLine, with: lineData)
        return lines
    }

    /// Applies the changes in `content` for this `BufLinesEvent`.
    public func applyChanges(in content: String) -> String? {
        guard let (range, replacement) = changes(in: content) else {
            return nil
        }
        var content = content
        content.replaceSubrange(range, with: replacement)
        return content
    }

    /// Computes the changes to be made in `content` to apply the `BufLinesEvent`.
    ///
    /// Returns the `range` in `content` to be replaced by `replacement`.
    public func changes(in content: String) -> Changes? {
        // Sometimes Nvim sends events with no content (same `firstLine` and
        // `lastLine` with empty `lineData`). As we don't know what to do with
        // it, they should be ignored.
        guard !lineData.isEmpty || firstLine != lastLine else {
            return nil
        }

        if lastLine == -1 {
            return initialChanges(in: content)
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        precondition(firstLine <= lines.count)
        precondition(lastLine <= lines.count)

        if lineData.isEmpty {
            return deletionChanges(in: content, lines: lines)
        } else {
            return modificationChanges(in: content, lines: lines)
        }
    }

    /// Changes for an initial notification containing the whole buffer.
    public func initialChanges(in content: String) -> Changes {
        precondition(lastLine == -1)
        precondition(firstLine == 0)
        return (content.startIndex ..< content.endIndex, data)
    }

    /// Changes for suppressions of existing lines.
    public func deletionChanges<S: StringProtocol>(in content: String, lines: [S]) -> Changes {
        precondition(lineData.isEmpty)

        var range = range(in: lines, firstLine: firstLine, lastLine: lastLine)
        if firstLine > 0 {
            range = content.index(range.lowerBound, offsetBy: -1) ..< range.upperBound
        } else if lastLine < lines.count {
            range = range.lowerBound ..< content.index(range.upperBound, offsetBy: +1)
        }

        return (range, data)
    }

    /// Changes for modifications of existing lines.
    public func modificationChanges<S: StringProtocol>(in content: String, lines: [S]) -> Changes {
        precondition(!lineData.isEmpty)

        let range: Range<String.Index>
        if firstLine >= lines.count {
            range = content.endIndex ..< content.endIndex
        } else {
            range = self.range(in: lines, firstLine: firstLine, lastLine: lastLine)
        }

        var data = data
        if firstLine == lastLine {
            if firstLine >= lines.count {
                data = "\n" + data
            } else {
                data += "\n"
            }
        }

        return (range, data)
    }

    /// New buffer lines joined with newline characters.
    private var data: String {
        lineData.joined(separator: "\n")
    }

    /// Calculates the character range in `lines` between the indexes `firstLine` and
    /// `lastLine` (exclusive).
    private func range<S: StringProtocol>(
        in lines: [S],
        firstLine: LineIndex,
        lastLine: LineIndex
    ) -> Range<String.Index> {
        precondition(!lines.isEmpty)

        var startIndex: String.Index = lines[0].startIndex
        var endIndex = startIndex

        for (lineNb, line) in lines.enumerated() {
            if lineNb == firstLine {
                startIndex = line.startIndex
                endIndex = startIndex
            }
            if lineNb < lastLine {
                endIndex = line.endIndex
            }
            if lineNb == lastLine {
                break
            }
        }

        return startIndex ..< endIndex
    }
}

extension BufLinesEvent: CustomStringConvertible {
    public var description: String {
        "BufLinesEvent#\(changedTick ?? -1) \(firstLine)..<\(lastLine) \(lineData)"
    }
}
