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

public class API {
    /// The lock is used to protect calls to Nvim's API.
    ///
    /// Using the shared `Nvim.api` property, each call is in its own
    /// transaction. If you need to perform a sequence of `API` calls in a
    /// single atomic transaction, use `Api.transaction()`.
    private enum TransactionLevel {
        case root(lock: AsyncLock)
        case child(level: Int)

        func makeChild() -> TransactionLevel {
            switch self {
            case .root:
                return .child(level: 0)
            case let .child(level):
                return .child(level: level + 1)
            }
        }
    }

    private let session: RPCSession
    private let logger: Logger?
    private let transactionLevel: TransactionLevel

    convenience init(session: RPCSession, logger: Logger?) {
        self.init(
            session: session,
            logger: logger,
            transactionLevel: .root(lock: AsyncLock(logger: logger?.domain("lock")))
        )
    }

    private init(
        session: RPCSession,
        logger: Logger?,
        transactionLevel: TransactionLevel
    ) {
        self.session = session
        self.logger = logger?.with(.transaction, to: {
            switch transactionLevel {
            case .root:
                return "root"
            case let .child(level):
                return "child(\(level))"
            }
        }())
        self.transactionLevel = transactionLevel
    }

    /// Performs a sequence of `API` calls in a single atomic transaction.
    ///
    /// You must return an `Async` object completed when the transaction is
    /// done.
    public func transaction<Value, Failure>(
        _ block: @escaping (API) -> Async<Value, Failure>
    ) -> Async<Value, Failure> {
        switch transactionLevel {
        case let .root(lock: lock):
            return lock.acquire()
                .setFailureType(to: Failure.self)
                .flatMap { [self] in
                    block(API(session: session, logger: logger, transactionLevel: transactionLevel.makeChild()))
                }
                .mapError { $0 }
                .onCompletion { _ in
                    lock.release()
                }

        case .child:
            // Already in a transaction
            return block(self)
        }
    }

    public func command(_ command: String) -> APIAsync<Value> {
        request("nvim_command", with: command)
    }

    public func cmd(_ cmd: String, bang: Bool = false, args: Value...) -> APIAsync<String> {
        request("nvim_cmd", with: [
            [
                "cmd": cmd.nvimValue,
                "bang": bang.nvimValue,
                "args": args.nvimValue,
            ],
            [
                "output": true,
            ],
        ])
        .checkedUnpacking { $0.stringValue }
    }

    public func exec(_ src: String) -> APIAsync<String> {
        request("nvim_exec", with: [
            src,
            true, // output
        ])
        .checkedUnpacking { $0.stringValue }
    }

    public func getCurrentBuf() -> APIAsync<BufferHandle> {
        request("nvim_get_current_buf")
            .checkedUnpacking { $0.bufferValue }
    }

