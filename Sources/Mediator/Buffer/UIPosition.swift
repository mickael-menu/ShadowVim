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

import Foundation
import Nvim
import Toolkit

/// 0-indexed line number.
public typealias LineIndex = Int

/// 0-indexed column number.
public typealias ColumnIndex = Int

/// UI text position as 0-indexed offsets.
public struct UIPosition: Equatable {
    public var line: LineIndex
    public var column: ColumnIndex

    public init(_ position: BufferPosition) {
        self.init(
            line: position.line - 1,
            column: position.column - 1
        )
    }

    public init(line: LineIndex = 0, column: ColumnIndex = 0) {
        self.line = line
        self.column = column
    }

    public func moving(line: LineIndex? = nil, column: ColumnIndex? = nil) -> UIPosition {
        UIPosition(
            line: self.line + (line ?? 0),
            column: self.column + (column ?? 0)
        )
    }

    public func copy(line: LineIndex? = nil, column: ColumnIndex? = nil) -> UIPosition {
        UIPosition(
            line: line ?? self.line,
            column: column ?? self.column
        )
    }
}

public extension BufferPosition {
    init(_ position: UIPosition) {
        self.init(
            line: position.line + 1,
            column: position.column + 1
        )
    }
}

/// Represents a text selection in an UI text area.
public struct UISelection: Equatable {

    /// Fixed start of the selection.
    public var start: UIPosition

    /// Movable end of the selection.
    public var end: UIPosition

    public init(start: UIPosition = .init(), end: UIPosition = .init()) {
        self.start = start
        self.end = end
    }

    public func copy(
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
}

// MARK: Logging

extension UIPosition: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["line": line, "column": column]
    }
}

extension UISelection: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["start": start, "end": end]
    }
}
