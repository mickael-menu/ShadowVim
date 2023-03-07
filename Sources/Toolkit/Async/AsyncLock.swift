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

/// A non-blocking lock to protect critical sections.
///
/// Instead of blocking the calling thread, `acquire` returns an `Async` object
/// which will be completed when the lock is freed.
public class AsyncLock {
    private let name: String
    private let queue: DispatchQueue
    private var isLocked: Bool = false
    private var waitlist: [(Result<Void, Never>) -> Void] = []
    private let logger: Logger?

    public init(name: String, logger: Logger? = nil) {
        self.name = name
        queue = DispatchQueue(label: "menu.mickael.AsyncLock.\(name)")
        self.logger = logger
    }

    public func acquire() -> Async<Void, Never> {
        Async(on: queue) { [self] completion in
            if isLocked {
                waitlist.append(completion)
            } else {
                logger?.t("Locked \(name)")
                isLocked = true
                completion(.success(()))
            }
        }
    }

    public func release() {
        queue.async { [self] in
            if waitlist.isEmpty {
                logger?.t("Released \(name)")
                isLocked = false
            } else {
                waitlist.removeFirst()(.success(()))
            }
        }
    }
}
