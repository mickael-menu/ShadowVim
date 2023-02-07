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
import Mediator
import NSLoggerAdapter
import Nvim
import Toolkit

final class Container {
    let logger: Logger? = Debug.isDebugging
        ? NSLoggerLogger().filter(minimumLevel: .trace)
        : nil

    init() {
        AX.setLogger(logger?.domain("ax"))
    }

    lazy var app = App(
        mediator: mainMediator,
        logger: logger?.domain("app")
    )

    lazy var mainMediator = MainMediator(
        bundleIDs: [
            "com.apple.dt.Xcode",
//            "com.apple.TextEdit",
//            "com.google.android.studio",
        ],
        logger: logger?.domain("mediator.main"),
        appMediatorFactory: appMediator
    )

    func appMediator(app: NSRunningApplication) throws -> AppMediator {
        let nvim = try Nvim.start(logger: logger?.domain("nvim"))

        return try AppMediator(
            app: app,
            nvim: nvim,
            buffers: NvimBuffers(
                events: nvim.events,
                logger: logger?.domain("mediator.nvim.buffers")
            ),
            logger: logger?.domain("mediator.app"),
            bufferMediatorFactory: bufferMediator
        )
    }

    func bufferMediator(
        nvim: Nvim,
        nvimBuffer: NvimBuffer,
        uiElement: AXUIElement,
        name: String,
        nvimCursorPublisher: AnyPublisher<Cursor, APIError>
    ) -> BufferMediator {
        BufferMediator(
            nvim: nvim,
            nvimBuffer: nvimBuffer,
            uiElement: uiElement,
            name: name,
            nvimCursorPublisher: nvimCursorPublisher,
            logger: logger?.domain("mediator.buffer")
        )
    }
}
