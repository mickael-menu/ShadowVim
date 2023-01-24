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

public struct AXNotification: Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ notification: CFString) {
        self.init(rawValue: notification as String)
    }

    // Focus notifications

    /// Notification of a change in the main window.
    public static let mainWindow = AXNotification(rawValue: kAXMainWindowChangedNotification)

    /// Notification that the focused window changed.
    public static let focusedWindowChanged = AXNotification(rawValue: kAXFocusedWindowChangedNotification)

    /// Notification that the focused UI element has changed.
    public static let focusedUIElementChanged = AXNotification(rawValue: kAXFocusedUIElementChangedNotification)

    // Application notifications

    /// Notification that an application was activated.
    public static let applicationActivated = AXNotification(rawValue: kAXApplicationActivatedNotification)

    /// Notification that an application was deactivated.
    public static let applicationDeactivated = AXNotification(rawValue: kAXApplicationDeactivatedNotification)

    /// Notification that an application has been hidden.
    public static let applicationHidden = AXNotification(rawValue: kAXApplicationHiddenNotification)

    /// Notification that an application is no longer hidden.
    public static let applicationShown = AXNotification(rawValue: kAXApplicationShownNotification)

    // Window notifications

    /// Notification that a window was created.
    public static let windowCreated = AXNotification(rawValue: kAXWindowCreatedNotification)

    /// Notification that a window moved.
    ///
    /// This notification is sent at the end of the window move, not
    /// continuously as the window is being moved.
    public static let windowMoved = AXNotification(rawValue: kAXWindowMovedNotification)

    /// Notification that a window was resized.
    ///
    /// This notification is sent at the end of the window resize, not
    /// continuously as the window is being resized.
    public static let windowResized = AXNotification(rawValue: kAXWindowResizedNotification)

    /// Notification that a window was minimized.
    public static let windowMiniaturized = AXNotification(rawValue: kAXWindowMiniaturizedNotification)

    /// Notification that a window is no longer minimized.
    public static let windowDeminiaturized = AXNotification(rawValue: kAXWindowDeminiaturizedNotification)

    // New Drawer, Sheet, and Help notifications

    /// Notification that a drawer was created.
    public static let drawerCreated = AXNotification(rawValue: kAXDrawerCreatedNotification)

    /// Notification that a sheet was created.
    public static let sheetCreated = AXNotification(rawValue: kAXSheetCreatedNotification)

    /// Notification that a help tag was created.
    public static let helpTagCreated = AXNotification(rawValue: kAXHelpTagCreatedNotification)

    // Element notifications

    /// This notification is sent when the value of the UIElement's value
    /// attribute has changed, not when the value of any other attribute has
    /// changed.
    public static let valueChanged = AXNotification(rawValue: kAXValueChangedNotification)

    /// The returned UIElement is no longer valid in the target application.
    ///
    /// You can still use the local reference with calls like CFEqual (for
    /// example, to remove it from a list), but you should not pass it to the
    /// accessibility APIs.
    public static let uiElementDestroyed = AXNotification(rawValue: kAXUIElementDestroyedNotification)

    /// Notification that an element's busy state has changed.
    public static let elementBusyChanged = AXNotification(rawValue: kAXElementBusyChangedNotification)

    // Menu notifications

    /// Notification that a menu has been opened.
    public static let menuOpened = AXNotification(rawValue: kAXMenuOpenedNotification)

    /// Notification that a menu has been closed.
    public static let menuClosed = AXNotification(rawValue: kAXMenuClosedNotification)

    /// Notification that a menu item has been seleted.
    public static let menuItemSelected = AXNotification(rawValue: kAXMenuItemSelectedNotification)

    // Table/Outline notifications

    /// Notification that the number of rows in this table has changed.
    public static let rowCountChanged = AXNotification(rawValue: kAXRowCountChangedNotification)

    // Outline notifications

    /// Notification that a row in an outline has been expanded.
    public static let rowExpanded = AXNotification(rawValue: kAXRowExpandedNotification)

    /// Notification that a row in an outline has been collapsed.
    public static let rowCollapsed = AXNotification(rawValue: kAXRowCollapsedNotification)

    // Cell-based Table notifications

    /// Notification that the selected cells have changed.
    public static let selectedCellsChanged = AXNotification(rawValue: kAXSelectedCellsChangedNotification)

    // Layout area notifications

    /// Notification that the units have changed.
    public static let unitsChanged = AXNotification(rawValue: kAXUnitsChangedNotification)

    /// Notification that the selected children have moved.
    public static let selectedChildrenMoved = AXNotification(rawValue: kAXSelectedChildrenMovedNotification)

    // Other notifications

    /// Notification that a different subset of this element's children were
    /// selected.
    public static let selectedChildrenChanged = AXNotification(rawValue: kAXSelectedChildrenChangedNotification)

    /// Notification that this element has been resized.
    public static let resized = AXNotification(rawValue: kAXResizedNotification)

    /// Notification that this element has moved.
    public static let moved = AXNotification(rawValue: kAXMovedNotification)

    /// Notification that an element was created.
    public static let created = AXNotification(rawValue: kAXCreatedNotification)

    /// Notification that the set of selected rows changed.
    public static let selectedRowsChanged = AXNotification(rawValue: kAXSelectedRowsChangedNotification)

    /// Notification that the set of selected columns changed.
    public static let selectedColumnsChanged = AXNotification(rawValue: kAXSelectedColumnsChangedNotification)

    /// Notification that a different set of text was selected.
    public static let selectedTextChanged = AXNotification(rawValue: kAXSelectedTextChangedNotification)

    /// Notification that the title changed.
    public static let titleChanged = AXNotification(rawValue: kAXTitleChangedNotification)

    /// Notification that the layout changed.
    public static let layoutChanged = AXNotification(rawValue: kAXLayoutChangedNotification)

    /// Notification to request an announcement to be spoken.
    public static let announcementRequested = AXNotification(rawValue: kAXAnnouncementRequestedNotification)
}
