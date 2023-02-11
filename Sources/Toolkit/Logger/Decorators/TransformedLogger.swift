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

public struct TransformedLogger: Logger {
    private let logger: Logger
    private let transform: (LogEntry) -> LogEntry?

    public init(logger: Logger, transform: @escaping (LogEntry) -> LogEntry?) {
        self.logger = logger
        self.transform = transform
    }

    public func log(_ entry: LogEntry) {
        guard let entry = transform(entry) else {
            return
        }
        logger.log(entry)
    }
}

public extension Logger {
    func map(_ transform: @escaping (LogEntry) -> LogEntry?) -> Logger {
        TransformedLogger(logger: self, transform: transform)
    }

    /// A decorator filtering incoming log entries satisfying the given predicate.
    func filter(isLogged: @escaping (LogEntry) -> Bool) -> Logger {
        map { isLogged($0) ? $0 : nil }
    }

    /// A decorator filtering incoming log entries with the given
    /// `minimumLevel`.
    ///
    /// If `domains` are provided, only entries starting with one of these
    /// domains will be forwarded. Including the subdomains.
    ///
    /// A domain prefixed with `!` is ignored.
    func filter(minimumLevel: LogLevel = .trace, domains: [String] = []) -> Logger {
        func isDomainAuthorized(_ entry: LogEntry) -> LogEntry? {
            guard !domains.isEmpty else {
                return entry
            }

            let payload = entry.payload().logPayload()
            var entry = entry
            entry.payload = { payload } // To avoid recomputing it downstream.

            var foundMatches = false
            if case let .string(entryDomain) = payload[.domain]?.logValue {
                for var domain in domains {
                    var ignore = false
                    if domain.first == "!" {
                        ignore = true
                        domain.removeFirst()
                    }

                    if entryDomain == domain || entryDomain.hasPrefix("\(domain).") {
                        if ignore {
                            return nil
                        }
                        foundMatches = true
                    }
                }
            }

            return foundMatches ? entry : nil
        }

        return map { entry in
            guard entry.level >= minimumLevel else {
                return nil
            }

            return isDomainAuthorized(entry)
        }
    }
}
