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

import Sparkle
import SwiftUI
import Toolkit

@main
struct ShadowVimApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var shadowVim: ShadowVim {
        appDelegate.shadowVim
    }

    var body: some Scene {
        Settings {}
            .commands {
                CommandGroup(after: .appInfo) {
                    UpdaterButton(updater: updaterController.updater)
                }
            }

        MenuBarExtra("ShadowVim", systemImage: "n.square.fill") {
            KeysPassthroughButton(shadowVim: shadowVim)

            if Debug.isDebugging {
                Button("Verbose logging") { shadowVim.setVerboseLogger() }
                    .keyboardShortcut("/", modifiers: [.control, .option, .command])
            }

            Divider()

            Button("Copy Debug Info") { shadowVim.copyDebugInfo() }

            UpdaterButton(updater: updaterController.updater)
                .keyboardShortcut("u")

            Divider()

            Button("Reset ShadowVim") { shadowVim.reset() }
                .keyboardShortcut(.escape, modifiers: [.control, .option, .command])

            Button("Quit ShadowVim") { shadowVim.quit() }
                .keyboardShortcut("q")
        }
    }
}

struct KeysPassthroughButton: View {
    @ObservedObject var shadowVim: ShadowVim

    var body: some View {
        Toggle("Keys Passthrough", isOn: $shadowVim.keysPassthrough)
            .keyboardShortcut(".", modifiers: [.control, .option, .command])
    }
}
