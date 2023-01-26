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

/// Continuation monad implementation to manipulate asynchronous values easily,
/// with error forwarding.
///
/// This is used instead of Swift async tasks when the order of execution
/// of tasks matters.
///
/// This is NOT a Promise implementation, because state-less, simpler and not
/// thread-safe. It's a purely syntactic tool meant to flatten a sequence of
/// closure-based asynchronous calls into a monadic chain.
///
/// For example:
///
///     fetchFoo { status, error1 in
///         guard var status = val1 else {
///             completion(nil, error1)
///             return
///         }
///         status = "\(status + 100)"
///         parseBar(status) { object, error2 in
///             guard let object = object else {
///                 completion(nil, error2)
///                 return
///             }
///             do {
///                 let result = try processThing(object)
///                 completion(result, nil)
///             } catch {
///                 completion(nil, error)
///             }
///         }
///     }
///
/// becomes (if the async functions return `Deferred` objects):
///
///     fetchFoo()
///         // Transforms the value synchronously with map
///         .map { status in "\(status + 100)" }
///
///         // Transforms using an async function with flatMap, if it returns
///         // a Deferred
///         .flatMap(parseBar)
///
///         // If you don't call `get` nothing is executed, unlike Promises
///         // which are eager
///         .get(
///             onFailure: { print($0) },
///             onSuccess: { handle($0) }
///         )
public final class Deferred<Success, Failure: Error> {
    /// Traditional completion closure signature.
    public typealias Completion = (Result<Success, Failure>) -> Void

    /// A typed completion closure signature.
    public typealias NewCompletion<NewSuccess, NewFailure: Error> = (Result<NewSuccess, NewFailure>) -> Void

    /// Dispatch queue on which the `task` will be (asynchronously) executed.
    private let queue: DispatchQueue

    /// Task to run asynchronously.
    private let task: (@escaping Completion) -> Void

    /// Indicates whether the `Deferred` was executed already. It can only be
    /// executed once.
    private var done: Bool = false

    /// Constructs a `Deferred` from a task taking a traditional completion
    /// block to return its result.
    ///
    /// The task will be executed asynchronously on the given `queue`.
    public init(
        on queue: DispatchQueue = .global(),
        task: @escaping (@escaping Completion) -> Void
    ) {
        self.task = task
        self.queue = queue
    }

    /// Constructs a `Deferred` in a Promise style with two completion closures:
    /// one for the success, and one for the failure.
    ///
    ///     Deferred<Data, FetchError> { success, failure in
    ///         fetch(input) { response in
    ///             guard response.status == 200 else {
    ///                 failure(.wrongStatus)
    ///                 return
    ///             }
    ///             success(response.data)
    ///         }
    ///     }
    convenience init(
        on queue: DispatchQueue = .global(),
        task: @escaping (
            @escaping (Success) -> Void,
            @escaping (Failure) -> Void
        ) -> Void
    ) {
        self.init(on: queue) { completion in
            task(
                { completion(.success($0)) },
                { completion(.failure($0)) }
            )
        }
    }

    /// Shortcut to build a `Deferred` from a success value.
    ///
    /// Can be useful to return early a value in a `.flatMap`.
    public class func success(_ value: Success) -> Self {
        Self { $0(.success(value)) }
    }

    /// Shortcut to build a `Deferred` from an error.
    ///
    /// Can be useful to return early a value in a `.flatMap`.
    public class func failure(_ error: Failure) -> Self {
        Self { $0(.failure(error)) }
    }

