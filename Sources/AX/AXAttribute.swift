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

public struct AXAttribute: Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    // Informational Attributes
    public static let role = AXAttribute(rawValue: kAXRoleAttribute)
    public static let subrole = AXAttribute(rawValue: kAXSubroleAttribute)
    public static let roleDescription = AXAttribute(rawValue: kAXRoleDescriptionAttribute)
    public static let title = AXAttribute(rawValue: kAXTitleAttribute)
    public static let description = AXAttribute(rawValue: kAXDescriptionAttribute)
    public static let help = AXAttribute(rawValue: kAXHelpAttribute)

    // Hierarchy or relationship attributes
    public static let parent = AXAttribute(rawValue: kAXParentAttribute)
    public static let children = AXAttribute(rawValue: kAXChildrenAttribute)
    public static let selectedChildren = AXAttribute(rawValue: kAXSelectedChildrenAttribute)
    public static let visibleChildren = AXAttribute(rawValue: kAXVisibleChildrenAttribute)
    public static let window = AXAttribute(rawValue: kAXWindowAttribute)
    public static let topLevelUIElement = AXAttribute(rawValue: kAXTopLevelUIElementAttribute)
    public static let titleUIElement = AXAttribute(rawValue: kAXTitleUIElementAttribute)
    public static let serves = AXAttribute(rawValue: kAXServesAsTitleForUIElementsAttribute)
    public static let linkedUIElements = AXAttribute(rawValue: kAXLinkedUIElementsAttribute)
    public static let sharedFocusElements = AXAttribute(rawValue: kAXSharedFocusElementsAttribute)

    // Visual state attributes
    public static let enabled = AXAttribute(rawValue: kAXEnabledAttribute)
    public static let focused = AXAttribute(rawValue: kAXFocusedAttribute)
    public static let position = AXAttribute(rawValue: kAXPositionAttribute)
    public static let size = AXAttribute(rawValue: kAXSizeAttribute)

    // Value attributes
    public static let value = AXAttribute(rawValue: kAXValueAttribute)
    public static let valueDescription = AXAttribute(rawValue: kAXValueDescriptionAttribute)
    public static let minValue = AXAttribute(rawValue: kAXMinValueAttribute)
    public static let maxValue = AXAttribute(rawValue: kAXMaxValueAttribute)
    public static let valueIncrement = AXAttribute(rawValue: kAXValueIncrementAttribute)
    public static let valueWraps = AXAttribute(rawValue: kAXValueWrapsAttribute)
    public static let allowedValues = AXAttribute(rawValue: kAXAllowedValuesAttribute)
    public static let placeholderValue = AXAttribute(rawValue: kAXPlaceholderValueAttribute)

    // Text-specific attributes
    public static let selectedText = AXAttribute(rawValue: kAXSelectedTextAttribute)
    public static let selectedTextRange = AXAttribute(rawValue: kAXSelectedTextRangeAttribute)
    public static let selectedTextRanges = AXAttribute(rawValue: kAXSelectedTextRangesAttribute)
    public static let visibleCharacterRange = AXAttribute(rawValue: kAXVisibleCharacterRangeAttribute)
    public static let numberOfCharacters = AXAttribute(rawValue: kAXNumberOfCharactersAttribute)
    public static let sharedTextUIElements = AXAttribute(rawValue: kAXSharedTextUIElementsAttribute)
    public static let sharedCharacterRange = AXAttribute(rawValue: kAXSharedCharacterRangeAttribute)
    public static let insertionPointLineNumber = AXAttribute(rawValue: kAXInsertionPointLineNumberAttribute)

    // Window, sheet, or drawer-specific attributes
    public static let main = AXAttribute(rawValue: kAXMainAttribute)
    public static let minimized = AXAttribute(rawValue: kAXMinimizedAttribute)
    public static let closeButton = AXAttribute(rawValue: kAXCloseButtonAttribute)
    public static let zoomButton = AXAttribute(rawValue: kAXZoomButtonAttribute)
    public static let fullScreenButton = AXAttribute(rawValue: kAXFullScreenButtonAttribute)
    public static let minimizeButton = AXAttribute(rawValue: kAXMinimizeButtonAttribute)
    public static let toolbarButton = AXAttribute(rawValue: kAXToolbarButtonAttribute)
    public static let proxy = AXAttribute(rawValue: kAXProxyAttribute)
    public static let growArea = AXAttribute(rawValue: kAXGrowAreaAttribute)
    public static let modal = AXAttribute(rawValue: kAXModalAttribute)
    public static let defaultButton = AXAttribute(rawValue: kAXDefaultButtonAttribute)
    public static let cancelButton = AXAttribute(rawValue: kAXCancelButtonAttribute)

    // Menu or menu item-specific attributes
    public static let menuItemCmdChar = AXAttribute(rawValue: kAXMenuItemCmdCharAttribute)
    public static let menuItemCmdVirtualKey = AXAttribute(rawValue: kAXMenuItemCmdVirtualKeyAttribute)
    public static let menuItemCmdGlyph = AXAttribute(rawValue: kAXMenuItemCmdGlyphAttribute)
    public static let menuItemCmdModifiers = AXAttribute(rawValue: kAXMenuItemCmdModifiersAttribute)
    public static let menuItemMarkChar = AXAttribute(rawValue: kAXMenuItemMarkCharAttribute)
    public static let menuItemPrimaryUIElement = AXAttribute(rawValue: kAXMenuItemPrimaryUIElementAttribute)

    // Application element-specific attributes
    public static let menuBar = AXAttribute(rawValue: kAXMenuBarAttribute)
    public static let windows = AXAttribute(rawValue: kAXWindowsAttribute)
    public static let frontmost = AXAttribute(rawValue: kAXFrontmostAttribute)
    public static let hidden = AXAttribute(rawValue: kAXHiddenAttribute)
    public static let mainWindow = AXAttribute(rawValue: kAXMainWindowAttribute)
    public static let focusedWindow = AXAttribute(rawValue: kAXFocusedWindowAttribute)
    public static let focusedUIElement = AXAttribute(rawValue: kAXFocusedUIElementAttribute)
    public static let extrasMenuBar = AXAttribute(rawValue: kAXExtrasMenuBarAttribute)

    // Date/time-specific attributes
    public static let hourField = AXAttribute(rawValue: kAXHourFieldAttribute)
    public static let minuteField = AXAttribute(rawValue: kAXMinuteFieldAttribute)
    public static let secondField = AXAttribute(rawValue: kAXSecondFieldAttribute)
    public static let ampmField = AXAttribute(rawValue: kAXAMPMFieldAttribute)
    public static let dayField = AXAttribute(rawValue: kAXDayFieldAttribute)
    public static let monthField = AXAttribute(rawValue: kAXMonthFieldAttribute)
    public static let yearField = AXAttribute(rawValue: kAXYearFieldAttribute)

    // Table, outline, or browser-specific attributes
    public static let rows = AXAttribute(rawValue: kAXRowsAttribute)
    public static let visibleRows = AXAttribute(rawValue: kAXVisibleRowsAttribute)
    public static let selectedRows = AXAttribute(rawValue: kAXSelectedRowsAttribute)
    public static let columns = AXAttribute(rawValue: kAXColumnsAttribute)
    public static let visibleColumns = AXAttribute(rawValue: kAXVisibleColumnsAttribute)
    public static let selectedColumns = AXAttribute(rawValue: kAXSelectedColumnsAttribute)
    public static let sortDirection = AXAttribute(rawValue: kAXSortDirectionAttribute)
    public static let columnHeaderUIElements = AXAttribute(rawValue: kAXColumnHeaderUIElementsAttribute)
    public static let index = AXAttribute(rawValue: kAXIndexAttribute)
    public static let disclosing = AXAttribute(rawValue: kAXDisclosingAttribute)
    public static let disclosedRows = AXAttribute(rawValue: kAXDisclosedRowsAttribute)
    public static let disclosedByRow = AXAttribute(rawValue: kAXDisclosedByRowAttribute)

    // Matte-specific attributes
    public static let matteHole = AXAttribute(rawValue: kAXMatteHoleAttribute)
    public static let matteContentUIElement = AXAttribute(rawValue: kAXMatteContentUIElementAttribute)

    // Ruler-specific attributes
    public static let markerUIElements = AXAttribute(rawValue: kAXMarkerUIElementsAttribute)
    public static let units = AXAttribute(rawValue: kAXUnitsAttribute)
    public static let unitDescription = AXAttribute(rawValue: kAXUnitDescriptionAttribute)
    public static let markerType = AXAttribute(rawValue: kAXMarkerTypeAttribute)
    public static let markerTypeDescription = AXAttribute(rawValue: kAXMarkerTypeDescriptionAttribute)

    // Miscellaneous or role-specific attributes
    public static let horizontalScrollBar = AXAttribute(rawValue: kAXHorizontalScrollBarAttribute)
    public static let verticalScrollBar = AXAttribute(rawValue: kAXVerticalScrollBarAttribute)
    public static let orientation = AXAttribute(rawValue: kAXOrientationAttribute)
    public static let header = AXAttribute(rawValue: kAXHeaderAttribute)
    public static let edited = AXAttribute(rawValue: kAXEditedAttribute)
    public static let tabs = AXAttribute(rawValue: kAXTabsAttribute)
    public static let overflowButton = AXAttribute(rawValue: kAXOverflowButtonAttribute)
    public static let filename = AXAttribute(rawValue: kAXFilenameAttribute)
    public static let expanded = AXAttribute(rawValue: kAXExpandedAttribute)
    public static let selected = AXAttribute(rawValue: kAXSelectedAttribute)
    public static let splitters = AXAttribute(rawValue: kAXSplittersAttribute)
    public static let contents = AXAttribute(rawValue: kAXContentsAttribute)
    public static let nextContents = AXAttribute(rawValue: kAXNextContentsAttribute)
    public static let previousContents = AXAttribute(rawValue: kAXPreviousContentsAttribute)
    public static let document = AXAttribute(rawValue: kAXDocumentAttribute)
    public static let incrementor = AXAttribute(rawValue: kAXIncrementorAttribute)
    public static let decrementButton = AXAttribute(rawValue: kAXDecrementButtonAttribute)
    public static let incrementButton = AXAttribute(rawValue: kAXIncrementButtonAttribute)
    public static let columnTitle = AXAttribute(rawValue: kAXColumnTitleAttribute)
    public static let url = AXAttribute(rawValue: kAXURLAttribute)
    public static let labelUIElements = AXAttribute(rawValue: kAXLabelUIElementsAttribute)
    public static let labelValue = AXAttribute(rawValue: kAXLabelValueAttribute)
    public static let shownMenuUIElement = AXAttribute(rawValue: kAXShownMenuUIElementAttribute)
    public static let isApplicationRunning = AXAttribute(rawValue: kAXIsApplicationRunningAttribute)
    public static let focusedApplication = AXAttribute(rawValue: kAXFocusedApplicationAttribute)
    public static let elementBusy = AXAttribute(rawValue: kAXElementBusyAttribute)
    public static let alternateUIVisible = AXAttribute(rawValue: kAXAlternateUIVisibleAttribute)
    
    // Undocumented attributes
    
    /// Enable additional metadata for VoiceOver.
    public static let enhancedUserInterface = AXAttribute(rawValue: "AXEnhancedUserInterface")
    /// Enable accessibility with Electron apps.
    /// See https://github.com/electron/electron/pull/10305
    public static let manualAccessibility = AXAttribute(rawValue: "AXManualAccessibility")

    // MARK: - Parameterized attributes

    // Text suite parameterized attributes
    public static let lineForIndex = AXAttribute(rawValue: kAXLineForIndexParameterizedAttribute)
    public static let rangeForLine = AXAttribute(rawValue: kAXRangeForLineParameterizedAttribute)
    public static let stringForRange = AXAttribute(rawValue: kAXStringForRangeParameterizedAttribute)
    public static let rangeForPosition = AXAttribute(rawValue: kAXRangeForPositionParameterizedAttribute)
    public static let rangeForIndex = AXAttribute(rawValue: kAXRangeForIndexParameterizedAttribute)
    public static let boundsForRange = AXAttribute(rawValue: kAXBoundsForRangeParameterizedAttribute)
    public static let rtfForRange = AXAttribute(rawValue: kAXRTFForRangeParameterizedAttribute)
    public static let attributedStringForRange = AXAttribute(rawValue: kAXAttributedStringForRangeParameterizedAttribute)
    public static let styleRangeForIndex = AXAttribute(rawValue: kAXStyleRangeForIndexParameterizedAttribute)

    // Cell-based table parameterized attributes
    public static let cellForColumnAndRow = AXAttribute(rawValue: kAXCellForColumnAndRowParameterizedAttribute)

    // Layout area parameterized attributes
    public static let layoutPointForScreenPoint = AXAttribute(rawValue: kAXLayoutPointForScreenPointParameterizedAttribute)
    public static let layoutSizeForScreenSize = AXAttribute(rawValue: kAXLayoutSizeForScreenSizeParameterizedAttribute)
    public static let screenPointForLayoutPoint = AXAttribute(rawValue: kAXScreenPointForLayoutPointParameterizedAttribute)
    public static let screenSizeForLayoutSize = AXAttribute(rawValue: kAXScreenSizeForLayoutSizeParameterizedAttribute)
}

