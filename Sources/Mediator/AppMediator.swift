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

public protocol AppMediatorDelegate: AnyObject {
    /// Called when the `AppMediator` is being started.
    func appMediatorWillStart(_ mediator: AppMediator)

    /// Called when the `AppMediator` was stopped.
    func appMediatorDidStop(_ mediator: AppMediator)

    /// Called when an error occurred while mediating the app.
    func appMediator(_ mediator: AppMediator, didFailWithError error: Error)

    /// Returns whether an Nvim buffer should be associated with this
    /// accessibility `element`.
    func appMediator(_ mediator: AppMediator, shouldPlugInElement element: AXUIElement) -> Bool

    /// Returns the Nvim buffer name for the given accessibility `element`.
    func appMediator(_ mediator: AppMediator, nameForElement element: AXUIElement) -> String?

    /// Filters `event` before it is processed by this `AppMediator`.
    ///
    /// Return `nil` if you handled the event in the delegate.
    func appMediator(_ mediator: AppMediator, willHandleEvent event: CGEvent) -> CGEvent?
}

public extension AppMediatorDelegate {
    func appMediatorWillStart(_ mediator: AppMediator) {}
    func appMediatorDidStop(_ mediator: AppMediator) {}

    func appMediator(_ mediator: AppMediator, shouldPlugInElement element: AXUIElement) -> Bool {
        true
    }

    func appMediator(_ mediator: AppMediator, nameForElement element: AXUIElement) -> String? {
        element.document()
    }

    func appMediator(_ mediator: AppMediator, willHandleEvent event: CGEvent) -> CGEvent? {
        event
    }
}

public final class AppMediator {
    public weak var delegate: AppMediatorDelegate?

    public let app: NSRunningApplication
    public let appElement: AXUIElement
    private var isStarted = false
    private let nvim: Nvim
    private let buffers: Buffers
    private var bufferMediators: [BufferName: BufferMediator] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    private var focusedBufferMediator: BufferMediator? {
        didSet {
            syncCursor(with: focusedBufferMediator)
        }
    }

    init(app: NSRunningApplication, delegate: AppMediatorDelegate?) throws {
        self.app = app
        self.delegate = delegate
        appElement = AXUIElement.app(app)
        nvim = try Nvim.start()
        buffers = Buffers(events: nvim.events)
        nvim.delegate = self

        setupFocusSync()
        setupCursorSync()

//        nvim.api.uiAttach(
//            width: 1000,
//            height: 100,
//            options: API.UIOptions(
//                extCmdline: true,
//                extHlState: true,
//                extLineGrid: true,
//                extMessages: true,
//                extMultigrid: true,
//                extPopupMenu: true,
//                extTabline: true,
//                extTermColors: true
//            )
//        )
//        .assertNoFailure()
//        .run()
//
//        nvim.events.publisher(for: "redraw")
//            .assertNoFailure()
//            .sink { params in
//                for v in params {
//                    guard
//                        let a = v.arrayValue,
//                        let k = a.first?.stringValue,
//                        k.hasPrefix("msg_")
//                    else {
//                        continue
//                    }
//                    print(a)
//                }
//            }
//            .store(in: &subscriptions)
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isStarted else {
            return
        }
        delegate?.appMediatorWillStart(self)
        isStarted = true
    }

