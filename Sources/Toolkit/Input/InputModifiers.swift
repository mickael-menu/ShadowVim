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

public struct InputModifiers: OptionSet, Hashable, CustomStringConvertible {
    public static let none = InputModifiers([])
    public static let shift = InputModifiers(rawValue: 1 << 0)
    public static let control = InputModifiers(rawValue: 1 << 1)
    public static let option = InputModifiers(rawValue: 1 << 2)
    public static let command = InputModifiers(rawValue: 1 << 3)
    public static let function = InputModifiers(rawValue: 1 << 4)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        var desc = ""
        if contains(.control) {
            desc += "⌃"
        }
        if contains(.option) {
            desc += "⌥"
        }
        if contains(.command) {
            desc += "⌘"
        }
        if contains(.shift) {
            desc += "⇧"
        }
        if contains(.function) {
            desc += "Fn"
        }
        return desc
    }
}
