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

public enum NvimError: Error {
    case processStopped(status: Int)
    case apiFailure(APIError)
    case rpcFailure(RPCError)
}

public protocol NvimDelegate: AnyObject {
    func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>?
    func nvim(_ nvim: Nvim, didFailWithError error: NvimError)
}

public final class Nvim {
    public let api: API
    public let events: EventDispatcher
    public weak var delegate: NvimDelegate?

    private let process: NvimProcess
    private let session: RPCSession
    private let logger: Logger?
    private var subscriptions: Set<AnyCancellable> = []

    init(
        process: NvimProcess,
        session: RPCSession,
        api: API,
        events: EventDispatcher,
        logger: Logger?
    ) {
        self.process = process
        self.session = session
        self.api = api
        self.events = events
        self.logger = logger

        process.delegate = self
        session.start(delegate: self)
    }

    deinit {
        stop()
    }

    /// Stops the Nvim process.
    public func stop() {
        process.stop()
    }
}

extension Nvim: NvimProcessDelegate {
    public func nvimProcess(_ nvimProcess: NvimProcess, didTerminateWithStatus status: Int) {
        session.close()

        // When resetting Nvim, the status code will be 2. We can ignore it.
        if status != 2 {
            delegate?.nvim(self, didFailWithError: .processStopped(status: status))
        }
    }
}

extension Nvim: RPCSessionDelegate {
    func session(_ session: RPCSession, didFailWithError error: RPCError) {
        delegate?.nvim(self, didFailWithError: .rpcFailure(error))
    }

    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value]) {
        events.dispatch(event: method, data: params)
    }

    func session(_ session: RPCSession, didReceiveRequest method: String, with params: [Value]) -> Result<Value, Error>? {
        delegate?.nvim(self, didRequest: method, with: params)
    }
}
