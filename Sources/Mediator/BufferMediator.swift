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

struct Cursor {
    let position: BufferPosition
    let mode: Mode
}

protocol BufferMediatorDelegate: AnyObject {
    /// Called when an error occurred while mediating the buffer.
    func bufferMediator(_ mediator: BufferMediator, didFailWithError error: Error)
}

final class BufferMediator {
    var element: AXUIElement
    let buffer: BufferHandle
    let name: String
    weak var delegate: BufferMediatorDelegate?

    private let nvim: Nvim
    private var subscriptions: Set<AnyCancellable> = []

    /// When we synchronize from Nvim to `AXUIElement`, a lot of accessibility
    /// events (`selectedTextRangeChanged`, `valueChanged`, etc.) will be fired
    /// in a row. To prevent synchronizing these changes back to Nvim, we ignor
    /// the events with this lock debounced with a given delay.
    private var editLock = TimeSwitch(timer: 0.5)

    init(
        nvim: Nvim,
        buffer: BufferHandle,
        element: AXUIElement,
        name: String,
        nvimLinesPublisher: AnyPublisher<BufLinesEvent, APIError>,
        nvimCursorPublisher: AnyPublisher<Cursor, APIError>,
        delegate: BufferMediatorDelegate?
    ) {
        self.nvim = nvim
        self.buffer = buffer
        self.element = element
        self.name = name
        self.delegate = delegate

        setupContentSync(nvimLinesPublisher: nvimLinesPublisher)
        setupCursorSync(nvimCursorPublisher: nvimCursorPublisher)
    }

    func didFocus() {
        syncCursorAX2Nvim()
    }

    // MARK: - Content synchronization

    private func setupContentSync(nvimLinesPublisher: AnyPublisher<BufLinesEvent, APIError>) {
        nvimLinesPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] event in
                    nvimDidUpdateLines(event)
                }
            )
            .store(in: &subscriptions)
    }

    private func nvimDidUpdateLines(_ event: BufLinesEvent) {
        do {
            let content = (try element.get(.value) as String?) ?? ""
            guard let (range, replacement) = event.changes(in: content) else {
                return
            }

            try element.set(.selectedTextRange, value: range.cfRange(in: content))
            try element.set(.selectedText, value: replacement)
            editLock.activate()

        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    private func lines() -> (String, [Substring]) {
        guard let value: String = element[.value] else {
            return ("", [])
        }
        return (value, value.lines)
    }

    // MARK: - Cursor synchronization

    /// Current Nvim cursor state.
    private var cursor: Cursor = .init(
        position: (0, 0),
        mode: .normal
    )

    private func setupCursorSync(nvimCursorPublisher: AnyPublisher<Cursor, APIError>) {
        // Nvim -> AX
        nvimCursorPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] cursor in
                    syncCursorNvim2AX(cursor)
                }
            )
            .store(in: &subscriptions)

        // AX -> Nvim
        element.publisher(for: .selectedTextChanged)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] _ in
                    syncCursorAX2Nvim()
                }
            )
            .store(in: &subscriptions)
    }

    private func syncCursorNvim2AX(_ cursor: Cursor) {
        precondition(Thread.isMainThread)
        editLock.activate()

        self.cursor = cursor

        let (_, lines) = lines()
        var offset = 0
        for (i, line) in lines.enumerated() {
            if i == cursor.position.line {
                offset += cursor.position.column
                break
            }
            offset += line.count + 1
        }

        let length: Int = {
            switch cursor.mode {
            case .insert, .replace:
                return 0
            default:
                return 1
            }
        }()

        let range = CFRange(location: offset, length: length)
        try? element.set(.selectedTextRange, value: range)
    }

    private func syncCursorAX2Nvim() {
        precondition(Thread.isMainThread)
        do {
            guard
                !editLock.isOn,
                let curPos = try cursorPosition(of: element),
                cursor.position != curPos
            else {
                return
            }

            nvim.api.winSetCursor(position: curPos)
                .forwardErrorToDelegate(of: self)
                .run()

        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    /// Returns the current cursor position of the given accessibility
    /// `element`.
    private func cursorPosition(of element: AXUIElement) throws -> BufferPosition? {
        guard
            let selection: CFRange = try element.get(.selectedTextRange),
            let line: Int = try element.get(.lineForIndex, with: selection.location),
            let lineRange: CFRange = try element.get(.rangeForLine, with: line)
        else {
            return nil
        }
        return BufferPosition(
            line: line,
            column: selection.location - lineRange.location
        )
    }
}

private extension Async {
    func forwardErrorToDelegate(of mediator: BufferMediator) -> Async<Success, Never> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { error, _ in
                mediator.delegate?.bufferMediator(mediator, didFailWithError: error)
            }
        )
    }
}
