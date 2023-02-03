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
    fileprivate let payload: LogPayloadConvertible

    public init(
        logger: Logger,
        payload: LogPayloadConvertible
    ) {
        self.logger = logger
        self.payload = payload
    }

    public func log(_ entry: LogEntry) {
        logger.log(entry.combined(with: payload))
    }
}

public extension Logger {
    func with(_ payload: LogPayloadConvertible) -> Logger {
        AttributedLogger(
            logger: self,
            payload: payload
        )
    }

    func with(_ key: LogKey, to value: LogValueConvertible) -> Logger {
        with([key: value])
    }
}
