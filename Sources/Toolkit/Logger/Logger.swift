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

/// A logger supporting structured logging.
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
                res.merge(i.logPayload().mapValues(\.logValue)) { _, new in new }
            }
        ))
    }
}

public struct LogEntry {
    /// Severity level.
    public let level: LogLevel
    public let file: String
    public let line: Int
    public let function: String

    /// Structured payload for this log entry.
    public var payload: LogPayload

    public init(
        level: LogLevel,
        file: String,
        line: Int,
        function: String,
        payload: LogPayload
    ) {
        self.level = level
        self.file = file
        self.line = line
        self.function = function
        self.payload = payload
    }
}

/// Severity level.
public enum LogLevel: Int, Comparable {
    case debug
    case info
    case warning
    case error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A `LogKey` identifies a structured metadata in a `LogPayload`.
public struct LogKey: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    /// Free tag for grouping entries together.
    public static let tag: LogKey = "tag"

    /// A human-readable string message.
    public static let message: LogKey = "message"

    /// The callstack returned by `Thread.callStackSymbols`.
    public static let callStack: LogKey = "callStack"

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public typealias LogPayload = [LogKey: LogValue]

public protocol LogPayloadConvertible: LogValueConvertible {
    func logPayload() -> [LogKey: any LogValueConvertible]
}

extension String: LogPayloadConvertible {
    public func logPayload() -> [LogKey: any LogValueConvertible] {
        [.message: self]
    }
}

public extension LogPayloadConvertible {
    func logValue() -> LogValue {
        .dict(logPayload().mapValues(\.logValue))
    }
}

extension Dictionary: LogPayloadConvertible where Key == LogKey, Value == any LogValueConvertible {
    public func logPayload() -> [LogKey: any LogValueConvertible] { self }
}
