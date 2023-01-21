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

public class EventDispatcher {
    public typealias OnEvent = ([Value]) -> Void

    private struct Handler {
        let subscriptionID: EventSubscription.ID
        let event: String
        let callback: OnEvent
    }

    private let api: API
    private var handlers: [Handler] = []
    private var nextSubscriptionID: EventSubscription.ID = 0
    private let queue = DispatchQueue(label: "menu.mickael.Nvim.EventDispatcher")

    init(api: API) {
        self.api = api
    }

    func dispatch(event: String, data: [Value]) {
        queue.async { [unowned self] in
            for handler in handlers {
                if handler.event == event {
                    handler.callback(data)
                }
            }
        }
    }

    public func subscribe(
        to event: String,
        handler: @escaping OnEvent
    ) async -> APIResult<EventSubscription> {
        await api.subscribe(to: event)
            .map { addHandler(for: event, callback: handler) }
    }

    //    try await nvim.command("autocmd CursorMoved * call rpcnotify(0, 'moved')")
    //    try await nvim.command("autocmd ModeChanged * call rpcnotify(0, 'mode', mode())")
    //    try await nvim.command("autocmd CmdlineChanged * call rpcnotify(0, 'cmdline', getcmdline())")
    public func autoCmd(
        event: String...,
        args: String...,
        handler: @escaping OnEvent
    ) async -> APIResult<EventSubscription> {
        let eventName = "autocmd-\(UUID().uuidString)"
        var argsList = ""
        if !args.isEmpty {
            argsList = ", " + args.joined(separator: ", ")
        }

        let autocmdID = await api.createAutocmd(
            for: event,
            command: "call rpcnotify(0, '\(eventName)'\(argsList))"
        )
        if case let .failure(error) = autocmdID {
            return .failure(error)
        }

        return await subscribe(to: eventName, handler: handler)
    }

    private func addHandler(for event: String, callback: @escaping OnEvent) -> EventSubscription {
        queue.sync { [unowned self] in
            let id = nextSubscriptionID
            nextSubscriptionID += 1

            let subscription = EventSubscription { [weak self] in
                self?.unsubscribe(id)
            }

            handlers.append(Handler(
                subscriptionID: id,
                event: event,
                callback: callback
            ))

            return subscription
        }
    }

    func unsubscribe(_ id: EventSubscription.ID) {
        queue.async { [unowned self] in
            self.handlers.removeAll { $0.subscriptionID == id }
        }
    }
}

public class EventSubscription {
    public typealias ID = Int

    private let onCancel: () -> Void
    private var isCancelled: Bool = false

    fileprivate init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    deinit {
        cancel()
    }

    public func cancel() {
        guard !isCancelled else {
            return
        }
        isCancelled = true
        onCancel()
    }

    public func store(in set: inout [EventSubscription]) {
        set.append(self)
    }
}
