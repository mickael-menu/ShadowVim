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

import AX
import Combine
import Foundation
import Nvim

enum Mode: String {
    case normal = "n"
    case insert = "i"
}

final class BufferMediator {
    var element: AXUIElement
    let buffer: BufferHandle
    let name: String

    private let nvim: Nvim
    private let buffers: Buffers
    private var subscriptions: Set<AnyCancellable> = []

    init(nvim: Nvim, buffer: BufferHandle, element: AXUIElement, name: String, buffers: Buffers) {
        self.nvim = nvim
        self.buffer = buffer
        self.element = element
        self.name = name
        self.buffers = buffers

        buffers.subscribeToLines(of: buffer)
            .sink { [weak self] in
                do {
                    try self?.update($0)
                } catch {
                    print(error)
                }
            }
            .store(in: &subscriptions)
    }

    private func update(_ event: BufLinesEvent) throws {
//        print("\(event)")
//        print("\n")
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
        return (value, value.lines)
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
