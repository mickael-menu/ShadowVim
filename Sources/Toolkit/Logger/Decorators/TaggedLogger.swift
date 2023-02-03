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

/// A decorator presetting the `tag` of every log entry.
///
/// If the entry already has a `tag`, it is appended to the logger tag.
public struct TaggedLogger: Logger {
    private let logger: Logger
    private let tag: String

    public init(
        logger: Logger,
        tag: String
    ) {
        self.logger = logger
        self.tag = tag
    }

    public func log(_ entry: LogEntry) {
        var copy = entry
        copy.payload = {
            var payload = entry.payload().logPayload()
            var tag = tag
            if case let .string(entryTag) = payload[.tag]?.logValue {
                tag += ".\(entryTag)"
            }
            payload[.tag] = tag
            return payload
        }
        logger.log(copy)
    }
}

public extension Logger {
    func tagged(_ tag: String) -> Logger {
        TaggedLogger(logger: self, tag: tag)
    }
}
