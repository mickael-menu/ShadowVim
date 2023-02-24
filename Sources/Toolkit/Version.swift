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

enum VersionError: Error {
    case invalidVersion(String)
}

/// Represents a semantic version number.
///
/// See https://semver.org/
public struct Version: Equatable, Comparable, RawRepresentable {
    public let rawValue: String

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(rawValue: String) {
        do {
            let parts = try rawValue
                .split(separator: "-", maxSplits: 1)[0]
                .split(separator: ".")
                .map {
                    guard let value = Int($0) else {
                        throw VersionError.invalidVersion(rawValue)
                    }
                    return value
                }

            guard parts.count <= 3 else {
                return nil
            }

            self.init(
                major: parts.count > 0 ? parts[0] : 0,
                minor: parts.count > 1 ? parts[1] : 0,
                patch: parts.count > 2 ? parts[2] : 0
            )
        } catch {
            return nil
        }
    }

    public init(major: Int, minor: Int, patch: Int) {
        rawValue = "\(major).\(minor).\(patch)"
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }
        return false
    }
}

extension Version: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)!
    }
}

extension Version: CustomStringConvertible {
    public var description: String { rawValue }
}

private func format(major: Int, minor: Int, patch: Int) -> String {
    "\(major).\(minor).\(patch)"
}
