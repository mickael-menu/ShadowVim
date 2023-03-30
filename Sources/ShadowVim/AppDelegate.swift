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
import Toolkit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let container = Container()

    var shadowVim: ShadowVim { container.shadowVim }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prevent showing the menu bar and dock icon.
//        NSApp.setActivationPolicy(.accessory)

//        let cmdline = CmdlineController(frame: NSRect(x: 0, y: 0, width: 480, height: 44))
//        cmdline.show()

        if Debug.isDebugging {
            BufferPreviewController(
                frame: NSRect(x: 0, y: 0, width: 800, height: 500),
                shadowVim: shadowVim
            ).show()
        }

        shadowVim.didLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shadowVim.willTerminate()
    }
}
