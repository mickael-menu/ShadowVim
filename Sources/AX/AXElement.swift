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
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AppKit
import ApplicationServices
import Foundation

/// An accessibility object provides information about the user interface object
/// it represents. This information includes the object's position in the
/// accessibility hierarchy, its position on the display, details about what it
/// is, and what actions it can perform.
///
/// Accessibility objects respond to messages sent by assistive applications and
/// send notifications that describe state changes.
open class AXElement {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    public func attribute<Value>(_ attribute: AXAttribute) throws -> Value? {
        try element.attribute(attribute) as? Value
    }

    public func attribute<Value: RawRepresentable>(_ attribute: AXAttribute) throws -> Value? {
        let rawValue = try element.attribute(attribute) as? Value.RawValue
        return rawValue.flatMap(Value.init(rawValue:))
    }
}

public extension AXElement {
    func role() throws -> AXRole? {
        try attribute(.role)
    }

    func subrole() throws -> AXSubrole? {
        try attribute(.subrole)
    }

    func roleDescription() throws -> String? {
        try attribute(.roleDescription)
    }

    func description() throws -> String? {
        try attribute(.description)
    }

    func help() throws -> String? {
        try attribute(.help)
    }

    func isBusy() throws -> Bool {
        try attribute(.elementBusy) ?? false
    }

    // FIXME: Here?
    func document() throws -> String? {
        try attribute(.document)
    }

    // FIXME: Here?
    func url() throws -> String? {
        try attribute(.url)
    }
}

public class AXSystemWideElement: AXElement {
    public static let shared = AXSystemWideElement(element: AXUIElementCreateSystemWide())

    public func focusedApplication() throws -> AXApplication? {
        try attribute(.focusedApplication)
    }

    public func focusedUIElement() throws -> AXElement? {
        try attribute(.focusedUIElement)
    }
}

public class AXApplication: AXElement,
    AXTitledElement
{
    public convenience init?(pid: pid_t) {
        guard pid >= 0 else {
            return nil
        }
        self.init(element: AXUIElementCreateApplication(pid))
    }

    public convenience init?(bundleID: String) {
        guard
            let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })
        else {
            return nil
        }
        self.init(app: app)
    }

    public convenience init?(app: NSRunningApplication) {
        guard !app.isTerminated else {
            return nil
        }
        self.init(pid: app.processIdentifier)
    }

    public func isFrontmost() throws -> Bool {
        try attribute(.frontmost) ?? false
    }

    public func isHidden() throws -> Bool {
        try attribute(.hidden) ?? false
    }

    public func windows() throws -> [AXWindow] {
        try attribute(.windows) ?? []
    }

    public func mainWindow() throws -> AXWindow? {
        try attribute(.mainWindow)
    }

    public func focusedWindow() throws -> AXWindow? {
        try attribute(.focusedWindow)
    }

    public func focusedUIElement() throws -> AXFocusableElement? {
        try attribute(.focusedUIElement)
    }
}

open class AXWindow: AXElement,
    AXTitledElement, AXPositionedElement, AXParentingElement, AXFocusableElement
{
    public typealias Child = AXElement

    public func isMain() throws -> Bool {
        try attribute(.main) ?? false
    }

    public func isMinimized() throws -> Bool {
        try attribute(.minimized) ?? false
    }

    public func isModal() throws -> Bool {
        try attribute(.modal) ?? false
    }

    public func defaultButton() throws -> AXButton? {
        try attribute(.defaultButton)
    }

    public func cancelButton() throws -> AXButton? {
        try attribute(.cancelButton)
    }

    public func closeButton() throws -> AXButton? {
        try attribute(.closeButton)
    }

    public func zoomButton() throws -> AXButton? {
        try attribute(.zoomButton)
    }

    public func fullScreenButton() throws -> AXButton? {
        try attribute(.fullScreenButton)
    }

    public func minimizeButton() throws -> AXButton? {
        try attribute(.minimizeButton)
    }

    public func toolbarButton() throws -> AXButton? {
        try attribute(.toolbarButton)
    }
}

open class AXView: AXElement,
    AXPositionedElement
{
    public func isEnabled() throws -> Bool {
        try attribute(.enabled) ?? false
    }

    public func window() throws -> AXWindow? {
        try attribute(.window)
    }

    public func topLevelUIElement() throws -> AXElement? {
        try attribute(.topLevelUIElement)
    }
}

public class AXButton: AXView,
    AXTitledElement {}

public class AXTextField: AXView,
    AXTextualElement, AXFocusableElement {}

public class AXTextArea: AXView,
    AXTextualElement, AXFocusableElement {}

public protocol AXPositionedElement: AXElement {}
public extension AXPositionedElement {
    func position() throws -> CGPoint {
        try attribute(.position) ?? .zero
    }

    func size() throws -> CGSize {
        try attribute(.size) ?? .zero
    }

    func parent() throws -> AXElement? {
        try attribute(.parent)
    }
}

public protocol AXParentingElement: AXPositionedElement {
    associatedtype Child: AXElement
}

public extension AXParentingElement {
    func children() throws -> [Child] {
        try attribute(.children) ?? []
    }

    func visibleChildren() throws -> [Child] {
        try attribute(.visibleChildren) ?? []
    }

    func contents() throws -> [Child] {
        try attribute(.contents) ?? []
    }
}

public protocol AXFocusableElement: AXElement {
    func focus() throws
}

public extension AXFocusableElement {
    func focus() throws {
        // TODO:
    }

    func isFocused() throws -> Bool {
        try attribute(.focused) ?? false
    }

    func sharedFocusElements() throws -> [AXElement] {
        try attribute(.sharedFocusElements) ?? []
    }
}

public protocol AXTitledElement: AXElement {}
public extension AXTitledElement {
    func title() throws -> String? {
        try attribute(.title)
    }
}

public protocol AXValuedElement: AXElement {
    associatedtype Value

    func setValue(_ value: Value) throws
}

public extension AXValuedElement {
    func setValue(_ value: Value) throws {
        // TODO:
    }

    func value() throws -> Value? {
        try attribute(.value)
    }

    func valueDescription() throws -> String? {
        try attribute(.valueDescription)
    }

    func valueWraps() throws -> Bool {
        try attribute(.valueWraps) ?? false
    }
}

public protocol AXTextualElement: AXValuedElement where Value == String {}
public extension AXTextualElement {
    func text() throws -> String {
        try value() ?? ""
    }

    func placeholder() throws -> String? {
        try attribute(.placeholderValue)
    }

    func numberOfCharacters() throws -> Int {
        try attribute(.numberOfCharacters) ?? 0
    }

    func selectedText() throws -> String? {
        try attribute(.selectedText)
    }

    func selectedTextRange() throws -> CFRange? {
        try attribute(.selectedTextRange)
    }

    func selectedTextRanges() throws -> [CFRange] {
        try attribute(.selectedTextRanges) ?? []
    }

    func insertionPointLineNumber() throws -> Int? {
        try attribute(.insertionPointLineNumber)
    }

    func visibleCharacterRange() throws -> CFRange? {
        try attribute(.visibleCharacterRange)
    }
}
