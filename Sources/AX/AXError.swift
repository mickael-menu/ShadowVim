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

/// Error codes returned by accessibility functions (`AXError.h`).
public enum AXError: LocalizedError {
    /// Received an unknown error code.
    case unknown(ApplicationServices.AXError)

    /// Received a value with an unexpected type.
    case unexpectedValue(AnyObject)

    /// Failed to pack the given value to send to AX APIs.
    case packFailure(Any)

    /// A system error occurred, such as the failure to allocate an object.
    case failure

    /// An illegal argument was passed to the function.
    case illegalArgument

    /// The AXUIElementRef passed to the function is invalid.
    case invalidUIElement

    /// The AXObserverRef passed to the function is not a valid observer.
    case invalidUIElementObserver

    /// The function cannot complete because messaging failed in some way or
    /// because the application with which the function is communicating is busy
    /// or unresponsive.
    case cannotComplete

    /// The attribute is not supported by the AXUIElementRef.
    case attributeUnsupported

    /// The action is not supported by the AXUIElementRef.
    case actionUnsupported

    /// The notification is not supported by the AXUIElementRef.
    case notificationUnsupported

    /// Indicates that the function or method is not implemented (this can be
    /// returned if a process does not support the accessibility API).
    case notImplemented

    /// This notification has already been registered for.
    case notificationAlreadyRegistered

    /// Indicates that a notification is not registered yet.
    case notificationNotRegistered

    /// The accessibility API is disabled (as when, for example, the user
    /// deselects "Enable access for assistive devices" in Universal Access
    /// Preferences).
    case apiDisabled

    /// The requested value or `AXUIElementRef` does not exist.
    case noValue

    /// The parameterized attribute is not supported by the `AXUIElementRef`.
    case parameterizedAttributeUnsupported

    /// Not enough precision.
    case notEnoughPrecision

    init?(code: ApplicationServices.AXError) {
        switch code {
        case .success:
            return nil
        case .failure:
            self = .failure
        case .illegalArgument:
            self = .illegalArgument
        case .invalidUIElement:
            self = .invalidUIElement
        case .invalidUIElementObserver:
            self = .invalidUIElementObserver
        case .cannotComplete:
            self = .cannotComplete
        case .attributeUnsupported:
            self = .attributeUnsupported
        case .actionUnsupported:
            self = .actionUnsupported
        case .notificationUnsupported:
            self = .notificationUnsupported
        case .notImplemented:
            self = .notImplemented
        case .notificationAlreadyRegistered:
            self = .notificationAlreadyRegistered
        case .notificationNotRegistered:
            self = .notificationNotRegistered
        case .apiDisabled:
            self = .apiDisabled
        case .noValue:
            self = .noValue
        case .parameterizedAttributeUnsupported:
            self = .parameterizedAttributeUnsupported
        case .notEnoughPrecision:
            self = .notEnoughPrecision
        @unknown default:
            self = .unknown(code)
        }
    }

    public var errorDescription: String? {
        String(describing: self)
    }
}
