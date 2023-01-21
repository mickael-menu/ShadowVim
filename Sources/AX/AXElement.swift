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
import Combine
import Foundation

/// An accessibility object provides information about the user interface object
/// it represents. This information includes the object's position in the
/// accessibility hierarchy, its position on the display, details about what it
/// is, and what actions it can perform.
///
/// Accessibility objects respond to messages sent by assistive applications and
/// send notifications that describe state changes.
open class AXElement {
    public let element: AXUIElement

    public class func wrap(_ element: AXUIElement) -> AXElement {
        guard let rawRole = try? element.get(.role) as? String else {
            return AXElement(element: element)
        }
        let role = AXRole(rawValue: rawRole)
        switch role {
        case .application: return AXApplication(element: element)
        case .systemWide: return AXSystemWideElement(element: element)
        case .window, .sheet, .drawer: return AXWindow(element: element)
        case .button: return AXButton(element: element)
        case .textField: return AXTextField(element: element)
        case .textArea: return AXTextArea(element: element)
        default:
            return AXElement(element: element)
        }
    }

    init(element: AXUIElement) {
        self.element = element
    }
    
    public func attributes() throws -> [AXAttribute] {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &names)
        if let error = AXError(code: result) {
            throw error
        }

        return (names! as [AnyObject]).map { AXAttribute(rawValue: $0 as! String) }
    }
        
    public func attributeValues() throws -> [AXAttribute: Any] {
        let attributes = try attributes()
        let values = try element.get(attributes)
        guard attributes.count == values.count else {
            throw AXError.unexpectedValueCount(values)
        }
        return Dictionary(zip(attributes, values), uniquingKeysWith: { a, b in b })
    }

    public func get<Value>(_ attribute: AXAttribute) throws -> Value? {
        try element.get(attribute) as? Value
    }

    public func get<Value: RawRepresentable>(_ attribute: AXAttribute) throws -> Value? {
        let rawValue = try get(attribute) as Value.RawValue?
        return rawValue.flatMap(Value.init(rawValue:))
    }

    public func get<V1, V2>(_ attribute1: AXAttribute, _ attribute2: AXAttribute) throws -> (V1?, V2?) {
        let values = try element.get([attribute1, attribute2])
        guard values.count == 2 else {
            throw AXError.unexpectedValueCount(values)
        }
        return (values[0] as? V1, values[1] as? V2)
    }

    public func get<V1, V2, V3>(_ attribute1: AXAttribute, _ attribute2: AXAttribute, _ attribute3: AXAttribute) throws -> (V1?, V2?, V3?) {
        let values = try element.get([attribute1, attribute2, attribute3])
        guard values.count == 3 else {
            throw AXError.unexpectedValueCount(values)
        }
        return (values[0] as? V1, values[1] as? V2, values[2] as? V3)
    }

    public func set<Value>(_ attribute: AXAttribute, value: Value) throws {
        try element.set(attribute, value: value)
    }

    public func set<Value: RawRepresentable>(_ attribute: AXAttribute, value: Value) throws {
        try set(attribute, value: value.rawValue)
    }

    /// Returns the process ID associated with this accessibility object.
    public func pid() throws -> pid_t {
        var pid: pid_t = -1
        let result = AXUIElementGetPid(element, &pid)
        if let error = AXError(code: result) {
            throw error
        }
        guard pid > 0 else {
            throw AXError.invalidPid(pid)
        }
        return pid
    }

    public func publisher(for notification: AXNotification) -> AnyPublisher<AXElement, Error> {
        do {
            return try AXNotificationObserver.shared(for: pid())
                .publisher(for: notification, element: element)
                .map { AXElement.wrap($0) }
                .eraseToAnyPublisher()
        } catch {
            return Fail<AXElement, Error>(error: error)
                .eraseToAnyPublisher()
        }
    }
}

public extension AXElement {
    func role() throws -> AXRole? {
        try get(.role)
    }

    func subrole() throws -> AXSubrole? {
        try get(.subrole)
    }

    func roleDescription() throws -> String? {
        try get(.roleDescription)
    }

    func description() throws -> String? {
        try get(.description)
    }

    func help() throws -> String? {
        try get(.help)
    }

    func isBusy() throws -> Bool {
        try get(.elementBusy) ?? false
    }

    // FIXME: Here?
    func document() throws -> String? {
        try get(.document)
    }

    // FIXME: Here?
    func url() throws -> String? {
        try get(.url)
    }
}

public class AXSystemWideElement: AXElement {
    public static let shared = AXSystemWideElement(element: AXUIElementCreateSystemWide())

    public func focusedApplication() throws -> AXApplication? {
        try get(.focusedApplication)
    }

