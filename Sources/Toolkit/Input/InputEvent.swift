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

import CoreGraphics
import Foundation

public enum InputEvent {
    case key(KeyEvent)
    case mouse(MouseEvent)

    public init?(event: CGEvent, keyResolver: CGKeyResolver) {
        if let keyCombo = keyResolver.keyCombo(for: event) {
            self = .key(KeyEvent(event: event, keyCombo: keyCombo))
        } else if let mouse = MouseEvent(event: event) {
            self = .mouse(mouse)
        } else {
            return nil
        }
    }
}

public struct KeyEvent {
    public let event: CGEvent
    public let keyCombo: KeyCombo

    public init(event: CGEvent, keyCombo: KeyCombo) {
        precondition(event.type == .keyDown || event.type == .keyUp)
        self.event = event
        self.keyCombo = keyCombo
    }

    public var character: String? {
        let maxStringLength = 4
        var actualStringLength = 0
        var unicodeString = [UniChar](repeating: 0, count: Int(maxStringLength))
        event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
        let char = String(utf16CodeUnits: &unicodeString, count: Int(actualStringLength))
        guard !char.isEmpty else {
            return nil
        }
        return char
    }
}

public struct MouseEvent {
    public enum Kind: Equatable {
        case down(Button)
        case up(Button)
        case dragged(Button)
        case moved
    }

    public enum Button: Equatable {
        case left
        case right
        case other
    }

    public let event: CGEvent
    public let kind: Kind
    public let modifiers: InputModifiers

    public init?(event: CGEvent) {
        self.event = event

        switch event.type {
        case .leftMouseDown:
            kind = .down(.left)
        case .leftMouseUp:
            kind = .up(.left)
        case .rightMouseDown:
            kind = .down(.right)
        case .rightMouseUp:
            kind = .up(.right)
        case .otherMouseDown:
            kind = .down(.other)
        case .otherMouseUp:
            kind = .up(.other)
        case .leftMouseDragged:
            kind = .dragged(.left)
        case .rightMouseDragged:
            kind = .dragged(.right)
        case .otherMouseDragged:
            kind = .dragged(.other)
        case .mouseMoved:
            kind = .moved
        default:
            return nil
        }

        modifiers = InputModifiers(cgFlags: event.flags)
    }
}
