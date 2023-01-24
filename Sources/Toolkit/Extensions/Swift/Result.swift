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
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

public extension Result {
    var error: Failure? {
        switch self {
        case let .failure(error):
            return error
        case .success:
            return nil
        }
    }

    var value: Success? {
        switch self {
        case let .success(value):
            return value
        case .failure:
            return nil
        }
    }

    func onError(_ block: (Failure) -> Void) {
        if case let .failure(error) = self {
            block(error)
        }
    }

    func dropResult() -> Result<Void, Failure> {
        map { _ in () }
    }

    func flatMap<NewSuccess>(_ transform: (Success) async -> (Result<NewSuccess, Failure>)) async -> Result<NewSuccess, Failure> {
        switch self {
        case let .success(result):
            return await transform(result)
        case let .failure(error):
            return .failure(error)
        }
    }

    func `throw`() throws {
        _ = try get()
    }
}
