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

extension AXObserver {
    func add(notification: AXNotification, element: AXUIElement, context: AnyObject) throws {
        let notification = notification.rawValue as CFString
        let context = Unmanaged.passUnretained(context).toOpaque()
        let result = AXObserverAddNotification(self, element, notification, context)
        if let error = AXError(code: result), case .notificationAlreadyRegistered = error {
            throw error
        }
    }

    func remove(notification: AXNotification, element: AXUIElement) throws {
        let notification = notification.rawValue as CFString
        let result = AXObserverRemoveNotification(self, element, notification)
        if let error = AXError(code: result), case .notificationNotRegistered = error {
            throw error
        }
    }
}
