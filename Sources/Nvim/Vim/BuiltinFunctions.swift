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
    public subscript(dynamicMember member: String) -> (ValueConvertible...) -> Async<Value, NvimError> {
        { [api] args in
            api.callFunction(member, args: args)
        }
    }

    /// Get the position for
    /// https://neovim.io/doc/user/builtin.html#getpos()
    public func getpos(_ position: Position) -> Async<GetposResult, NvimError> {
        api.callFunction("getpos", with: position.expr) { value in
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

            return (
                bufnum: BufferHandle(bufnum),
                lnum: LineIndex(lnum),
                col: ColumnIndex(col),
                off: off
            )
        }
    }

    public typealias GetposResult = (
        bufnum: BufferHandle,
        lnum: LineIndex,
        col: ColumnIndex,
        off: Int
    )

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