    public func createBuf(listed: Bool, scratch: Bool) -> APIAsync<BufferHandle> {
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

    public func bufAttach(buffer: BufferHandle, sendBuffer: Bool) -> APIAsync<Bool> {
        request("nvim_buf_attach", with: [
            Value.buffer(buffer),
            sendBuffer,
            [:] as [String: Value], // options
        ])
        .checkedUnpacking { $0.boolValue }
    }

    public func bufSetName(buffer: BufferHandle = 0, name: String) -> APIAsync<Void> {
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
    ) -> APIAsync<[String]> {
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
    ) -> APIAsync<Void> {
        request("nvim_buf_set_lines", with: [
            Value.buffer(buffer),
            start,
            end,
            strictIndexing,
            replacement.map { String($0) },
        ])
        .discardResult()
    }

    public func winGetWidth(_ window: WindowHandle = 0) -> APIAsync<Int> {
        request("nvim_win_get_width", with: Value.window(window))
            .checkedUnpacking { $0.intValue }
    }

    public func winGetCursor(_ window: WindowHandle = 0) -> APIAsync<Value> {
        request("nvim_win_get_cursor", with: Value.window(window))
    }

    public func winSetCursor(_ window: WindowHandle = 0, position: BufferPosition, failOnInvalidPosition: Bool = true) -> APIAsync<Void> {
        request("nvim_win_set_cursor", with: [
            Value.window(window),
            [
                position.line + 1,
                position.column,
            ],
        ])
        .discardResult()
        .catch { error in
            if !failOnInvalidPosition, case APIError.validation = error {
                return .success(())
            } else {
                return .failure(error)
            }
        }
    }

    public func input(_ keyCombo: KeyCombo) -> APIAsync<Int> {
        request("nvim_input", with: keyCombo.nvimNotation)
            .checkedUnpacking { $0.intValue }
    }

    public func input(_ keys: String) -> APIAsync<Int> {
        var keys = keys
        // Note: keycodes like <CR> are translated, so "<" is special.
        // To input a literal "<", send <LT>.
        if keys == "<" {
            keys = "<LT>"
        }

        return request("nvim_input", with: keys)
            .checkedUnpacking { $0.intValue }
    }

    public func subscribe(to event: String) -> APIAsync<Void> {
        request("nvim_subscribe", with: event)
            .discardResult()
    }

    public func unsubscribe(from event: String) -> APIAsync<Void> {
        request("nvim_unsubscribe", with: event)
            .discardResult()
    }

    public func evalStatusline(_ str: String) -> APIAsync<String> {
        request("nvim_eval_statusline", with: str, [:] as [String: Value])
            .checkedUnpacking { $0.dictValue?[.string("str")]?.stringValue }
    }

    public func createAutocmd(
        for event: String,
        once: Bool = false,
        command: String
    ) -> APIAsync<AutocmdID> {
        createAutocmd(for: [event], once: once, command: command)
    }

    public func createAutocmd(
        for events: [String],
        once: Bool = false,
        command: String
    ) -> APIAsync<AutocmdID> {
        request("nvim_create_autocmd", with: [
            events,
            [
                "once": once.nvimValue,
                "command": command.nvimValue,
            ],
        ])
        .checkedUnpacking { $0.intValue }
    }

    public func delAutocmd(_ id: AutocmdID) -> APIAsync<Void> {
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
    public func uiAttach(width: Int, height: Int, options: UIOptions) -> APIAsync<Void> {
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
    public func request(_ method: String, with params: ValueConvertible...) -> APIAsync<Value> {
        request(method, with: params)
    }

    @discardableResult
    public func request(_ method: String, with params: [ValueConvertible]) -> APIAsync<Value> {
        logger?.t("Call Nvim API", [.method: method, .params: params.map(\.nvimValue)])

        let requestCallbacks: RPCRequestCallbacks = {
            switch transactionLevel {
            case let .root(lock: lock):
                return RPCRequestCallbacks(
                    prepare: { lock.acquire() },
                    onSent: { lock.release() }
                )
            case .child:
                return RPCRequestCallbacks()
            }
        }()

        return session.request(method: method, params: params, callbacks: requestCallbacks)
            .mapError { APIError(from: $0) }
    }
}

public enum APIError: Error {
    case exception(message: String)
    case validation(message: String)
    // When Nvim sends an unknown error in an RPC response.
    case unexpectedResponseError(content: Value)
    // When Nvim returns an unexpected result for the request `method`.
    case unexpectedResult(Value)
    // When Nvim sends a notification with an unexpected payload.
    case unexpectedNotificationPayload(event: String, payload: [Value])
    // A low-level RPC failure occurred.
    case rpcFailure(RPCError)

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

public typealias APIAsync<Success> = Async<Success, APIError>

extension Async where Success == Value, Failure == APIError {
    func checkedUnpacking<NewSuccess>(transform: @escaping (Success) -> NewSuccess?) -> APIAsync<NewSuccess> {
        flatMap {
            guard let res = transform($0) else {
                return .failure(.unexpectedResult($0))
            }
            return .success(res)
        }
    }
}

private extension LogKey {
    static var method: LogKey { "method" }
    static var params: LogKey { "params" }
    static var transaction: LogKey { "@transaction" }
}
