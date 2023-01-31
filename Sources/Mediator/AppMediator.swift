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

    /// Indicates whether the given `event` should be ignored by the mediator.
    func appMediator(_ mediator: AppMediator, shouldIgnoreEvent event: CGEvent) -> Bool

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

    func appMediator(_ mediator: AppMediator, shouldIgnoreEvent event: CGEvent) -> Bool {
        false
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
    private var focusedBufferMediator: BufferMediator?
    private var subscriptions: Set<AnyCancellable> = []

    init(app: NSRunningApplication, delegate: AppMediatorDelegate?) throws {
        self.app = app
        self.delegate = delegate
        appElement = AXUIElement.app(app)
        nvim = try Nvim.start()
        buffers = Buffers(events: nvim.events)
        nvim.delegate = self

        setupFocusSync()

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
            !shouldIgnoreEvent(event),
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

        editBuffer(for: element, name: name)
            .forwardErrorToDelegate(of: self)
            .get { [self] bufferMediator in
                focusedBufferMediator = bufferMediator
                bufferMediator.didFocus()
            }
    }

    private func editBuffer(for element: AXUIElement, name: BufferName) -> Async<BufferMediator, APIError> {
        buffers.edit(name: name, contents: element[.value] ?? "", with: nvim.api)
            .map { [self] handle in
                let buffer = bufferMediators.getOrPut(name) {
                    BufferMediator(
                        nvim: nvim,
                        buffer: handle,
                        element: element,
                        name: name,
                        nvimLinesPublisher: buffers.linesPublisher(for: handle),
                        nvimCursorPublisher: nvimCursorPublisher
                            .compactMap { buf, cur in
                                guard buf == handle else {
                                    return nil
                                }
                                return cur
                            }
                            .eraseToAnyPublisher(),
                        delegate: self
                    )
                }
                buffer.element = element
                return buffer
            }
    }

    /// This publisher is used to observe the Neovim cursor position and mode
    /// changes.
    lazy var nvimCursorPublisher: AnyPublisher<(BufferHandle, Cursor), APIError> =
        nvim.events.autoCmdPublisher(
            for: "ModeChanged", "CursorMoved", "CursorMovedI",
            args: "bufnr()", "mode()", "getcursorcharpos()",
            unpack: { params -> (BufferHandle, Cursor)? in
                guard
                    params.count == 3,
                    let buffer: BufferHandle = params[0].intValue,
                    let mode = params[1].stringValue,
                    let cursorParams = params[2].arrayValue,
                    cursorParams.count == 5,
                    let line = cursorParams[1].intValue,
                    let col = cursorParams[2].intValue
                else {
                    return nil
                }

                let cursor = Cursor(
                    position: (line: line - 1, column: col - 1),
                    mode: Mode(rawValue: mode) ?? .normal
                )
                return (buffer, cursor)
            }
        )

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

    private func shouldIgnoreEvent(_ event: CGEvent) -> Bool {
        guard let delegate = delegate else {
            return false
        }
        return delegate.appMediator(self, shouldIgnoreEvent: event)
    }

    private func willHandleEvent(_ event: CGEvent) -> CGEvent? {
        guard let delegate = delegate else {
            return event
        }
        return delegate.appMediator(self, willHandleEvent: event)
    }
}

extension AppMediator: BufferMediatorDelegate {
    func bufferMediator(_ mediator: BufferMediator, didFailWithError error: Error) {
        delegate?.appMediator(self, didFailWithError: error)
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

private extension Async {
    func forwardErrorToDelegate(of appMediator: AppMediator) -> Async<Success, Never> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { error, _ in
                appMediator.delegate?.appMediator(appMediator, didFailWithError: error)
            }
        )
    }
}
