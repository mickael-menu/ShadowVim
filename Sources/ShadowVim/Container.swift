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
import Mediator
import NSLoggerAdapter
import SauceAdapter
import Toolkit

final class Container {
    let shadowVim: ShadowVim
    let preferences: Preferences
    let logger: Logger?
    private let mediator: MediatorContainer

    init() {
        let preferences = UserDefaultsPreferences(defaults: .standard)
        let logger = ReferenceLogger(logger:
            Debug.isDebugging
                ? NSLoggerLogger().filter(
                    minimumLevel: .warning,
                    domains: [
                        "app",
                        "ax",
                        "mediator",
                        "mediator.main",
                        "mediator.app",
                        "mediator.buffer",
                        "nvim",
                        "nvim.api",
                        "!nvim.api.lock",
                        "!nvim.rpc",
                        "!nvim.events",
                    ]
                )
                : nil
        )

        let mediator = MediatorContainer(
            logger: logger
        )

        self.logger = logger.domain("app")
        self.preferences = preferences
        self.mediator = mediator
        shadowVim = ShadowVim(
            preferences: preferences,
            keyResolver: SauceCGKeyResolver(),
            logger: logger,
            setVerboseLogger: { logger.set(NSLoggerLogger()) },
            mediatorFactory: mediator.mainMediator
        )
    }
}
