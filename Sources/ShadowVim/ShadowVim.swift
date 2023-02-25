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
import Mediator
import Nvim
import ServiceManagement
import Toolkit

class ShadowVim: ObservableObject {
    @Published var keysPassthrough: Bool = false

    private var mediator: MainMediator?
    private let eventTap = EventTap()

    private let preferences: Preferences
    public let setVerboseLogger: () -> Void
    private let mediatorFactory: () -> MainMediator
    private let keyResolver: CGKeyResolver
    private let logger: Logger?

    init(
        preferences: Preferences,
        keyResolver: CGKeyResolver,
        logger: Logger?,
        setVerboseLogger: @escaping () -> Void,
        mediatorFactory: @escaping () -> MainMediator
    ) {
        self.preferences = preferences
        self.keyResolver = keyResolver
        self.logger = logger
        self.setVerboseLogger = setVerboseLogger
        self.mediatorFactory = mediatorFactory

        eventTap.delegate = self
    }

    func didLaunch() {
        addToLoginItems()
        start()
    }

    private func addToLoginItems() {
        guard !preferences.isAddedToLoginItems else {
            return
        }
        preferences.isAddedToLoginItems = true

        do {
            try SMAppService.mainApp.register()
        } catch {
            logger?.w(error)
        }
    }

    func willTerminate() {
        stop()
    }

    func setKeysPassthrough(_ enabled: Bool) {
        keysPassthrough = enabled
        mediator?.didToggleKeysPassthrough(enabled: enabled)
    }

    func toggleKeysPassthrough() {
        setKeysPassthrough(!keysPassthrough)
    }

    private func start() {
        guard mediator == nil else {
            return
        }

        do {
            try checkRequirements()
            try eventTap.start()

            let mediator = mediatorFactory()
            mediator.delegate = self
            try mediator.start()
            self.mediator = mediator
            hide()

        } catch {
            presentAlert(error: error, style: .critical)
        }
    }

    private func checkRequirements() throws {
        guard AX.isProcessTrusted(prompt: true) else {
            throw UserError.a11yPermissionRequired
        }

        try checkNvimVersion()
    }

    private func checkNvimVersion() throws {
        let expectedVersion: Version = "0.8"
        let currentVersion = try? Nvim.apiInfo(logger: logger).version
        guard let currentVersion = currentVersion, expectedVersion <= currentVersion else {
            throw UserError.nvimVersion(current: currentVersion, expected: expectedVersion)
        }
    }

    private func stop() {
        mediator?.stop()
        mediator = nil

        eventTap.stop()
    }

    enum AlertStyle {
        case warning
        case critical
    }

    /// Error description for the currently displayed alert.
    private var presentedError: String?

    func presentAlert(error: Error, style: AlertStyle) {
        switch style {
        case .warning:
            logger?.w(error)
        case .critical:
            logger?.e(error)
        }

        // Prevent showing multiple alerts for the same error.
        let description = String(reflecting: error)
        guard presentedError != description else {
            return
        }

        presentedError = description

        var alert = Alert(error: error)

        switch style {
        case .warning:
            alert.addButton("Ignore") {}
            alert.addButton("Reset", action: reset)
            alert.addButton("Quit", action: quit)

        case .critical:
            alert.addButton("Reset", action: reset)
            alert.addButton("Quit", action: quit)
            activate()
        }

        alert.showModal()

        presentedError = nil
    }

    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        NSApp.hide(self)
    }

    func quit() {
        NSApp.terminate(self)
    }

    func reset() {
        logger?.i("Reset ShadowVim")
        precondition(Thread.isMainThread)
        stop()
        start()
    }

    func copyDebugInfo() {
        Task.detached {
            let info = await Debug.info()
            NSPasteboard.set(info)
        }
    }

    private func playSound(_ name: String) {
        guard let sound = NSSound(named: name) else {
            return
        }
        sound.stop()
        sound.play()
    }
}

extension ShadowVim: EventTapDelegate {
    func eventTap(_ tap: EventTap, didReceive event: CGEvent) -> CGEvent? {
        guard
            event.type == .keyDown,
            let keyCombo = keyResolver.keyCombo(for: event),
            let event = KeyEvent(event: event, keyCombo: keyCombo)
        else {
            return event
        }

        if keyCombo.modifiers == [.control, .option, .command] {
            switch keyCombo.key {
            case .escape:
                reset()
                return nil
            case .period:
                toggleKeysPassthrough()
                return nil
            case .slash:
                setVerboseLogger()
                return nil
            default:
                break
            }
        }

        if keysPassthrough, keyCombo == KeyCombo(.escape) {
            setKeysPassthrough(false)
        }

        guard
            !keysPassthrough,
            let mediator = mediator,
            mediator.handle(event)
        else {
            return event.event
        }

        return nil
    }
}

extension ShadowVim: MainMediatorDelegate {
    func mainMediator(_ mediator: MainMediator, didFailWithError error: Error) {
        DispatchQueue.main.async {
            let userError = UserError(error: error)
            let critical = userError?.critical ?? false
            let error = userError ?? error

            self.presentAlert(error: error, style: critical ? .critical : .warning)
        }
    }
}

enum UserError: LocalizedError {
    case a11yPermissionRequired
    case nvimNotExecutable
    case nvimNotFound
    case nvimVersion(current: Version?, expected: Version)
    case nvimTerminated(status: Int)

    var errorDescription: String? {
        switch self {
        case .a11yPermissionRequired:
            return "ShadowVim needs the accessibility permission to interact with Xcode"
        case .nvimNotExecutable:
            return "Neovim failed to execute"
        case .nvimNotFound:
            return "Neovim not found"
        case .nvimVersion:
            return "Please upgrade Neovim"
        case let .nvimTerminated(status: status):
            return "Nvim closed with status \(status)"
        }
    }

    var failureReason: String? {
        switch self {
        case .nvimNotExecutable:
            return "Verify the nvim binary file permissions."
        case .nvimNotFound:
            return "Verify it is installed on your computer at the expected location."
        case let .nvimVersion(current: current, expected: expected):
            var message = "ShadowVim requires Neovim \(expected)"
            if let current = current {
                message += ", but \(current) was found"
            }
            message += "."
            return message
        case .nvimTerminated:
            return "Reset ShadowVim?"
        default:
            return nil
        }
    }

    var critical: Bool {
        switch self {
        case .a11yPermissionRequired, .nvimNotExecutable, .nvimNotFound, .nvimVersion, .nvimTerminated:
            return true
        }
    }

    init?(error: Error) {
        switch error {
        case let NvimError.terminated(status: status):
            // man env
            // > The env utility exits 0 on success, and >0 if an error occurs.
            // > An exit status of 126 indicates that utility was found, but
            // > could not be executed.  An exit status of 127 indicates that
            // > utility could not be found.
            switch status {
            case 126:
                self = .nvimNotExecutable
            case 127:
                self = .nvimNotFound
            default:
                self = .nvimTerminated(status: status)
            }
        default:
            return nil
        }
    }
}
