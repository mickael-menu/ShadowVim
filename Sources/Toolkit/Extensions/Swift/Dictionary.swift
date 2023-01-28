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

public extension Dictionary {
    /// Returns the value for the given `key` if the value is present and not `nil`. Otherwise,
    /// puts the `defaultValue` into the dictionary under the given key and returns it.
    mutating func getOrPut(_ key: Key, defaultValue: () throws -> Value) rethrows -> Value {
        if let value = self[key] {
            return value
        }
        let value = try defaultValue()
        self[key] = value
        return value
    }
}
