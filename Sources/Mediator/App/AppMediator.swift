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
    func appMediator(_ mediator: AppMediator, shouldIgnoreEvent event: InputEvent) -> Bool

    /// Filters `event` before it is processed by this `AppMediator`.
    ///
    /// Return `nil` if you handled the key combo in the delegate.
    func appMediator(_ mediator: AppMediator, willHandleEvent event: InputEvent) -> InputEvent?
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

    func appMediator(_ mediator: AppMediator, shouldIgnoreEvent event: InputEvent) -> Bool {
        false
    }

    func appMediator(_ mediator: AppMediator, willHandleEvent event: InputEvent) -> InputEvent? {
        event
    }
}

public enum AppMediatorError: LocalizedError {
    case deprecatedCommand(name: String, replacement: String)

    public var errorDescription: String? {
        switch self {
        case let .deprecatedCommand(name: name, _):
            return "'\(name)' is deprecated"
        }
    }

    public var failureReason: String? {
        switch self {
        case let .deprecatedCommand(_, replacement: replacement):
            return replacement
        }
    }
}

public final class AppMediator {
    public typealias Factory = (_ app: NSRunningApplication) throws -> AppMediator

    public weak var delegate: AppMediatorDelegate?

    public let app: NSRunningApplication
    public let appElement: AXUIElement
    private let nvim: Nvim
    private let buffers: NvimBuffers
    private let eventSource: EventSource
    private let logger: Logger?
    private let bufferMediatorFactory: BufferMediator.Factory
    private let enableKeysPassthrough: () -> Void
    private let resetShadowVim: () -> Void

    private var state: AppState = .stopped
    private var bufferMediators: [BufferName: BufferMediator] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    public init(
        app: NSRunningApplication,
        nvim: Nvim,
        buffers: NvimBuffers,
        eventSource: EventSource,
        logger: Logger?,
        bufferMediatorFactory: @escaping BufferMediator.Factory,
        enableKeysPassthrough: @escaping () -> Void,
        resetShadowVim: @escaping () -> Void
    ) {
        precondition(app.isFinishedLaunching)

        self.app = app
        appElement = AXUIElement.app(app)
        self.nvim = nvim
        self.buffers = buffers
        self.eventSource = eventSource
        self.logger = logger
        self.bufferMediatorFactory = bufferMediatorFactory
        self.enableKeysPassthrough = enableKeysPassthrough
        self.resetShadowVim = resetShadowVim

        nvim.delegate = self

        setupUserCommands()

        // nvim.vim?.api.uiAttach(
        //     width: 1000,
        //     height: 100,
        //     options: API.UIOptions(
        //         extCmdline: true,
        //         extHlState: true,
        //         extLineGrid: true,
        //         extMessages: true,
        //         extMultigrid: true,
        //         extPopupMenu: true,
        //         extTabline: true,
        //         extTermColors: true
        //     )
        // )
        // .forwardErrorToDelegate(of: self)
        // .run()

        // nvim.publisher(for: "redraw")
        //     .assertNoFailure()
        //     .sink { params in
        //         for v in params {
        //             guard
        //             let a = v.arrayValue,
        //             let k = a.first?.stringValue,
        //             k.hasPrefix("msg_")
        //             else {
        //                 continue
        //             }
        //             print(a)
        //         }
        //     }
        //     .store(in: &subscriptions)
    }

