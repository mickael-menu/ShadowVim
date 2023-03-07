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

import AppKit
import Foundation
import MessagePack
import Toolkit

/// Ex command options table
///
/// See https://neovim.io/doc/user/api.html#nvim_parse_cmd()
public struct CmdOptions {
    /// Whether command contains a `<bang>` (!) modifier.
    public var bang: Bool
    /// Command arguments.
    public var args: [ValueConvertible]

    public init(bang: Bool = false, args: [ValueConvertible]) {
        self.bang = bang
        self.args = args
    }

    public init(bang: Bool = false, with args: ValueConvertible...) {
        self.init(bang: bang, args: args)
    }
}

public class API {
    private let logger: Logger?
    private let sendRequest: (RPCRequest) -> Async<Value, RPCError>

    init(
        logger: Logger?,
        sendRequest: @escaping (RPCRequest) -> Async<Value, RPCError>
    ) {
        self.logger = logger
        self.sendRequest = sendRequest
    }

    public func command(_ command: String) -> Async<Value, NvimError> {
        request("nvim_command", with: command)
    }

    public func cmd(_ cmd: String, with args: ValueConvertible..., output: Bool = true) -> Async<String, NvimError> {
        self.cmd(cmd, opts: CmdOptions(args: args), output: output)
    }

    public func cmd(_ cmd: String, opts: CmdOptions, output: Bool = true) -> Async<String, NvimError> {
        request("nvim_cmd", with: [
            [
                "cmd": cmd.nvimValue,
                "bang": opts.bang.nvimValue,
                "args": opts.args.map(\.nvimValue).nvimValue,
            ],
            [
                "output": output,
            ],
        ])
        .checkedUnpacking { $0.stringValue }
    }

    public func exec(_ src: String, output: Bool = true) -> Async<String, NvimError> {
        request("nvim_exec", with: [src, output])
            .checkedUnpacking { $0.stringValue }
    }

    /// Calls a VimL function with the given arguments.
    /// https://neovim.io/doc/user/api.html#nvim_call_function()
    public func callFunction<UnpackedValue>(
        _ fn: String,
        with args: ValueConvertible...,
        unpack: @escaping (Value) -> UnpackedValue? = { $0 }
    ) -> Async<UnpackedValue, NvimError> {
        callFunction(fn, args: args, unpack: unpack)
    }

    /// Calls a VimL function with the given arguments.
    /// https://neovim.io/doc/user/api.html#nvim_call_function()
    public func callFunction<UnpackedValue>(
        _ fn: String,
        args: [ValueConvertible],
        unpack: @escaping (Value) -> UnpackedValue? = { $0 }
    ) -> Async<UnpackedValue, NvimError> {
        request("nvim_call_function", with: [fn, args.map(\.nvimValue)])
            .flatMap { payload in
                guard let value = unpack(payload) else {
                    return .failure(.unexpectedResult(payload: payload))
                }
                return .success(value)
            }
    }

    /// Evaluates a VimL expression.
    /// https://neovim.io/doc/user/api.html#nvim_eval()
    public func eval<UnpackedValue>(
        _ expr: String,
        unpack: @escaping (Value) -> UnpackedValue? = { $0 }
    ) -> Async<UnpackedValue, NvimError> {
        request("nvim_eval", with: expr)
            .flatMap { payload in
                guard let value = unpack(payload) else {
                    return .failure(.unexpectedResult(payload: payload))
                }
                return .success(value)
            }
    }

    public func getCurrentBuf() -> Async<BufferHandle, NvimError> {
        request("nvim_get_current_buf")
            .checkedUnpacking { $0.bufferValue }
    }

    public func createBuf(listed: Bool, scratch: Bool) -> Async<BufferHandle, NvimError> {
        request("nvim_create_buf", with: [
            listed,
            scratch,
        ])
        .checkedUnpacking {
            guard let buf = $0.bufferValue, buf > 0 else {
                return nil
            }
            return buf
        }
    }

    public func bufAttach(buffer: BufferHandle, sendBuffer: Bool) -> Async<Bool, NvimError> {
        request("nvim_buf_attach", with: [
            Value.buffer(buffer),
            sendBuffer,
            [:] as [String: Value], // options
        ])
        .checkedUnpacking { $0.boolValue }
    }

    public func bufSetName(buffer: BufferHandle = 0, name: String) -> Async<Void, NvimError> {
        request("nvim_buf_set_name", with: [
            Value.buffer(buffer),
            name,
        ])
        .discardResult()
    }

