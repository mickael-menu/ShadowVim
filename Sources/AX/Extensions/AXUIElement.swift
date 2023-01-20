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

import ApplicationServices
import Foundation

extension AXUIElement {
    func get(_ attribute: AXAttribute) throws -> Any? {
        precondition(Thread.isMainThread)

        var value: AnyObject?
        let code = AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)
        if let error = AXError(code: code) {
            if case .noValue = error {
                return nil
            } else {
                throw error
            }
        }
        return try value.map(unpack)
    }

    private func unpack(_ value: AnyObject) throws -> Any {
        switch CFGetTypeID(value) {
        case AXUIElementGetTypeID():
            return try wrapElement(value as! AXUIElement)
        case CFArrayGetTypeID():
            return try (value as! [AnyObject]).map(unpack)
        case AXValueGetTypeID():
            return unpackValue(value as! AXValue)
        default:
            return value
        }
    }

    private func wrapElement(_ element: AXUIElement) throws -> AXElement {
        guard let rawRole = try element.get(.role) as? String else {
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

    func set(_ attribute: AXAttribute, value: Any) throws {
        precondition(Thread.isMainThread)

        guard let value = pack(value) else {
            throw AXError.packFailure(value)
        }

        let result = AXUIElementSetAttributeValue(self, attribute.rawValue as CFString, value)
        if let error = AXError(code: result) {
            throw error
        }
    }

    private func pack(_ value: Any) -> AnyObject? {
        switch value {
        case let value as AXElement:
            return value.element
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
}
