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

import AppKit
import Combine
import Foundation
import Toolkit

/// Entry-point to the Neovim APIs.
///
/// It is highly inspired by the Lua APIs described in https://neovim.io/doc/user/lua-guide.html
public final class Vim {
    /// The "Neovim API" written in C for use in remote plugins and GUIs.
    /// See https://neovim.io/doc/user/api.html
    public let api: API

    /// Vim builtin-functions.
    /// See https://neovim.io/doc/user/builtin.html
    public let fn: BuiltinFunctions

    private let logger: Logger?
    private let startTransaction: () -> Async<Vim, Never>
    private let endTransaction: () -> Void

    init(
        api: API,
        fn: BuiltinFunctions,
        logger: Logger?,
        startTransaction: @escaping () -> Async<Vim, Never>,
        endTransaction: @escaping () -> Void
    ) {
        self.api = api
        self.fn = fn
        self.logger = logger
        self.startTransaction = startTransaction
        self.endTransaction = endTransaction
    }

    /// Performs a sequence of API calls in a single atomic transaction.
    ///
    /// You must return an `Async` object completed when the transaction is
    /// done.
    public func atomic<Value, Failure>(
        _ block: @escaping (Vim) -> Async<Value, Failure>
    ) -> Async<Value, Failure> {
        startTransaction()
            .setFailureType(to: Failure.self)
            .flatMap(block)
            .mapError { $0 }
            .onCompletion { _ in self.endTransaction() }
    }
}
