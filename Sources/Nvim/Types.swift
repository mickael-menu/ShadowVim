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
import Toolkit

public typealias BufferName = String
public typealias BufferHandle = Int
public typealias WindowHandle = Int
public typealias TabpageHandle = Int

public typealias AutocmdID = Int

/// 1-indexed line number.
public typealias LineIndex = Int

/// 1-indexed column number.
public typealias ColumnIndex = Int

/// Buffer location as 1-indexed offsets.
public struct BufferPosition: Equatable {
    public var line: LineIndex
    public var column: ColumnIndex

    public init(line: LineIndex = 1, column: ColumnIndex = 1) {
        self.line = line
        self.column = column
    }

    public func moving(line: LineIndex? = nil, column: ColumnIndex? = nil) -> BufferPosition {
        BufferPosition(
            line: self.line + (line ?? 1),
            column: self.column + (column ?? 1)
        )
    }

    public func copy(line: LineIndex? = nil, column: ColumnIndex? = nil) -> BufferPosition {
        BufferPosition(
            line: line ?? self.line,
            column: column ?? self.column
        )
    }
}

/// https://neovim.io/doc/user/builtin.html#mode()
public enum Mode: String, Equatable {
    case normal = "n"
    case visual = "v"
    case visualLine = "V"
    case select = "s"
    case selectLine = "S"
    case insert = "i"
    case replace = "R"
    case cmdline = "c"
    case hitEnterPrompt = "r"
    case shell = "!"
    case terminal = "t"
}

public struct Cursor: Equatable {
    /// The current mode.
    public var mode: Mode

    /// The cursor position.
    public var position: BufferPosition

    /// The start of the visual area.
    ///
    /// When not in Visual or Select mode, this is the same as the cursor
    /// `position`.
    public var visual: BufferPosition

    public init(mode: Mode, position: BufferPosition, visual: BufferPosition) {
        self.mode = mode
        self.position = position
        self.visual = visual
    }
}

extension BufferPosition: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["line": line, "column": column]
    }
}

extension Cursor: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["position": position, "mode": mode.rawValue]
    }
}
