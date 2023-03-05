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

    /// Returns whether this selection has a length of 0.
    var isCollapsed: Bool {
        start.line == end.line && start.column == end.column
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

    /// Returns the character range in the given `element`'s text value for
    /// this selection.
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

    /// Adjusts this `BufferSelection` to match the given Nvim `mode`.
    func adjust(to mode: Mode, lines: [String]) -> UISelection {
        guard
            start.line == end.line,
            (start.column ... start.column + 1).contains(end.column),
            lines.indices.contains(start.line)
        else {
            return self
        }

        switch mode {
        case .insert, .replace:
            return UISelection(start: start, end: start)

        case .visual, .visualLine, .visualBlock, .select, .selectLine, .selectBlock:
            guard !isCollapsed else {
                fallthrough
            }
            return UISelection(start: start, end: end)

        default:
            let line = lines[start.line]
            if line.isEmpty {
                return UISelection(
                    start: start.copy(column: 0),
                    end: start.copy(column: 1)
                )
            } else {
                var start = start
                start.column = min(start.column, line.count - 1)
                return UISelection(
                    start: start,
                    end: start.moving(column: +1)
                )
            }
        }
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

extension UISelection: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        ["start": start, "end": end]
    }
}