    /// Constructs a `Deferred` from a closure taking a traditional completion
    /// block to return its result.
    ///
    /// Any thrown error is caught and wrapped in a `Result`.
    public class func catching(
        on queue: DispatchQueue = .global(),
        task: @escaping (@escaping Deferred<Success, Error>.Completion) throws -> Void
    ) -> Deferred<Success, Error> {
        Deferred<Success, Error>(on: queue) { completion in
            do {
                try task(completion)
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Runs the deferred task and forwards the result to the given
    /// `completion` block.
    ///
    /// The completion block is systematically dispatched
    /// asynchronously on the given queue (default is the main thread), to
    /// avoid temporal coupling at the calling site.
    public func getResult(
        on completionQueue: DispatchQueue = .main,
        _ completion: @escaping Completion
    ) {
        run { result in
            completionQueue.async {
                completion(result)
            }
        }
    }

    /// Runs the deferred task and forwards the result to `onSuccess`, or any
    /// error to `onFailure`.
    public func get(
        on completionQueue: DispatchQueue = .main,
        onFailure: @escaping (Failure) -> Void,
        onSuccess: @escaping (Success) -> Void
    ) {
        getResult(on: completionQueue) { result in
            switch result {
            case let .success(value):
                onSuccess(value)
            case let .failure(error):
                onFailure(error)
            }
        }
    }

    /// Transforms the computed value or error.
    public func map<NewSuccess, NewFailure>(
        success: @escaping (Success, @escaping NewCompletion<NewSuccess, NewFailure>) -> Void,
        failure: @escaping (Failure, @escaping NewCompletion<NewSuccess, NewFailure>) -> Void
    ) -> Deferred<NewSuccess, NewFailure> {
        Deferred<NewSuccess, NewFailure> { completion in
            self.run { result in
                switch result {
                case let .success(value):
                    success(value, completion)
                case let .failure(error):
                    failure(error, completion)
                }
            }
        }
    }

    /// Runs the deferred task and forwards the result to the given
    /// `completion` block.
    ///
    /// To keep things simple, this can only be called once.
    private func run(completion: @escaping Completion) {
        precondition(!done, "Deferred doesn't cache the task's value. It must only be called once.")
        done = true
        queue.async { self.task(completion) }
    }
}

public extension Deferred where Success == Void {
    /// Runs the deferred task and forwards any error to `onFailure`.
    func get(
        on completionQueue: DispatchQueue = .main,
        onFailure: @escaping (Failure) -> Void
    ) {
        get(
            on: completionQueue,
            onFailure: onFailure,
            onSuccess: { _ in }
        )
    }
}

public extension Deferred where Failure == Never {
    /// Runs the deferred task and forwards the result to `onResult`.
    func get(on completionQueue: DispatchQueue = .main, onResult: @escaping (Success) -> Void) {
        get(
            on: completionQueue,
            onFailure: { _ in
                fatalError("Received an unexpected Error for a Deferred<_, Never>")
            },
            onSuccess: onResult
        )
    }

    /// Bridges the `Deferred` to async `Task`.
    func async() async -> Success {
        await withCheckedContinuation { continuation in
            get(onResult: {
                continuation.resume(returning: $0)
            })
        }
    }
}

public extension Deferred where Success == Void, Failure == Never {
    /// Runs the deferred task on the given `queue`.
    func run(on completionQueue: DispatchQueue = .main) {
        get(
            on: completionQueue,
            onResult: { _ in }
        )
    }
}

public extension Deferred {
    /// Closure called with the result when the deferred task is run.
    func onSuccess(
        _ callback: @escaping (Success) -> Void
    ) -> Deferred<Success, Failure> {
        map(
            success: { val, compl in
                callback(val)
                compl(.success(val))
            },
            failure: { err, compl in compl(.failure(err)) }
        )
    }

    /// Closure called with the error that occurred when the deferred task
    /// was run.
    func onFailure(
        _ callback: @escaping (Failure) -> Void
    ) -> Deferred<Success, Failure> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { err, compl in
                callback(err)
                compl(.failure(err))
            }
        )
    }

    /// Transforms the value synchronously.
    ///
    ///     .map { user in
    ///        "Hello, \(user.name)"
    ///     }
    func map<NewSuccess>(
        _ transform: @escaping (Success) -> NewSuccess
    ) -> Deferred<NewSuccess, Failure> {
        map(
            success: { val, compl in compl(.success(transform(val))) },
            failure: { err, compl in compl(.failure(err)) }
        )
    }

    /// Transforms the value synchronously, catching any error.
    func tryMap<NewSuccess>(
        _ transform: @escaping (Success) throws -> NewSuccess
    ) -> Deferred<NewSuccess, Error> {
        map(
            success: { val, compl in
                do {
                    compl(.success(try transform(val)))
                } catch {
                    compl(.failure(error))
                }
            },
            failure: { err, compl in compl(.failure(err)) }
        )
    }

    /// Transforms the value asynchronously using a nested `Deferred`.
    ///
    ///     func asyncOperation(value: Int) -> Deferred<String>
    ///
    ///     .flatMap { val in
    ///        asyncOperation(val)
    ///     }
    func flatMap<NewSuccess>(
        _ transform: @escaping (Success) -> Deferred<NewSuccess, Failure>
    ) -> Deferred<NewSuccess, Failure> {
        map(
            success: { val, compl in transform(val).getResult(compl) },
            failure: { err, compl in compl(.failure(err)) }
        )
    }

    /// Discards the returned value.
    func discardResult() -> Deferred<Void, Failure> {
        map { _ in () }
    }

    /// Returns a new `Deferred`, mapping any failure value using the given
    /// transformation.
    func mapError<NewFailure>(
        _ transform: @escaping (Failure) -> NewFailure
    ) -> Deferred<Success, NewFailure> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { err, compl in compl(.failure(transform(err))) }
        )
    }

    /// Returns a `Deferred` with the same value, but typed with a generic
    /// `Error`.
    func eraseToAnyError() -> Deferred<Success, Error> {
        mapError { $0 as Error }
    }

    /// Recovers from an error with the given `result` value.
    func replaceError(with result: Success) -> Deferred<Success, Never> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { _, compl in compl(.success(result)) }
        )
    }

    /// Attempts to recover from an error.
    ///
    /// You can either return an alternate success value, or throw again
    /// another (or the same) error to forward it.
    ///
    ///     .catch { error in
    ///        if case Error.network = error {
    ///           return fetch()
    ///        }
    ///        throw error
    ///     }
    func `catch`(
        _ transform: @escaping (Failure) -> Result<Success, Failure>
    ) -> Deferred<Success, Failure> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { err, compl in compl(transform(err)) }
        )
    }

    /// Same as `catch`, but attempts to recover asynchronously, by returning a
    /// new `Deferred` object.
    func flatCatch(
        _ transform: @escaping (Failure) -> Deferred<Success, Failure>
    ) -> Deferred<Success, Failure> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { err, compl in transform(err).getResult(compl) }
        )
    }

    /// Bridges the `Deferred` to async `Task`.
    func async() async throws -> Success {
        try await withCheckedThrowingContinuation { continuation in
            getResult { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Raises a fatal error when the task returns an error.
    func assertNoFailure() -> Deferred<Success, Never> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { error, _ in
                fatalError("Unexpected no failure, got: \(error.localizedDescription)")
            }
        )
    }
}
