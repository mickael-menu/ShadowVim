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
    var uiBuffer: AXUIElement
    let nvimBuffer: Buffer
    let name: String
    weak var delegate: BufferMediatorDelegate?

    private let nvim: Nvim
    private let logger: Logger?
    private var subscriptions: Set<AnyCancellable> = []

    /// When we synchronize from Nvim to `AXUIElement`, a lot of accessibility
    /// events (`selectedTextChanged`, `valueChanged`, etc.) will be fired in a
    /// row. To prevent synchronizing these changes back to Nvim, we ignore the
    /// events with this lock debounced with a given delay.
    private var token: BufferToken!

    init(
        nvim: Nvim,
        nvimBuffer: Buffer,
        uiBuffer: AXUIElement,
        name: String,
        nvimCursorPublisher: AnyPublisher<Cursor, APIError>,
        logger: Logger?,
        delegate: BufferMediatorDelegate?
    ) {
        self.nvim = nvim
        self.nvimBuffer = nvimBuffer
        self.uiBuffer = uiBuffer
        self.name = name
        self.logger = logger
        self.delegate = delegate
        
        self.token = BufferToken(
            logger: logger?.domain("token"),
            onRelease: { [weak self] in self?.didReleaseToken(owner: $0) }
        )

        setupBufferSync()
        setupCursorSync(nvimCursorPublisher: nvimCursorPublisher)
    }

    func didFocus() {
        uiCursorDidChange()
    }

    private func didReleaseToken(owner: BufferToken.Owner) {
        DispatchQueue.main.async { [self] in
            do {
                let uiLines = (try uiBuffer.get(.value) ?? "").lines.map { String($0) }
                let nvimLines = nvimBuffer.lines
            
                switch owner {
                case .nvim:
                    let changes = nvimLines.difference(from: uiLines)
                    if !changes.isEmpty {
                        logger?.d([
                            .message: "Needs updating Nvim → UI",
                            "changes": changes,
                            "nvimLines": nvimLines,
                            "uiLines": uiLines
                        ])
                        applyNvimChanges(changes)
                        nvimCursorDidChange(nvimCursor)
                    }
                    
                case .ui:
                    let changes = uiLines.difference(from: nvimLines)
                    if !changes.isEmpty {
                        logger?.d([
                            .message: "Needs updating UI → Nvim",
                            "changes": changes,
                            "nvimLines": nvimLines,
                            "uiLines": uiLines
                        ])
                        
//                        nvim.api.bufSetLines(buffer: nvimBuffer.handle, start: 0, end: -1, replacement: uiLines)
//                            .forwardErrorToDelegate(of: self)
//                            .run()
                    }
                }
                    
            } catch {
                delegate?.bufferMediator(self, didFailWithError: error)
            }
        }
    }
    
    private func applyNvimChanges(_ changes: CollectionDifference<String>) {
        do {
            for change in changes {
                switch change {
                case .insert(offset: let offset, element: let element, _):
                    guard let range: CFRange = try uiBuffer.get(.rangeForLine, with: offset) else {
                        logger?.w("Failed to insert line at \(offset)")
                        return
                    }
                    try uiBuffer.set(.selectedTextRange, value: CFRange(location: range.location, length: 0))
                    try uiBuffer.set(.selectedText, value: element + "\n")
                    
                case .remove(offset: let offset, _, _):
                    guard let range: CFRange = try uiBuffer.get(.rangeForLine, with: offset) else {
                        logger?.w("Failed to remove line at \(offset)")
                        return
                    }
                    try uiBuffer.set(.selectedTextRange, value: range)
                    try uiBuffer.set(.selectedText, value: "")
                }
            }
        } catch {
            logger?.e(error)
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    // MARK: - Buffer synchronization

    func refreshUI() -> Bool {
        guard token.tryAcquire(for: .nvim) else {
            return false
        }
        
        do {
            try uiBuffer.set(.value, value: nvimBuffer.lines.joinedLines())
            nvimCursorDidChange(nvimCursor)
        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
        return true
    }

    private func setupBufferSync() {
        // Nvim -> UI
        nvimBuffer.didChangePublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] _ in
                    nvimBufferDidChange()
                }
            )
            .store(in: &subscriptions)

        // UI -> Nvim
        uiBuffer.publisher(for: .valueChanged)
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] _ in
                    uiBufferDidChange()
                }
            )
            .store(in: &subscriptions)
    }

    private func nvimBufferDidChange() {
        precondition(Thread.isMainThread)

        guard token.tryAcquire(for: .nvim) else {
            return
        }
        
        do {
            let uiContent = try uiBuffer.get(.value) ?? ""
            guard uiContent == nvimBuffer.oldLines.joinedLines() else {
                logger?.t([
                    .message: "Cannot apply buffer changes from Nvim",
                    "expected": self.nvimBuffer.oldLines,
                    "current": uiContent.lines.map { String($0) }
                ])
                return
            }
            
            guard
                uiContent != nvimBuffer.lines.joinedLines(),
                let (range, replacement) = nvimBuffer.lastLinesEvent?.changes(in: uiContent)
            else {
                return
            }

            try uiBuffer.set(.selectedTextRange, value: range.cfRange(in: uiContent))
            try uiBuffer.set(.selectedText, value: replacement)
            nvimCursorDidChange(nvimCursor)

        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    private func uiBufferDidChange() {
        precondition(Thread.isMainThread)

        guard token.tryAcquire(for: .ui) else {
            return
        }
        
        do {
            let lines = (try uiBuffer.get(.value) ?? "").lines

            try withAsyncGroup { group in
                let cursor = try cursorPosition(of: uiBuffer)
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
                    nvim.api.bufSetLines(buffer: nvimBuffer.handle, start: start, end: end, replacement: replacement)
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
        // Nvim -> UI
        nvimCursorPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] cursor in
                    nvimCursorDidChange(cursor)
                }
            )
            .store(in: &subscriptions)

        // UI -> Nvim
        uiBuffer.publisher(for: .selectedTextChanged)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.bufferMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] _ in
                    uiCursorDidChange()
                }
            )
            .store(in: &subscriptions)
    }

    private func nvimCursorDidChange(_ cursor: Cursor) {
        precondition(Thread.isMainThread)
        
        nvimCursor = cursor
        
        guard token.tryAcquire(for: .nvim) else {
            return
        }

        do {
            guard let lineRange: CFRange = try uiBuffer.get(.rangeForLine, with: cursor.position.line) else {
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

            try uiBuffer.set(.selectedTextRange, value: range)
        } catch {
            delegate?.bufferMediator(self, didFailWithError: error)
        }
    }

    private func uiCursorDidChange() {
        precondition(Thread.isMainThread)
        
        guard token.tryAcquire(for: .ui) else {
            return
        }
        
        do {
            guard
                let curPos = try cursorPosition(of: uiBuffer),
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
