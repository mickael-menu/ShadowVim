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

/// Receives Neovim RPC notifactions and dispatch them to observers using
/// publishers.
public class EventDispatcher {
    private let api: API
    private let logger: Logger?
    @Atomic private var mediators: [Event: EventMediator] = [:]

    init(api: API, logger: Logger?) {
        self.api = api
        self.logger = logger
    }

    /// Receives an `event` and dispatches it to the listening `EventMediator`.
    func dispatch(event: String, data: [Value]) {
        mediators[event]?.receive(with: data)
    }

    public func publisher(for event: String) -> AnyPublisher<[Value], NvimError> {
        let mediator = $mediators.write {
            $0.getOrPut(event) {
                EventMediator(event: event, api: api, logger: logger)
            }
        }

        return EventPublisher(event: event, mediator: mediator)
            .eraseToAnyPublisher()
    }

    public func publisher<UnpackedValue>(
        for event: String,
        unpack: @escaping ([Value]) -> UnpackedValue?
    ) -> AnyPublisher<UnpackedValue, NvimError> {
        publisher(for: event)
            .flatMap { data -> AnyPublisher<UnpackedValue, NvimError> in
                guard let payload = unpack(data) else {
                    return .fail(.unexpectedNotificationPayload(event: event, payload: data))
                }
                return .just(payload)
            }
            .eraseToAnyPublisher()
    }

    public func autoCmdPublisher(
        name: String? = nil,
        for events: [String],
        args: [String]
    ) -> AnyPublisher<[Value], NvimError> {
        let eventName = "autocmd-\(name ?? UUID().uuidString)"

        var autocmdID: AutocmdID?
        let mediator = EventMediator(
            event: eventName,
            api: api,
            logger: logger,

            onSetup: { [api] in
                var argsList = ""
                if !args.isEmpty {
                    argsList = ", " + args.joined(separator: ", ")
                }

                return api.createAutocmd(
                    for: events,
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

    public func autoCmdPublisher<UnpackedValue>(
        name: String? = nil,
        for events: [String],
        args: [String],
        unpack: @escaping ([Value]) -> UnpackedValue?
    ) -> AnyPublisher<UnpackedValue, NvimError> {
        autoCmdPublisher(name: name, for: events, args: args)
            .flatMap { data -> AnyPublisher<UnpackedValue, NvimError> in
                guard let payload = unpack(data) else {
                    let event = events.joined(separator: ", ")
                    return .fail(.unexpectedNotificationPayload(event: event, payload: data))
                }
                return .just(payload)
            }
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
    private let logger: Logger?
    private let onSetup: () -> Async<Void, NvimError>
    private let onTeardown: () -> Async<Void, NvimError>
    @Atomic private var receivers: [any EventReceiver] = []

    init(
        event: Event,
        api: API,
        logger: Logger?,
        onSetup: @escaping () -> Async<Void, NvimError> = { .success(()) },
        onTeardown: @escaping () -> Async<Void, NvimError> = { .success(()) }
    ) {
        self.event = event
        self.logger = logger
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
                    .logFailure(with: logger, message: "subscribe(\(event))")
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
                    .logFailure(with: logger, message: "unsubscribe(\(event))")
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
    public typealias Failure = NvimError

    private let event: Event
    private let mediator: EventMediator
    private var tasks: [Task<Void, Never>] = []

    init(event: Event, mediator: EventMediator) {
        self.event = event
        self.mediator = mediator
    }

    public func receive<S>(
        subscriber: S
    ) where S: Subscriber, S.Input == [Value], S.Failure == NvimError {
        let subscription = Subscription(event: event, mediator: mediator, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }

    private class Subscription<S: Subscriber>:
        EventReceiver,
        Combine.Subscription where S.Input == [Value], S.Failure == NvimError
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