    public func bufGetLines(
        buffer: BufferHandle = 0,
        start: LineIndex,
        end: LineIndex,
        strictIndexing: Bool = true
    ) -> Async<[String], NvimError> {
        request("nvim_buf_get_lines", with: [
            Value.buffer(buffer),
            start,
            end,
            strictIndexing,
        ])
        .checkedUnpacking { $0.arrayValue?.compactMap(\.stringValue) }
    }

    /// Clearing:
    ///     bufSetLines(start: 0, end: -1, replacement: [])
    ///
    /// Replacing:
    ///     bufSetLines(start: 0, end: -1, replacement: ["foo", "bar"])
    ///
    /// Appending:
    ///     bufSetLines(start: -1, end: -1, replacement: ["foo", "bar"])
    public func bufSetLines<S: StringProtocol>(
        buffer: BufferHandle = 0,
        start: LineIndex,
        end: LineIndex,
        strictIndexing: Bool = true,
        replacement: [S]
    ) -> Async<Void, NvimError> {
        request("nvim_buf_set_lines", with: [
            Value.buffer(buffer),
            start,
            end,
            strictIndexing,
            replacement.map { String($0) },
        ])
        .discardResult()
    }

    /// Pastes at cursor, in any mode.
    /// https://neovim.io/doc/user/api.html#nvim_paste()
    public func paste(_ data: String) -> Async<Void, NvimError> {
        request("nvim_paste", with: [
            data,
            false, // crlf
            -1, // phase
        ])
        .discardResult()
    }

    public func winGetWidth(_ window: WindowHandle = 0) -> Async<Int, NvimError> {
        request("nvim_win_get_width", with: Value.window(window))
            .checkedUnpacking { $0.intValue }
    }

    public func winGetCursor(_ window: WindowHandle = 0) -> Async<Value, NvimError> {
        request("nvim_win_get_cursor", with: Value.window(window))
    }

    public func winSetCursor(
        _ window: WindowHandle = 0,
        position: BufferPosition,
        failOnInvalidPosition: Bool = true
    ) -> Async<Void, NvimError> {
        request("nvim_win_set_cursor", with: [
            Value.window(window),
            [
                // win_set_cursor is (1,0)-indexed.
                position.line,
                position.column - 1,
            ],
        ])
        .discardResult()
        .catch { error in
            if !failOnInvalidPosition, case .apiFailed(.validation) = error {
                return .success(())
            } else {
                return .failure(error)
            }
        }
    }

    public func input(_ keyCombo: KeyCombo) -> Async<Int, NvimError> {
        request("nvim_input", with: keyCombo.nvimNotation)
            .checkedUnpacking { $0.intValue }
    }

    public func input(_ keys: String) -> Async<Int, NvimError> {
        var keys = keys
        // Note: keycodes like <CR> are translated, so "<" is special.
        // To input a literal "<", send <LT>.
        if keys == "<" {
            keys = "<LT>"
        }

        return request("nvim_input", with: keys)
            .checkedUnpacking { $0.intValue }
    }

    public func subscribe(to event: String) -> Async<Void, NvimError> {
        request("nvim_subscribe", with: event)
            .discardResult()
    }

    public func unsubscribe(from event: String) -> Async<Void, NvimError> {
        request("nvim_unsubscribe", with: event)
            .discardResult()
    }

    public func evalStatusline(_ str: String) -> Async<String, NvimError> {
        request("nvim_eval_statusline", with: str, [:] as [String: Value])
            .checkedUnpacking { $0.dictValue?[.string("str")]?.stringValue }
    }

    public func createAutocmd(
        for event: String,
        once: Bool = false,
        command: String
    ) -> Async<AutocmdID, NvimError> {
        createAutocmd(for: [event], once: once, command: command)
    }

    public func createAutocmd(
        for events: [String],
        once: Bool = false,
        command: String
    ) -> Async<AutocmdID, NvimError> {
        request("nvim_create_autocmd", with: [
            events,
            [
                "once": once.nvimValue,
                "command": command.nvimValue,
            ],
        ])
        .checkedUnpacking { $0.intValue }
    }

    public func delAutocmd(_ id: AutocmdID) -> Async<Void, NvimError> {
        request("nvim_del_autocmd", with: id)
            .discardResult()
    }