    private func setupUserCommands() {
        nvim.add(command: "SVSynchronizeUI") { [weak self] _ in
            self?.synchronizeFocusedBuffer(source: .nvim)
            return .nil
        }
        .forwardErrorToDelegate(of: self)
        .run()

        nvim.add(command: "SVSynchronizeNvim") { [weak self] _ in
            self?.synchronizeFocusedBuffer(source: .ui)
            return .nil
        }
        .forwardErrorToDelegate(of: self)
        .run()

        nvim.add(command: "SVPressKeys", args: .one) { [weak self] _ in
            if let self = self {
                let error = AppMediatorError.deprecatedCommand(name: "SVPressKeys", replacement: "Use 'SVPress' in your Neovim configuration instead.")
                self.delegate?.appMediator(self, didFailWithError: error)
            }
            return .bool(false)
        }
        .forwardErrorToDelegate(of: self)
        .run()

        nvim.add(command: "SVPress", args: .one) { [weak self] params in
            guard
                let self,
                params.count == 1,
                case let .string(notation) = params[0]
            else {
                return .bool(false)
            }
            return .bool(self.press(notation: notation))
        }
        .forwardErrorToDelegate(of: self)
        .run()

        nvim.add(command: "SVEnableKeysPassthrough") { [weak self] _ in
            self?.enableKeysPassthrough()
            return .nil
        }
        .forwardErrorToDelegate(of: self)
        .run()

        nvim.add(command: "SVReset") { [weak self] _ in
            self?.resetShadowVim()
            return .nil
        }
        .forwardErrorToDelegate(of: self)
        .run()
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

    private func synchronizeFocusedBuffer(source: BufferState.Host) {
        if case let .focused(buffer) = state {
            buffer.synchronize(source: source)
        }
    }

    // MARK: - Input handling

    public func handle(_ event: InputEvent) -> Bool {
        precondition(app.isActive)

        guard
            !shouldIgnoreEvent(event),
            // Check that we're still the focused app. Useful when the Spotlight
            // modal is opened.
            isAppFocused,
            case let .focused(buffer: buffer) = state,
            buffer.uiElement?.hashValue == (appElement[.focusedUIElement] as AXUIElement?)?.hashValue
        else {
            return false
        }

        guard let event = willHandleEvent(event) else {
            return true
        }

        return handle(event, in: buffer)
    }

    private let cmdZ = KeyCombo(.z, modifiers: .command)
    private let cmdShiftZ = KeyCombo(.z, modifiers: [.command, .shift])
    private let cmdV = KeyCombo(.v, modifiers: [.command])

    private func handle(_ event: InputEvent, in buffer: BufferMediator) -> Bool {
        switch event {
        case let .key(event):
            return handle(event, in: buffer)
        case let .mouse(event):
            return handle(event, in: buffer)
        }
    }

    private func handle(_ event: MouseEvent, in buffer: BufferMediator) -> Bool {
        buffer.didReceiveMouseEvent(event)
        return false
    }

    private func handle(_ event: KeyEvent, in buffer: BufferMediator) -> Bool {
        let buffer = buffer.nvimBuffer

        switch event.keyCombo {
        case cmdZ:
            nvim.vim?.atomic(in: buffer) { vim in
                vim.cmd.undo()
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

        case cmdShiftZ:
            nvim.vim?.atomic(in: buffer) { vim in
                vim.cmd.redo()
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

        case cmdV:
            // We override the system paste behavior to improve performance and
            // nvim's undo history.
            guard let text = NSPasteboard.get() else {
                break
            }
            nvim.vim?.atomic(in: buffer) { vim in
                vim.api.paste(text)
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

        default:
            let mods = event.keyCombo.modifiers

            // Passthrough for ⌘-based keyboard shortcuts.
            guard
                !mods.contains(.command)
            else {
                return false
            }

            nvim.vim?.atomic(in: buffer) { vim in
                // If the user pressed control, we send the key combo as is to
                // be able to remap this keyboard shortcut in Nvim.
                // Otherwise, we send the unicode character for this event.
                // See Documentation/Research/Keyboard.md.
                if
                    !mods.contains(.control),
                    !event.keyCombo.key.isNonPrintableCharacter,
                    let character = event.character
                {
                    return vim.api.input(character)
                } else {
                    return vim.api.input(event.keyCombo)
                }
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()
        }
        return true
    }

    private var isAppFocused: Bool {
        let focusedAppPid = try? AXUIElement.systemWide.focusedApplication()?.pid()
        return app.processIdentifier == focusedAppPid
    }

    /// Simulates a key combo press in the app using an Nvim notation.
    private func press(notation: Notation) -> Bool {
        guard let kc = KeyCombo(nvimNotation: notation) else {
            return false
        }

        if !kc.key.isMouseButton {
            return eventSource.press(kc)
        } else {
            click(kc)
            return true
        }
    }

    private func click(_ kc: KeyCombo) {
        DispatchQueue.main.async { [self] in
            do {
                guard
                    case let .focused(buffer: buffer) = state,
                    let cursorLocation = try buffer.uiCursorLocation()
                else {
                    return
                }
                eventSource.click(kc, at: cursorLocation)

            } catch {
                delegate?.appMediator(self, didFailWithError: error)
            }
        }
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

    private func editBuffer(for element: AXUIElement, name: BufferName) -> Async<BufferMediator, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return buffers.edit(name: name, contents: element[.value] ?? "", with: vim)
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

    /// This publisher is used to observe the Neovim selection and mode
    /// changes.
    lazy var nvimCursorPublisher: AnyPublisher<(BufferHandle, Cursor), NvimError> =
        nvim.autoCmdPublisher(
            for: "ModeChanged", "CursorMoved", "CursorMovedI",
            args: "bufnr()", "mode()", "getcharpos('.')", "getcharpos('v')",
            unpack: { params -> (BufferHandle, Cursor)? in
                guard
                    params.count == 4,
                    let buffer: BufferHandle = params[0].intValue,
                    let mode = params[1].stringValue,
                    let position = BuiltinFunctions.GetposResult(params[2]),
                    let visual = BuiltinFunctions.GetposResult(params[3])
                else {
                    return nil
                }

                let cursor = Cursor(
                    mode: Mode(rawValue: mode) ?? .normal,
                    position: position.position,
                    visual: visual.position
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

    private func shouldIgnoreEvent(_ event: InputEvent) -> Bool {
        guard let delegate = delegate else {
            return false
        }
        return delegate.appMediator(self, shouldIgnoreEvent: event)
    }

    private func willHandleEvent(_ event: InputEvent) -> InputEvent? {
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
        logger?.w("Received unknown RPC request", ["method": method, "data": data])
        return nil
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
