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

/// An `AsyncGroup` runs a list of `Async` tasks serially in the order they
/// were added.
///
///     withAsyncGroup { group in
///         for url in urls {
///             http.fetch(url)
///                .add(to: group)
///         }
///     }
///     .logFailure()
///     .get { results in ... }
public class AsyncGroup<GroupSuccess, TaskSuccess, Failure: Error> {
    public typealias Reduce = (_ result: GroupSuccess, _ element: TaskSuccess) -> GroupSuccess

    private let start: GroupSuccess
    private let reduce: Reduce
    private var isJoined = false
    private var tasks: [Async<TaskSuccess, Failure>] = []

    fileprivate init(start: GroupSuccess, reduce: @escaping Reduce) {
        self.start = start
        self.reduce = reduce
    }

    public func add(_ task: Async<TaskSuccess, Failure>) {
        precondition(!isJoined)
        tasks.append(task)
    }

    public func join() -> Async<GroupSuccess, Failure> {
        precondition(!isJoined)
        isJoined = true
        return joinNext(result: start)
    }

    private func joinNext(result: GroupSuccess) -> Async<GroupSuccess, Failure> {
        guard !tasks.isEmpty else {
            return .success(result)
        }
        return tasks.removeFirst()
            .flatMap { [self] element in
                joinNext(result: reduce(result, element))
            }
    }
}

public extension Async {
    /// Shortcut to add a task to an `AsyncGroup`.
    func add<GroupSuccess>(to group: AsyncGroup<GroupSuccess, Success, Failure>) {
        group.add(self)
    }
}

/// Creates an `AsyncGroup` that will collect the tasks results in a list.
public func withAsyncGroup<TaskSuccess, Failure: Error>(
    body: (AsyncGroup<[TaskSuccess], TaskSuccess, Failure>) throws -> Void
) rethrows -> Async<[TaskSuccess], Failure> {
    let group = AsyncGroup<[TaskSuccess], TaskSuccess, Failure>(
        start: [],
        reduce: { res, i in
            var res = res
            res.append(i)
            return res
        }
    )
    try body(group)
    return group.join()
}

/// Creates an `AsyncGroup` ignoring any tasks result.
public func withAsyncGroup<TaskSuccess, Failure: Error>(
    body: (AsyncGroup<Void, TaskSuccess, Failure>) throws -> Void
) rethrows -> Async<Void, Failure> {
    let group = AsyncGroup<Void, TaskSuccess, Failure>(start: (), reduce: { _, _ in () })
    try body(group)
    return group.join()
}

/// Creates an `AsyncGroup` with a custom `reduce` strategy for its result.
public func withAsyncGroup<GroupSuccess, TaskSuccess, Failure: Error>(
    start: GroupSuccess,
    reduce: @escaping AsyncGroup<GroupSuccess, TaskSuccess, Failure>.Reduce,
    body: (AsyncGroup<GroupSuccess, TaskSuccess, Failure>) throws -> Void
) rethrows -> Async<GroupSuccess, Failure> {
    let group = AsyncGroup<GroupSuccess, TaskSuccess, Failure>(start: start, reduce: reduce)
    try body(group)
    return group.join()
}