    public func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        nvim.stop()
        subscriptions.removeAll()
        delegate?.appMediatorDidStop(self)
    }

    // MARK: - Input handling

    public func handle(_ event: CGEvent) -> CGEvent? {
        precondition(app.isActive)

        guard
            // Check that we're still the focused app. Useful when the Spotlight
            // modal is opened.
            isAppFocused,
            let focusedBufferMediator = focusedBufferMediator,
            focusedBufferMediator.element.hashValue == (appElement[.focusedUIElement] as AXUIElement?)?.hashValue
        else {
            return event
        }

        guard let event = willHandleEvent(event) else {
            return nil
        }

        switch event.type {
        case .keyDown:
            // Passthrough for ⌘-based keyboard shortcuts.
            guard !event.flags.contains(.maskCommand) else {
                break
            }

            // FIXME: See `nvim.paste` "Faster than nvim_input()."

            nvim.api.transaction { [self] api in
                buffers.edit(buffer: focusedBufferMediator.buffer, with: api)
                    .flatMap { api.input(event.nvimKey) }
            }
            .discardResult()
            .get(onFailure: { [self] in
                delegate?.appMediator(self, didFailWithError: $0)
            })

            return nil

        default:
            break
        }

        return event
    }

    private var isAppFocused: Bool {
        let focusedAppPid = try? AXUIElement.systemWide.focusedApplication()?.pid()
        return app.processIdentifier == focusedAppPid
    }

    // MARK: - Focus synchronization

    private func setupFocusSync() {
        if let focusedElement = appElement[.focusedUIElement] as AXUIElement? {
            focusedUIElementDidChange(focusedElement)
        }

        appElement.publisher(for: .focusedUIElementChanged)
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.appMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] element in
                    focusedUIElementDidChange(element)
                }
            )
            .store(in: &subscriptions)
    }

    private func focusedUIElementDidChange(_ element: AXUIElement) {
        guard
            element.isValid,
            (try? element.get(.role)) == AXRole.textArea,
            shouldPlugInElement(element),
            let name = nameForElement(element)
        else {
            focusedBufferMediator = nil
            return
        }

        buffers.edit(name: name, contents: element[.value] ?? "", with: nvim.api)
            .map { [self] handle in
                let buffer = bufferMediators.getOrPut(name) {
                    BufferMediator(nvim: nvim, buffer: handle, element: element, name: name, buffers: buffers)
                }
                buffer.element = element
                focusedBufferMediator = buffer

                return buffer
            }
            .tryMap { [self] buffer in
                guard let cursor = try cursor(of: buffer.element) else {
                    return
                }
                buffer.setCursor(position: cursor)
            }
            .discardResult()
            .get(onFailure: { [self] error in
                delegate?.appMediator(self, didFailWithError: error)
            })
    }

    // MARK: - Cursor synchronization

    private func setupCursorSync() {
        nvim.events.autoCmdPublisher(
            for: "ModeChanged", "CursorMoved", "CursorMovedI",
            args: "mode()", "getcursorcharpos()",
            unpack: { params -> (mode: Mode, cursor: CursorPosition)? in
                guard
                    params.count == 2,
                    let mode = params[0].stringValue,
                    let cursorParams = params[1].arrayValue,
                    cursorParams.count == 5,
                    let line = cursorParams[1].intValue,
                    let col = cursorParams[2].intValue
                else {
                    return nil
                }

                return (
                    mode: Mode(rawValue: mode) ?? .normal,
                    cursor: (line: line - 1, column: col - 1)
                )
            }
        )
        .receive(on: DispatchQueue.main)
        .sink(
            onFailure: { [unowned self] error in
                delegate?.appMediator(self, didFailWithError: error)
            },
            receiveValue: { [unowned self] mode, position in
                focusedBufferMediator?.setCursor(position: position, mode: mode)
            }
        )
        .store(in: &subscriptions)
    }

    private var syncCursorSubscription: AnyCancellable?

    private func syncCursor(with buffer: BufferMediator?) {
        guard let buffer = buffer else {
            syncCursorSubscription = nil
            return
        }

        syncCursorSubscription = buffer.element.publisher(for: .selectedTextChanged)
            .tryCompactMap { [unowned self] in
                try cursor(of: $0)
            }
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.appMediator(self, didFailWithError: error)
                },
                receiveValue: { cursor in
                    buffer.setCursor(position: cursor)
                }
            )
    }

    private func cursor(of element: AXUIElement) throws -> CursorPosition? {
        guard
            let selection: CFRange = try element.get(.selectedTextRange),
            let line: Int = try element.get(.lineForIndex, with: selection.location),
            let lineRange: CFRange = try element.get(.rangeForLine, with: line)
        else {
            return nil
        }
        return CursorPosition(line: line, column: selection.location - lineRange.location)
    }

    // MARK: - Delegate

    private func shouldPlugInElement(_ element: AXUIElement) -> Bool {
        guard let delegate = delegate else {
            return true
        }
        return delegate.appMediator(self, shouldPlugInElement: element)
    }

    private func nameForElement(_ element: AXUIElement) -> String? {
        guard let delegate = delegate else {
            return element.document()
        }
        return delegate.appMediator(self, nameForElement: element)
    }

    private func willHandleEvent(_ event: CGEvent) -> CGEvent? {
        guard let delegate = delegate else {
            return event
        }
        return delegate.appMediator(self, willHandleEvent: event)
    }
}

extension AppMediator: NvimDelegate {
    public func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>? {
        switch method {
        case "SVRefresh":
            guard let mediator = focusedBufferMediator else {
                return .success(.bool(false))
            }
            print("Refresh")
            nvim.api.transaction { api in
                self.buffers.edit(buffer: mediator.buffer, with: api)
                    .flatMap {
                        api.bufGetLines(buffer: mediator.buffer, start: 0, end: -1)
                    }
                    .map { lines in
                        try? mediator.element.set(.value, value: lines.joined(separator: "\n"))
                    }
            }
            .assertNoFailure()
            .run()
            return .success(.bool(true))
        default:
            return nil
        }
    }

    public func nvim(_ nvim: Nvim, didFailWithError error: NvimError) {
        delegate?.appMediator(self, didFailWithError: error)
    }
}