extension AXAttribute: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

public struct AXRole: Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let application = AXRole(rawValue: kAXApplicationRole)
    public static let systemWide = AXRole(rawValue: kAXSystemWideRole)
    public static let window = AXRole(rawValue: kAXWindowRole)
    public static let sheet = AXRole(rawValue: kAXSheetRole)
    public static let drawer = AXRole(rawValue: kAXDrawerRole)
    public static let growArea = AXRole(rawValue: kAXGrowAreaRole)
    public static let image = AXRole(rawValue: kAXImageRole)
    public static let unknown = AXRole(rawValue: kAXUnknownRole)
    public static let button = AXRole(rawValue: kAXButtonRole)
    public static let radioButton = AXRole(rawValue: kAXRadioButtonRole)
    public static let checkBox = AXRole(rawValue: kAXCheckBoxRole)
    public static let popUpButton = AXRole(rawValue: kAXPopUpButtonRole)
    public static let menuButton = AXRole(rawValue: kAXMenuButtonRole)
    public static let tabGroup = AXRole(rawValue: kAXTabGroupRole)
    public static let table = AXRole(rawValue: kAXTableRole)
    public static let column = AXRole(rawValue: kAXColumnRole)
    public static let row = AXRole(rawValue: kAXRowRole)
    public static let outline = AXRole(rawValue: kAXOutlineRole)
    public static let browser = AXRole(rawValue: kAXBrowserRole)
    public static let scrollArea = AXRole(rawValue: kAXScrollAreaRole)
    public static let scrollBar = AXRole(rawValue: kAXScrollBarRole)
    public static let radioGroup = AXRole(rawValue: kAXRadioGroupRole)
    public static let list = AXRole(rawValue: kAXListRole)
    public static let group = AXRole(rawValue: kAXGroupRole)
    public static let valueIndicator = AXRole(rawValue: kAXValueIndicatorRole)
    public static let comboBox = AXRole(rawValue: kAXComboBoxRole)
    public static let slider = AXRole(rawValue: kAXSliderRole)
    public static let incrementor = AXRole(rawValue: kAXIncrementorRole)
    public static let busyIndicator = AXRole(rawValue: kAXBusyIndicatorRole)
    public static let progressIndicator = AXRole(rawValue: kAXProgressIndicatorRole)
    public static let relevanceIndicator = AXRole(rawValue: kAXRelevanceIndicatorRole)
    public static let toolbar = AXRole(rawValue: kAXToolbarRole)
    public static let disclosureTriangle = AXRole(rawValue: kAXDisclosureTriangleRole)
    public static let textField = AXRole(rawValue: kAXTextFieldRole)
    public static let textArea = AXRole(rawValue: kAXTextAreaRole)
    public static let staticText = AXRole(rawValue: kAXStaticTextRole)
    public static let heading = AXRole(rawValue: kAXHeadingRole)
    public static let menuBar = AXRole(rawValue: kAXMenuBarRole)
    public static let menuBarItem = AXRole(rawValue: kAXMenuBarItemRole)
    public static let menu = AXRole(rawValue: kAXMenuRole)
    public static let menuItem = AXRole(rawValue: kAXMenuItemRole)
    public static let splitGroup = AXRole(rawValue: kAXSplitGroupRole)
    public static let splitter = AXRole(rawValue: kAXSplitterRole)
    public static let colorWell = AXRole(rawValue: kAXColorWellRole)
    public static let timeField = AXRole(rawValue: kAXTimeFieldRole)
    public static let dateField = AXRole(rawValue: kAXDateFieldRole)
    public static let helpTag = AXRole(rawValue: kAXHelpTagRole)
    public static let matte = AXRole(rawValue: kAXMatteRole)
    public static let dockItem = AXRole(rawValue: kAXDockItemRole)
    public static let ruler = AXRole(rawValue: kAXRulerRole)
    public static let rulerMarker = AXRole(rawValue: kAXRulerMarkerRole)
    public static let grid = AXRole(rawValue: kAXGridRole)
    public static let levelIndicator = AXRole(rawValue: kAXLevelIndicatorRole)
    public static let cell = AXRole(rawValue: kAXCellRole)
    public static let layoutArea = AXRole(rawValue: kAXLayoutAreaRole)
    public static let layoutItem = AXRole(rawValue: kAXLayoutItemRole)
    public static let handle = AXRole(rawValue: kAXHandleRole)
    public static let popover = AXRole(rawValue: kAXPopoverRole)
}

