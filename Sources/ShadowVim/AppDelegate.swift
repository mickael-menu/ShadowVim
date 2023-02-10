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

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var container: Container?
    var shadowVim: ShadowVim?

    private func startup() {
        container = Container()
        shadowVim = container?.shadowVim()
        shadowVim?.delegate = self
        shadowVim?.didLaunch()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prevent showing the menu bar and dock icon.
//        NSApp.setActivationPolicy(.accessory)

//        let cmdline = CmdlineController(frame: NSRect(x: 0, y: 0, width: 480, height: 44))
//        cmdline.show()

        startup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shadowVim?.willTerminate()
    }
}

extension AppDelegate: ShadowVimDelegate {
    func shadowVimDidRequestRelaunch(_ shadowVim: ShadowVim) {
        startup()
    }
}