    /// https://neovim.io/doc/user/ui.html#ui-option
    public struct UIOptions {
        /// Decides the color format.
        /// https://neovim.io/doc/user/ui.html#ui-rgb
        public let rgb: Bool

        /// Decides how UI capabilities are resolved.
        /// https://neovim.io/doc/user/ui.html#ui-override
        public let override: Bool

        /// Externalize the cmdline.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extCmdline: Bool

        /// Detailed highlight state.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extHlState: Bool

        /// Line-based grid events.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extLineGrid: Bool

        /// Externalize messages.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extMessages: Bool

        /// Per-window grid events.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extMultigrid: Bool

        /// Externalize popupmenu-completion and 'wildmenu'.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extPopupMenu: Bool

        /// Externalize the tabline.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extTabline: Bool

        /// Use external default colors.
        /// https://neovim.io/doc/user/ui.html#ui-ext-options
        public let extTermColors: Bool

        public init(
            rgb: Bool = true,
            override: Bool = false,
            extCmdline: Bool = false,
            extHlState: Bool = false,
            extLineGrid: Bool = false,
            extMessages: Bool = false,
            extMultigrid: Bool = false,
            extPopupMenu: Bool = false,
            extTabline: Bool = false,
            extTermColors: Bool = false
        ) {
            self.rgb = rgb
            self.override = override
            self.extCmdline = extCmdline
            self.extHlState = extHlState
            self.extLineGrid = extLineGrid
            self.extMessages = extMessages
            self.extMultigrid = extMultigrid
            self.extPopupMenu = extPopupMenu
            self.extTabline = extTabline
            self.extTermColors = extTermColors
        }
    }

    /// https://neovim.io/doc/user/api.html#nvim_ui_attach()
    public func uiAttach(width: Int, height: Int, options: UIOptions) -> Async<Void, NvimError> {
        request("nvim_ui_attach", with: [
            width, height,
            [
                "rgb": options.rgb,
                "override": options.override,
                "ext_cmdline": options.extCmdline,
                "ext_hlstate": options.extHlState,
                "ext_linegrid": options.extLineGrid,
                "ext_messages": options.extMessages,
                "ext_multigrid": options.extMultigrid,
                "ext_popupmenu": options.extPopupMenu,
                "ext_tabline": options.extTabline,
                "ext_termcolors": options.extTermColors,
            ],
        ])
        .discardResult()
    }

    @discardableResult
    public func request(_ method: String, with params: ValueConvertible...) -> Async<Value, NvimError> {
        request(method, with: params)
    }

    @discardableResult
    public func request(_ method: String, with params: [ValueConvertible]) -> Async<Value, NvimError> {
        logger?.t("Call Nvim API: \(method)", [.params: params.map(\.nvimValue)])

        return sendRequest((method: method, params: params))
            .mapError { .apiFailed(APIError(from: $0)) }
    }
}

public enum APIError: Error {
    case exception(message: String)
    case validation(message: String)
    // When Nvim sends an unknown error in an RPC response.
    case unexpectedResponseError(content: Value)
    // When Nvim returns an unexpected result for the request `method`.
    case unexpectedResult(Value)
    // A low-level RPC failure occurred.
    case rpcFailure(RPCError)
    // The RPC session is closed.
    case rpcSessionClosed

    init(from error: RPCError) {
        switch error {
        case let .responseError(content):
            guard
                let array = content.arrayValue,
                array.count == 2,
                let type = array[0].intValue,
                let message = array[1].stringValue
            else {
                self = .unexpectedResponseError(content: content)
                return
            }

            // https://github.com/neovim/neovim/blob/266a1c61b97313f2a516140fc691dd8be8eed47a/src/nvim/api/private/defs.h#L26-L31
            switch type {
            case 0:
                self = .exception(message: message)
            case 1:
                self = .validation(message: message)
            default:
                self = .unexpectedResponseError(content: content)
            }
        default:
            self = .rpcFailure(error)
        }
    }
}

extension Async where Success == Value, Failure == NvimError {
    func checkedUnpacking<NewSuccess>(transform: @escaping (Success) -> NewSuccess?) -> Async<NewSuccess, NvimError> {
        flatMap {
            guard let res = transform($0) else {
                return .failure(.apiFailed(.unexpectedResult($0)))
            }
            return .success(res)
        }
    }
}

private extension LogKey {
    static var method: LogKey { "method" }
    static var params: LogKey { "params" }
}
