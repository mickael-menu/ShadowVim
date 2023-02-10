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
import Cocoa
import Combine
import CoreGraphics
import Foundation
import Toolkit

/// Xcode-specific overrides for `AppMediator`.
public class XcodeAppMediatorDelegate: AppMediatorDelegate {
    public weak var delegate: AppMediatorDelegate?
    private let logger: Logger?

    private var subscriptions: Set<AnyCancellable> = []

    public init(delegate: AppMediatorDelegate, logger: Logger?) {
        self.delegate = delegate
        self.logger = logger
    }

    private let xcodeDefaults = UserDefaults(suiteName: "com.apple.dt.Xcode")
    private var originalKeyBindingsMode: String?

    public func appMediatorWillStart(_ mediator: AppMediator) {
        if let defaults = xcodeDefaults {
            // Disable Xcode's Vim bindings to avoid conflicts with ShadowVim.
            originalKeyBindingsMode = defaults.keyBindingsMode
            defaults.keyBindingsMode = "Default"
        }

        observeCompletionPopUp(in: mediator.appElement)
    }

    public func appMediatorDidStop(_ mediator: AppMediator) {
        subscriptions = []

        // Restore original Xcode's key bindings mode.
        if let defaults = xcodeDefaults, let mode = originalKeyBindingsMode {
            defaults.keyBindingsMode = mode
        }

        // Reset cursor, otherwise we start with a single character selected
        // when quitting from normal mode.
        do {
            if
                let focusedElement: AXUIElement = try mediator.appElement.get(.focusedUIElement),
                let selection: CFRange = try focusedElement.get(.selectedTextRange)
            {
                try focusedElement.set(.selectedTextRange, value: CFRange(location: selection.location, length: 0))
            }
        } catch {
            delegate?.appMediator(mediator, didFailWithError: error)
        }
    }

    public func appMediator(_ mediator: AppMediator, didFailWithError error: Error) {
        delegate?.appMediator(mediator, didFailWithError: error)
    }

    public func appMediator(_ mediator: AppMediator, shouldPlugInElement element: AXUIElement, name: String) -> Bool {
        return (try? element.get(.description)) == "Source Editor"
            // When showing a read-only editor (e.g. SDK header files), the name
            // will end with "MyProject.xcodeproj/". So we can safely ignore
            // folders.
            && !name.hasSuffix("/")
    }

    public func appMediator(_ mediator: AppMediator, shouldIgnoreEvent event: CGEvent) -> Bool {
        shouldIgnoreEventForCompletionPopUp(event)
    }

    public func appMediator(_ mediator: AppMediator, willHandleEvent event: CGEvent) -> CGEvent? {
        // We override the default Xcode "Stop" keyboard shortcut to quit
        // manually the app. This way `AppDelegate.applicationWillTerminate()`
        // will be called, allowing to revert the Vim bindings setting.
        if event.modifiers == [.command], event.keyCode == .period {
            NSApp.terminate(self)
            return nil
        }

        return event
    }

    // MARK: - Completion pop-up passthrough keys

    /// When Xcode's completion pop-up is visible, we want to let it handle
    /// the following keys instead of forwarding them to Nvim.
    private let completionPopUpPassthrougKeys: [String] = [
        "<Enter>",
        "<Up>",
        "<Down>",
        "\u{0E}", // ⌃N
        "\u{10}", // ⌃P
    ]

    private func shouldIgnoreEventForCompletionPopUp(_ event: CGEvent) -> Bool {
        guard
            isCompletionPopUpVisible,
            event.type == .keyDown
        else {
            return false
        }

        let key = event.nvimKey
        return completionPopUpPassthrougKeys.contains { $0 == key }
    }

    @Published private var isCompletionPopUpVisible = false

    private func observeCompletionPopUp(in element: AXUIElement) {
        func isCompletionPopUp(_ element: AXUIElement) -> Bool {
            element.children().contains { child in
                (try? child.identifier()) == "_XC_COMPLETION_TABLE_"
            }
        }

        element.publisher(for: .created)
            .filter(isCompletionPopUp)
            .ignoreFailure()
            .map { _ in true }
            .assign(to: &$isCompletionPopUpVisible)

        element.publisher(for: .uiElementDestroyed)
            .filter(isCompletionPopUp)
            .ignoreFailure()
            .map { _ in false }
            .assign(to: &$isCompletionPopUpVisible)
    }
}

private extension UserDefaults {
    enum Keys {
        static let keyBindingsMode = "KeyBindingsMode"
    }

    var keyBindingsMode: String? {
        get { string(forKey: Keys.keyBindingsMode) }
        set { set(newValue, forKey: Keys.keyBindingsMode) }
    }
}
