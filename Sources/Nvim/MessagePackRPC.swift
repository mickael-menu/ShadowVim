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
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//
//

import Foundation
import MessagePack

struct RPCRequest {
    let method: String
    let params: [MessagePackValue]
}

public struct RPCResponseError: Error {
    let value: MessagePackValue
}

public enum RPCError: Error {
    case unexpectedMessage(MessagePackValue)
    case unknownRequestId(UInt64)
}

enum RPCType: UInt64 {
    case request = 0
    case response = 1
    case notification = 2
}

final class RPCSession {
    typealias OnNotificationHandler = (_ method: String, _ params: [MessagePackValue]) -> Void

    let input: FileHandle
    let output: FileHandle
    private let onNotification: OnNotificationHandler

    actor Requests {
        private var lastRequestId: UInt64 = 0
        private var requests: [UInt64: CheckedContinuation<MessagePackValue, Error>] = [:]

        func start(for continuation: CheckedContinuation<MessagePackValue, Error>) -> UInt64 {
            lastRequestId += 1
            requests[lastRequestId] = continuation
            return lastRequestId
        }

        func end(id: UInt64, with result: Result<MessagePackValue, Error>) throws {
            guard let continuation = requests.removeValue(forKey: id) else {
                throw RPCError.unknownRequestId(id)
            }
            continuation.resume(with: result)
        }
    }

    private let requests = Requests()

    init(
        input: FileHandle,
        output: FileHandle,
        onNotification: @escaping OnNotificationHandler
    ) {
        self.input = input
        self.output = output
        self.onNotification = onNotification
    }

    func run() async throws {
        var data = output.availableData
        while data.count > 0 {
            try Task.checkCancellation()
            for message in try MessagePack.unpackAll(data) {
                try await receive(message: message)
            }
            data = output.availableData
        }
    }

    @discardableResult
    func send(method: String, params: [MessagePackValue]) async throws -> MessagePackValue {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let id = await requests.start(for: continuation)

                let request = MessagePackValue([.uint(0), .uint(id), .string(method), .array(params)])
                let data = MessagePack.pack(request)
//                print(">\(method)(\(params))\n")
                do {
                    try input.write(contentsOf: data)
                } catch {
                    try await requests.end(id: id, with: .failure(error))
                }
            }
        }
    }

    private func receive(message: MessagePackValue) async throws {
        guard
            case let .array(body) = message,
            case let .uint(intType) = body.first,
            let type = RPCType(rawValue: intType)
        else {
            throw RPCError.unexpectedMessage(message)
        }

        switch type {
        case .request:
            guard
                body.count == 4,
                case let .uint(id) = body[1],
                case let .string(method) = body[2],
                case let .array(params) = body[3]
            else {
                throw RPCError.unexpectedMessage(message)
            }
            print(">\(id) \(method)(\(params))\n")

        case .response:
            guard
                body.count == 4,
                case let .uint(id) = body[1]
            else {
                throw RPCError.unexpectedMessage(message)
            }

            let result: Result<MessagePackValue, Error> = {
                let err = body[2]
                if case .nil = err {
                    return .success(body[3])
                } else {
                    return .failure(RPCResponseError(value: err))
                }
            }()

            try await requests.end(id: id, with: result)
            // print("<\(id) \(body[2]) | \(body[3])\n")

        case .notification:
            guard
                body.count == 3,
                case let .string(method) = body[1],
                case var .array(params) = body[2]
            else {
                throw RPCError.unexpectedMessage(message)
            }
//            print("@\(method): \(params)\n")
            params = params.map { value in
                if case let .extended(_, data) = value {
                    do {
                        return try MessagePack.unpackFirst(data)
                    } catch {
                        print(error) // FIXME: proper error reporting
                        return value
                    }
                } else {
                    return value
                }
            }
            onNotification(method, params)
        }
    }
}
