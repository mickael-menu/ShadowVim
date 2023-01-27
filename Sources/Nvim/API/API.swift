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
    private let session: RPCSession
    private let requestCallbacks: RPCRequestCallbacks

    init(
        session: RPCSession,
        requestCallbacks: RPCRequestCallbacks = RPCRequestCallbacks()
    ) {
        self.session = session
        self.requestCallbacks = requestCallbacks
    }

    public func command(_ command: String) -> APIAsync<Value> {
        request("nvim_command", with: .string(command))
    }

    public func cmd(_ cmd: String, bang: Bool = false, args: Value...) -> APIAsync<String> {
        request("nvim_cmd", with: [
            .dict([
                .string("cmd"): .string(cmd),
                .string("bang"): .bool(bang),
                .string("args"): .array(args),
            ]),
            .dict([
                .string("output"): .bool(true),
            ]),
        ])
        .checkedUnpacking { $0.stringValue }
    }

    public func exec(_ src: String) -> APIAsync<String> {
        request("nvim_exec", with: [
            .string(src),
            .bool(true), // output
        ])
        .checkedUnpacking { $0.stringValue }
    }

    public func getCurrentBuf() -> APIAsync<BufferHandle> {
        request("nvim_get_current_buf")
            .checkedUnpacking { $0.bufferValue }
    }

    public func createBuf(listed: Bool, scratch: Bool) -> APIAsync<BufferHandle> {
        request("nvim_create_buf", with: [
            .bool(listed),
            .bool(scratch),
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
            .buffer(buffer),
            .bool(sendBuffer),
            .dict([:]), // options
        ])
        .checkedUnpacking { $0.boolValue }
    }

    public func bufSetName(buffer: BufferHandle = 0, name: String) -> APIAsync<Void> {
        request("nvim_buf_set_name", with: [
            .buffer(buffer),
            .string(name),
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
            .buffer(buffer),
            .int(start),
            .int(end),
            .bool(strictIndexing),
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
    public func bufSetLines(
        buffer: BufferHandle = 0,
        start: LineIndex,
        end: LineIndex,
        strictIndexing: Bool = true,
        replacement: [String]
    ) -> APIAsync<Void> {
        request("nvim_buf_set_lines", with: [
            .buffer(buffer),
            .int(start),
            .int(end),
            .bool(strictIndexing),
            .array(replacement.map { .string($0) }),
        ])
        .discardResult()
    }

    public func winGetWidth(_ window: WindowHandle = 0) -> APIAsync<Int> {
        request("nvim_win_get_width", with: .window(window))
            .checkedUnpacking { $0.intValue }
    }

    public func winGetCursor(_ window: WindowHandle = 0) -> APIAsync<Value> {
        request("nvim_win_get_cursor", with: .window(window))
    }

    public func input(_ keys: String) -> APIAsync<Int> {
        request("nvim_input", with: .string(keys))
            .checkedUnpacking { $0.intValue }
    }

    public func subscribe(to event: String) -> APIAsync<Void> {
        request("nvim_subscribe", with: .string(event))
            .discardResult()
    }

    public func unsubscribe(from event: String) -> APIAsync<Void> {
        request("nvim_unsubscribe", with: .string(event))
            .discardResult()
    }

    public func evalStatusline(_ str: String) -> APIAsync<String> {
        request("nvim_eval_statusline", with: .string(str), .dict([:]))
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
            .array(events.map { .string($0) }),
            .dict([
                .string("once"): .bool(once),
                .string("command"): .string(command),
            ]),
        ])
        .checkedUnpacking { $0.intValue }
    }

    public func delAutocmd(_ id: AutocmdID) -> APIAsync<Void> {
        request("nvim_del_autocmd", with: .int(id))
            .discardResult()
    }

    @discardableResult
    public func request(_ method: String, with params: Value...) -> APIAsync<Value> {
        request(method, with: params)
    }

    @discardableResult
    public func request(_ method: String, with params: [Value]) -> APIAsync<Value> {
        session.request(method: method, params: params, callbacks: requestCallbacks)
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
