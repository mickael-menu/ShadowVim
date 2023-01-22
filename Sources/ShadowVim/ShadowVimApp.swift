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

import AX
import Combine
import Mediator
import Nvim
import SwiftUI

private let apps = [
    "com.apple.TextEdit",
    "com.apple.dt.Xcode",
]

final class AppViewModel: ObservableObject {
    private var subscriptions: Set<AnyCancellable> = []

    init() throws {
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
                receiveValue: { app in
                    print(app)
                }
            )
            .store(in: &subscriptions)

        Task {
            try! await self.eventTap.run()
        }
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

@main
struct ShadowVimApp: App {
    @StateObject private var viewModel = try! AppViewModel()
    @State private var text: String = ""

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading) {
                TextEditor(
                    text: $text
                )
                .lineLimit(nil)
                .font(.body.monospaced())
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: 400, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
//
//                HStack {
//                    Text(viewModel.mode).font(.title2)
//                    Text(viewModel.cmdline)
//                    Spacer()
//                }
            }.padding()
        }
    }
}