public struct AXSubrole: Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    // Standard subroles

    public static let closeButton = AXSubrole(rawValue: kAXCloseButtonSubrole)
    public static let minimizeButton = AXSubrole(rawValue: kAXMinimizeButtonSubrole)
    public static let zoomButton = AXSubrole(rawValue: kAXZoomButtonSubrole)
    public static let toolbarButton = AXSubrole(rawValue: kAXToolbarButtonSubrole)
    public static let full = AXSubrole(rawValue: kAXFullScreenButtonSubrole)
    public static let secureTextField = AXSubrole(rawValue: kAXSecureTextFieldSubrole)
    public static let tableRow = AXSubrole(rawValue: kAXTableRowSubrole)
    public static let outlineRow = AXSubrole(rawValue: kAXOutlineRowSubrole)
    public static let unknown = AXSubrole(rawValue: kAXUnknownSubrole)

    // New subroles

    public static let standardWindow = AXSubrole(rawValue: kAXStandardWindowSubrole)
    public static let dialog = AXSubrole(rawValue: kAXDialogSubrole)
    public static let systemDialog = AXSubrole(rawValue: kAXSystemDialogSubrole)
    public static let floatingWindow = AXSubrole(rawValue: kAXFloatingWindowSubrole)
    public static let systemFloatingWindow = AXSubrole(rawValue: kAXSystemFloatingWindowSubrole)
    public static let decorative = AXSubrole(rawValue: kAXDecorativeSubrole)
    public static let incrementArrow = AXSubrole(rawValue: kAXIncrementArrowSubrole)
    public static let decrementArrow = AXSubrole(rawValue: kAXDecrementArrowSubrole)
    public static let incrementPage = AXSubrole(rawValue: kAXIncrementPageSubrole)
    public static let decrementPage = AXSubrole(rawValue: kAXDecrementPageSubrole)
    public static let sortButton = AXSubrole(rawValue: kAXSortButtonSubrole)
    public static let searchField = AXSubrole(rawValue: kAXSearchFieldSubrole)
    public static let timeline = AXSubrole(rawValue: kAXTimelineSubrole)
    public static let ratingIndicator = AXSubrole(rawValue: kAXRatingIndicatorSubrole)
    public static let contentList = AXSubrole(rawValue: kAXContentListSubrole)
    // Superseded by kAXDescriptionListSubrole in OS X 10.9
    public static let definitionList = AXSubrole(rawValue: kAXDefinitionListSubrole)
    // OS X 10.9 and later
    public static let descriptionList = AXSubrole(rawValue: kAXDescriptionListSubrole)
    public static let toggle = AXSubrole(rawValue: kAXToggleSubrole)
    public static let `switch` = AXSubrole(rawValue: kAXSwitchSubrole)

    // Dock subroles

    public static let applicationDockItem = AXSubrole(rawValue: kAXApplicationDockItemSubrole)
    public static let documentDockItem = AXSubrole(rawValue: kAXDocumentDockItemSubrole)
    public static let folderDockItem = AXSubrole(rawValue: kAXFolderDockItemSubrole)
    public static let minimizedWindowDockItem = AXSubrole(rawValue: kAXMinimizedWindowDockItemSubrole)
    public static let urlDockItem = AXSubrole(rawValue: kAXURLDockItemSubrole)
    public static let dockExtraDockItem = AXSubrole(rawValue: kAXDockExtraDockItemSubrole)
    public static let trashDockItem = AXSubrole(rawValue: kAXTrashDockItemSubrole)
    public static let separatorDockItem = AXSubrole(rawValue: kAXSeparatorDockItemSubrole)
    public static let process = AXSubrole(rawValue: kAXProcessSwitcherListSubrole)
}
