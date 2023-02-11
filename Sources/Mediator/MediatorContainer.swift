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
    let logger: Logger?
    private let setVerboseLogger: () -> Void
    private let nvimContainer: NvimContainer

    public init(logger: Logger?, setVerboseLogger: @escaping () -> Void) {
        self.logger = logger?.domain("mediator")
            .filter(minimumLevel: .trace)

        self.setVerboseLogger = setVerboseLogger

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
            setVerboseLogger: setVerboseLogger,
            appMediatorFactory: appMediator
        )
    }

    func appMediator(app: NSRunningApplication) throws -> AppMediator {
        let nvim = try nvimContainer.nvim()
        return try AppMediator(
            app: app,
            nvim: nvim,
            buffers: NvimBuffers(
                events: nvim.events,
                logger: logger?.domain("nvim-buffers")
            ),
            logger: logger?.domain("app"),
            bufferMediatorFactory: bufferMediator
        )
    }

    func bufferMediator(
        nvim: Nvim,
        nvimBuffer: NvimBuffer,
        uiElement: AXUIElement,
        nvimCursorPublisher: AnyPublisher<Cursor, APIError>
    ) -> BufferMediator {
        BufferMediator(
            nvim: nvim,
            nvimBuffer: nvimBuffer,
            uiElement: uiElement,
            nvimCursorPublisher: nvimCursorPublisher,
            logger: logger?.domain("buffer.\(nvimBuffer.handle)")
                .with("path", to: nvimBuffer.name ?? "")
        )
    }
}
