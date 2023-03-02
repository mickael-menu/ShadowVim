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

public enum EventSourceError: Error {
    case failedToCreateSource
}

/// An event source allows to post events (e.g. key combos) to the system.
public final class EventSource {
    private let source: CGEventSource
    private let keyResolver: CGKeyResolver

    public init(keyResolver: CGKeyResolver) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw EventSourceError.failedToCreateSource
        }

        self.source = source
        self.keyResolver = keyResolver
    }

    public func press(_ kc: KeyCombo) -> Bool {
        guard
            let code = keyResolver.code(for: kc.key),
            let downEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
            let upEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else {
            return false
        }

        DispatchQueue.main.async {
            let flags = kc.modifiers.cgFlags
            downEvent.flags = flags
            upEvent.flags = flags
            downEvent.post(tap: .cgSessionEventTap)
            upEvent.post(tap: .cgSessionEventTap)
        }

        return true
    }
}
