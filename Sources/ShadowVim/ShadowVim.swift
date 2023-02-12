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
import Toolkit

class ShadowVim: ObservableObject {
    @Published var keysPassthrough: Bool = false

    private var mediator: MainMediator?
    private let eventTap = EventTap()

    private let setVerboseLogger: () -> Void
    private let mediatorFactory: () -> MainMediator
    private let logger: Logger?

    init(
        logger: Logger?,
        setVerboseLogger: @escaping () -> Void,
        mediatorFactory: @escaping () -> MainMediator
    ) {
        self.logger = logger
        self.setVerboseLogger = setVerboseLogger
        self.mediatorFactory = mediatorFactory

        eventTap.delegate = self
    }

    func didLaunch() {
        start()
    }

    func willTerminate() {
        stop()
    }

    private func start() {
        guard mediator == nil else {
            return
        }

        do {
            guard AX.isProcessTrusted(prompt: true) else {
                throw UserError.a11yPermissionRequired
            }

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

        let alert = NSAlert()
        alert.alertStyle = .warning

        if let error = error as? LocalizedError {
            alert.messageText = error.errorDescription ?? ""
            alert.informativeText = error.failureReason ?? ""

        } else {
            switch style {
            case .warning:
                alert.messageText = "An error occurred"
            case .critical:
                alert.messageText = "A critical error occurred"
            }

            let rawCode = NSTextView(frame: .init(origin: .zero, size: .init(width: 350, height: 0)))
            rawCode.string = String(reflecting: error)
            rawCode.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            rawCode.sizeToFit()
            rawCode.isEditable = false
            rawCode.isSelectable = true
            alert.accessoryView = rawCode
        }

        switch style {
        case .warning:
            alert.addButton(withTitle: "Ignore")
            alert.addButton(withTitle: "Reset")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                reset()
            }

        case .critical:
            alert.addButton(withTitle: "Reset")
            alert.addButton(withTitle: "Quit")

            activate()

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                reset()
            } else {
                quit()
            }
        }

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
        guard event.type == .keyDown else {
            return event
        }

        if event.modifiers == [.control, .option, .command] {
            switch event.keyCode {
            case .escape:
                reset()
                return nil
            case .period:
                keysPassthrough.toggle()
                playSound("Pop")
                return nil
            case .slash:
                setVerboseLogger()
                return nil
            default:
                break
            }
        }

        guard
            !keysPassthrough,
            let mediator = mediator
        else {
            return event
        }

        return mediator.handle(event)
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
    case nvimTerminated(status: Int)

    var errorDescription: String? {
        switch self {
        case .a11yPermissionRequired:
            return "ShadowVim needs the accessibility permission to work properly"
        case .nvimNotExecutable:
            return "Neovim failed to execute"
        case .nvimNotFound:
            return "Neovim not found"
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
        case .nvimTerminated:
            return "Reset ShadowVim?"
        default:
            return nil
        }
    }

    var critical: Bool {
        switch self {
        case .a11yPermissionRequired, .nvimNotExecutable, .nvimNotFound, .nvimTerminated:
            return true
        }
    }

    init?(error: Error) {
        switch error {
        case let NvimError.processStopped(status: status):
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