    public func focusedUIElement() throws -> AXElement? {
        try get(.focusedUIElement)
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
        try get(.frontmost) ?? false
    }

    public func isHidden() throws -> Bool {
        try get(.hidden) ?? false
    }

    public func windows() throws -> [AXWindow] {
        try get(.windows) ?? []
    }

    public func mainWindow() throws -> AXWindow? {
        try get(.mainWindow)
    }

    public func focusedWindow() throws -> AXWindow? {
        try get(.focusedWindow)
    }

    public func focusedUIElement() throws -> AXFocusableElement? {
        try get(.focusedUIElement)
    }
}

open class AXWindow: AXElement,
    AXTitledElement, AXPositionedElement, AXParentingElement
{
    public typealias Child = AXElement

    public func isMain() throws -> Bool {
        try get(.main) ?? false
    }

    public func isMinimized() throws -> Bool {
        try get(.minimized) ?? false
    }

    public func isModal() throws -> Bool {
        try get(.modal) ?? false
    }

    public func defaultButton() throws -> AXButton? {
        try get(.defaultButton)
    }

    public func cancelButton() throws -> AXButton? {
        try get(.cancelButton)
    }

    public func closeButton() throws -> AXButton? {
        try get(.closeButton)
    }

    public func zoomButton() throws -> AXButton? {
        try get(.zoomButton)
    }

    public func fullScreenButton() throws -> AXButton? {
        try get(.fullScreenButton)
    }

    public func minimizeButton() throws -> AXButton? {
        try get(.minimizeButton)
    }

    public func toolbarButton() throws -> AXButton? {
        try get(.toolbarButton)
    }
}

open class AXView: AXElement,
    AXPositionedElement
{
    public func isEnabled() throws -> Bool {
        try get(.enabled) ?? false
    }

    public func window() throws -> AXWindow? {
        try get(.window)
    }

    public func topLevelUIElement() throws -> AXElement? {
        try get(.topLevelUIElement)
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
        try get(.position) ?? .zero
    }

    func size() throws -> CGSize {
        try get(.size) ?? .zero
    }

    func parent() throws -> AXElement? {
        try get(.parent)
    }
}

public protocol AXParentingElement: AXPositionedElement {
    associatedtype Child: AXElement
}

public extension AXParentingElement {
    func children() throws -> [Child] {
        try get(.children) ?? []
    }

    func visibleChildren() throws -> [Child] {
        try get(.visibleChildren) ?? []
    }

    func contents() throws -> [Child] {
        try get(.contents) ?? []
    }
}

public protocol AXFocusableElement: AXElement {}
public extension AXFocusableElement {
    func focus() throws {
        try set(.focused, value: true)
    }

    func isFocused() throws -> Bool {
        try get(.focused) ?? false
    }

    func sharedFocusElements() throws -> [AXElement] {
        try get(.sharedFocusElements) ?? []
    }
}

public protocol AXTitledElement: AXElement {}
public extension AXTitledElement {
    func title() throws -> String? {
        try get(.title)
    }
}

public protocol AXValuedElement: AXElement {
    associatedtype Value

    func setValue(_ value: Value) throws
}

public extension AXValuedElement {
    func setValue(_ value: Value) throws {
        try set(.value, value: value)
    }

    func value() throws -> Value? {
        try get(.value)
    }

    func valuePublisher() throws -> AnyPublisher<Value?, Error> {
        publisher(for: .valueChanged)
            .tryMap { [element] el in
                precondition(el.element == element)
                return try (el as? Self)?.value() as? Value
            }
            .eraseToAnyPublisher()
    }

    func valueDescription() throws -> String? {
        try get(.valueDescription)
    }

    func valueWraps() throws -> Bool {
        try get(.valueWraps) ?? false
    }
}

public protocol AXTextualElement: AXValuedElement where Value == String {}
public extension AXTextualElement {
    func text() throws -> String {
        try value() ?? ""
    }

    func placeholder() throws -> String? {
        try get(.placeholderValue)
    }

    func numberOfCharacters() throws -> Int {
        try get(.numberOfCharacters) ?? 0
    }

    func selectedText() throws -> String? {
        try get(.selectedText)
    }

    func selectedTextRange() throws -> CFRange? {
        try get(.selectedTextRange)
    }

    func selectedTextRanges() throws -> [CFRange] {
        try get(.selectedTextRanges) ?? []
    }

    func insertionPointLineNumber() throws -> Int? {
        try get(.insertionPointLineNumber)
    }

    func visibleCharacterRange() throws -> CFRange? {
        try get(.visibleCharacterRange)
    }
}
