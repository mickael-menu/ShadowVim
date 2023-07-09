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

/// Resolves a key from its virtual key code, and vice versa.
///
/// This should take into account the current virtual layout of the input
/// source.
public protocol CGKeyResolver {
    func key(for code: CGKeyCode) -> Key?
    func code(for key: Key) -> CGKeyCode?
}

public extension CGKeyResolver {
    func keyCombo(for event: CGEvent) -> KeyCombo? {
        guard
            event.type == .keyDown || event.type == .keyUp,
            let key = key(for: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
        else {
            return nil
        }

        return KeyCombo(key, modifiers: InputModifiers(cgFlags: event.flags))
    }
}

extension InputModifiers {
    init(cgFlags: CGEventFlags) {
        self = .none
        if cgFlags.contains(.maskShift) {
            insert(.shift)
        }
        if cgFlags.contains(.maskControl) {
            insert(.control)
        }
        if cgFlags.contains(.maskAlternate) {
            insert(.option)
        }
        if cgFlags.contains(.maskCommand) {
            insert(.command)
        }
        if cgFlags.contains(.maskSecondaryFn) {
            insert(.function)
        }
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.shift) {
            flags.insert(.maskShift)
        }
        if contains(.control) {
            flags.insert(.maskControl)
        }
        if contains(.option) {
            flags.insert(.maskAlternate)
        }
        if contains(.command) {
            flags.insert(.maskCommand)
        }
        if contains(.function) {
            flags.insert(.maskSecondaryFn)
        }
        return flags
    }
}
