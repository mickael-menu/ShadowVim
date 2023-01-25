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
import Toolkit

public typealias Event = String

/// Receives Neovim RPC events and dispatch them to observers using publishers.
public class EventDispatcher {
    private let api: API

    init(api: API) {
        self.api = api
    }

    func dispatch(event: String, data: [Value]) {
        subscriptions[event]?.receive(with: data)
    }

    public func subscribe(to event: String) -> AnyPublisher<[Value], APIError> {
        EventPublisher(dispatcher: self, event: event)
            .eraseToAnyPublisher()
    }

    //    try await nvim.command("autocmd CursorMoved * call rpcnotify(0, 'moved')")
    //    try await nvim.command("autocmd ModeChanged * call rpcnotify(0, 'mode', mode())")
    //    try await nvim.command("autocmd CmdlineChanged * call rpcnotify(0, 'cmdline', getcmdline())")
    public func autoCmd(
        event: String...,
        args: String...
    ) async -> AnyPublisher<[Value], APIError> {
        let eventName = "autocmd-\(UUID().uuidString)"
        var argsList = ""
        if !args.isEmpty {
            argsList = ", " + args.joined(separator: ", ")
        }

        api.createAutocmd(
            for: event,
            command: "call rpcnotify(0, '\(eventName)'\(argsList))"
        )
        .assertNoFailure()
        .get { _ in }

        return subscribe(to: eventName)
    }

    // MARK: - Subscriptions

    @Atomic private var subscriptions: [Event: EventSubscription] = [:]

    /// Registers a new `receiver`, creating a shared `NotificationSubscription` if needed.
    fileprivate func register(_ receiver: any EventReceiver) -> APIDeferred<Void> {
        let event = receiver.event

        var needsSubscribe = false
        $subscriptions.write {
            let subscription = $0.getOrPut(
                key: event,
                defaultValue: EventSubscription(event: event)
            )
            needsSubscribe = subscription.isEmpty
            subscription.add(receiver)
        }

        return needsSubscribe
            ? api.subscribe(to: event)
            : .success(())
    }

    /// Removes a `receiver` previously registered.
    fileprivate func deregister(_ receiver: EventReceiver) -> APIDeferred<Void> {
        let event = receiver.event

        var needsUnsubscribe = false
        $subscriptions.write {
            guard let subscription = $0[event] else {
                assertionFailure("No subscription found")
                return
            }

            subscription.remove(receiver)

            if subscription.isEmpty {
                needsUnsubscribe = true
                $0.removeValue(forKey: event)
            }
        }

        return needsUnsubscribe
            ? api.unsubscribe(from: event)
            : .success(())
    }
}

/// A subscription to the given `event` shared between several receivers.
///
/// It manages a list of `EventReceiver` representing individual publisher
/// subscriptions.
private class EventSubscription {
    let event: Event
    private var receivers: [any EventReceiver] = []

    init(event: Event) {
        self.event = event
    }

    var isEmpty: Bool {
        receivers.isEmpty
    }

    func add(_ receiver: any EventReceiver) {
        precondition(receiver.event == event)
        receivers.append(receiver)
    }

    func remove(_ receiver: any EventReceiver) {
        precondition(receiver.event == event)
        receivers.removeAll { ObjectIdentifier($0) == ObjectIdentifier(receiver) }
    }

    func receive(with data: [Value]) {
        for receiver in receivers {
            receiver.receive(with: data)
        }
    }
}

/// Adapter protocol used to connect an `EventSubscription` with a publisher
/// subscription.
private protocol EventReceiver: AnyObject {
    /// Event to observe.
    var event: Event { get }

    func receive(with data: [Value])
}

/// Combine publisher to observe Neovim events.
public struct EventPublisher: Publisher {
    public typealias Output = [Value]
    public typealias Failure = APIError

    private let dispatcher: EventDispatcher
    private let event: Event
    private var tasks: [Task<Void, Never>] = []

    init(dispatcher: EventDispatcher, event: Event) {
        self.dispatcher = dispatcher
        self.event = event
    }

    public func receive<S>(
        subscriber: S
    ) where S: Subscriber, S.Input == [Value], S.Failure == APIError {
        let subscription = Subscription(dispatcher: dispatcher, event: event, subscriber: subscriber)
        subscriber.receive(subscription: subscription)

        dispatcher.register(subscription)
            .get(onFailure: { error in
                subscriber.receive(completion: .failure(error))
            })
    }

    private class Subscription<S: Subscriber>:
        EventReceiver,
        Combine.Subscription where S.Input == [Value], S.Failure == APIError
    {
        private let dispatcher: EventDispatcher
        let event: Event
        private var subscriber: S?

        init(dispatcher: EventDispatcher, event: Event, subscriber: S) {
            self.dispatcher = dispatcher
            self.event = event
            self.subscriber = subscriber
        }

        func request(_ demand: Subscribers.Demand) {}

        func cancel() {
            subscriber = nil

            dispatcher.deregister(self)
                .assertNoFailure()
                .get()
        }

        func receive(with data: [Value]) {
            _ = subscriber?.receive(data)
        }
    }
}
