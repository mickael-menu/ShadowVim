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
import AX
import Combine
import Foundation
import Nvim
import Toolkit

protocol BufferMediatorDelegate: AnyObject {
    /// Called when an error occurred while mediating the buffer.
    func bufferMediator(_ mediator: BufferMediator, didFailWithError error: Error)
}

public final class BufferMediator {
    public typealias Factory = ((
        nvim: Nvim,
        nvimBuffer: NvimBuffer,
        uiElement: AXUIElement,
        nvimCursorPublisher: AnyPublisher<Cursor, NvimError>
    )) -> BufferMediator

    weak var delegate: BufferMediatorDelegate?

    private var state: BufferState
    private let nvim: Nvim
    let nvimBuffer: NvimBuffer
    private let logger: Logger?
    private let tokenTimeoutSubject = PassthroughSubject<Void, Never>()

    private var subscriptions: Set<AnyCancellable> = []
    private var uiSubscriptions: Set<AnyCancellable> = []

    private(set) var uiElement: AXUIElement? {
        didSet {
            if oldValue != uiElement {
                uiSubscriptions = []
                if let uiElement = uiElement {
                    subscribeToElementChanges(uiElement)
                }
            }
        }
    }

    public init(
        nvim: Nvim,
        nvimBuffer: NvimBuffer,
        uiElement: AXUIElement,
        nvimCursorPublisher: AnyPublisher<Cursor, NvimError>,
        logger: Logger?
    ) {
        self.nvim = nvim
        self.nvimBuffer = nvimBuffer
        self.uiElement = uiElement
        self.logger = logger

        state = BufferState(
            nvim: .init(lines: nvimBuffer.lines),
            ui: .init(lines: (try? uiElement.lines()) ?? [])
        )

        subscribeToElementChanges(uiElement)

        nvimBuffer.didChangePublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] in
                    on(.nvimBufferDidChange(lines: $0.lines, event: $0.event))
                }
            )
            .store(in: &subscriptions)

        nvimCursorPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] cursor in
                    on(.nvimCursorDidChange(cursor))
                }
            )
            .store(in: &subscriptions)

        tokenTimeoutSubject
            .receive(on: DispatchQueue.main)
            .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.on(.tokenDidTimeout) }
            .store(in: &subscriptions)
    }

    func synchronize(source: BufferState.Host) {
        DispatchQueue.main.async {
            self.on(.didRequestRefresh(source: .nvim))
        }
    }

    func didToggleKeysPassthrough(enabled: Bool) {
        DispatchQueue.main.async {
            self.on(.didToggleKeysPassthrough(enabled: enabled))
        }
    }

    func didFocus(element: AXUIElement) {
        do {
            uiElement = element

            on(.uiBufferDidChange(lines: try element.lines()))

            if let selection = try element.selection() {
                on(.uiSelectionDidChange(selection))
            }
        } catch AX.AXError.invalidUIElement {
            uiElement = nil
        } catch {
            fail(error)
        }
    }

    func didReceiveMouseEvent(_ event: MouseEvent) {
        // We use the element's parent to get the frame because Xcode's source
        // editors return garbage positions.
        let bufferFrame = uiElement?.parent()?.frame() ?? .zero
        let screenPoint = event.event.location
        var bufferPoint: CGPoint? = nil
        if bufferFrame.contains(screenPoint) {
            // Adapts point in the coordinates of frame
            bufferPoint = CGPoint(
                x: screenPoint.x - bufferFrame.origin.x,
                y: screenPoint.y - bufferFrame.origin.y
            )
        }

        on(.uiDidReceiveMouseEvent(event.kind, bufferPoint: bufferPoint))
    }

    private func subscribeToElementChanges(_ element: AXUIElement) {
        uiSubscriptions = []

        element.publisher(for: .valueChanged)
            .receive(on: DispatchQueue.main)
            .tryMap { try $0.lines() }
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] in
                    on(.uiBufferDidChange(lines: $0))
                }
            )
            .store(in: &uiSubscriptions)

        element.publisher(for: .selectedTextChanged)
            .receive(on: DispatchQueue.main)
            .tryCompactMap { try $0.selection() }
            .removeDuplicates()
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] in
                    on(.uiSelectionDidChange($0))
                }
            )
            .store(in: &uiSubscriptions)
    }

    private func on(_ event: BufferState.Event) {
        precondition(Thread.isMainThread)
        let actions = state.on(event, logger: logger)
        for action in actions {
            perform(action)
        }
    }

    private func perform(_ action: BufferState.Action) {
        do {
            switch action {
            case let .updateNvim(_, diff: diff, cursorPosition: cursorPosition):
                updateNvim(diff: diff, cursorPosition: cursorPosition)
            case let .moveNvimCursor(position):
                moveNvimCursor(position: position)
            case let .startNvimVisual(start: start, end: end):
                startNvimVisual(from: start, to: end)
            case .stopNvimVisual:
                stopNvimVisual()
            case let .updateUI(_, diff: diff, selections: selections):
                try updateUI(diff: diff, selections: selections)
            case let .updateUIPartialLines(event: event):
                try updateUIPartialLines(with: event)
            case let .updateUISelections(selections):
                try updateUISelections(selections)
            case let .scrollUI(visibleSelection: visibleSelection):
                try scrollUI(to: visibleSelection)
            case .startTokenTimeout:
                tokenTimeoutSubject.send(())
            case .bell:
                NSSound.beep()
            case let .alert(error):
                delegate?.bufferMediator(self, didFailWithError: error.error)
            }
        } catch AX.AXError.invalidUIElement {
            uiElement = nil
        } catch {
            fail(error)
        }
    }

    private func updateNvim(diff: CollectionDifference<String>, cursorPosition: BufferPosition) {
        nvim.vim?.atomic(in: nvimBuffer) { [self] vim in
            withAsyncGroup { group in
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
                    vim.api.bufSetLines(buffer: nvimBuffer.handle, start: start, end: end, replacement: replacement)
                        .eraseToAnyError()
                        .add(to: group)
                }

                vim.api.winSetCursor(position: cursorPosition, failOnInvalidPosition: false)
                    .eraseToAnyError()
                    .add(to: group)
            }
        }
        .get(onFailure: fail)
    }

    private func moveNvimCursor(position: BufferPosition) {
        nvim.vim?.atomic(in: nvimBuffer) { vim in
            vim.api.winSetCursor(position: position, failOnInvalidPosition: false)
        }
        .discardResult()
        .get(onFailure: fail)
    }

    /// Starts the Neovim Visual mode and selects from the given `start` and
    /// `end` positions.
    private func startNvimVisual(from start: BufferPosition, to end: BufferPosition) {
        nvim.vim?.atomic(in: nvimBuffer) { vim in
            vim.cmd(
                """
                " Exit the current mode, hopefully.
                execute "normal! \\<Ignore>\\<Esc>"
                normal! \(start.line)G\(start.column)|v\(end.line)G\(end.column)|",
                """
            )
        }
        .discardResult()
        .get(onFailure: fail)
    }

    /// Exits the Neovim Visual mode (character, line or block-wise).
    private func stopNvimVisual() {
        nvim.vim?.cmd(
            """
            if mode() =~ "^[vV\\<C-v>]$"
                execute "normal! \\<Ignore>\\<Esc>"
            endif
            """
        )
        .discardResult()
        .get(onFailure: fail)
    }

    private func updateUI(diff: CollectionDifference<String>, selections: [UISelection]) throws {
        guard let uiElement = uiElement else {
            return
        }

        if !diff.isEmpty {
            for change in diff {
                let eof = (try uiElement.get(.numberOfCharacters) as Int?) ?? 0

                switch change {
                case .insert(offset: let offset, element: var element, _):
                    guard let range: CFRange = try uiElement.get(.rangeForLine, with: offset) else {
                        logger?.w("Failed to insert line at \(offset)")
                        return
                    }
                    // If the line is not inserted at the end of the file, then
                    // we append a newline to separate it from the next line.
                    if range.location + range.length < eof {
                        element += "\n"
                    }
                    try uiElement.set(.selectedTextRange, value: CFRange(location: range.location, length: 0))
                    try uiElement.set(.selectedText, value: element)

                case let .remove(offset: offset, _, _):
                    guard var range: CFRange = try uiElement.get(.rangeForLine, with: offset) else {
                        logger?.w("Failed to remove line at \(offset)")
                        return
                    }
                    // If we're removing the last line, then the previous
                    // newline is also removed to avoid keeping an empty
                    // ghost line.
                    if range.location + range.length == eof, range.location > 0 {
                        range = CFRange(location: range.location - 1, length: range.length + 1)
                    }
                    try uiElement.set(.selectedTextRange, value: range)
                    try uiElement.set(.selectedText, value: "")
                }
            }
        }

        try updateUISelections(selections)
    }

    private func updateUIPartialLines(with event: BufLinesEvent) throws {
        guard
            let uiElement = uiElement,
            let uiContent: String = try uiElement.get(.value)
        else {
            return
        }

        if event.firstLine == event.lastLine - 1, event.lineData.count == 1 {
            try updateUIOneLine(at: event.firstLine, in: uiElement, content: uiContent, replacement: event.lineData[0])
        } else {
            try updateUIMultipleLines(event: event, in: uiElement, content: uiContent)
        }
    }

    private func updateUIMultipleLines(event: BufLinesEvent, in element: AXUIElement, content: String) throws {
        guard let (range, replacement) = event.changes(in: content) else {
            logger?.w("Failed to update partial lines")
            return
        }

        try element.set(.selectedTextRange, value: range.cfRange(in: content))
        try element.set(.selectedText, value: replacement)
    }

    // Optimizes changing only the tail of a line, to avoid refreshing the whole
    // line which triggers selection artifacts.
    private func updateUIOneLine(at lineIndex: LineIndex, in element: AXUIElement, content: String, replacement: String) throws {
        let lines = content.lines
        guard
            var range: CFRange = try element.get(.rangeForLine, with: lineIndex),
            lines.indices.contains(lineIndex)
        else {
            logger?.w("Failed to update partial lines")
            return
        }

        if lineIndex < lines.count - 1 {
            range = CFRange(location: range.location, length: max(0, range.length - 1))
        }
        let line = content.lines[lineIndex]

        var replacement = replacement
        if replacement.hasPrefix(line) {
            replacement.removeFirst(line.count)
            range = CFRange(location: range.location + range.length, length: 0)
        } else if line.hasPrefix(replacement) {
            range = CFRange(location: range.location + replacement.count, length: line.count - replacement.count)
            replacement = ""
        }

        try element.set(.selectedTextRange, value: range)
        try element.set(.selectedText, value: replacement)
    }

    private func updateUISelections(_ selections: [UISelection]) throws {
        guard let uiElement = uiElement, selections.count > 0 else {
            return
        }

        // Unfortunately, setting `selectedTextRanges` doesn't work in Xcode 14
        // (it works in TextEdit though). For now, we will join the selections
        // into a single continuous one.
        /*
         let ranges: [CFRange] = try selections
             .compactMap { try $0.range(in: uiElement) }
         try uiElement.set(.selectedTextRanges, value: ranges)
         */
        guard
            let selection = selections.joined(),
            let range = try selection.range(in: uiElement)
        else {
            return
        }
        try uiElement.set(.selectedTextRange, value: range)
    }

    private func scrollUI(to visibleSelection: UISelection) throws {
        guard
            let uiElement = uiElement,
            let range = try visibleSelection.range(in: uiElement)
        else {
            return
        }
        try uiElement.set(.visibleCharacterRange, value: range)
    }

    private func fail(_ error: Error) {
        on(.didFail(error.equatable()))
    }
}

private extension AXUIElement {
    /// Returns the string value of the receiving accessibility element split as
    /// lines.
    func lines() throws -> [String] {
        try (get(.value) as String?).map { $0.lines.map { String($0) } } ?? []
    }

    /// Returns the UI selection of the receiving accessibility element.
    func selection() throws -> UISelection? {
        guard let selection: CFRange = try get(.selectedTextRange) else {
            return nil
        }

        let start = selection.location
        let end = start + selection.length

        guard
            let startLine: Int = try get(.lineForIndex, with: start),
            let startLineRange: CFRange = try get(.rangeForLine, with: startLine),
            let endLine: Int = try get(.lineForIndex, with: end),
            let endLineRange: CFRange = try get(.rangeForLine, with: endLine)
        else {
            return nil
        }

        return UISelection(
            start: UIPosition(
                line: startLine,
                column: start - startLineRange.location
            ),
            end: UIPosition(
                line: endLine,
                column: end - endLineRange.location
            )
        )
    }
}

// MARK: - Logging

extension BufferMediator: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        [
            "handle": nvimBuffer.handle,
            "name": nvimBuffer.name ?? "",
        ]
    }
}
