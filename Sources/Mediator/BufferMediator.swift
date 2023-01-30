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
import Toolkit

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

    /// When we synchronize from Nvim to `AXUIElement`, a lot of accessibility
    /// events (`selectedTextRangeChanged`, `valueChanged`, etc.) will be fired
    /// in a row. To prevent synchronizing these changes back to Nvim, we ignore
    /// the events with this lock debounced with a given delay.
    private var editLock = TimeSwitch(timer: 0.5)

    init(nvim: Nvim, buffer: BufferHandle, element: AXUIElement, name: String, buffers: Buffers) {
        self.nvim = nvim
        self.buffer = buffer
        self.element = element
        self.name = name
        self.buffers = buffers

        buffers.subscribeToLines(of: buffer)
            .receive(on: DispatchQueue.main)
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

        try element.set(.selectedTextRange, value: range.cfRange(in: content))
        try element.set(.selectedText, value: replacement)
        editLock.activate()
    }

    private func lines() -> (String, [Substring]) {
        guard let value: String = element[.value] else {
            return ("", [])
        }
        return (value, value.lines)
    }

    private(set) var cursorPosition: CursorPosition = (0, 0)
    private(set) var mode: Mode = .normal

    func setCursor(position: CursorPosition) {
        precondition(Thread.isMainThread)
        if !editLock.isOn, cursorPosition != position {
            nvim.api.winSetCursor(position: position)
                .assertNoFailure()
                .run()
        }
    }

    func setCursor(position: CursorPosition, mode: Mode) {
        precondition(Thread.isMainThread)
        editLock.activate()

        cursorPosition = position
        self.mode = mode

        let (_, lines) = lines()
        var offset = 0
        for (i, line) in lines.enumerated() {
            if i == position.line {
                offset += position.column
                break
            }
            offset += line.count + 1
        }

        let length: Int = {
            switch mode {
            case .normal:
                return 1
            case .insert:
                return 0
            }
        }()

        let range = CFRange(location: offset, length: length)
        try? element.set(.selectedTextRange, value: range)
    }
}
