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
        updateXcodeSettings()
        observeCompletionPopUp(in: mediator.appElement)
    }

    /// This will adjust existing Xcode settings to prevent conflicts with ShadowVim.
    /// For example, auto-indenting and pairing.
    private func updateXcodeSettings() {
        guard let defaults = xcodeDefaults else {
            logger?.e("Cannot modify Xcode's defaults")
            return
        }

        let expectedSettings = XcodeSettings(
            keyBindingsMode: "Default",
            textAutoCloseBlockComment: false,
            textAutoInsertCloseBrace: false,
            textEditorTrimTrailingWhitespace: false,
            textEnableTypeOverCompletions: false,
            textIndentCaseInC: false,
            textUsesSyntaxAwareIndenting: false
        )

        let currentSettings = XcodeSettings(defaults: defaults)
        if expectedSettings != currentSettings {
            expectedSettings.apply(to: defaults)

            let commands = currentSettings.commands()
            var alert = Alert(style: .info, title: "Updated Xcode settings")
            alert.message = """
                Your Xcode settings were changed to prevent conflicts with ShadowVim.
                If you want to restore them after closing ShadowVim, run the following commands in the terminal.
                """
            alert.accessory = .code(commands, width: 620)
            alert.addButton("Copy and Close") {
                NSPasteboard.set(commands)
            }
            alert.addButton("Close") {}
            alert.showModal()
        }
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

private struct XcodeSettings: Equatable {
    var keyBindingsMode: String?
    var textAutoCloseBlockComment: Bool?
    var textAutoInsertCloseBrace: Bool?
    var textEditorTrimTrailingWhitespace: Bool?
    var textEnableTypeOverCompletions: Bool?
    var textIndentCaseInC: Bool?
    var textUsesSyntaxAwareIndenting: Bool?

    init(
        keyBindingsMode: String? = nil,
        textAutoCloseBlockComment: Bool? = nil,
        textAutoInsertCloseBrace: Bool? = nil,
        textEditorTrimTrailingWhitespace: Bool? = nil,
        textEnableTypeOverCompletions: Bool? = nil,
        textIndentCaseInC: Bool? = nil,
        textUsesSyntaxAwareIndenting: Bool? = nil
    ) {
        self.keyBindingsMode = keyBindingsMode
        self.textAutoCloseBlockComment = textAutoCloseBlockComment
        self.textAutoInsertCloseBrace = textAutoInsertCloseBrace
        self.textEditorTrimTrailingWhitespace = textEditorTrimTrailingWhitespace
        self.textEnableTypeOverCompletions = textEnableTypeOverCompletions
        self.textIndentCaseInC = textIndentCaseInC
        self.textUsesSyntaxAwareIndenting = textUsesSyntaxAwareIndenting
    }

    init(defaults: UserDefaults) {
        self.init(
            keyBindingsMode: defaults.keyBindingsMode,
            textAutoCloseBlockComment: defaults.textAutoCloseBlockComment,
            textAutoInsertCloseBrace: defaults.textAutoInsertCloseBrace,
            textEditorTrimTrailingWhitespace: defaults.textEditorTrimTrailingWhitespace,
            textEnableTypeOverCompletions: defaults.textEnableTypeOverCompletions,
            textIndentCaseInC: defaults.textIndentCaseInC,
            textUsesSyntaxAwareIndenting: defaults.textUsesSyntaxAwareIndenting
        )
    }

    func apply(to userDefaults: UserDefaults) {
        userDefaults.keyBindingsMode = keyBindingsMode
        userDefaults.textAutoCloseBlockComment = textAutoCloseBlockComment
        userDefaults.textAutoInsertCloseBrace = textAutoInsertCloseBrace
        userDefaults.textEditorTrimTrailingWhitespace = textEditorTrimTrailingWhitespace
        userDefaults.textEnableTypeOverCompletions = textEnableTypeOverCompletions
        userDefaults.textIndentCaseInC = textIndentCaseInC
        userDefaults.textUsesSyntaxAwareIndenting = textUsesSyntaxAwareIndenting
    }

    /// Returns the commands to run in a shell to apply the settings.
    func commands() -> String {
        var commands: [String] = []

        func cmd(key: String, value: Any?) {
            switch value {
            case nil:
                commands.append("defaults delete -app Xcode \(key)")
            case let string as String:
                commands.append("defaults write -app Xcode \(key) -string '\(string)'")
            case let bool as Bool:
                commands.append("defaults write -app Xcode \(key) -bool \(bool)")
            default:
                preconditionFailure("Invalid Xcode settings value type \(String(describing: value))")
            }
        }

        cmd(key: UserDefaults.Keys.keyBindingsMode, value: keyBindingsMode)
        cmd(key: UserDefaults.Keys.textAutoCloseBlockComment, value: textAutoCloseBlockComment)
        cmd(key: UserDefaults.Keys.textAutoInsertCloseBrace, value: textAutoInsertCloseBrace)
        cmd(key: UserDefaults.Keys.textEditorTrimTrailingWhitespace, value: textEditorTrimTrailingWhitespace)
        cmd(key: UserDefaults.Keys.textEnableTypeOverCompletions, value: textEnableTypeOverCompletions)
        cmd(key: UserDefaults.Keys.textIndentCaseInC, value: textIndentCaseInC)
        cmd(key: UserDefaults.Keys.textUsesSyntaxAwareIndenting, value: textUsesSyntaxAwareIndenting)

        return commands.joined(separator: "\n")
    }
}

private extension UserDefaults {

    enum Keys {
        static let keyBindingsMode = "KeyBindingsMode"
        static let textAutoCloseBlockComment = "DVTTextAutoCloseBlockComment"
        static let textAutoInsertCloseBrace = "DVTTextAutoInsertCloseBrace"
        static let textEditorTrimTrailingWhitespace = "DVTTextEditorTrimTrailingWhitespace"
        static let textEnableTypeOverCompletions = "DVTTextEnableTypeOverCompletions"
        static let textIndentCaseInC = "DVTTextIndentCaseInC"
        static let textUsesSyntaxAwareIndenting = "DVTTextUsesSyntaxAwareIndenting"
    }

    var keyBindingsMode: String? {
        get { string(forKey: Keys.keyBindingsMode) }
        set { set(newValue, forKey: Keys.keyBindingsMode) }
    }

    var textAutoCloseBlockComment: Bool? {
        get { optBool(forKey: Keys.textAutoCloseBlockComment) }
        set { set(newValue, forKey: Keys.textAutoCloseBlockComment) }
    }

    var textAutoInsertCloseBrace: Bool? {
        get { optBool(forKey: Keys.textAutoInsertCloseBrace) }
        set { set(newValue, forKey: Keys.textAutoInsertCloseBrace) }
    }

    var textEditorTrimTrailingWhitespace: Bool? {
        get { optBool(forKey: Keys.textEditorTrimTrailingWhitespace) }
        set { set(newValue, forKey: Keys.textEditorTrimTrailingWhitespace) }
    }

    var textEnableTypeOverCompletions: Bool? {
        get { optBool(forKey: Keys.textEnableTypeOverCompletions) }
        set { set(newValue, forKey: Keys.textEnableTypeOverCompletions) }
    }

    var textIndentCaseInC: Bool? {
        get { optBool(forKey: Keys.textIndentCaseInC) }
        set { set(newValue, forKey: Keys.textIndentCaseInC) }
    }

    var textUsesSyntaxAwareIndenting: Bool? {
        get { optBool(forKey: Keys.textUsesSyntaxAwareIndenting) }
        set { set(newValue, forKey: Keys.textUsesSyntaxAwareIndenting) }
    }

    private func optBool(forKey key: String) -> Bool? {
        guard object(forKey: key) != nil else {
            return nil
        }
        return bool(forKey: key)
    }
}
