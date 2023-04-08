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
public struct BufferPosition: Equatable, Comparable {
    public var line: LineIndex
    public var column: ColumnIndex

    public init(line: LineIndex = 1, column: ColumnIndex = 1) {
        self.line = line
        self.column = column
    }

    public func moving(line: LineIndex? = nil, column: ColumnIndex? = nil) -> BufferPosition {
        BufferPosition(
            line: self.line + (line ?? 0),
            column: self.column + (column ?? 0)
        )
    }

    public func copy(line: LineIndex? = nil, column: ColumnIndex? = nil) -> BufferPosition {
        BufferPosition(
            line: line ?? self.line,
            column: column ?? self.column
        )
    }

    public static func < (lhs: BufferPosition, rhs: BufferPosition) -> Bool {
        if lhs.line == rhs.line {
            return lhs.column < rhs.column
        } else {
            return lhs.line < rhs.line
        }
    }
}

/// https://neovim.io/doc/user/builtin.html#mode()
public enum Mode: String, Equatable {
    case normal = "n"
    case operatorPending = "no"
    case visual = "v"
    case visualLine = "V"
    case visualBlock = "\u{16}" // Ctrl-V
    case select = "s"
    case selectLine = "S"
    case selectBlock = "\u{13}" // Ctrl-S
    case insert = "i"
    case replace = "R"
    case cmdline = "c"
    case hitEnterPrompt = "r"
    case shell = "!"
    case terminal = "t"

    public init?(name: String) {
        if name.hasPrefix("no") {
            self = .operatorPending
        } else if let name = name.first.map(String.init) {
            self.init(rawValue: name)
        } else {
            return nil
        }
    }
}

// MARK: - Logging

extension Mode: LogValueConvertible {
    public var logValue: LogValue {
        .string(rawValue)
    }
}

extension BufferPosition: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["line": line, "column": column]
    }
}
