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
    private let tokenTimeoutSubject = PassthroughSubject<Void, Never>()
    private var subscriptions: Set<AnyCancellable> = []

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
        
        state.uiBuffer.lines = (try? uiLines()) ?? []
        state.nvimBuffer.lines = nvimBuffer.lines
        
        setupBufferSync()
        setupCursorSync(nvimCursorPublisher: nvimCursorPublisher)
        
        tokenTimeoutSubject
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.on(.tokenDidTimeout) }
            .store(in: &subscriptions)
    }

    func didFocus() {
        do {
            if let selection = try uiSelection() {
                on(.uiSelectionDidChange(selection))
            }
        } catch {
            fail(error)
        }
    }
    
    // MARK: - State machine

    private enum Owner: Equatable {
        case nvim
        case ui
    }
    
    private struct State {
        var nvimBuffer: NvimBufferState = NvimBufferState()
        var uiBuffer: UIBufferState = UIBufferState()
        var token: EditionToken = .free
        
        mutating func on(_ event: Event, logger: Logger?) -> [Action] {
            var actions: [Action] = []
            
            // Syntactic sugar.
            func perform(_ action: Action) {
                actions.append(action)
            }
            
            func tryAcquire(for owner: Owner) -> Bool {
                switch token {
                case .free, .acquired(owner):
                    token = .acquired(owner)
                    perform(.startTokenTimeout)
                    return true
                default:
                    return false
                }
            }
            
            switch event {
            case .tokenDidTimeout:
                switch token {
                case .free, .synchronizing:
                    break
                case .acquired(let owner):
                    if nvimBuffer.lines != uiBuffer.lines {
                        token = .synchronizing
                        switch owner {
                        case .nvim:
                            perform(.updateUI(lines: nvimBuffer.lines, selection: nvimBuffer.uiSelection))
                        case .ui:
                            perform(.updateNvim(lines: uiBuffer.lines, cursorPosition: uiBuffer.selection.start))
                        }
                    } else {
                        token = .free
                    }
                }
                
            case .userDidRequestRefresh:
                break
                
            case .nvimBufferDidChange(oldLines: let oldLines, newLines: let newLines, event: let event):
                nvimBuffer.lines = newLines
                
                if tryAcquire(for: .nvim), uiBuffer.lines == oldLines {
                    perform(.updateUIPartialLines(fromLines: oldLines, event: event))
                    perform(.updateUISelection(nvimBuffer.uiSelection))
                }
                
            case .nvimCursorDidChange(let cursor):
                nvimBuffer.cursor = cursor
                
                if tryAcquire(for: .nvim) {
                    perform(.updateUISelection(nvimBuffer.uiSelection))
                }
                
            case .uiDidFocus(lines: let lines, selection: let selection):
                uiBuffer.lines = lines
                uiBuffer.selection = selection
                
                if tryAcquire(for: .ui) {
                    perform(.updateNvim(lines: lines, cursorPosition: selection.start))
                }
                
            case .uiBufferDidChange(lines: let lines):
                uiBuffer.lines = lines
                
                if tryAcquire(for: .ui) {
                    perform(.updateNvim(lines: lines, cursorPosition: uiBuffer.selection.start))
                }
                
            case .uiSelectionDidChange(let selection):
                uiBuffer.selection = selection
                
                if tryAcquire(for: .ui), nvimBuffer.cursor.position != selection.start {
                    perform(.updateNvimCursor(selection.start))
                }
                
            case .didFail(let error):
                perform(.alert(error))
            }
            
            if token == .synchronizing, nvimBuffer.lines == uiBuffer.lines {
                token = .free
            }
            
            return actions
        }
    }
    
    private struct NvimBufferState {
        var cursor: Cursor = Cursor(position: (0, 0), mode: .normal)
        var lines: [String] = []
        
        var uiSelection: BufferSelection {
            switch cursor.mode {
            case .insert, .replace:
                return (start: cursor.position, end: cursor.position)
            default:
                let end = (line: cursor.position.line, column: cursor.position.column + 1)
                return (start: cursor.position, end: end)
            }
        }
    }
    
    private struct UIBufferState {
        var selection: BufferSelection = ((0, 0), (0, 0))
        var lines: [String] = []
    }
    
    private enum EditionToken: Equatable {
        case free
        case acquired(Owner)
        case synchronizing
    }

    private enum Event {
        case tokenDidTimeout
        case userDidRequestRefresh
        case nvimBufferDidChange(oldLines: [String], newLines: [String], event: BufLinesEvent)
        case nvimCursorDidChange(Cursor)
        case uiDidFocus(lines: [String], selection: BufferSelection)
        case uiBufferDidChange(lines: [String])
        case uiSelectionDidChange(BufferSelection)
        case didFail(Error)
    }
    
    private enum Action {
        case updateNvim(lines: [String], cursorPosition: BufferPosition)
        case updateNvimCursor(BufferPosition)
        case updateUI(lines: [String], selection: BufferSelection)
        case updateUIPartialLines(fromLines: [String], event: BufLinesEvent)
        case updateUISelection(BufferSelection)
        case startTokenTimeout
        case alert(Error)
    }

    private var state: State = State()
    
    private func on(_ event: Event) {
        DispatchQueue.main.async { [self] in
            logger?.d("on \(event)")
            let actions = state.on(event, logger: logger)
            logger?.d("actions \(actions)")
            logger?.d("new state \(state.token)")
            for action in actions {
                perform(action)
            }
        }
    }
    
    private func perform(_ action: Action) {
        do {
            switch action {
            case .updateNvim(lines: let lines, cursorPosition: let cursorPosition):
                updateNvim(lines: lines, cursorPosition: cursorPosition)
            case .updateNvimCursor(let position):
                updateNvimCursor(position: position)
            case .updateUI(lines: let lines, selection: let selection):
                try updateUI(lines: lines, selection: selection)
            case .updateUIPartialLines(fromLines: let fromLines, event: let event):
                try updateUIPartialLines(from: fromLines, with: event)
            case .updateUISelection(let selection):
                try updateUISelection(selection)
            case .startTokenTimeout:
                tokenTimeoutSubject.send(())
            case .alert(let error):
                delegate?.bufferMediator(self, didFailWithError: error)
            }
        } catch {
            fail(error)
        }
    }    
    
    private func updateNvim(lines: [String], cursorPosition: BufferPosition) {
        nvim.api.transaction(in: nvimBuffer) { [self] api in
            withAsyncGroup { group in
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
                    api.bufSetLines(buffer: nvimBuffer.handle, start: start, end: end, replacement: replacement)
                        .eraseToAnyError()
                        .add(to: group)
                }

                api.winSetCursor(position: cursorPosition)
                    .eraseToAnyError()
                    .add(to: group)
            }
        }
        .get(onFailure: fail)
    }
    
    private func updateNvimCursor(position: BufferPosition) {
        nvim.api.transaction(in: nvimBuffer) { api in
            api.winSetCursor(position: position)
        }
        .discardResult()
        .get(onFailure: fail)
    }
    
    private func updateUI(lines: [String], selection: BufferSelection) throws {
        let changes = lines.difference(from: state.uiBuffer.lines)
        if !changes.isEmpty {
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
        }
        
        try updateUISelection(selection)
    }

    private func updateUIPartialLines(from fromLines: [String], with event: BufLinesEvent) throws {
        guard
            let uiContent: String = try uiBuffer.get(.value),
            let (range, replacement) = event.changes(in: uiContent)
        else {
            logger?.w("Failed to update partial lines")
            return
        }

        try uiBuffer.set(.selectedTextRange, value: range.cfRange(in: uiContent))
        try uiBuffer.set(.selectedText, value: replacement)
    }
    
    private func updateUISelection(_ selection: BufferSelection) throws {
        guard
            let startLineRange: CFRange = try uiBuffer.get(.rangeForLine, with: selection.start.line),
            let endLineRange: CFRange = try uiBuffer.get(.rangeForLine, with: selection.end.line)
        else {
            return
        }

        let start = startLineRange.location + selection.start.column
        let end = endLineRange.location + selection.end.column
        
        let range = CFRange(
            location: start,
            length: end - start
        )

        try uiBuffer.set(.selectedTextRange, value: range)
    }    
    
    private func fail(_ error: Error) {
        on(.didFail(error))
    }
    
    private func uiLines() throws -> [String] {
        (try uiBuffer.get(.value) ?? "").lines.map { String($0) }
    }

    private func uiSelection() throws -> BufferSelection? {
        try selection(of: uiBuffer)
    }

    // MARK: - Buffer synchronization

    func refreshUI() -> Bool {
//        guard token.tryAcquire(for: .nvim) else {
//            return false
//        }
//        
//        do {
//            try uiBuffer.set(.value, value: nvimBuffer.lines.joinedLines())
//            nvimCursorDidChange(nvimCursor)
//        } catch {
//            delegate?.bufferMediator(self, didFailWithError: error)
//        }
//        return true
        return true
    }

    private func setupBufferSync() {
        // Nvim -> UI
        nvimBuffer.didChangePublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] _ in
                    guard let event = nvimBuffer.lastLinesEvent else {
                        return
                    }
                    on(.nvimBufferDidChange(oldLines: nvimBuffer.oldLines, newLines: nvimBuffer.lines, event: event))
                }
            )
            .store(in: &subscriptions)

        // UI -> Nvim
        uiBuffer.publisher(for: .valueChanged)
            .receive(on: DispatchQueue.main)
            .tryMap { [unowned self] _ in try uiLines() }
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] in
                    on(.uiBufferDidChange(lines: $0))
                }
            )
            .store(in: &subscriptions)
    }

    private func setupCursorSync(nvimCursorPublisher: AnyPublisher<Cursor, APIError>) {
        // Nvim -> UI
        nvimCursorPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] cursor in
                    on(.nvimCursorDidChange(cursor))
                }
            )
            .store(in: &subscriptions)

        // UI -> Nvim
        uiBuffer.publisher(for: .selectedTextChanged)
            .receive(on: DispatchQueue.main)
            .tryCompactMap { [unowned self] _ in try uiSelection() }
            .sink(
                onFailure: { [unowned self] in fail($0) },
                receiveValue: { [unowned self] in
                    on(.uiSelectionDidChange($0))
                }
            )
            .store(in: &subscriptions)
    }

    /// Returns the buffer selection of the given accessibility `element`.
    private func selection(of element: AXUIElement) throws -> BufferSelection? {
        guard let selection: CFRange = try element.get(.selectedTextRange) else {
            return nil
        }
        
        let start = selection.location
        let end = start + selection.length
        
        guard
            let startLine: Int = try element.get(.lineForIndex, with: start),
            let startLineRange: CFRange = try element.get(.rangeForLine, with: startLine),
            let endLine: Int = try element.get(.lineForIndex, with: end),
            let endLineRange: CFRange = try element.get(.rangeForLine, with: endLine)
        else {
            logger?.w("Failed to compute cursor position")
            return nil
        }
        
        return (
            start: (
                line: startLine,
                column: start - startLineRange.location
            ),
            end: (
                line: endLine,
                column: end - endLineRange.location
            )
        )
    }
}
