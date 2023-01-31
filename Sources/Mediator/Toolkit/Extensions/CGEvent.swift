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

extension CGEvent {
    /// Returns the Nvim-compatible key code for this keyboard event.
    var nvimKey: String {
        switch keyCode {
        case .escape:
            return "<Esc>"
        case .enter:
            return "<Enter>"
        case .leftArrow:
            return "<Left>"
        case .rightArrow:
            return "<Right>"
        case .downArrow:
            return "<Down>"
        case .upArrow:
            return "<Up>"
        default:
            return character
        }
    }
}
