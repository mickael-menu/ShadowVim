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

/// Swift wrapper around Vim's Ex commands.
///
/// https://neovim.io/doc/user/lua.html#vim.cmd()
@dynamicCallable
@dynamicMemberLookup
public final class ExCommands {
    private let api: API

    init(api: API) {
        self.api = api
    }

    /// Dynamic resolution for the Ex commands.
    public subscript(dynamicMember name: String) -> ExCommand {
        ExCommand(name: name, api: api)
    }

    /// Executes multiple lines of Vim script at once.
    ///
    /// This is an alias to `nvim_exec()`.
    public func dynamicallyCall(withArguments args: [String]) -> Async<Void, NvimError> {
        guard !args.isEmpty else {
            return .success(())
        }

        return api.exec(args.joinedLines(), output: false)
            .discardResult()
    }

    /// Defines a user command.
    ///
    /// https://neovim.io/doc/user/map.html#%3Acommand
    public func command(
        cmd: String,
        bang: Bool = false,
        args: ArgsCardinality = .none,
        repl: String
    ) -> Async<Void, NvimError> {
        api.cmd("command", opts: CmdOptions(
            bang: bang,
            args: ["-nargs=\(args.rawValue)", cmd, repl]
        ))
        .discardResult()
    }

    public enum ArgsCardinality: String {
        /// No arguments are allowed (the default).
        case none = "0"

        /// Exactly one argument is required, it includes spaces.
        case one = "1"

        /// Any number of arguments are allowed (0, 1, or many), separated by white space.
        case any = "*"

        /// 0 or 1 arguments are allowed.
        case noneOrOne = "?"

        /// Arguments must be supplied, but any number are allowed.
        case moreThanOne = "+"
    }
}

@dynamicCallable
public final class ExCommand {
    public let name: String
    private let api: API

    init(name: String, api: API) {
        self.name = name
        self.api = api
    }

    public func dynamicallyCall(withArguments args: [Any]) -> Async<String, NvimError> {
        if args.count == 1, let opts = args[0] as? CmdOptions {
            return api.cmd(name, opts: opts)
        } else if let args = args as? [ValueConvertible] {
            return api.cmd(name, opts: CmdOptions(args: args))
        } else {
            preconditionFailure("Unsupported arguments")
        }
    }
}
