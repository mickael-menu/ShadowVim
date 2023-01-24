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

public protocol NvimDelegate: AnyObject {
    func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>?
}

public class Nvim {
    public let api: API
    public let events: EventDispatcher
    public weak var delegate: NvimDelegate?

    convenience init(session: RPCSession, delegate: NvimDelegate? = nil) {
        let api = API(session: session)
        let events = EventDispatcher(api: api)

        self.init(api: api, events: events, delegate: delegate)

        session.delegate = self
    }

    private init(api: API, events: EventDispatcher, delegate: NvimDelegate? = nil) {
        self.api = api
        self.events = events
        self.delegate = delegate
    }

    public func edit(url: URL) async throws {
        let path = url.path.replacingOccurrences(of: "%", with: "\\%")
        try await api.cmd("edit", args: .string(path)).throw()
    }

    /// - Parameter handle: Handle of the buffer, or 0 for the current buffer.
    public func buffer(_ handle: BufferHandle = 0) async throws -> Buffer {
        var handle = handle
        if handle == 0 {
            handle = try await api.getCurrentBuf().get()
        }

        return Buffer(handle: handle, api: api, events: events)
    }
}

extension Nvim: RPCSessionDelegate {
    func session(_ session: RPCSession, didReceiveError error: RPCError) {
        print(error.localizedDescription)
    }

    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value]) {
        events.dispatch(event: method, data: params)
    }

    func session(_ session: RPCSession, didReceiveRequest method: String, with params: [Value]) -> Result<Value, Error>? {
        delegate?.nvim(self, didRequest: method, with: params)
    }
}
