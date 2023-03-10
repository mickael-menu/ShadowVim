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

import Foundation

protocol Preferences: AnyObject {
    /// Indicates whether ShadowVim was added to the system Login Items, to be launched on startup.
    var isAddedToLoginItems: Bool { get set }
}

final class UserDefaultsPreferences: Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults.standard) {
        self.defaults = defaults
    }

    var isAddedToLoginItems: Bool {
        get { defaults.bool(forKey: Keys.isAddedToLoginItems) }
        set { defaults.set(newValue, forKey: Keys.isAddedToLoginItems) }
    }

    private enum Keys {
        static let isAddedToLoginItems = "isAddedToLoginItems"
    }
}
