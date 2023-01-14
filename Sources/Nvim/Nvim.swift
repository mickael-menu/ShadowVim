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
//

import AppKit
import Foundation

public class Nvim {
    public let api: API
    public let events: EventDispatcher

    convenience init(session: RPCSession) {
        let api = API(session: session)
        let events = EventDispatcher(api: api)

        self.init(api: api, events: events)

        session.delegate = self
    }

    private init(api: API, events: EventDispatcher) {
        self.api = api
        self.events = events
    }

    /// - Parameter handle: Handle of the buffer, or 0 for the current buffer.
    public func buffer(_ handle: BufferHandle = 0) async -> APIResult<Buffer> {
        let handle: APIResult<BufferHandle> = await {
            if handle > 0 {
                return .success(handle)
            } else {
                return await api.getCurrentBuf()
            }
        }()

        return handle.map { Buffer(handle: $0, api: api, events: events) }
    }
}

extension Nvim: RPCSessionDelegate {
    func session(_ session: RPCSession, didReceiveError error: RPCError) {
        print(error.localizedDescription)
    }

    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value]) {
        events.dispatch(event: method, data: params)
    }
}
