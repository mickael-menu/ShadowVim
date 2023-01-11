//
//  Event.swift
//  PhantomVim
//
//  Created by Mickaël Menu on 08/01/2023.
//

import Foundation
import CoreGraphics

enum EventTapError: Error {
    case failedToCreateTap
}

/// Inspirations
///  - https://gist.github.com/osnr/23eb05b4e0bcd335c06361c4fabadd6f
///  - https://github.com/creasty/Keyboard/blob/9430e443e07bc236bc2acc1d0d33afe4692428e8/keyboard/AppDelegate.swift#L72
///  - https://stackoverflow.com/a/31898592/1474476
class EventTap {
    private var tap: CFMachPort!
    
    typealias Handler = (_ type: CGEventType, _ event: CGEvent) -> CGEvent?
    
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }
    
    func run() throws {
        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { proxy, type, event, refcon in
                return Unmanaged<EventTap>.fromOpaque(refcon!)
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
        CFRunLoopRun()
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout:
            CGEvent.tapEnable(tap: tap, enable: true)
            return event
        default:
            return self.handler(type, event)
        }
    }
}
