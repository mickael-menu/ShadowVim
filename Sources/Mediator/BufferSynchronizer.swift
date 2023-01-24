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
import Foundation
import Nvim

enum Mode: String {
    case normal = "n"
    case insert = "i"
}

enum BufferSynchronizerError: Error {}

final class BufferSynchronizer {
    var element: AXUIElement

    private let nvim: Nvim
    private let name: String
    private var buffer: Buffer!

    init(nvim: Nvim, element: AXUIElement, name: String) {
        self.nvim = nvim
        self.element = element
        self.name = name
    }

    func edit() async throws {
        let caches = URL.cachesDirectory
            .appending(component: "menu.mickael.ShadowVim")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let url = caches.appending(path: name)

//        var pos: CursorPosition = (0, 0)
//        var selection: CFRange = element[.selectedTextRange] ?? CFRange(location: 0, length: 0)
//        selection = CFRange(location: selection.location, length: 1) // Normal mode
//        pos.row = element[.lineForIndex] ?? 0
//        pos.col = element[.lineForIndex] ?? 0

        let content: String = element[.value] ?? ""
        try content.write(to: url, atomically: true, encoding: .utf8)

        print("edit \(url.path)")
        try await nvim.edit(url: url)

        buffer = try await nvim.buffer()

        await buffer.attach(
            sendBuffer: false,
            onLines: { event in
                DispatchQueue.main.sync {
                    try! self.update(event)
                }
            }
        )

//        element[.selectedTextRange] = selection
    }

    private func update(_ event: BufLinesEvent) throws {
        print("\(event)")
        print("\n")

        let content = (try element.get(.value) as String?) ?? ""
        guard let (range, replacement) = event.changes(in: content) else {
            return
        }

        element[.selectedTextRange] = range.cfRange(in: content)
        element[.selectedText] = replacement
    }

    func lines() -> (String, [Substring]) {
        guard let value: String = element[.value] else {
            return ("", [])
        }
        return (value, value.split(separator: "\n", omittingEmptySubsequences: false))
    }

    func setCursor(position: Int, mode: Mode) {
        let length: Int = {
            switch mode {
            case .normal:
                return 1
            case .insert:
                return 0
            }
        }()
        let range = CFRange(location: position, length: length)
        try? element.set(.selectedTextRange, value: range)
    }
}
