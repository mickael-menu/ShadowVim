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

import AppKit
import AX
import Combine
import Foundation
import Nvim
import Toolkit

public final class MediatorContainer {
    private let keyResolver: CGKeyResolver
    private let logger: Logger?
    private let enableKeysPassthrough: () -> Void
    private let resetShadowVim: () -> Void
    private let nvimContainer: NvimContainer

    public init(
        keyResolver: CGKeyResolver,
        logger: Logger?,
        enableKeysPassthrough: @escaping () -> Void,
        resetShadowVim: @escaping () -> Void
    ) {
        self.keyResolver = keyResolver
        self.logger = logger?.domain("mediator")
        self.enableKeysPassthrough = enableKeysPassthrough
        self.resetShadowVim = resetShadowVim

        nvimContainer = NvimContainer(logger: logger)

        AX.setLogger(logger?.domain("ax"))
    }

    public func mainMediator() -> MainMediator {
        MainMediator(
            bundleIDs: [
                "com.apple.dt.Xcode",
                // "com.apple.TextEdit",
                // "com.google.android.studio",
            ],
            logger: logger?.domain("main"),
            appMediatorFactory: appMediator
        )
    }

    func appMediator(app: NSRunningApplication) -> AppMediator {
        let nvimController = nvimController()

        return AppMediator(
            app: app,
            nvimController: nvimController,
            eventSource: EventSource(keyResolver: keyResolver),
            logger: logger?.domain("app"),
            bufferMediatorFactory: { buffer, element in
                BufferMediator(
                    nvimController: nvimController,
                    nvimBuffer: buffer,
                    uiElement: element,
                    logger: self.logger?.domain("buffer.\(buffer.handle)")
                        .with("path", to: buffer.name ?? "")
                )
            }
        )
    }

    func nvimController() -> NvimController {
        let logger = logger?.domain("nvim")
        let nvim = nvimContainer.nvim()
        return NvimController(
            nvim: nvim,
            buffers: NvimBuffers(
                nvim: nvim,
                logger: logger?.domain("buffers")
            ),
            logger: logger,
            enableKeysPassthrough: enableKeysPassthrough,
            resetShadowVim: resetShadowVim
        )
    }
}
