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

import ApplicationServices
import Combine
import Foundation
import Toolkit

/// Manages the notification subscriptions for the application with given `pid`.
final class AXNotificationObserver {
    /// Global shared observer instances per `pid`.
    @Atomic private static var observers: [pid_t: AXNotificationObserver] = [:]

    /// Gets the shared observer for the application with given `pid`, creating it if needed.
    static func shared(for pid: pid_t) -> AXNotificationObserver {
        if let obs = observers[pid] {
            return obs
        }

        return $observers.write {
            // In the very unlikely case the observer was created after the
            // previous read.
            if let obs = $0[pid] {
                return obs
            }
            let obs = AXNotificationObserver(pid: pid)
            $0[pid] = obs
            return obs
        }
    }

    private let pid: pid_t

    private init(pid: pid_t) {
        self.pid = pid
    }
  
    deinit {
        if let obs = _observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
    }
  
    /// Returns a new publisher for a notification emitted by the given source `element`.
    func publisher(for notification: AXNotification, element: AXUIElement) -> AXNotificationPublisher {
        AXNotificationPublisher(observer: self, key: NotificationKey(notification: notification, source: element))
    }

    // MARK: - Subscriptions

    @Atomic private var subscriptions: [NotificationKey: NotificationSubscription] = [:]

    /// Registers a new `receiver`, creating a shared `NotificationSubscription` if needed.
    fileprivate func register(_ receiver: any NotificationReceiver) throws {
        try $subscriptions.write {
            let subscription = $0.getOrPut(receiver.key) {
                NotificationSubscription(key: receiver.key)
            }
            if subscription.isEmpty {
                try observer().add(
                    notification: receiver.key.notification,
                    element: receiver.key.source,
                    context: subscription
                )
            }
            subscription.add(receiver)
        }
    }

    /// Removes a `receiver` previously registered.
    fileprivate func deregister(_ receiver: NotificationReceiver) throws {
        guard let subscription = subscriptions[receiver.key] else {
            assertionFailure("No subscription found")
            return
        }

        subscription.remove(receiver)

        if subscription.isEmpty {
            try observer().remove(
                notification: receiver.key.notification,
                element: receiver.key.source
            )
        }
    }

    // MARK: - AXObserver

    /// Returns the `AXObserver` instance for this application, creating it if needed.
    private func observer() throws -> AXObserver {
        if let obs = _observer {
            return obs
        }

        let callback: AXObserverCallback = { _, element, note, refcon in
            precondition(refcon != nil)
            Unmanaged<NotificationSubscription>
                .fromOpaque(refcon!).takeUnretainedValue()
                .receive(target: element)
        }

        let result = AXObserverCreate(pid, callback, &_observer)
        if let error = AXError(code: result) {
            throw error
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(_observer!), .defaultMode)
        return _observer!
    }

    private var _observer: AXObserver?
}

/// Identifies uniquely a `notification` with an associated `source` accessibility element.
private struct NotificationKey: Hashable {
    let notification: AXNotification
    let source: AXUIElement
}

/// A global subscription to the notification identified with `key`.
///
/// It manages a list of `NotificationReceiver` representing individual publisher subscriptions.
private class NotificationSubscription {
    let key: NotificationKey
    private var receivers: [any NotificationReceiver] = []

    init(key: NotificationKey) {
        self.key = key
    }

    var isEmpty: Bool {
        receivers.isEmpty
    }

    func add(_ receiver: any NotificationReceiver) {
        precondition(receiver.key == key)
        receivers.append(receiver)
    }

    func remove(_ receiver: any NotificationReceiver) {
        precondition(receiver.key == key)
        receivers.removeAll { ObjectIdentifier($0) == ObjectIdentifier(receiver) }
    }

    func receive(target: AXUIElement) {
        for receiver in receivers {
            receiver.receive(target: target)
        }
    }
}

/// Adapter protocol used to connect a `NotificationSubscription` with a publisher
/// subscription.
private protocol NotificationReceiver: AnyObject {
    /// Notification key to observe.
    var key: NotificationKey { get }

    /// Callback when the notification is received with the given `target` element.
    func receive(target: AXUIElement)
}

/// Combine publisher to observe `AXNotification` events.
struct AXNotificationPublisher: Publisher {
    public typealias Output = AXUIElement
    public typealias Failure = Error

    private let observer: AXNotificationObserver
    private let key: NotificationKey

    fileprivate init(observer: AXNotificationObserver, key: NotificationKey) {
        self.observer = observer
        self.key = key
    }

    public func receive<S>(
        subscriber: S
    ) where S: Subscriber, S.Input == AXUIElement, S.Failure == Error {
        let subscription = Subscription(observer: observer, key: key, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
        do {
            try observer.register(subscription)
        } catch {
            subscriber.receive(completion: .failure(error))
        }
    }

    private class Subscription<S: Subscriber>:
        NotificationReceiver,
        Combine.Subscription where S.Input == AXUIElement, S.Failure == Error
    {
        private let observer: AXNotificationObserver
        let key: NotificationKey
        private var subscriber: S?

        init(observer: AXNotificationObserver, key: NotificationKey, subscriber: S) {
            self.observer = observer
            self.key = key
            self.subscriber = subscriber
        }

        func request(_ demand: Subscribers.Demand) {}

        func cancel() {
            try? observer.deregister(self)
            subscriber = nil
        }

        func receive(target: AXUIElement) {
            _ = subscriber?.receive(target)
        }
    }
}

private extension AXObserver {
    func add(notification: AXNotification, element: AXUIElement, context: AnyObject) throws {
        precondition(Thread.isMainThread)
        let notification = notification.rawValue as CFString
        let context = Unmanaged.passUnretained(context).toOpaque()
        let result = AXObserverAddNotification(self, element, notification, context)
        if let error = AXError(code: result), case .notificationAlreadyRegistered = error {
            throw error
        }
    }

    func remove(notification: AXNotification, element: AXUIElement) throws {
        precondition(Thread.isMainThread)
        let notification = notification.rawValue as CFString
        let result = AXObserverRemoveNotification(self, element, notification)
        if let error = AXError(code: result), case .notificationNotRegistered = error {
            throw error
        }
    }
}
