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

public final class MainMediator {
    private let bundleIDs: [String]
    private var apps: [pid_t: AppMediator] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private let eventTap = EventTap()

    public init(bundleIDs: [String]) {
        self.bundleIDs = bundleIDs
    }

    public func start() throws {
        precondition(Thread.isMainThread)

        eventTap.delegate = self
        try eventTap.run()

        try reset()
    }

    private func reset() throws {
        precondition(Thread.isMainThread)

        subscriptions = []
        apps = [:]

        if let app = NSWorkspace.shared.frontmostApplication {
            _ = try mediator(of: app)
        }

        NSWorkspace.shared
            .didActivateApplicationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                do {
                    _ = try self?.mediator(of: $0)
                } catch {
                    print(error) // FIXME:
                }
            }
            .store(in: &subscriptions)

        NSWorkspace.shared
            .didTerminateApplicationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.terminate(app: $0)
            }
            .store(in: &subscriptions)
    }

    private func mediator(of app: NSRunningApplication) throws -> AppMediator? {
        precondition(Thread.isMainThread)

        guard
            let id = app.bundleIdentifier,
            bundleIDs.contains(id)
        else {
            return nil
        }

        return try apps.getOrPut(app.processIdentifier) {
            try AppMediator(app: app)
        }
    }

    private func terminate(app: NSRunningApplication) {
        apps.removeValue(forKey: app.processIdentifier)
    }
}

extension MainMediator: EventTapDelegate {
    func eventTap(_ tap: EventTap, didReceive event: CGEvent) -> CGEvent? {
        if isResetEvent(event) {
            do {
                print("Reset ShadowVim")
                try reset()
            } catch {
                // FIXME:
                print(error)
                Debug.printCallStack()
            }

            return nil
        }

        do {
            guard
                let app = NSWorkspace.shared.frontmostApplication,
                let mediator = try mediator(of: app)
            else {
                return event
            }
            return mediator.handle(event)

        } catch {
            // FIXME:
            print(error)
            return event
        }
    }

    /// ⌃⌥⌘-Esc triggers a reset of ShadowVim.
    private func isResetEvent(_ event: CGEvent) -> Bool {
        event.type == .keyDown
            && event.flags.isSuperset(of: [.maskControl, .maskAlternate, .maskCommand])
            && event.keyCode == .escape
    }
}
