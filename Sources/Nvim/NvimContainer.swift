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

/// Composition root for the Nvim module.
///
/// Manages dependencies and creates the objects.
public final class NvimContainer {
    let logger: Logger?

    public init(logger: Logger?) {
        self.logger = logger?.domain("nvim")
    }

    public func nvim() -> Nvim {
        Nvim(
            logger: logger?.domain("process"),
            runningStateFactory: runningState(process:pipes:)
        )
    }

    private func runningState(
        process: Process,
        pipes: (input: FileHandle, output: FileHandle)
    ) -> Nvim.RunningState {
        let session = RPCSession(
            logger: logger?.domain("rpc"),
            input: pipes.input,
            output: pipes.output
        )

        let vim = vim(
            session: session,
            lock: AsyncLock(logger: logger?.domain("lock"))
        )

        return Nvim.RunningState(
            process: process,
            session: session,
            vim: vim,
            events: EventDispatcher(
                api: vim.api,
                logger: logger?.domain("events")
            )
        )
    }

    private func vim(session: RPCSession, lock: AsyncLock?) -> Vim {
        Vim(
            api: API(
                logger: logger?.domain("api"),
                sendRequest: { request in
                    session.request(
                        request,
                        callbacks: lock.map {
                            RPCRequestCallbacks(
                                prepare: $0.acquire,
                                onSent: $0.release
                            )
                        } ?? .none
                    )
                }
            ),
            logger: logger,
            startTransaction: { [self] in
                let child = vim(session: session, lock: nil)
                if let lock = lock {
                    return lock.acquire()
                        .map { child }
                } else {
                    return .success(child)
                }
            },
            endTransaction: { lock?.release() }
        )
    }
}
