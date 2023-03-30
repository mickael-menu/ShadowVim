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
        element.bufferName()
    }

    func appMediator(_ mediator: AppMediator, shouldIgnoreEvent event: InputEvent) -> Bool {
        false
    }

    func appMediator(_ mediator: AppMediator, willHandleEvent event: InputEvent) -> InputEvent? {
        event
    }
}

private extension AXUIElement {
    func bufferName() -> String? {
        document()?
            .removingPrefix("file://")
            .removingPercentEncoding
    }
}

public final class AppMediator {
    public typealias Factory = (_ app: NSRunningApplication) -> AppMediator

    public weak var delegate: AppMediatorDelegate?

    public let app: NSRunningApplication
    public let appElement: AXUIElement
    private let nvimController: NvimController
    private let eventSource: EventSource
    private let logger: Logger?
    private let bufferMediatorFactory: BufferMediator.Factory

    private var state: AppState = .stopped
    private var bufferMediators: [BufferName: BufferMediator] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    init(
        app: NSRunningApplication,
        nvimController: NvimController,
        eventSource: EventSource,
        logger: Logger?,
        bufferMediatorFactory: @escaping BufferMediator.Factory
    ) {
        precondition(app.isFinishedLaunching)

        self.app = app
        appElement = AXUIElement.app(app)
        self.nvimController = nvimController
        self.eventSource = eventSource
        self.logger = logger
        self.bufferMediatorFactory = bufferMediatorFactory

        nvimController.delegate = self
    }

    deinit {
        stop()
    }

    @MainActor
    public func start() async {
        do {
            on(.willStart)
            delegate?.appMediatorWillStart(self)

            try await nvimController.start()
            try eventSource.start()
            setupCursorSync()
            setupFocusSync()

            on(.didStart)

        } catch {
            delegate?.appMediator(self, didFailWithError: error)
        }
    }

    public func stop() {
        nvimController.stop()
        subscriptions.removeAll()
        delegate?.appMediatorDidStop(self)
    }

    public func didToggleKeysPassthrough(enabled: Bool) {
        for (_, buffer) in bufferMediators {
            buffer.didToggleKeysPassthrough(enabled: enabled)
        }
    }

    private func on(_ event: AppState.Event) {
        precondition(Thread.isMainThread)
        state.on(event, logger: logger)

        focusedNvimBuffer.value = {
            if case let .focused(buffer) = state {
                return buffer.nvimBuffer
            } else {
                return nil
            }
        }()
    }

    private func synchronizeFocusedBuffer(source: BufferHost) {
        if case let .focused(buffer) = state {
            buffer.synchronize(source: source)
        }
    }

    // MARK: - Focused buffer and cursor

    private let focusedNvimBuffer = CurrentValueSubject<NvimBuffer?, Never>(nil)
    public lazy var focusedNvimBufferPublisher: AnyPublisher<NvimBuffer?, Never> =
        focusedNvimBuffer.eraseToAnyPublisher()

    public lazy var nvimSelectedRangesPublisher: AnyPublisher<[NSRange], Never> =
        nvimController.cursorPublisher()
            .map { [weak self] _, cursor in
                guard let lines = self?.focusedNvimBuffer.value?.lines else {
                    return []
                }

                return [UISelection](
                    mode: cursor.mode,
                    cursor: cursor.position,
                    visual: cursor.visual
                ).compactMap { $0.range(in: lines) }
            }
            .ignoreFailure()

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

        return buffer.didReceiveEvent(event)
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

    // MARK: - Cursor synchronization

    private func setupCursorSync() {
        nvimController.cursorPublisher()
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.appMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] buffer, cursor in
                    bufferMediator(for: buffer)?.nvimCursorDidChange(cursor)
                }
            )
            .store(in: &subscriptions)
    }

    // MARK: - Focus synchronization

    private func setupFocusSync() {
        focusedUIElementDidChange()

        appElement.publisher(for: .focusedUIElementChanged)
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.appMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] _ in
                    // We ignore the event element because the focused element
                    // might have changed by the time we execute the following.
                    focusedUIElementDidChange()
                }
            )
            .store(in: &subscriptions)
    }

    private func focusedUIElementDidChange() {
        guard
            let element = appElement.focusedUIElement(),
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
        nvimController.editBuffer(
            name: name,
            contents: { element[.value] ?? "" }
        )
        .map(on: .main) { [self] buffer in
            makeMediator(for: element, name: name, buffer: buffer)
        }
    }

    private func makeMediator(for element: AXUIElement, name: BufferName, buffer: NvimBuffer) -> BufferMediator {
        let mediator = bufferMediators.getOrPut(name) {
            bufferMediatorFactory((
                nvimBuffer: buffer,
                uiElement: element
            ))
        }
        mediator.delegate = self
        mediator.didFocus(element: element)
        return mediator
    }

    /// Returns the current `BufferMediator` associated with the given Nvim
    /// `buffer` handle.
    private func bufferMediator(for buffer: BufferHandle) -> BufferMediator? {
        for (_, mediator) in bufferMediators {
            if mediator.nvimHandle == buffer {
                return mediator
            }
        }
        return nil
    }

    // MARK: - Delegate

    private func shouldPlugInElement(_ element: AXUIElement, name: String) -> Bool {
        guard let delegate = delegate else {
            return true
        }
        return delegate.appMediator(self, shouldPlugInElement: element, name: name)
    }

    private func nameForElement(_ element: AXUIElement) -> String? {
        guard let delegate = delegate else {
            return element.bufferName()
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

extension AppMediator: NvimControllerDelegate {
    func nvimController(_ nvimController: NvimController, didReceiveUIEvent event: UIEvent) {
        switch event {
        case .flush:
            for (_, buffer) in bufferMediators {
                buffer.nvimDidFlush()
            }
        default:
            print(event)
        }
    }

    func nvimController(_ nvimController: NvimController, didFailWithError error: Error) {
        delegate?.appMediator(self, didFailWithError: error)
    }

    func nvimController(_ nvimController: NvimController, synchronizeFocusedBufferUsing source: BufferHost) {
        synchronizeFocusedBuffer(source: source)
    }

    func nvimController(_ nvimController: NvimController, press notation: Notation) -> Bool {
        press(notation: notation)
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
