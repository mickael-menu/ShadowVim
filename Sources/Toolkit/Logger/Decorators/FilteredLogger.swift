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

/// A decorator filtering incoming log entries satisfying the given predicate.
public struct FilteredLogger: Logger {
    private let logger: Logger
    private let isLogged: (LogEntry) -> Bool

    public init(logger: Logger, isLogged: @escaping (LogEntry) -> Bool) {
        self.logger = logger
        self.isLogged = isLogged
    }

    public func log(_ entry: LogEntry) {
        guard isLogged(entry) else {
            return
        }
        logger.log(entry)
    }
}

public extension Logger {
    func filter(isLogged: @escaping (LogEntry) -> Bool) -> Logger {
        FilteredLogger(logger: self, isLogged: isLogged)
    }

    func filter(minimumLevel: LogLevel) -> Logger {
        filter { $0.level >= minimumLevel }
    }
}
