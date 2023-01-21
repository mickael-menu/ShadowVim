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
        return try unpack(value!)
    }
    
    func get<Parameter>(_ attribute: AXAttribute, with param: Parameter) throws -> Any? {
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
        return try unpack(value!)
    }

    func get(_ attributes: [AXAttribute]) throws -> [Any] {
        let attributes = attributes.map { $0.rawValue } as CFArray
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
            return AXElement.wrap(value as! AXUIElement)
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
