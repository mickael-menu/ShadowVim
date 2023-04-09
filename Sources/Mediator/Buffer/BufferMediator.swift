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
    typealias Factory = ((
        nvimBuffer: NvimBuffer,
        uiElement: AXUIElement
    )) -> BufferMediator

    weak var delegate: BufferMediatorDelegate?

    private var state: any BufferState
    private let nvimController: NvimController
    private let nvimBuffer: NvimBuffer
    private let logger: Logger?

    private var timeoutTimers: [Int: Timer] = [:]
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

    public var nvimHandle: BufferHandle {
        nvimBuffer.handle
    }

    init(
        nvimController: NvimController,
        nvimBuffer: NvimBuffer,
        uiElement: AXUIElement,
        logger: Logger?
    ) {
        self.nvimController = nvimController
        self.nvimBuffer = nvimBuffer
        self.uiElement = uiElement
        self.logger = logger

        state = ExclusiveBufferState(
            nvim: .init(lines: nvimBuffer.lines),
            ui: .init(lines: uiElement.lines())
        ).loggable(logger)

        subscribeToElementChanges(uiElement)

        nvimBuffer.linesEventPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] in
                    on(.nvimLinesDidChange($0))
                }
            )
            .store(in: &subscriptions)
    }

    /// Returns the screen coordinates to the current UI cursor position.
    ///
    /// When a range is selected, returns the center point.
    func uiCursorLocation() throws -> CGPoint? {
        guard
            let element = uiElement,
            let selectedRange: CFRange = try element.get(.selectedTextRange),
            let bounds: CGRect = try element.get(.boundsForRange, with: selectedRange)
        else {
            return nil
        }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func synchronize(source: BufferHost) {
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
        precondition(Thread.isMainThread)

        do {
            uiElement = element

            try on(.uiDidFocus(lines: element.lines(), selection: element.selection() ?? .init()))

        } catch AX.AXError.invalidUIElement {
            uiElement = nil
        } catch {
            fail(error)
        }
    }

    func didReceiveEvent(_ event: InputEvent) -> Bool {
        switch event {
        case let .key(event):
            return on(.uiDidReceiveKeyEvent(event.keyCombo, character: event.character))
        case let .mouse(event):
            return handle(event)
        }
    }

    private func handle(_ event: MouseEvent) -> Bool {
        // We use the element's parent to get the frame because Xcode's source
        // editors return garbage positions.
        let bufferFrame = uiElement?.parent()?.frame() ?? .zero
        let screenPoint = event.event.location
        var bufferPoint: CGPoint?
        if bufferFrame.contains(screenPoint) {
            // Adapts point in the coordinates of frame
            bufferPoint = CGPoint(
                x: screenPoint.x - bufferFrame.origin.x,
                y: screenPoint.y - bufferFrame.origin.y
            )
        }

        on(.uiDidReceiveMouseEvent(event.kind, bufferPoint: bufferPoint))

        // Don't override default system behavior
        return false
    }

    func nvimDidFlush() {
        on(.nvimDidFlush)
    }

    func nvimModeDidChange(_ mode: Mode) {
        on(.nvimModeDidChange(mode))
    }

    func nvimCursorDidChange(_ cursor: NvimCursor) {
        on(.nvimCursorDidChange(cursor))
    }

    private func subscribeToElementChanges(_ element: AXUIElement) {
        uiSubscriptions = []

        element.publisher(for: .valueChanged)
//            .debounce(for: 0.2, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .map { $0.lines() }
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

    /// Returns whether the event triggered actions.
    @discardableResult
    private func on(_ event: BufferEvent) -> Bool {
        precondition(Thread.isMainThread)
        let actions = state.on(event, logger: logger)
        for action in actions {
            perform(action)
        }

        return !actions.isEmpty
    }

    private func perform(_ action: BufferAction) {
        do {
            switch action {
            case let .nvimUpdateLines(lines):
                nvimController.setLines(lines, in: nvimBuffer)
                    .get(onFailure: fail)

            case let .nvimMoveCursor(position):
                nvimController.setCursor(in: nvimBuffer, at: position)
                    .get(onFailure: fail)

            case let .nvimStartVisual(start: start, end: end):
                nvimController.startVisual(in: nvimBuffer, from: start, to: end)
                    .get(onFailure: fail)

            case .nvimStopVisual:
                nvimController.stopVisual()
                    .get(onFailure: fail)

            case .nvimUndo:
                nvimController.undo(in: nvimBuffer)
                    .get(onFailure: fail)

            case .nvimRedo:
                nvimController.redo(in: nvimBuffer)
                    .get(onFailure: fail)

            case .nvimPaste:
                if let text = NSPasteboard.get() {
                    nvimController.paste(text, in: nvimBuffer)
                        .get(onFailure: fail)
                }

            case let .nvimInput(keys):
                nvimController.input(keys, in: nvimBuffer)
                    .get(onFailure: fail)

            case let .uiUpdateLines(lines):
                try updateUILines(lines)

            case let .uiUpdateSelections(selections):
                try updateUISelections(selections)

            case let .uiScroll(visibleSelection: visibleSelection):
                try scrollUI(to: visibleSelection)

            case let .startTimeout(id: id, durationInSeconds: duration):
                startTimeout(id: id, for: duration)

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

    private func updateUILines(_ lines: [String]) throws {
        guard
            let uiElement = uiElement,
            let oldLines = uiElement.stringValue()?.lines
        else {
            return
        }

        let diff = lines.difference(from: oldLines.map { String($0) })

        if let (offset, line) = diff.updatedSingleItem {
            try updateUIOneLine(
                at: offset,
                in: uiElement,
                content: uiElement.stringValue() ?? "",
                replacement: line
            )
        } else if !diff.isEmpty {
            try updateUIMultipleLines(diff: diff, in: uiElement)
        }
    }

    private func updateUIMultipleLines(diff: CollectionDifference<String>, in uiElement: AXUIElement) throws {
        for change in diff.coalesceChanges() {
            let eof = try (uiElement.get(.numberOfCharacters) as Int?) ?? 0
            switch change {
            case let .insert(index, lines):
                var content = lines.joinedLines()
                guard let range: CFRange = try uiElement.get(.rangeForLine, with: index) else {
                    logger?.w("Failed to insert lines at \(index)")
                    return
                }
                // If the line is not inserted at the end of the file, then
                // we append a newline to separate it from the next line.
                if range.location < eof {
                    content += "\n"
                }

                let editRange = CFRange(location: range.location, length: 0)
                try uiElement.replaceText(in: editRange, with: content)

            case let .remove(indices):
                guard var range: CFRange = try uiElement.get(.rangeForLine, with: indices.lowerBound) else {
                    logger?.w("Failed to remove lines at \(indices.lowerBound)...\(indices.upperBound)")
                    return
                }
                if indices.lowerBound != indices.upperBound {
                    guard let lastLineRange: CFRange = try uiElement.get(.rangeForLine, with: indices.upperBound) else {
                        logger?.w("Failed to remove lines at \(indices.lowerBound)...\(indices.upperBound)")
                        return
                    }
                    range = CFRange(location: range.location, length: (lastLineRange.location + lastLineRange.length) - range.location)
                }

                // If we're removing the last line, then the previous
                // newline is also removed to avoid keeping an empty
                // ghost line.
                if range.location + range.length == eof, range.location > 0 {
                    range = CFRange(location: range.location - 1, length: range.length + 1)
                }
                try uiElement.replaceText(in: range, with: "")
            }
        }
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

        try element.replaceText(in: range.cfRange(in: content), with: replacement)
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

        try element.replaceText(in: range, with: replacement)
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

    private func startTimeout(id: Int, for duration: Double) {
        timeoutTimers[id]?.invalidate()
        timeoutTimers[id] = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.on(.didTimeout(id: id))
        }
    }

    private func fail(_ error: Error) {
        precondition(Thread.isMainThread)
        if case AX.AXError.invalidUIElement = error {
            uiElement = nil
        } else {
            on(.didFail(error.equatable()))
        }
    }
}

private extension AXUIElement {
    /// Returns the string value of the receiving accessibility element split as
    /// lines.
    func lines() -> [String] {
        guard let text = stringValue() else {
            return []
        }

        return text.lines.map { String($0) }
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
