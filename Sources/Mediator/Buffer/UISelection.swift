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

        // As the content of the lines might not be exactly as expected when
        // creating this selection (e.g. auto-indentation triggered), the
        // range will be clamped to the actual line lengths.
        var maxStartColumn = startLineRange.length
        var maxEndColumn = endLineRange.length
        if isCollapsed {
            // In the case of a collapsed selection (input cursor), we remove
            // the last character (newline), otherwise the selection might end
            // up on the next line.
            maxStartColumn -= 1
            maxEndColumn -= 1
        }

        let start = startLineRange.location + min(start.column, maxStartColumn)
        let end = endLineRange.location + min(end.column, maxEndColumn)
        guard start <= end else {
            return nil
        }

        return CFRange(
            location: start,
            length: end - start
        )
    }

    func adjusted(to mode: Mode, lines: [String]) -> UISelection {
        var adjusted = self
        adjusted.adjust(to: mode, lines: lines)
        return adjusted
    }

    /// Adjusts this `BufferSelection` to match the given Nvim `mode`.
    mutating func adjust(to mode: Mode, lines: [String]) {
        guard
            start.line == end.line,
            (start.column ... start.column + 1).contains(end.column),
            lines.indices.contains(start.line)
        else {
            return
        }

        switch mode {
        case .insert, .replace:
            end = start

        case .visual, .visualLine, .visualBlock, .select, .selectLine, .selectBlock:
            guard !isCollapsed else {
                fallthrough
            }

        default:
            let line = lines[start.line]
            if line.isEmpty {
                start = start.copy(column: 0)
                end = start.copy(column: 1)
            } else {
                start = start.copy(column: min(start.column, line.count - 1))
                end = start.moving(column: +1)
            }
        }
    }
}

extension Array where Element == UISelection {
    /// Converts the given Nvim cursor and visual positions to a list of UI
    /// selections
    init(mode: Mode, cursor: BufferPosition, visual: BufferPosition) {
        switch mode {
        case .normal, .operatorPending:
            let end = BufferPosition(line: cursor.line, column: cursor.column + 1)
            self = [UISelection(start: UIPosition(cursor), end: UIPosition(end))]

        case .insert, .replace:
            let position = UIPosition(cursor)
            self = [UISelection(start: position, end: position)]

        case .visualBlock, .selectBlock:
            // Block selections could be implemented using AX's
            // `selectedTextRanges` (plural). Unfortunately it doesn't seem
            // to be writable in Xcode... For now blocks are handled as
            // regular character selection, to see where the blocks start
            // and end.
            fallthrough

        case .visual, .select:
            // FIXME: Only the default `selection` option of `inclusive` is currently supported for the selection feedback. (https://neovim.io/doc/user/options.html#'selection')
            let start: UIPosition
            let end: UIPosition

            let cursor = UIPosition(cursor)
            let visual = UIPosition(visual)
            if cursor >= visual {
                start = visual
                end = cursor.moving(column: +1)
            } else {
                start = cursor
                end = visual.moving(column: +1)
            }
            self = [UISelection(start: start, end: end)]

        case .visualLine, .selectLine:
            let cursor = UIPosition(cursor)
            let visual = UIPosition(visual)
            var start = Swift.min(cursor, visual)
            var end = Swift.max(cursor, visual)
            start.column = 0
            end.line += 1
            end.column = 0
            self = [UISelection(start: start, end: end)]

        case .cmdline, .hitEnterPrompt, .shell, .terminal:
            self = []
        }
    }

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
