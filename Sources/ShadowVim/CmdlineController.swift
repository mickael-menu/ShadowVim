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
import Foundation
import SwiftUI

class CmdlineController {
    let window: NSPanel
    private let controller: NSWindowController

    init(frame: CGRect) {
        window = NSPanel(
            contentRect: frame,
            styleMask: [.resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        controller = NSWindowController(window: window)
        setupWindow()
    }

    private func setupWindow() {
//        window.hasShadow = false
        window.backgroundColor = .clear
        window.canHide = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        
        let contentView = window.contentView!
        contentView.wantsLayer                =   true
        contentView.layer?.cornerRadius       =   10
        contentView.layer?.backgroundColor    =   NSColor.white.cgColor
        window.invalidateShadow()
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.frame = contentView.bounds
        visualEffect.autoresizingMask = [.height, .width]
        contentView.addSubview(visualEffect)

        let hostingView = NSHostingView(rootView: Cmdline())
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.height, .width]
        contentView.addSubview(hostingView)
        
        // To pin the window to an element's bottom:
//        let parent = (element[.parent] as AXUIElement?)!
//        var pos = parent[.position] as CGPoint? ?? .zero
//        var size = parent[.size] as CGSize? ?? .zero
//        pos.y += size.height - 44
//        size.height = 44
//
//        var frame = NSRect(origin: pos, size: size)
//        let screenHeight = NSScreen.main!.frame.size.height
//        frame.origin.y = screenHeight - frame.origin.y - size.height
//        window.setFrame(frame, display: true, animate: false)
    }

    func show() {
        controller.showWindow(nil)
        window.center()
    }

    func close() {
        controller.close()
    }
}

struct Cmdline: View {
    var body: some View {
        HStack {
            Image("NeovimIcon")
                .resizable()
                .frame(width: 24, height: 24)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(Color(nsColor: NSColor.darkGray))
            Text("Normal")
            Spacer()
        }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
    }
}
