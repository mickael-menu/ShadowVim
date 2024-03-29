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
import Nvim
import Toolkit

public protocol MainMediatorDelegate: AnyObject {
    func mainMediator(_ mediator: MainMediator, didFailWithError error: Error)
}

private typealias BundleID = String

public final class MainMediator {
    public weak var delegate: MainMediatorDelegate?

    private let bundleIDs: [BundleID]
    private let logger: Logger?
    private let appMediatorFactory: AppMediator.Factory
    private var apps: [pid_t: AppMediator] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    private lazy var appDelegates: [BundleID: AppMediatorDelegate] = [
        "com.apple.dt.Xcode": XcodeAppMediatorDelegate(delegate: self, logger: logger?.domain("xcode")),
    ]

    public init(
        bundleIDs: [String],
        logger: Logger?,
        appMediatorFactory: @escaping AppMediator.Factory
    ) {
        self.bundleIDs = bundleIDs
        self.logger = logger
        self.appMediatorFactory = appMediatorFactory
    }

    public func start() throws {
        precondition(Thread.isMainThread)

        if let app = NSWorkspace.shared.frontmostApplication, app.isFinishedLaunching {
            _ = mediator(of: app)
        }

        NSWorkspace.shared
            .didLaunchApplicationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.didActivateApp($0)
            }
            .store(in: &subscriptions)

        NSWorkspace.shared
            .didActivateApplicationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.didActivateApp($0)
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

    public func stop() {
        precondition(Thread.isMainThread)

        for (_, app) in apps {
            app.stop()
        }

        subscriptions = []
        apps = [:]
    }

    public func handle(_ event: InputEvent) -> Bool {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let mediator = mediator(of: app)
        else {
            return false
        }
        return mediator.handle(event)
    }

    private func didActivateApp(_ app: NSRunningApplication) {
        _ = mediator(of: app)
    }

    private func mediator(of app: NSRunningApplication) -> AppMediator? {
        precondition(Thread.isMainThread)

        guard
            app.isFinishedLaunching,
//            app.bundleURL?.path.contains("Xcode-beta") == true,
            let id = app.bundleIdentifier,
            bundleIDs.contains(id)
        else {
            return nil
        }

        if let mediator = apps[app.processIdentifier] {
            return mediator
        }

        let mediator = appMediatorFactory(app)
        mediator.delegate = appDelegates[id] ?? self
        Task {
            await mediator.start()
        }
        apps[app.processIdentifier] = mediator
        return mediator
    }

    private func terminate(app: NSRunningApplication) {
        precondition(Thread.isMainThread)
        guard let mediator = apps.removeValue(forKey: app.processIdentifier) else {
            return
        }
        mediator.stop()
    }
}

extension MainMediator: AppMediatorDelegate {
    public func appMediator(_ mediator: AppMediator, didFailWithError error: Error) {
        delegate?.mainMediator(self, didFailWithError: error)
    }
}
