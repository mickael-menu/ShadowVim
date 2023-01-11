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

let nvim = Nvim()
var buffer: Buffer!

private var subscriptions: [Nvim.NotificationSubscription] = []
@main
struct PhantomVimApp: App {
    private let eventTap = EventTap { type, event in
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
                    try await nvim.input(character)

                    // REQUIRES Neovim 0.9
                    if case let .map(map) = try await nvim.request("nvim_eval_statusline", with: .string("%S"), .map([:])) {
                        print("\(map[.string("str")]?.stringValue ?? "")")
                    }
                }
            }
            return nil
        default:
            break
        }
        return event
    }

    init() {
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            try! self.eventTap.run()
        }

        Task {
            do {
                try await nvim.start()
//                try await nvim.subscribe(event: "moved")
//                try await nvim.subscribe(event: "mode")
//                try await nvim.subscribe(event: "cmdline")

//                try await nvim.command("autocmd CursorMoved * call rpcnotify(0, 'moved')")
//                try await nvim.command("autocmd ModeChanged * call rpcnotify(0, 'mode', mode())")
//                try await nvim.command("autocmd CmdlineChanged * call rpcnotify(0, 'cmdline', getcmdline())")

                subscriptions.append(try await nvim.createAutocmd(on: "CursorMoved", args: "getcurpos()", "showcmd") { params in
                    print("MOVED \(params)")
                })

                subscriptions.append(try await nvim.createAutocmd(on: "CursorMovedI", args: "getcurpos()") { params in
                    print("MOVEDI \(params)")
                })

                subscriptions.append(try await nvim.createAutocmd(on: "ModeChanged", args: "mode()") { params in
                    print("Mode changed \(params)")
                })

                subscriptions.append(try await nvim.createAutocmd(on: "CmdlineChanged", args: "getcmdline()") { params in
                    print("Cmdline changed \(params)")
                })

                buffer = try await nvim.buffer()
                try await buffer.attach(
                    sendBuffer: true,
                    onLines: { print("\($0.lineData)") }
                )

            } catch {
                print(error)
            }
        }
    }

    var body: some Scene {
        WindowGroup {}
    }
}
