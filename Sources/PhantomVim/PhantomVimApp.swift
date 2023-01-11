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
//

import Nvim
import SwiftUI

private var subscriptions: [EventSubscription] = []

final class AppViewModel: ObservableObject {
    private let process: NvimProcess
    private var buffer: Buffer?

    private var nvim: Nvim { process.nvim }

    init() throws {
        process = try NvimProcess.start()

        DispatchQueue.global(qos: .userInteractive).async { [self] in
            try! self.eventTap.run()
        }
    }

    func initialize() async throws {
        buffer = try await nvim.buffer().get()
        await buffer?.attach(
            sendBuffer: true,
            onLines: { print("\($0.lineData)") }
        )

        //                try await nvim.subscribe(event: "moved")
        //                try await nvim.subscribe(event: "mode")
        //                try await nvim.subscribe(event: "cmdline")

        //                try await nvim.command("autocmd CursorMoved * call rpcnotify(0, 'moved')")
        //                try await nvim.command("autocmd ModeChanged * call rpcnotify(0, 'mode', mode())")
        //                try await nvim.command("autocmd CmdlineChanged * call rpcnotify(0, 'cmdline', getcmdline())")

        let events = nvim.events

        try await events.autoCmd(event: "CursorMoved", args: "getcurpos()") { params in
            print("MOVED \(params)")
        }.get().store(in: &subscriptions)

        try await events.autoCmd(event: "ModeChanged", args: "mode()") { params in
            print("MODE \(params)")
        }.get().store(in: &subscriptions)
        //                subscriptions.append(try await nvim.createAutocmd(on: "CursorMoved", args: "getcurpos()", "showcmd") { params in
        //                    print("MOVED \(params)")
        //                })
        //
        //                subscriptions.append(try await nvim.createAutocmd(on: "CursorMovedI", args: "getcurpos()") { params in
        //                    print("MOVEDI \(params)")
        //                })
        //
        //                subscriptions.append(try await nvim.createAutocmd(on: "ModeChanged", args: "mode()") { params in
        //                    print("Mode changed \(params)")
        //                })
        //
        //                subscriptions.append(try await nvim.createAutocmd(on: "CmdlineChanged", args: "getcmdline()") { params in
        //                    print("Cmdline changed \(params)")
        //                })
    }

    private lazy var eventTap = EventTap { [unowned self] type, event in
        switch type {
        case .keyDown:
            guard !event.flags.contains(.maskCommand) else {
                break
            }
            Task {
                switch event.getIntegerValueField(.keyboardEventKeycode) {
//                case 0x35:
//                    try await nvim.input("<ESC>")
//                case 0x24:
//                    try await nvim.input("<CR>")
                default:
                    let maxStringLength: Int = 4
                    var actualStringLength: Int = 0
                    var unicodeString = [UniChar](repeating: 0, count: Int(maxStringLength))
                    event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
                    let character = String(utf16CodeUnits: &unicodeString, count: Int(actualStringLength))
                    await nvim.api.input(character)

                    // REQUIRES Neovim 0.9
                    let sl = try await nvim.api.evalStatusline("%S").get()
                    print(sl)
                }
            }
            return nil
        default:
            break
        }
        return event
    }
}

@main
struct PhantomVimApp: App {
    @StateObject private var viewModel = try! AppViewModel()

    var body: some Scene {
        WindowGroup {
            Group {}
                .task {
                    do {
                        try await viewModel.initialize()
                    } catch {
                        print(error)
                    }
                }
        }
    }
}
