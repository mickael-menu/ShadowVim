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

public typealias LineIndex = Int
public typealias ColumnIndex = Int

/// Buffer location as 0-indexed offsets.
public struct BufferPosition: Equatable {
    public var line: LineIndex
    public var column: ColumnIndex

    public init(line: LineIndex = 0, column: ColumnIndex = 0) {
        self.line = line
        self.column = column
    }
}

public struct BufferSelection: Equatable {
    public var start: BufferPosition
    public var end: BufferPosition

    public init(start: BufferPosition = .init(), end: BufferPosition = .init()) {
        self.start = start
        self.end = end
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
    public var position: BufferPosition
    public var mode: Mode

    public init(position: BufferPosition, mode: Mode) {
        self.position = position
        self.mode = mode
    }
}

extension BufferPosition: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["line": line, "column": column]
    }
}

extension BufferSelection: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["start": start, "end": end]
    }
}

extension Cursor: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["position": position, "mode": mode.rawValue]
    }
}
