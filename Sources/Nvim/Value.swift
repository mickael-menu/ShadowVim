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
import MessagePack
import Toolkit

/// See https://neovim.io/doc/user/api.html section "Basic types"
public enum Value: Hashable {
    case `nil`
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([Value])
    case dict([Value: Value])

    case buffer(BufferHandle)
    case window(WindowHandle)
    case tabpage(TabpageHandle)
}

extension Value: CustomStringConvertible {
    public var description: String {
        switch self {
        case .nil:
            return "nil"
        case let .bool(value):
            return "bool(\(value))"
        case let .int(value):
            return "int(\(value))"
        case let .double(value):
            return "double(\(value))"
        case let .string(string):
            return "string(\(string))"
        case let .array(array):
            return "array(\(array.description))"
        case let .dict(dict):
            return "dict(\(dict.description))"
        case let .buffer(handle):
            return "buffer(\(handle))"
        case let .window(handle):
            return "window(\(handle))"
        case let .tabpage(handle):
            return "tabpage(\(handle))"
        }
    }
}

/// Makes `Value` directly loggable with a `Logger`.
extension Value: LogValueConvertible {
    public var logValue: LogValue {
        switch nvimValue {
        case .nil:
            return .nil
        case let .bool(bool):
            return .bool(bool)
        case let .int(int):
            return .int(int)
        case let .double(double):
            return .double(double)
        case let .string(string):
            return .string(string)
        case let .array(array):
            return .array(array.map(\.logValue))
        case let .dict(dict):
            return .dict(dict.reduce(into: [:]) { res, i in
                let key = LogKey(rawValue: i.key.stringValue ?? String(describing: i.key))
                res[key] = i.value.logValue
            })
        case let .buffer(handle):
            return .string("buf#\(handle)")
        case let .window(handle):
            return .string("win#\(handle)")
        case let .tabpage(handle):
            return .string("tab#\(handle)")
        }
    }
}

public extension Value {
    /// True if `.nil`, false otherwise.
    var isNil: Bool {
        switch self {
        case .nil:
            return true
        default:
            return false
        }
    }

    /// The wrapped boolean value if `.bool`, `nil` otherwise.
    var boolValue: Bool? {
        switch self {
        case let .bool(value):
            return value
        default:
            return nil
        }
    }

    /// The wrapped integer if `.int`, `nil` otherwise.
    var intValue: Int? {
        switch self {
        case let .int(value):
            return value
        default:
            return nil
        }
    }

    /// The wrapped double value if `.double`, `nil` otherwise.
    var doubleValue: Double? {
        switch self {
        case let .double(value):
            return value
        default:
            return nil
        }
    }

    /// The wrapped string if `.string`, `nil` otherwise.
    var stringValue: String? {
        switch self {
        case let .string(string):
            return string
        default:
            return nil
        }
    }

    /// The wrapped array if `.array`, `nil` otherwise.
    var arrayValue: [Value]? {
        switch self {
        case let .array(array):
            return array
        default:
            return nil
        }
    }

    /// The wrapped dictionary if `.map`, `nil` otherwise.
    var dictValue: [Value: Value]? {
        if case let .dict(dict) = self {
            return dict
        } else {
            return nil
        }
    }

    /// The wrapped buffer handle if `.buffer`, `nil` otherwise.
    var bufferValue: BufferHandle? {
        if case let .buffer(handle) = self {
            return handle
        } else {
            return nil
        }
    }

    /// The wrapped window handle if `.window`, `nil` otherwise.
    var windowValue: WindowHandle? {
        if case let .window(handle) = self {
            return handle
        } else {
            return nil
        }
    }

    /// The wrapped tabpage handle if `.tabpage`, `nil` otherwise.
    var tabpageValue: TabpageHandle? {
        if case let .tabpage(handle) = self {
            return handle
        } else {
            return nil
        }
    }
}

public protocol ValueConvertible {
    var nvimValue: Value { get }
}

extension Value: ValueConvertible {
    public var nvimValue: Value {
        self
    }
}

extension Optional: ValueConvertible where Wrapped: ValueConvertible {
    public var nvimValue: Value {
        switch self {
        case .none:
            return .nil
        case let .some(value):
            return value.nvimValue
        }
    }
}

extension Bool: ValueConvertible {
    public var nvimValue: Value {
        .bool(self)
    }
}

extension Int: ValueConvertible {
    public var nvimValue: Value {
        .int(self)
    }
}

extension Double: ValueConvertible {
    public var nvimValue: Value {
        .double(self)
    }
}

extension String: ValueConvertible {
    public var nvimValue: Value {
        .string(self)
    }
}

extension Substring: ValueConvertible {
    public var nvimValue: Value {
        .string(String(self))
    }
}

extension Array: ValueConvertible where Element: ValueConvertible {
    public var nvimValue: Value {
        .array(map(\.nvimValue))
    }
}

// FIXME: Find a proper workaround? Can't use Value as it conflicts in Dictionary.
public typealias _Value = Value

extension Dictionary: ValueConvertible where Key: ValueConvertible, Value: ValueConvertible {
    public var nvimValue: _Value {
        let res = reduce(into: [:]) { res, item in
            res[item.key.nvimValue] = item.value.nvimValue
        }
        return .dict(res)
    }
}
