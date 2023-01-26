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
    @Atomic private var mediators: [Event: EventMediator] = [:]

    init(api: API) {
        self.api = api
    }

    /// Receives an `event` and dispatches it to the listening `EventMediator`.
    func dispatch(event: String, data: [Value]) {
        mediators[event]?.receive(with: data)
    }

    public func subscribe(to event: String) -> AnyPublisher<[Value], APIError> {
        let mediator = $mediators.write {
            $0.getOrPut(
                key: event,
                defaultValue: EventMediator(event: event, api: api)
            )
        }

        return EventPublisher(event: event, mediator: mediator)
            .eraseToAnyPublisher()
    }

    public func subscribe<UnpackedValue>(
        to event: String,
        unpack: @escaping ([Value]) -> UnpackedValue?
    ) -> AnyPublisher<UnpackedValue, APIError> {
        subscribe(to: event)
            .flatMap { data -> AnyPublisher<UnpackedValue, APIError> in
                guard let payload = unpack(data) else {
                    return .fail(.unexpectedNotificationPayload(event: event, payload: data))
                }
                return .just(payload)
            }
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

        var autocmdID: AutocmdID?
        let mediator = EventMediator(
            event: eventName,
            api: api,

            onSetup: { [api] in
                var argsList = ""
                if !args.isEmpty {
                    argsList = ", " + args.joined(separator: ", ")
                }

                return api.createAutocmd(
                    for: event,
                    // FIXME: RPC channel ID
                    command: "call rpcnotify(0, '\(eventName)'\(argsList))"
                )
                .map {
                    autocmdID = $0
                    return ()
                }
            },

            onTeardown: { [api] in
                guard let autocmdID = autocmdID else {
                    return .success(())
                }

                return api.delAutocmd(autocmdID)
            }
        )

        $mediators.write {
            $0[eventName] = mediator
        }

        return EventPublisher(event: eventName, mediator: mediator)
            .eraseToAnyPublisher()
    }
}

/// Manages a set of `EventReceiver` for the given `event`.
///
/// Automatically takes care of (un)subscribing to the event with Neovim when
/// the number of receivers changes.
private class EventMediator {
    let event: Event

    private let api: API
    private let onSetup: () -> APIAsync<Void>
    private let onTeardown: () -> APIAsync<Void>
    @Atomic private var receivers: [any EventReceiver] = []

    init(
        event: Event,
        api: API,
        onSetup: @escaping () -> APIAsync<Void> = { .success(()) },
        onTeardown: @escaping () -> APIAsync<Void> = { .success(()) }
    ) {
        self.event = event
        self.api = api
        self.onSetup = onSetup
        self.onTeardown = onTeardown
    }

    func add(_ receiver: any EventReceiver) {
        precondition(receiver.event == event)

        $receivers.write {
            if $0.isEmpty {
                api.subscribe(to: event)
                    .flatMap(onSetup)
                    .assertNoFailure()
                    .run()
            }

            $0.append(receiver)
        }
    }

    func remove(_ receiver: any EventReceiver) {
        precondition(receiver.event == event)
        $receivers.write {
            $0.removeAll { ObjectIdentifier($0) == ObjectIdentifier(receiver) }

            if $0.isEmpty {
                api.unsubscribe(from: event)
                    .flatMap(onTeardown)
                    .assertNoFailure()
                    .run()
            }
        }
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
private struct EventPublisher: Publisher {
    public typealias Output = [Value]
    public typealias Failure = APIError

    private let event: Event
    private let mediator: EventMediator
    private var tasks: [Task<Void, Never>] = []

    init(event: Event, mediator: EventMediator) {
        self.event = event
        self.mediator = mediator
    }

    public func receive<S>(
        subscriber: S
    ) where S: Subscriber, S.Input == [Value], S.Failure == APIError {
        let subscription = Subscription(event: event, mediator: mediator, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }

    private class Subscription<S: Subscriber>:
        EventReceiver,
        Combine.Subscription where S.Input == [Value], S.Failure == APIError
    {
        let event: Event
        private let mediator: EventMediator
        private var subscriber: S?

        init(event: Event, mediator: EventMediator, subscriber: S) {
            self.event = event
            self.mediator = mediator
            self.subscriber = subscriber

            mediator.add(self)
        }

        func request(_ demand: Subscribers.Demand) {}

        func cancel() {
            subscriber = nil
            mediator.remove(self)
        }

        func receive(with data: [Value]) {
            _ = subscriber?.receive(data)
        }
    }
}
