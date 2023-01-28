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

/// Smart pointer protecting concurrent access to its memory to avoid data races.
///
/// This is also a property wrapper, which makes it easy to use as:
/// ```
/// @Atomic var data: Int
/// ```
///
/// The property becomes read-only, to prevent a common error when modifying
/// the property using its previous value. For example:
/// ```
/// data += 1
/// ```
/// This is not safe, because it's actually two operations: a read and a write.
/// The value might have changed between the moment you read it and when you
/// write the result of incrementing the value.
///
/// Instead, you must use `write()` to mutate the property:
/// ```
/// $data.write { value in
///     value += 1
/// }
/// ```
@propertyWrapper
public final class Atomic<Value> {
    private var value: Value

    /// Queue used to protect accesses to `value`.
    ///
    /// We could use a serial queue but that would impact performances as
    /// concurrent reads would not be possible. To make sure we don't get data
    /// races, writes are done using a `.barrier` flag.
    private let queue: DispatchQueue

    public init(
        wrappedValue value: Value,
        queue: DispatchQueue = DispatchQueue(label: "menu.mickael.Atomic", attributes: .concurrent)
    ) {
        self.queue = queue
        self.value = value
    }

    public var wrappedValue: Value {
        get { read() }
        set { fatalError("Use $property.write { $0 = ... } to mutate this property") }
    }

    public var projectedValue: Atomic<Value> {
        self
    }

    /// Reads the current value synchronously.
    public func read() -> Value {
        queue.sync {
            value
        }
    }

    /// Reads the current value asynchronously.
    public func read(completion: @escaping (Value) -> Void) {
        queue.async {
            completion(self.value)
        }
    }

    /// Writes the value synchronously in a safe way.
    public func write<T>(_ changes: (inout Value) throws -> T) rethrows -> T {
        // The `barrier` flag here guarantees that we will never have a
        // concurrent read on `value` while we are modifying it. This prevents
        // a data race.
        try queue.sync(flags: .barrier) {
            try changes(&value)
        }
    }
}
