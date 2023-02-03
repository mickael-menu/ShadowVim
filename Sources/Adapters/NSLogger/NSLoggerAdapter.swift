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

import NSLogger
import Toolkit

/// An implementation of `Toolkit.Logger` using NSLogger under the hood.
public struct NSLoggerLogger: Toolkit.Logger {
    private let logger: NSLogger.Logger

    public init(logger: NSLogger.Logger = .shared) {
        self.logger = logger
    }

    public func log(_ entry: LogEntry) {
        DispatchQueue.main.async {
            var payload = entry.payload().logPayload().mapValues(\.logValue)
            let domain = payload.removeNSDomain()

            var output = ""

            if case let .string(message) = payload.removeValue(forKey: .message) {
                output += message
            }

            if !payload.isEmpty {
                let payloadOutput = LogValue.dict(payload).format()
                if !output.isEmpty {
                    output += "\n"
                }
                output += payloadOutput
            }

            logger.log(domain, entry.level.nsLevel, output, entry.file, entry.line, entry.function)
        }
    }
}

private extension LogPayload {
    mutating func removeNSDomain() -> NSLogger.Logger.Domain {
        guard case let .string(tag) = removeValue(forKey: .tag) else {
            return .custom("app")
        }
        return .custom(tag)
    }
}

private extension LogLevel {
    var nsLevel: NSLogger.Logger.Level {
        switch self {
        case .trace:
            return .noise
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }
}
