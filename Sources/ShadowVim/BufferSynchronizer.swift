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

import AXSwift
import Foundation
import Nvim

enum BufferSynchronizerError: Error {}

final class BufferSynchronizer {
    private let nvim: Nvim
    private let element: UIElement
    private var buffer: Buffer!

    init(nvim: Nvim, element: UIElement) {
        self.nvim = nvim
        self.element = element
    }

    lazy var name: String = {
        if
            let window = try? element.attribute(.window) as UIElement?,
            let documentPath = try? window.attribute(.document) as String?,
            let documentURL = URL(string: documentPath)
        {
            return documentURL
                .resolvingSymlinksInPath()
                .path
                .replacingOccurrences(of: "/", with: "%")
                .replacingOccurrences(of: ":", with: "%")
        } else {
            return UUID().uuidString
        }
    }()

    func edit() async throws {
        let url = URL.temporaryDirectory.appending(path: name)

        let content = (try element.attribute(.value) as String?) ?? ""
        try content.write(to: url, atomically: true, encoding: .utf8)

        print("EDIT \(url.path)")
        try await nvim.edit(url: url)

        buffer = try await nvim.buffer()

        await buffer.attach(
            sendBuffer: true,
            onLines: { event in
                DispatchQueue.main.sync {
                    try! self.update(event)
                }
            }
        )
    }

    private func update(_ event: BufLinesEvent) throws {
        print("\(event)")
        print("\n")

        let content = (try element.attribute(.value) as String?) ?? ""
        guard let (range, replacement) = event.changes(in: content) else {
            return
        }

        let cfRange = range.cfRange(in: content)
        try element.setAttribute(.selectedTextRange, value: cfRange)
        try element.setAttribute(.selectedText, value: replacement)
    }
}
