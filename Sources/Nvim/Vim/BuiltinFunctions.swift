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

/// Swift wrapper around Vim's built-in functions
///
/// See https://neovim.io/doc/user/builtin.html
@dynamicMemberLookup
public final class BuiltinFunctions {
    private let api: API

    init(api: API) {
        self.api = api
    }

    /// Dynamic resolution for the builtin functions.
    public subscript(dynamicMember name: String) -> (ValueConvertible...) -> Async<Value, NvimError> {
        { [api] args in
            api.callFunction(name, args: args)
        }
    }

    /// https://neovim.io/doc/user/builtin.html#getcharpos()
    public func getcharpos(_ position: Position) -> Async<GetposResult, NvimError> {
        api.callFunction("getpos", with: position.expr) {
            GetposResult($0)
        }
    }

    public struct GetposResult {
        public var bufnum: BufferHandle
        public var lnum: LineIndex
        public var col: ColumnIndex
        public var off: Int

        public init?(_ value: Value) {
            guard
                let values = value.arrayValue,
                values.count == 4,
                let bufnum = values[0].intValue,
                let lnum = values[1].intValue,
                let col = values[2].intValue,
                let off = values[3].intValue
            else {
                return nil
            }

            self.bufnum = BufferHandle(bufnum)
            self.lnum = LineIndex(lnum)
            self.col = ColumnIndex(col)
            self.off = off
        }

        public var position: BufferPosition {
            BufferPosition(line: lnum, column: col)
        }
    }

    /// Position expression.
    /// https://neovim.io/doc/user/builtin.html#line()
    public enum Position {
        /// The cursor position.
        case cursor
        /// The last line in the current buffer
        case lastLine
        /// Position of a mark.
        case mark(String)
        /// First line visible in current window.
        case firstVisibleLine
        /// Last line visible in current window.
        case lastVisibleLine
        /// In Visual mode: the start of the Visual area (the cursor is the
        /// end).  When not in Visual mode returns the cursor position.
        /// Differs from '< in that it's updated right away.
        case visual

        var expr: String {
            switch self {
            case .cursor: return "."
            case .lastLine: return "$"
            case let .mark(name): return "'\(name)"
            case .firstVisibleLine: return "w0"
            case .lastVisibleLine: return "w$"
            case .visual: return "v"
            }
        }
    }
}
