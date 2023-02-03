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

/// Value types supported by the logger.
public enum LogValue {
    case `nil`
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case array([LogValue])
    case dict([LogKey: LogValue])

    /// Formats the receiving value into its string representation.
    public func format(indent: String = "    ") -> String {
        switch self {
        case .nil:
            return "nil"
        case let .bool(bool):
            return String(bool)
        case let .int(int):
            return String(int)
        case let .double(double):
            return String(double)
        case let .string(string):
            return "\"\(string)\""
        case let .data(data):
            return "Data (\(data.count) bytes)"
        case let .array(array):
            guard !array.isEmpty else {
                return "[]"
            }

            var output: String = "[\n"
            for (i, v) in array.enumerated() {
                if i > 0 {
                    output += "\n"
                }
                output += v.format(indent: indent).indent(with: indent) + ","
            }
            output += "\n]"
            return output

        case let .dict(dict):
            guard !dict.isEmpty else {
                return "{}"
            }

            var output: String = "{\n"
            let keys = dict.keys.sorted(by: { k1, k2 in k1.rawValue.localizedStandardCompare(k2.rawValue) == .orderedAscending })
            for (i, k) in keys.enumerated() {
                guard let v = dict[k] else {
                    continue
                }
                if i > 0 {
                    output += "\n"
                }
                output += "\(indent)\(k.rawValue): "

                var valueOutput = v.format()
                if valueOutput.range(of: "\n") != nil {
                    valueOutput = "\n" + valueOutput.indent(with: indent + indent)
                }
                output += valueOutput
            }
            output += "\n}"
            return output
        }
    }
}

/// Converts an object into a `LogValue`.
public protocol LogValueConvertible {
    var logValue: LogValue { get }
}

extension LogValue: LogValueConvertible {
    public var logValue: LogValue { self }
}

public extension Optional where Wrapped: LogValueConvertible {
    var logValue: LogValue {
        switch self {
        case .none:
            return .nil
        case let .some(value):
            return value.logValue
        }
    }
}

extension Bool: LogValueConvertible {
    public var logValue: LogValue {
        .bool(self)
    }
}

extension Int: LogValueConvertible {
    public var logValue: LogValue {
        .int(self)
    }
}

extension Int64: LogValueConvertible {
    public var logValue: LogValue {
        .int(Int(self))
    }
}

extension UInt64: LogValueConvertible {
    public var logValue: LogValue {
        .int(Int(self))
    }
}

extension Double: LogValueConvertible {
    public var logValue: LogValue {
        .double(self)
    }
}

extension String: LogValueConvertible {
    public var logValue: LogValue {
        .string(self)
    }
}

extension Data: LogValueConvertible {
    public var logValue: LogValue {
        .data(self)
    }
}

extension Array: LogValueConvertible where Element: LogValueConvertible {
    public var logValue: LogValue {
        .array(map(\.logValue))
    }
}

extension Dictionary: LogValueConvertible where Key == LogKey, Value == any LogValueConvertible {
    public var logValue: LogValue {
        .dict(logPayload().mapValues(\.logValue))
    }
}
