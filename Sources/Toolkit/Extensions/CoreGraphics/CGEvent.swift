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

import CoreGraphics
import Foundation
import Sauce

public extension CGEvent {
    /// Returns the title for this event key.
    var key: String? {
        Sauce.shared.character(
            for: Int(getIntegerValueField(.keyboardEventKeycode)),
            carbonModifiers: Int(flags.rawValue)
        )
    }

    /// Returns the unicode character for this event key.
    var character: String {
        let maxStringLength = 4
        var actualStringLength = 0
        var unicodeString = [UniChar](repeating: 0, count: Int(maxStringLength))
        keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
        return String(utf16CodeUnits: &unicodeString, count: Int(actualStringLength))
    }
}
