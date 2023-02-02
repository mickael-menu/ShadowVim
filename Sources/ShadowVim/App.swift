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
import Foundation
import Mediator
import Toolkit

class App {
    private let logger: Logger
    private let mediator: MainMediator

    init(logger: Logger) {
        self.logger = logger

        mediator = MainMediator(
            bundleIDs: [
                "com.apple.dt.Xcode",
//                "com.apple.TextEdit",
//                "com.google.android.studio",
            ],
            logger: logger
        )
        mediator.delegate = self
    }

    func didLaunch() {
        do {
            try mediator.start()
            hide()
        } catch {
            presentAlert(error: error, style: .critical)
        }
    }

    func willTerminate() {
        mediator.stop()
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
            logger.w(error)
        case .critical:
            logger.e(error)
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
                mediator.reset()
            }

        case .critical:
            alert.addButton(withTitle: "Relaunch")
            alert.addButton(withTitle: "Quit")

            activate()

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                relaunch()
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

    func relaunch() {
        if let bundleID = Bundle.main.bundleIdentifier {
            Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-b", bundleID])
        }
        quit()
    }
}

extension App: MainMediatorDelegate {
    func mainMediator(_ mediator: MainMediator, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.presentAlert(error: error, style: .warning)
        }
    }
}
