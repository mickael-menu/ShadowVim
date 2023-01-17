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

import Foundation

/// Error codes returned by accessibility functions (`AXError.h`).
public enum AXError: Int, LocalizedError {
    /// Received an unknown error code.
    case unknown = -1

    /// A system error occurred, such as the failure to allocate an object.
    case failure = -25200

    /// An illegal argument was passed to the function.
    case illegalArgument = -25201

    /// The AXUIElementRef passed to the function is invalid.
    case invalidUIElement = -25202

    /// The AXObserverRef passed to the function is not a valid observer.
    case invalidUIElementObserver = -25203

    /// The function cannot complete because messaging failed in some way or
    /// because the application with which the function is communicating is busy
    /// or unresponsive.
    case cannotComplete = -25204

    /// The attribute is not supported by the AXUIElementRef.
    case attributeUnsupported = -25205

    /// The action is not supported by the AXUIElementRef.
    case actionUnsupported = -25206

    /// The notification is not supported by the AXUIElementRef.
    case notificationUnsupported = -25207

    /// Indicates that the function or method is not implemented (this can be
    /// returned if a process does not support the accessibility API).
    case notImplemented = -25208

    /// This notification has already been registered for.
    case notificationAlreadyRegistered = -25209

    /// Indicates that a notification is not registered yet.
    case notificationNotRegistered = -25210

    /// The accessibility API is disabled (as when, for example, the user
    /// deselects "Enable access for assistive devices" in Universal Access
    /// Preferences).
    case apiDisabled = -25211

    /// The requested value or `AXUIElementRef` does not exist.
    case noValue = -25212

    /// The parameterized attribute is not supported by the `AXUIElementRef`.
    case parameterizedAttributeUnsupported = -25213

    /// Not enough precision.
    case notEnoughPrecision = -25214

    init?(code: Int) {
        guard code != 0 else {
            return nil
        }
        self = AXError(rawValue: code) ?? .unknown
    }

    public var errorDescription: String? {
        String(describing: self)
    }
}
