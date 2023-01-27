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
import ApplicationServices
import Combine
import Foundation

public typealias AXUIElement = ApplicationServices.AXUIElement

public extension AXUIElement {
    static var systemWide: AXUIElement { AXUIElementCreateSystemWide() }

    static func app(_ application: NSRunningApplication) -> AXUIElement {
        app(pid: application.processIdentifier)
    }

    static func app(pid: pid_t) -> AXUIElement {
        precondition(pid >= 0)
        return AXUIElementCreateApplication(pid)
    }

    static func app(bundleID: String) -> AXUIElement? {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })
            .map { app($0) }
    }
    
    var isValid: Bool {
        do {
            _ = try get(.role) as String?
        } catch AXError.invalidUIElement {
            return false
        } catch {
            print(error) // FIXME
        }
        return true
    }

    func attributes() throws -> [AXAttribute] {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(self, &names)
        if let error = AXError(code: result) {
            throw error
        }

        return (names! as [AnyObject]).map { AXAttribute(rawValue: $0 as! String) }
    }

    func attributeValues() throws -> [AXAttribute: Any] {
        let attributes = try attributes()
        let values = try get(attributes)
        guard attributes.count == values.count else {
            throw AXError.unexpectedValueCount(values)
        }
        return Dictionary(zip(attributes, values), uniquingKeysWith: { _, b in b })
    }

    func parameterizedAttributes() throws -> [AXAttribute] {
        var names: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(self, &names)
        if let error = AXError(code: result) {
            throw error
        }

        return (names! as [AnyObject]).map { AXAttribute(rawValue: $0 as! String) }
    }

    func count(_ attribute: AXAttribute) throws -> Int {
        var count = 0
        let code = AXUIElementGetAttributeValueCount(self, attribute.rawValue as CFString, &count)
        if let error = AXError(code: code) {
            throw error
        }
        return count
    }

    subscript<Value>(_ attribute: AXAttribute) -> Value? {
        get {
            do {
                return try get(attribute)
            } catch {
                print(error) // FIXME:
                return nil
            }
        }
        set(value) {
            do {
                try set(attribute, value: value)
            } catch {
                print(error) // FIXME:
            }
        }
    }

    subscript<Value: RawRepresentable>(_ attribute: AXAttribute) -> Value? {
        get {
            do {
                return try get(attribute)
            } catch {
                print(error) // FIXME:
//                Thread.callStackSymbols.forEach { print($0) }
                return nil
            }
        }
        set(value) {
            do {
                try set(attribute, value: value)
            } catch {
                print(error) // FIXME:
//                Thread.callStackSymbols.forEach { print($0) }
            }
        }
    }

    func get<Value>(_ attribute: AXAttribute) throws -> Value? {
        var value: AnyObject?
        let code = AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)
        if let error = AXError(code: code) {
            if case .noValue = error {
                return nil
            } else {
                throw error
            }
        }
        return try unpack(value!) as? Value
    }

    func get<Value: RawRepresentable>(_ attribute: AXAttribute) throws -> Value? {
        let rawValue = try get(attribute) as Value.RawValue?
        return rawValue.flatMap(Value.init(rawValue:))
    }

    func get<V1, V2>(_ attribute1: AXAttribute, _ attribute2: AXAttribute) throws -> (V1?, V2?) {
        let values = try get([attribute1, attribute2])
        guard values.count == 2 else {
            throw AXError.unexpectedValueCount(values)
        }
        return (values[0] as? V1, values[1] as? V2)
    }

    func get<V1, V2, V3>(_ attribute1: AXAttribute, _ attribute2: AXAttribute, _ attribute3: AXAttribute) throws -> (V1?, V2?, V3?) {
        let values = try get([attribute1, attribute2, attribute3])
        guard values.count == 3 else {
            throw AXError.unexpectedValueCount(values)
        }
        return (values[0] as? V1, values[1] as? V2, values[2] as? V3)
    }

    func get<Value, Parameter>(_ attribute: AXAttribute, with param: Parameter) throws -> Value? {
        precondition(Thread.isMainThread)

        var value: AnyObject?
        let code = AXUIElementCopyParameterizedAttributeValue(self, attribute.rawValue as CFString, param as AnyObject, &value)
        if let error = AXError(code: code) {
            if case .noValue = error {
                return nil
            } else {
                throw error
            }
        }
        return try unpack(value!) as? Value
    }

    func get(_ attributes: [AXAttribute]) throws -> [Any] {
        let attributes = attributes.map(\.rawValue) as CFArray
        var values: CFArray?
        let code = AXUIElementCopyMultipleAttributeValues(self, attributes, AXCopyMultipleAttributeOptions(), &values)
        if let error = AXError(code: code) {
            throw error
        }
        return try (values! as [AnyObject]).map(unpack)
    }

    private func unpack(_ value: AnyObject) throws -> Any {
        switch CFGetTypeID(value) {
        case AXUIElementGetTypeID():
            return value as! AXUIElement
        case CFArrayGetTypeID():
            return try (value as! [AnyObject]).map(unpack)
        case AXValueGetTypeID():
            return unpackValue(value as! AXValue)
        default:
            return value
        }
    }

    private func unpackValue(_ value: AXValue) -> Any {
        func getValue<Value>(_ value: AnyObject, type: AXValueType, in result: inout Value) {
            let success = AXValueGetValue(value as! AXValue, type, &result)
            assert(success)
        }

        let type = AXValueGetType(value)
        switch type {
        case .cgPoint:
            var result: CGPoint = .zero
            getValue(value, type: .cgPoint, in: &result)
            return result
        case .cgSize:
            var result: CGSize = .zero
            getValue(value, type: .cgSize, in: &result)
            return result
        case .cgRect:
            var result: CGRect = .zero
            getValue(value, type: .cgRect, in: &result)
            return result
        case .cfRange:
            var result: CFRange = .init()
            getValue(value, type: .cfRange, in: &result)
            return result
        case .axError:
            var result: ApplicationServices.AXError = .success
            getValue(value, type: .axError, in: &result)
            return AXError(code: result) as Any
        case .illegal:
            return value
        @unknown default:
            return value
        }
    }

    func isSettable(_ attribute: AXAttribute) throws -> Bool {
        var settable: DarwinBoolean = false
        let code = AXUIElementIsAttributeSettable(self, attribute.rawValue as CFString, &settable)
        if let error = AXError(code: code) {
            throw error
        }
        return settable.boolValue
    }

    func set<Value>(_ attribute: AXAttribute, value: Value) throws {
//        precondition(Thread.isMainThread)

        guard let value = pack(value) else {
            throw AXError.packFailure(value)
        }

        let result = AXUIElementSetAttributeValue(self, attribute.rawValue as CFString, value)
        if let error = AXError(code: result) {
            throw error
        }
    }

    func set<Value: RawRepresentable>(_ attribute: AXAttribute, value: Value) throws {
        try set(attribute, value: value.rawValue)
    }

    private func pack(_ value: Any) -> AnyObject? {
        switch value {
        case let value as AXUIElement:
            return value
        case let value as [Any]:
            return value.compactMap(pack) as CFArray
        case var value as CGPoint:
            return AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &value)
        case var value as CGSize:
            return AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &value)
        case var value as CGRect:
            return AXValueCreate(AXValueType(rawValue: kAXValueCGRectType)!, &value)
        case var value as CFRange:
            return AXValueCreate(AXValueType(rawValue: kAXValueCFRangeType)!, &value)
        default:
            return value as AnyObject
        }
    }

    // MARK: Notifications

    /// Returns a new publisher for a notification emitted by this element.
    func publisher(for notification: AXNotification) -> AnyPublisher<AXUIElement, Error> {
        do {
            return try AXNotificationObserver.shared(for: pid())
                .publisher(for: notification, element: self)
                .eraseToAnyPublisher()
        } catch {
            return Fail<AXUIElement, Error>(error: error)
                .eraseToAnyPublisher()
        }
    }

    // MARK: Metadata

    /// Returns the process ID associated with this accessibility object.
    func pid() throws -> pid_t {
        var pid: pid_t = -1
        let result = AXUIElementGetPid(self, &pid)
        if let error = AXError(code: result) {
            throw error
        }
        guard pid > 0 else {
            throw AXError.invalidPid(pid)
        }
        return pid
    }

    func role() throws -> AXRole? {
        try get(.role)
    }

    func subrole() throws -> AXSubrole? {
        try get(.subrole)
    }
}
