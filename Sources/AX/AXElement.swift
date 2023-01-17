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
}
