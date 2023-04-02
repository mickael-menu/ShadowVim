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
import Cocoa
import Foundation
import Mediator
import Nvim
import SwiftUI

/// The buffer preview window is used to display the content of the currently
/// focused Nvim buffer, for debugging purposes.
class BufferPreviewController {
    let window: NSWindow
    private let controller: NSWindowController
    private let shadowVim: ShadowVim

    init(frame: CGRect, shadowVim: ShadowVim) {
        self.shadowVim = shadowVim

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        controller = NSWindowController(window: window)
        setupWindow()
    }

    private func setupWindow() {
        window.canHide = false
        window.level = .floating
        window.isMovableByWindowBackground = true

        let contentView = window.contentView!

        let hostingView = NSHostingView(rootView: BufferPreview(shadowVim: shadowVim))
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.height, .width]
        contentView.addSubview(hostingView)
    }

    func show() {
        controller.showWindow(nil)
        window.center()
    }

    func close() {
        controller.close()
    }
}

struct BufferPreview: View {
    @ObservedObject var shadowVim: ShadowVim

    var body: some View {
        if let nvimBuffer = shadowVim.focusedNvimBuffer {
            TextView(buffer: nvimBuffer, selectedRanges: shadowVim.nvimSelectedRanges)
        } else {
            Text("No focused buffer")
        }
    }
}

struct TextView: NSViewRepresentable {
    @ObservedObject var buffer: NvimBuffer
    let selectedRanges: [NSRange]

    @Environment(\.colorScheme)
    var colorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        var frame = scrollView.bounds
        frame.size.width = 1000

        let textView = NSTextView(frame: frame)
        // textView.isEditable = false
        // textView.isSelectable = false
        textView.autoresizingMask = [.height]

        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.selectedTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .backgroundColor: NSColor.textColor,
        ]

        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard
            let textView = nsView.documentView as? NSTextView
        else {
            return
        }

        let content = buffer.lines.joinedLines() + "∅"
        if textView.string != content {
            textView.string = content
        }

        DispatchQueue.main.async {
            if !selectedRanges.isEmpty {
                textView.selectedRanges = selectedRanges.map { NSValue(range: $0) }
            }

            if let range = selectedRanges.first {
                textView.scrollRangeToVisible(range)
            }
        }
    }
}
