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

enum EventTapError: Error {
    case failedToCreateTap
}

protocol EventTapDelegate: AnyObject {
    func eventTap(_ tap: EventTap, didReceive event: CGEvent) -> CGEvent?
}

/// Inspirations
///  - https://gist.github.com/osnr/23eb05b4e0bcd335c06361c4fabadd6f
///  - https://github.com/creasty/Keyboard/blob/9430e443e07bc236bc2acc1d0d33afe4692428e8/keyboard/AppDelegate.swift#L72
///  - https://stackoverflow.com/a/31898592/1474476
class EventTap {
    weak var delegate: EventTapDelegate?
    private var tap: CFMachPort!

    init() {}

    func run() throws {
        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(
                1 << CGEventType.keyDown.rawValue
//                | 1 << CGEventType.leftMouseDown.rawValue
//                | 1 << CGEventType.otherMouseDown.rawValue
            ),
            callback: { proxy, type, event, refcon in
                Unmanaged<EventTap>.fromOpaque(refcon!)
                    .takeUnretainedValue()
                    .handle(proxy: proxy, type: type, event: event)
                    .map { Unmanaged.passUnretained($0) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard tap != nil else {
            throw EventTapError.failedToCreateTap
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout:
            CGEvent.tapEnable(tap: tap, enable: true)
            return event
        default:
            guard let delegate = delegate else {
                return event
            }
            return delegate.eventTap(self, didReceive: event)
        }
    }
}
