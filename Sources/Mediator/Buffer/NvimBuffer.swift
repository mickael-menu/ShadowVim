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

import Combine
import Foundation
import Nvim
import Toolkit

protocol BufferDelegate: AnyObject {
    func buffer(_ buffer: NvimBuffer, activateWith api: API) -> APIAsync<Void>
}

/// Represents a live buffer in Nvim.
final class NvimBuffer {
    typealias ChangeEvent = (lines: [String], event: BufLinesEvent)

    /// Nvim buffer handle.
    let handle: BufferHandle

    /// Name of the buffer.
    var name: String?

    /// Current content lines.
    var lines: [String] = []

    private let didChangeSubject = PassthroughSubject<ChangeEvent, Never>()

    lazy var didChangePublisher: AnyPublisher<ChangeEvent, Never> =
        didChangeSubject.eraseToAnyPublisher()

    private var subscriptions: Set<AnyCancellable> = []

    weak var delegate: BufferDelegate?

    init(
        handle: BufferHandle,
        name: String,
        delegate: BufferDelegate?,
        linesEventPublisher: AnyPublisher<BufLinesEvent, Never>
    ) {
        self.handle = handle
        self.name = name
        self.delegate = delegate

        linesEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] event in
                precondition(event.buf == handle)

                lines = event.applyChanges(in: lines)
                didChangeSubject.send((
                    lines: lines,
                    event: event
                ))
            }
            .store(in: &subscriptions)
    }

    func activate(with api: API) -> APIAsync<Void> {
        guard let delegate = delegate else {
            preconditionFailure("Expected a delegate")
        }

        return delegate.buffer(self, activateWith: api)
    }
}

extension API {
    func transaction<Result>(in buffer: NvimBuffer, block: @escaping (API) -> APIAsync<Result>) -> APIAsync<Result> {
        transaction { api in
            buffer.activate(with: api)
                .flatMap { block(api) }
        }
    }

    func transaction<Result>(in buffer: NvimBuffer, block: @escaping (API) throws -> Async<Result, Error>) -> Async<Result, Error> {
        transaction { api in
            buffer.activate(with: api)
                .tryFlatMap { try block(api) }
        }
    }
}
