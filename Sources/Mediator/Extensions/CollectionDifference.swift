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

extension CollectionDifference {
    /// Returns the offset and new value of the updated item, if there's only
    /// one in this diff.
    var updatedSingleItem: (offset: Int, element: ChangeElement)? {
        guard
            insertions.count == 1,
            removals.count == 1,
            insertions[0].offset == removals[0].offset,
            case let .insert(offset, element, _) = insertions.first
        else {
            return nil
        }

        return (offset, element)
    }
}

extension CollectionDifference.Change {
    var offset: Int {
        switch self {
        case let .insert(offset: offset, _, _):
            return offset
        case let .remove(offset: offset, _, _):
            return offset
        }
    }
}
