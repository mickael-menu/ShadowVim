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

import Cocoa
import Combine
import Mediator
import SwiftUI
import UserNotifications

private let apps = [
    "com.apple.dt.Xcode",
//    "com.apple.TextEdit",
]

class AppDelegate: NSObject, NSApplicationDelegate {
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prevent showing the menu bar and dock icon.
//        NSApp.setActivationPolicy(.accessory)

//        let cmdline = CmdlineController(frame: NSRect(x: 0, y: 0, width: 480, height: 44))
//        cmdline.show()

        NSWorkspace.shared
            .didActivateApplicationPublisher
            .filter { apps.contains($0.bundleIdentifier ?? "") }
            .tryMap { try AppMediator.shared(for: $0) }
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print(error)
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &subscriptions)

        try! eventTap.run()

        NSRunningApplication.current.hide()
    }

    private lazy var eventTap = EventTap { [unowned self] _, event in
        guard
            let nsApp = NSWorkspace.shared.frontmostApplication,
            apps.contains(nsApp.bundleIdentifier ?? "")
        else {
            return event
        }

        do {
            return try AppMediator.shared(for: nsApp)
                .handle(event)
        } catch {
            print(error)
            return event
        }
    }
}
