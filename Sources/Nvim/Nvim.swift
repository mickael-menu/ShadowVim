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
import Foundation
import Toolkit

public protocol NvimDelegate: AnyObject {
    func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>?
    func nvim(_ nvim: Nvim, didFailWithError error: Error)
}

public class Nvim {
    public let api: API
    public let events: EventDispatcher
    public weak var delegate: NvimDelegate?
    private let session: RPCSession

    /// The API lock is used to protect calls to `api`.
    ///
    /// Using the shared `api` property, each call is in its own transaction.
    /// If you need to perform a sequence of `API` calls in a single atomic
    /// transaction, use `transaction()`.
    private let apiLock: AsyncLock

    init(session: RPCSession, delegate: NvimDelegate? = nil) {
        let apiLock = AsyncLock()
        let api = API(
            session: session,
            requestCallbacks: RPCRequestCallbacks(
                prepare: { apiLock.acquire() },
                onSent: { apiLock.release() }
            )
        )

        self.api = api
        self.apiLock = apiLock
        self.session = session
        events = EventDispatcher(api: api)
        self.delegate = delegate

        session.start(delegate: self)
    }

    /// Performs a sequence of `API` calls in a single atomic transaction.
    ///
    /// You must return an `Async` object completed when the transaction is
    /// done.
    public func transaction<Value>(
        _ block: @escaping (API) -> APIAsync<Value>
    ) -> APIAsync<Value> {
        apiLock.acquire()
            .setFailureType(to: APIError.self)
            .flatMap { [self] in
                block(API(session: session))
            }
            .onCompletion { [self] _ in
                apiLock.release()
            }
    }
}

extension Nvim: RPCSessionDelegate {
    func session(_ session: RPCSession, didFailWithError error: RPCError) {
        delegate?.nvim(self, didFailWithError: error)
    }

    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value]) {
        events.dispatch(event: method, data: params)
    }

    func session(_ session: RPCSession, didReceiveRequest method: String, with params: [Value]) -> Result<Value, Error>? {
        delegate?.nvim(self, didRequest: method, with: params)
    }
}
