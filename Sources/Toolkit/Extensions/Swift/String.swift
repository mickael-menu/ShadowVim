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

public extension String {
    var lines: [Substring] {
        split(separator: "\n", omittingEmptySubsequences: false)
    }

    func indent(with indent: String) -> String {
        indent + split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: "\n" + indent)
    }

    /// Returns a copy of the string after removing the given `prefix`, when
    /// present.
    func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return String(dropFirst(prefix.count))
    }

    /// Returns a copy of the string after removing the given `suffix`, when
    /// present.
    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else {
            return self
        }
        return String(dropLast(suffix.count))
    }
}

public extension Range where Bound == String.Index {
    /// Converts a range of `String.Index` into a `CFRange` of character indices.
    func cfRange(in string: String) -> CFRange {
        CFRange(
            location: string.distance(from: string.startIndex, to: lowerBound),
            length: string.distance(from: lowerBound, to: upperBound)
        )
    }
}

public extension Sequence where Element: StringProtocol {
    func joinedLines() -> String {
        joined(separator: "\n")
    }
}
