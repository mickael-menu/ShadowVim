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

import Combine
import Foundation
import Nvim
import Toolkit

extension Nvim {
    /// Tells Nvim ShadowVim is ready to enable UI interactions.
    ///
    /// - Returns an async value which will be resolved once Nvim is fully
    /// started, after running the user configuration.
    func attachUI() -> Async<Void, NvimError> {
        guard let vim = vim else {
            return .failure(.notStarted)
        }

        return Async { [self] completion in
            var finished = false

            // According to the Nvim documentation, observing the VimEnter events
            // can be used to be notified when the user config is fully loaded after
            // attaching the UI.
            // See https://neovim.io/doc/user/ui.html#ui-startup
            let result = addRequestHandler(for: "vimenter") { _ in
                precondition(!finished)
                completion(.success(()))
                return .nil
            }
            guard case .success = result else {
                completion(result)
                return
            }

            vim.api.createAutocmd(
                for: "VimEnter",
                once: true,
                command: "call rpcrequest(1, 'vimenter')"
            )
            .flatMap { _ in
                vim.api.uiAttach(
                    width: 1000,
                    height: 100,
                    options: API.UIOptions(
                        extCmdline: true,
                        extHlState: false,
                        extLineGrid: true,
                        extMessages: true,
                        extMultigrid: true,
                        extPopupMenu: true,
                        extTabline: false,
                        extTermColors: false
                    )
                )
            }
            .discardResult()
            .get(onFailure: { error in
                precondition(!finished)
                finished = true
                completion(.failure(error))
            })
        }
    }
}
