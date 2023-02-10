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
import Toolkit

public final class NvimContainer {
    let logger: Logger?

    public init(logger: Logger?) {
        self.logger = logger?.domain("nvim")
            .filter(minimumLevel: .trace)
    }

    public func nvim() throws -> Nvim {
        let process = try NvimProcess.start(logger: logger?.domain("process"))

        let session = RPCSession(
            logger: logger?.domain("rpc"),
            input: process.input,
            output: process.output
        )

        let api = API(
            session: session,
            logger: logger?.domain("api")
        )

        return Nvim(
            process: process,
            session: session,
            api: api,
            events: EventDispatcher(
                api: api,
                logger: logger?.domain("events")
            ),
            logger: logger
        )
    }
}
