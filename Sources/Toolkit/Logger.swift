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

import CallStackSymbols
import Foundation

public enum LogValue {
    case `nil`
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case array([LogValue])
    case dict([LogKey: LogValue])

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
            for (i, v) in dict.enumerated() {
                if i > 0 {
                    output += "\n"
                }
                output += "\(indent)\(v.key.rawValue): "

                var valueOutput = v.value.format()
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

public protocol LogValueConvertible {
    func logValue() -> LogValue
}

extension LogValue: LogValueConvertible {
    public func logValue() -> LogValue { self }
}

public protocol LogPayloadConvertible: LogValueConvertible {
    func logPayload() -> [LogKey: any LogValueConvertible]
}

public extension Optional where Wrapped: LogValueConvertible {
    func logValue() -> LogValue {
        switch self {
        case .none:
            return .nil
        case let .some(value):
            return value.logValue()
        }
    }
}

extension Bool: LogValueConvertible {
    public func logValue() -> LogValue {
        .bool(self)
    }
}

extension Int: LogValueConvertible {
    public func logValue() -> LogValue {
        .int(self)
    }
}

extension Double: LogValueConvertible {
    public func logValue() -> LogValue {
        .double(self)
    }
}

extension String: LogValueConvertible {
    public func logValue() -> LogValue {
        .string(self)
    }
}

extension Data: LogValueConvertible {
    public func logValue() -> LogValue {
        .data(self)
    }
}

extension String: LogPayloadConvertible {
    public func logPayload() -> [LogKey: any LogValueConvertible] {
        [.message: self]
    }
}

public typealias LogPayload = [LogKey: LogValue]

public extension LogPayloadConvertible {
    func logValue() -> LogValue {
        .dict(logPayload().mapValues { $0.logValue() })
    }
}

extension Array: LogValueConvertible where Element: LogValueConvertible {
    public func logValue() -> LogValue {
        .array(map { $0.logValue() })
    }
}

extension Dictionary: LogValueConvertible where Key == LogKey, Value == any LogValueConvertible {
    public func logValue() -> LogValue {
        .dict(logPayload().mapValues { $0.logValue() })
    }
}

extension Dictionary: LogPayloadConvertible where Key == LogKey, Value == any LogValueConvertible {
    public func logPayload() -> [LogKey: any LogValueConvertible] { self }
}

public struct LogEntry {
    public let level: LogLevel
    public let file: String
    public let line: Int
    public let function: String
    public let payload: LogPayload

    public init(
        level: LogLevel,
        file: String,
        line: Int,
        function: String,
        payload: [LogKey: LogValue]
    ) {
        self.level = level
        self.file = file
        self.line = line
        self.function = function
        self.payload = payload
    }
}

public enum LogLevel: Int, Comparable {
    case debug
    case info
    case warning
    case error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct LogKey: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    public static let message = LogKey(rawValue: "message")
    public static let callStack = LogKey(rawValue: "callStack")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public protocol Logger {
    func log(_ entry: LogEntry)
}

public extension Logger {
    func log(_ level: LogLevel, _ payloads: LogPayloadConvertible..., file: String = #file, line: Int = #line, function: String = #function) {
        log(level: level, file: file, line: line, function: function, payloads: payloads)
    }

    func d(_ payloads: LogPayloadConvertible..., file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .debug, file: file, line: line, function: function, payloads: payloads)
    }

    func i(_ payloads: LogPayloadConvertible..., file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .info, file: file, line: line, function: function, payloads: payloads)
    }

    func w(_ payloads: LogPayloadConvertible..., file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .warning, file: file, line: line, function: function, payloads: payloads)
    }

    func e(_ payloads: LogPayloadConvertible..., file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .error, file: file, line: line, function: function, payloads: payloads)
    }

    func w(_ error: Error, file: String = #file, line: Int = #line, function: String = #function) {
        log(error: error, level: .warning, file: file, line: line, function: function)
    }

    func e(_ error: Error, file: String = #file, line: Int = #line, function: String = #function) {
        log(error: error, level: .error, file: file, line: line, function: function)
    }

    private func log(error: Error, level: LogLevel, file: String, line: Int, function: String) {
        var payload: [LogKey: any LogValueConvertible] = [
            .message: "Error: \(String(reflecting: error))",
            .callStack: Thread.callStackSymbols,
        ]
        if let error = error as? LocalizedError {
            if let desc = error.errorDescription {
                payload["errorDescription"] = desc
            }
            if let reason = error.failureReason {
                payload["failureReason"] = reason
            }
        }
        log(level: level, file: file, line: line, function: function, payloads: [payload])
    }

    private func log(level: LogLevel, file: String, line: Int, function: String, payloads: [LogPayloadConvertible]) {
        log(LogEntry(
            level: level,
            file: file,
            line: line,
            function: function,
            payload: payloads.reduce(into: [:]) { res, i in
                res.merge(i.logPayload().mapValues { $0.logValue() }) { _, new in new }
            }
        ))
    }
}
