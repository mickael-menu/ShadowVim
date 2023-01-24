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

public class API {
    private let session: RPCSession

    init(session: RPCSession) {
        self.session = session
    }

    public func command(_ command: String) async -> APIResult<Value> {
        await request("nvim_command", with: .string(command))
    }

    public func cmd(_ cmd: String, args: Value...) async -> APIResult<String> {
        await request("nvim_cmd", with: [
            .dict([
                .string("cmd"): .string(cmd),
                .string("args"): .array(args),
            ]),
            .dict([
                .string("output"): .bool(true),
            ]),
        ])
        .checkedUnpacking { $0.stringValue }
    }

    public func getCurrentBuf() async -> APIResult<BufferHandle> {
        await request("nvim_get_current_buf")
            .checkedUnpacking { $0.bufferValue }
    }

    public func bufAttach(buffer: BufferHandle, sendBuffer: Bool) async -> APIResult<Bool> {
        await request("nvim_buf_attach", with: [
            .buffer(buffer),
            .bool(sendBuffer),
            .dict([:]), // options
        ])
        .checkedUnpacking { $0.boolValue }
    }

    public func bufSetName(buffer: BufferHandle = 0, name: String) async -> APIResult<Void> {
        await request("nvim_buf_set_name", with: [
            .buffer(buffer),
            .string(name),
        ])
        .dropResult()
    }

    public func winGetWidth(_ window: WindowHandle = 0) async -> APIResult<Int> {
        await request("nvim_win_get_width", with: .window(window))
            .checkedUnpacking { $0.intValue }
    }

    public func winGetCursor(_ window: WindowHandle = 0) async -> APIResult<Value> {
        await request("nvim_win_get_cursor", with: .window(window))
    }

    public func input(_ keys: String) async -> APIResult<Int> {
        await request("nvim_input", with: .string(keys))
            .checkedUnpacking { $0.intValue }
    }

    public func subscribe(to event: String) async -> APIResult<Void> {
        await request("nvim_subscribe", with: .string(event))
            .dropResult()
    }

    public func unsubscribe(from event: String) async -> APIResult<Void> {
        await request("nvim_unsubscribe", with: .string(event))
            .dropResult()
    }

    public func evalStatusline(_ str: String) async -> APIResult<String> {
        await request("nvim_eval_statusline", with: .string(str), .dict([:]))
            .checkedUnpacking { $0.dictValue?[.string("str")]?.stringValue }
    }

    public func createAutocmd(
        for event: String,
        once: Bool = false,
        command: String
    ) async -> APIResult<AutocmdID> {
        await createAutocmd(for: [event], once: once, command: command)
    }

    public func createAutocmd(
        for events: [String],
        once: Bool = false,
        command: String
    ) async -> APIResult<AutocmdID> {
        await request("nvim_create_autocmd", with: [
            .array(events.map { .string($0) }),
            .dict([
                .string("once"): .bool(once),
                .string("command"): .string(command),
            ]),
        ])
        .checkedUnpacking { $0.intValue }
    }

    @discardableResult
    public func request(_ method: String, with params: Value...) async -> APIResult<Value> {
        await request(method, with: params)
    }

    @discardableResult
    public func request(_ method: String, with params: [Value]) async -> APIResult<Value> {
        await session.request(method: method, params: params)
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

public typealias APIResult<Success> = Result<Success, APIError>

extension Result where Success == Value, Failure == APIError {
    func checkedUnpacking<NewSuccess>(transform: (Success) -> NewSuccess?) -> APIResult<NewSuccess> {
        flatMap {
            guard let res = transform($0) else {
                return .failure(.unexpectedResult($0))
            }
            return .success(res)
        }
    }
}
