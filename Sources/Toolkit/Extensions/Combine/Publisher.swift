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

public extension Publisher {
    func ignoreFailure() -> AnyPublisher<Output, Never> {
        map { $0 as Output? }
            .replaceError(with: nil)
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    func sink(
        onFailure: @escaping (Error) -> Void,
        receiveValue: @escaping (Output) -> Void
    ) -> AnyCancellable {
        sink(
            receiveCompletion: { res in
                if case let .failure(error) = res {
                    onFailure(error)
                }
            },
            receiveValue: receiveValue
        )
    }
}

public extension AnyPublisher {
    static func just(_ value: Output) -> Self {
        Just(value)
            .setFailureType(to: Failure.self)
            .eraseToAnyPublisher()
    }

    static func fail(_ error: Failure) -> Self {
        Fail(error: error).eraseToAnyPublisher()
    }
}
