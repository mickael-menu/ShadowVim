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
import Toolkit

enum LinesDiffChange {
    case insert(index: LineIndex, lines: [String])
    case remove(indices: ClosedRange<LineIndex>)
}

extension LinesDiffChange: LogPayloadConvertible {
    func logPayload() -> [LogKey: LogValueConvertible] {
        switch self {
        case let .insert(index, lines):
            return ["@type": "insert", "index": index, "lines": lines]
        case let .remove(indices):
            return ["@type": "remove", "indices": "\(indices.lowerBound)...\(indices.upperBound)"]
        }
    }
}

extension CollectionDifference where ChangeElement == String {
    func coalesceChanges() -> [LinesDiffChange] {
        guard !isEmpty else {
            return []
        }

        var changes: [LinesDiffChange] = []
        var firstOffset: Int? = nil
        var lastOffset: Int? = nil
        var lines: [String] = []

        for change in removals.reversed() {
            guard case let .remove(offset, _, _) = change else {
                assertionFailure("Unexpected change in removals")
                continue
            }
            print(change)

            if offset + 1 == firstOffset {
                firstOffset = offset
            } else {
                flushRemove()

                firstOffset = offset
                lastOffset = offset
            }
        }
        flushRemove()

        for change in insertions {
            guard case let .insert(offset, line, _) = change else {
                assertionFailure("Unexpected change in insertions")
                continue
            }

            print(change)
            if offset - 1 == lastOffset {
                lastOffset = offset
                lines.append(line)
            } else {
                flushInsert()

                firstOffset = offset
                lastOffset = offset
                lines.append(line)
            }
        }
        flushInsert()

        func flushInsert() {
            guard
                let first = firstOffset,
                !lines.isEmpty
            else {
                return
            }
            changes.append(.insert(index: first, lines: lines))
            firstOffset = nil
            lastOffset = nil
            lines = []
        }

        func flushRemove() {
            guard
                let first = firstOffset,
                let last = lastOffset
            else {
                return
            }
            changes.append(.remove(indices: first ... last))
            firstOffset = nil
            lastOffset = nil
        }

        return changes
    }
}

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
