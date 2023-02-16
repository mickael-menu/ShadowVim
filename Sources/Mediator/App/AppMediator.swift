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
    func appMediator(_ mediator: AppMediator, shouldPlugInElement element: AXUIElement, name: String) -> Bool

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

    func appMediator(_ mediator: AppMediator, shouldPlugInElement element: AXUIElement, name: String) -> Bool {
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
    public typealias Factory = (_ app: NSRunningApplication) throws -> AppMediator

    public weak var delegate: AppMediatorDelegate?

    public let app: NSRunningApplication
    public let appElement: AXUIElement
    private let nvim: Nvim
    private let buffers: NvimBuffers
    private let logger: Logger?
    private let bufferMediatorFactory: BufferMediator.Factory

    private var state: AppState = .stopped
    private var bufferMediators: [BufferName: BufferMediator] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    public init(
        app: NSRunningApplication,
        nvim: Nvim,
        buffers: NvimBuffers,
        logger: Logger?,
        bufferMediatorFactory: @escaping BufferMediator.Factory
    ) throws {
        self.app = app
        appElement = AXUIElement.app(app)
        self.nvim = nvim
        self.buffers = buffers
        self.logger = logger
        self.bufferMediatorFactory = bufferMediatorFactory

        nvim.delegate = self

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
        on(.start)
    }

    public func stop() {
        on(.stop)
    }

    public func didToggleKeysPassthrough(enabled: Bool) {
        for (_, buffer) in bufferMediators {
            buffer.didToggleKeysPassthrough(enabled: enabled)
        }
    }

    private func on(_ event: AppState.Event) {
        precondition(Thread.isMainThread)
        for action in state.on(event, logger: logger) {
            perform(action)
        }
    }

    private func perform(_ action: AppState.Action) {
        switch action {
        case .start:
            setupFocusSync()
            delegate?.appMediatorWillStart(self)
        case .stop:
            performStop()
        }
    }

    private func performStop() {
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
            case let .focused(buffer: buffer) = state,
            buffer.uiElement?.hashValue == (appElement[.focusedUIElement] as AXUIElement?)?.hashValue
        else {
            return event
        }

        guard let event = willHandleEvent(event) else {
            return nil
        }

        switch event.type {
        case .keyDown:
            return handleKeyDown(event, in: buffer.nvimBuffer)
        default:
            return event
        }
    }

    private func handleKeyDown(_ event: CGEvent, in buffer: NvimBuffer) -> CGEvent? {
        let modifiers = event.modifiers

        switch (modifiers, event.character) {
        case ([.command], "z"):
            nvim.api.transaction(in: buffer) { api in
                api.command("undo")
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

            return nil

        case ([.command, .shift], "z"):
            nvim.api.transaction(in: buffer) { api in
                api.command("redo")
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

            return nil

        case ([.control], "\u{0F}"), ([.control], "\t"):
            // Passthrough for the navigation shortcuts.
            // They need to be set in the Xcode config.
            return event

        default:
            // Passthrough for ⌘ or ⌥-based keyboard shortcuts.
            guard
                !event.flags.contains(.maskCommand),
                !event.flags.contains(.maskAlternate)
            else {
                return event
            }

            // FIXME: See `nvim.paste` "Faster than nvim_input()."

            nvim.api.transaction(in: buffer) { api in
                api.input(event.nvimKey)
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

            return nil
        }
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
            let name = nameForElement(element),
            shouldPlugInElement(element, name: name)
        else {
            on(.unfocus)
            return
        }

        editBuffer(for: element, name: name)
            .forwardErrorToDelegate(of: self)
            .get { [self] mediator in
                on(.focus(buffer: mediator))
            }
    }

    private func editBuffer(for element: AXUIElement, name: BufferName) -> Async<BufferMediator, APIError> {
        buffers.edit(name: name, contents: element[.value] ?? "", with: nvim.api)
            .map(on: .main) { [self] buffer in
                let mediator = bufferMediators.getOrPut(name) {
                    bufferMediatorFactory((
                        nvim: nvim,
                        nvimBuffer: buffer,
                        uiElement: element,
                        nvimCursorPublisher: nvimCursorPublisher
                            .compactMap { buf, cur in
                                guard buf == buffer.handle else {
                                    return nil
                                }
                                return cur
                            }
                            .eraseToAnyPublisher()
                    ))
                }
                mediator.delegate = self
                mediator.didFocus(element: element)
                return mediator
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
                    position: BufferPosition(line: line - 1, column: col - 1),
                    mode: Mode(rawValue: mode) ?? .normal
                )
                return (buffer, cursor)
            }
        )

    // MARK: - Delegate

    private func shouldPlugInElement(_ element: AXUIElement, name: String) -> Bool {
        guard let delegate = delegate else {
            return true
        }
        return delegate.appMediator(self, shouldPlugInElement: element, name: name)
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
            if case let .focused(buffer) = state {
                buffer.didRequestRefresh()
            }
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
