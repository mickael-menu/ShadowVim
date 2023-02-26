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

import AX
import Foundation
import Nvim
import Toolkit

/// 0-indexed line number.
typealias LineIndex = Int

/// 0-indexed column number.
typealias ColumnIndex = Int

/// UI text position as 0-indexed offsets.
struct UIPosition: Equatable, Comparable {
    var line: LineIndex
    var column: ColumnIndex

    init(_ position: BufferPosition) {
        self.init(
            line: position.line - 1,
            column: position.column - 1
        )
    }

    init(line: LineIndex = 0, column: ColumnIndex = 0) {
        self.line = line
        self.column = column
    }

    func moving(line: LineIndex? = nil, column: ColumnIndex? = nil) -> UIPosition {
        UIPosition(
            line: self.line + (line ?? 0),
            column: self.column + (column ?? 0)
        )
    }

    func copy(line: LineIndex? = nil, column: ColumnIndex? = nil) -> UIPosition {
        UIPosition(
            line: line ?? self.line,
            column: column ?? self.column
        )
    }

    static func < (lhs: UIPosition, rhs: UIPosition) -> Bool {
        if lhs.line == rhs.line {
            return lhs.column < rhs.column
        } else {
            return lhs.line < rhs.line
        }
    }
}

extension BufferPosition {
    init(_ position: UIPosition) {
        self.init(
            line: position.line + 1,
            column: position.column + 1
        )
    }
}

/// Represents a text selection in an UI text area.
struct UISelection: Equatable {
    /// Fixed start of the selection.
    var start: UIPosition

    /// Movable end of the selection.
    var end: UIPosition

    init(start: UIPosition = .init(), end: UIPosition = .init()) {
        self.start = start
        self.end = end
    }

    func copy(
        startLine: LineIndex? = nil,
        startColumn: ColumnIndex? = nil,
        endLine: LineIndex? = nil,
        endColumn: ColumnIndex? = nil
    ) -> UISelection {
        UISelection(
            start: UIPosition(
                line: startLine ?? start.line,
                column: startColumn ?? start.column
            ),
            end: UIPosition(
                line: endLine ?? end.line,
                column: endColumn ?? end.column
            )
        )
    }

    func range(in element: AXUIElement) throws -> CFRange? {
        guard
            let startLineRange: CFRange = try element.get(.rangeForLine, with: start.line),
            let endLineRange: CFRange = try element.get(.rangeForLine, with: end.line)
        else {
            return nil
        }

        let start = startLineRange.location + start.column
        let end = endLineRange.location + end.column
        assert(start <= end)

        return CFRange(
            location: start,
            length: end - start
        )
    }
}

extension Array where Element == UISelection {
    /// Joins noncontiguous selections into a single selection.
    func joined() -> UISelection? {
        guard count > 1 else {
            return first
        }

        var start = first!.start
        var end = first!.end
        for selection in self {
            if start > selection.start {
                start = selection.start
            }
            if end < selection.end {
                end = selection.end
            }
        }
        return UISelection(start: start, end: end)
    }
}

// MARK: Logging

extension UIPosition: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["line": line, "column": column]
    }
}

extension UISelection: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["start": start, "end": end]
    }
}
