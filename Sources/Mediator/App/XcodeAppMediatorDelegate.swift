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
import Nvim
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

    public func appMediatorWillStart(_ mediator: AppMediator) {
        if let defaults = xcodeDefaults {
            // Disable Xcode's Vim bindings to avoid conflicts with ShadowVim.
            defaults.keyBindingsMode = "Default"
        }

        observeCompletionPopUp(in: mediator.appElement)
    }

    public func appMediatorDidStop(_ mediator: AppMediator) {
        subscriptions = []

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
        (try? element.get(.description)) == "Source Editor"
            // When showing a read-only editor (e.g. SDK header files), the name
            // will end with "MyProject.xcodeproj/". So we can safely ignore
            // folders.
            && !name.hasSuffix("/")
    }

    public func appMediator(_ mediator: AppMediator, shouldIgnoreKeyEvent event: KeyEvent) -> Bool {
        shouldIgnoreKeyEventForCompletionPopUp(event)
    }

    // MARK: - Completion pop-up passthrough keys

    /// When Xcode's completion pop-up is visible, we want to let it handle
    /// the following key combos instead of forwarding them to Nvim.
    private let completionPopUpPassthrougKeyCombos: [KeyCombo] = [
        KeyCombo(.escape),
        KeyCombo(.return),
        KeyCombo(.upArrow),
        KeyCombo(.downArrow),
        KeyCombo(.n, modifiers: .control),
        KeyCombo(.p, modifiers: .control),
    ]

    private func shouldIgnoreKeyEventForCompletionPopUp(_ event: KeyEvent) -> Bool {
        guard isCompletionPopUpVisible else {
            return false
        }

        return completionPopUpPassthrougKeyCombos.contains(event.keyCombo)
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
