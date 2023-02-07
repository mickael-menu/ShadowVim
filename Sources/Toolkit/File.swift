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

/// Lossy equatable error wrapper to help with unit testing and keeping enum
/// equatables.
public struct EquatableError: Equatable {
    public let error: Error

    public init(error: Error) {
        self.error = error
    }

    public static func == (lhs: EquatableError, rhs: EquatableError) -> Bool {
        String(reflecting: lhs.error) == String(reflecting: rhs.error)
    }
}

extension EquatableError: LogValueConvertible {
    public var logValue: LogValue { .string(String(reflecting: error)) }
}

public extension Error {
    func equatable() -> EquatableError {
        EquatableError(error: self)
    }
}
