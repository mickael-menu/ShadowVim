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

public struct Alert {
    public enum Style {
        case info
        case warning
    }

    public enum Accessory {
        case code(String, width: Int)
    }

    public var style: Style
    public var title: String
    public var message: String?

    public init(style: Style, title: String, message: String? = nil) {
        self.style = style
        self.title = title
        self.message = message
    }

    public init(error: Error) {
        style = .warning

        if let error = error as? LocalizedError {
            title = error.errorDescription ?? ""
            message = error.failureReason ?? ""
        } else {
            title = "An error occurred"
            accessory = .code(String(reflecting: error), width: 350)
        }
    }

    public var accessory: Accessory?

    private typealias Button = (title: String, action: () -> Void)
    private var buttons: [Button] = []

    public mutating func addButton(_ title: String, action: @escaping () -> Void) {
        precondition(buttons.count < 3)
        buttons.append((title: title, action: action))
    }

    public func showModal() {
        precondition(Thread.isMainThread)
        switch alert().runModal() {
        case .alertFirstButtonReturn:
            buttons[0].action()
        case .alertSecondButtonReturn:
            buttons[1].action()
        case .alertThirdButtonReturn:
            buttons[2].action()
        default:
            return
        }
    }

    private func alert() -> NSAlert {
        let alert = NSAlert()
        switch style {
        case .info:
            alert.alertStyle = .informational
        case .warning:
            alert.alertStyle = .warning
        }

        alert.messageText = title
        alert.informativeText = message ?? ""

        switch accessory {
        case let .code(code, width: width):
            let codeView = NSTextView(frame: .init(origin: .zero, size: .init(width: width, height: 0)))
            codeView.string = code
            codeView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            codeView.sizeToFit()
            codeView.isEditable = false
            codeView.isSelectable = true
            alert.accessoryView = codeView
        case .none:
            break
        }

        for (title, _) in buttons {
            alert.addButton(withTitle: title)
        }

        return alert
    }
}
