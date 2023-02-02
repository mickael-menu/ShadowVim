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

/// Decorates a `Logger` with an initial "parent" payload.
///
/// This can be used to pre-set attributes in a payload.
public struct AttributedLogger: Logger {
    private let logger: Logger
    fileprivate let payload: LogPayload

    public init(
        logger: Logger,
        payload: LogPayload
    ) {
        self.logger = logger
        self.payload = payload
    }

    public func log(_ entry: LogEntry) {
        var entry = entry
        entry.payload = reducePayload(outer: entry.payload, inner: payload)
        logger.log(entry)
    }
}

public extension Logger {
    func with(_ key: LogKey, to value: LogValueConvertible) -> Logger {
        AttributedLogger(logger: self, payload: [key: value.logValue])
    }

    func with(_ payload: LogPayloadConvertible) -> Logger {
        let outerPayload = payload.logPayload().mapValues(\.logValue)
        let innerPayload = (self as? AttributedLogger)?.payload ?? [:]

        return AttributedLogger(
            logger: self,
            payload: reducePayload(outer: outerPayload, inner: innerPayload)
        )
    }

    func tagged(_ tag: String) -> Logger {
        with(.tag, to: tag)
    }
}

public func reducePayload(outer: LogPayload, inner: LogPayload) -> LogPayload {
    var payload: LogPayload = [:]
    let keys = Set(outer.keys).union(Set(inner.keys))
    for key in keys {
        let outerValue = outer[key]
        let innerValue = inner[key]

        switch key {
        case .message:
            guard
                case let .string(ov) = outerValue,
                case let .string(iv) = innerValue
            else {
                payload[key] = outerValue ?? innerValue
                continue
            }
            payload[key] = .string("\(ov)\n\(iv)")

        case .tag:
            guard
                case let .string(ov) = outerValue,
                case let .string(iv) = innerValue
            else {
                payload[key] = outerValue ?? innerValue
                continue
            }
            payload[key] = .string("\(iv).\(ov)")

        default:
            payload[key] = outerValue ?? innerValue
        }
    }

    return payload
}
