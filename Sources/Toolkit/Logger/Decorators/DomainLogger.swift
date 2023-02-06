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

/// A decorator presetting the `domain` of every log entry.
///
/// If the entry already has a `domain`, it becomes a subdomain of the logger
/// domain.
public struct DomainLogger: Logger {
    private let logger: Logger
    private let domain: String

    public init(
        logger: Logger,
        domain: String
    ) {
        self.logger = logger
        self.domain = domain
    }

    public func log(_ entry: LogEntry) {
        var copy = entry
        copy.payload = {
            var payload = entry.payload().logPayload()
            var domain = domain
            if case let .string(entryDomain) = payload[.domain]?.logValue {
                domain += ".\(entryDomain)"
            }
            payload[.domain] = domain
            return payload
        }
        logger.log(copy)
    }
}

public extension Logger {
    
    /// Creates a new logger as a sub-domain of the receiver.
    func domain(_ domain: String) -> Logger {
        DomainLogger(logger: self, domain: domain)
    }
}
