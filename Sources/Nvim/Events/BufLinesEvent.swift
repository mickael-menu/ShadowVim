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
//

import Foundation

extension EventDispatcher {
    func subscribeToBufLines(
        handler: @escaping (BufLinesEvent) -> Void
    ) async -> APIResult<EventSubscription> {
        await subscribe(to: "nvim_buf_lines_event") { params in
            guard let event = BufLinesEvent(params: params) else {
                return
            }
            handler(event)
        }
    }
}

public struct BufLinesEvent {
    public let buffer: BufferHandle
    public let changedTick: Int?
    public let firstLine: LineIndex
    public let lastLine: LineIndex?
    public let lineData: [String]
    public let more: Bool

    init?(params: [Value]) {
        guard
            params.count == 6,
            let buffer = params[0].bufferValue,
            let firstLine = params[2].intValue,
            let lastLine = params[3].intValue,
            let lineData = params[4].arrayValue,
            let more = params[5].boolValue
        else {
            return nil
        }

        switch params[1] {
        case .nil:
            changedTick = nil
        case let .int(changedTick):
            self.changedTick = changedTick
        default:
            return nil
        }

        self.buffer = buffer
        self.firstLine = LineIndex(firstLine)
        self.lastLine = (lastLine >= 0) ? LineIndex(lastLine) : nil

        self.lineData = lineData
            .compactMap {
                guard case let .string(data) = $0 else {
                    return nil
                }
                return data
            }
        self.more = more
    }
    
    public func changes(in content: String) -> (range: Range<String.Index>, content: String)? {
        var range: Range<String.Index>
        var replacement = lineData.joined(separator: "\n")
        
        guard let lastLine = lastLine, !content.isEmpty else {
            precondition(firstLine == 0)
            return (content.startIndex ..< content.endIndex, replacement)
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        precondition(firstLine <= lines.count)
        precondition(lastLine <= lines.count)

        if lineData.isEmpty {
            guard firstLine != lastLine else {
                // Garbage event, apparently.
                return nil
            }
            
            range = self.range(in: lines, firstLine: firstLine, lastLine: lastLine)
            if firstLine > 0 {
                range = content.index(range.lowerBound, offsetBy: -1) ..< range.upperBound
            } else if lastLine < lines.count {
                range = range.lowerBound ..< content.index(range.upperBound, offsetBy: +1)
            }

        } else {
            if firstLine >= lines.count {
                range = content.endIndex ..< content.endIndex
            } else {
                range = self.range(in: lines, firstLine: firstLine, lastLine: lastLine)
            }

            if firstLine == lastLine {
                if firstLine >= lines.count {
                    replacement = "\n" + replacement
                } else {
                    replacement += "\n"
                }
            }
        }
        
        return (range, replacement)
    }
        
    private func range<S : StringProtocol>(in lines: [S], firstLine: Int, lastLine: Int) -> Range<String.Index> {
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
        "BufLinesEvent#\(changedTick ?? -1) \(firstLine)..<\(lastLine ?? -1) \(lineData)"
    }
}
