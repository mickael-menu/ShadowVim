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
    private let logger: Logger?
    private var subscriptions: Set<AnyCancellable> = []

    /// When we synchronize from Nvim to `AXUIElement`, a lot of accessibility
    /// events (`selectedTextChanged`, `valueChanged`, etc.) will be fired in a
    /// row. To prevent synchronizing these changes back to Nvim, we ignore the
    /// events with this lock debounced with a given delay.
    private var nvimLock = TimeSwitch(timer: 0.3)

    init(
        nvim: Nvim,
        buffer: BufferHandle,
        element: AXUIElement,
        name: String,
        nvimBufferPublisher: AnyPublisher<Buffer, Never>,
        nvimCursorPublisher: AnyPublisher<Cursor, APIError>,
        logger: Logger?,
        delegate: BufferMediatorDelegate?
    ) {
        self.nvim = nvim
        self.buffer = buffer
        self.element = element
        self.name = name
        self.logger = logger
        self.delegate = delegate

        setupBufferSync(nvimBufferPublisher: nvimBufferPublisher)
        setupCursorSync(nvimCursorPublisher: nvimCursorPublisher)
    }

    func didFocus() {
        syncCursorAX2Nvim()
    }

    // MARK: - Buffer synchronization

    private var nvimBuffer: Buffer?

    private func setupBufferSync(nvimBufferPublisher: AnyPublisher<Buffer, Never>) {
        // Nvim -> AX
        nvimBufferPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] event in
                    syncBufferNvim2AX(with: event)
                }
            )
            .store(in: &subscriptions)

        // AX -> Nvim
        element.publisher(for: .valueChanged)
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] _ in
                    syncBufferAX2Nvim()
                }
            )
            .store(in: &subscriptions)
    }

    private func syncBufferNvim2AX(with buffer: Buffer) {
        do {
            nvimBuffer = buffer
            let content = (try element.get(.value) as String?) ?? ""
            let value = try element.get(.value) ?? ""
            guard
                value != buffer.lines.joinedLines(),
                let (range, replacement) = buffer.lastLinesEvent?.changes(in: content)
            else {
                return
            }

            nvimLock.activate()
            try element.set(.selectedTextRange, value: range.cfRange(in: content))
            try element.set(.selectedText, value: replacement)
            syncCursorNvim2AX(nvimCursor)

        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    private func syncBufferAX2Nvim() {
        do {
            guard !nvimLock.isOn, let nvimBuffer = nvimBuffer else {
                return
            }
            let lines = (try element.get(.value) ?? "").lines

            try withAsyncGroup { group in
                let cursor = try cursorPosition(of: element)
                let diff = lines.map { String($0) }.difference(from: nvimBuffer.lines)
                for change in diff {
                    var start: LineIndex
                    var end: LineIndex
                    var replacement: [String]
                    switch change {
                    case let .insert(offset: offset, element: element, _):
                        start = offset
                        end = offset
                        replacement = [element]
                    case let .remove(offset: offset, _, _):
                        start = offset
                        end = offset + 1
                        replacement = []
                    }
                    nvim.api.bufSetLines(buffer: buffer, start: start, end: end, replacement: replacement)
                        .add(to: group)
                }

                if let cursor = cursor {
                    nvim.api.getCurrentBuf()
                        .flatMap { _ in
                            self.nvim.api.winSetCursor(position: cursor)
                        }
                        .discardResult()
                        .add(to: group)
                }
            }
            .forwardErrorToDelegate(of: self)
            .run()

        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    // MARK: - Cursor synchronization

    /// Current Nvim cursor state.
    private var nvimCursor: Cursor = .init(
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
        nvimLock.activate()

        nvimCursor = cursor

        do {
            guard let lineRange: CFRange = try element.get(.rangeForLine, with: cursor.position.line) else {
                return
            }

            let range = CFRange(
                location: lineRange.location + cursor.position.column,
                length: {
                    switch cursor.mode {
                    case .insert, .replace:
                        return 0
                    default:
                        return 1
                    }
                }()
            )

            try element.set(.selectedTextRange, value: range)
        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    private func syncCursorAX2Nvim() {
        precondition(Thread.isMainThread)
        do {
            guard
                !nvimLock.isOn,
                let curPos = try cursorPosition(of: element),
                nvimCursor.position != curPos
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
