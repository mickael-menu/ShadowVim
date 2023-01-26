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

public class Buffer {
    public let handle: BufferHandle

    private let api: API
    private let events: EventDispatcher
    private var subscriptions: Set<AnyCancellable> = []

    init(handle: BufferHandle, api: API, events: EventDispatcher) {
        precondition(handle > 0, "The `current buffer` handle is not valid")
        self.handle = handle
        self.api = api
        self.events = events
    }

    @discardableResult
    public func attach(
        sendBuffer: Bool,
        onLines: @escaping (BufLinesEvent) -> Void
    ) -> APIAsync<Bool> {
        events.subscribeToBufLines()
            .filter { [handle] in $0.buf == handle }
            .assertNoFailure()
            .sink(receiveValue: onLines)
            .store(in: &subscriptions)

        return api.bufAttach(buffer: handle, sendBuffer: sendBuffer)
    }

    public func getLines(
        start: LineIndex = 0,
        end: LineIndex = -1,
        strictIndexing: Bool = false
    ) -> APIAsync<[String]> {
        api.request("nvim_buf_get_lines", with: [
            .buffer(handle),
            .int(start),
            .int(end),
            .bool(strictIndexing),
        ])
        .checkedUnpacking { $0.arrayValue?.compactMap(\.stringValue) }
    }
}
