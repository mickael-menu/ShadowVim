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
    let preferences: Preferences
    let logger: Logger?
    private(set) var shadowVim: ShadowVim!
    private var mediator: MediatorContainer!

    init() {
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
        self.logger = logger.domain("app")

        preferences = UserDefaultsPreferences(defaults: .standard)

        let keyResolver = SauceCGKeyResolver()

        mediator = MediatorContainer(
            keyResolver: keyResolver,
            logger: logger,
            enableKeysPassthrough: { [unowned self] in enableKeysPassthrough() },
            resetShadowVim: { [unowned self] in resetShadowVim() }
        )

        shadowVim = ShadowVim(
            preferences: preferences,
            keyResolver: keyResolver,
            logger: logger,
            setVerboseLogger: { logger.set(NSLoggerLogger()) },
            mediatorFactory: mediator.mainMediator
        )
    }

    private func enableKeysPassthrough() {
        DispatchQueue.main.async { [self] in
            shadowVim.setKeysPassthrough(true)
        }
    }

    private func resetShadowVim() {
        DispatchQueue.main.async { [self] in
            shadowVim.reset()
        }
    }
}
