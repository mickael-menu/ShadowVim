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

import Foundation
import MessagePack
import Toolkit

public enum RPCError: Error {
    case unexpectedMessage(MessagePackValue)
    case unexpectedMessagePackValue(MessagePackValue)
    case unknownRequestId(UInt64)
    case responseError(Value)
    case ioFailure(Error)
    case unpackFailure(Error)
}

enum RPCType: UInt64 {
    case request = 0
    case response = 1
    case notification = 2
}

protocol RPCSessionDelegate: AnyObject {
    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value])
    func session(_ session: RPCSession, didReceiveError error: RPCError)
}

final class RPCSession {
    let input: FileHandle
    let output: FileHandle
    let debug: Bool = true

    weak var delegate: RPCSessionDelegate?

    actor Requests {
        typealias Continuation = CheckedContinuation<Result<Value, RPCError>, Never>

        private var lastRequestId: UInt64 = 0
        private var requests: [UInt64: Continuation] = [:]
        private let onError: (RPCError) -> Void
        var delegate: RPCSessionDelegate?

        init(onError: @escaping (RPCError) -> Void) {
            self.onError = onError
        }

        func start(for continuation: Continuation) -> UInt64 {
            lastRequestId += 1
            requests[lastRequestId] = continuation
            return lastRequestId
        }

        func end(id: UInt64, with result: Result<Value, RPCError>) {
            guard let continuation = requests.removeValue(forKey: id) else {
                onError(.unknownRequestId(id))
                return
            }
            continuation.resume(returning: result)
        }
    }

    private var requests: Requests!

    init(
        input: FileHandle,
        output: FileHandle,
        delegate: RPCSessionDelegate? = nil
    ) {
        self.input = input
        self.output = output
        self.delegate = delegate

        requests = Requests(
            onError: { [unowned self] in
                self.delegate?.session(self, didReceiveError: $0)
            }
        )
    }

    func run() async {
        var data = output.availableData
        while data.count > 0, !Task.isCancelled {
            do {
                for message in try MessagePack.unpackAll(data) {
                    await receive(message: message)
                        .onError { delegate?.session(self, didReceiveError: $0) }
                }
            } catch {
                delegate?.session(self, didReceiveError: .unpackFailure(error))
            }
            data = output.availableData
        }
    }

    @discardableResult
    func send(method: String, params: [Value]) async -> Result<Value, RPCError> {
        await withCheckedContinuation { continuation in
            Task {
                let id = await requests.start(for: continuation)

                let request = MessagePackValue([
                    .uint(RPCType.request.rawValue), // message type
                    .uint(id), // request ID
                    .string(method), // method name
                    .array(params.map(\.messagePackValue)), // method arguments.
                ])
                let data = MessagePack.pack(request)
                log(">\(method)(\(params))\n")
                do {
                    try input.write(contentsOf: data)
                } catch {
                    await requests.end(id: id, with: .failure(.ioFailure(error)))
                }
            }
        }
    }

    private func receive(message: MessagePackValue) async -> Result<Void, RPCError> {
        do {
            guard
                let body = message.arrayValue,
                let intType = body.first?.uint64Value,
                let type = RPCType(rawValue: intType)
            else {
                return .failure(.unexpectedMessage(message))
            }

            switch type {
            case .request:
                guard
                    body.count == 4,
                    let id = body[1].uint64Value,
                    let method = body[2].stringValue,
                    let params = body[3].arrayValue
                else {
                    return .failure(.unexpectedMessage(message))
                }
                // TODO:
                log(">\(id) \(method)(\(params))\n")

            case .response:
                guard
                    body.count == 4,
                    let id = body[1].uint64Value
                else {
                    return .failure(.unexpectedMessage(message))
                }

                let result: Result<Value, RPCError> = {
                    do {
                        let err = body[2]
                        guard err.isNil else {
                            return .failure(.responseError(try Value.from(err).get()))
                        }
                        return .success(try Value.from(body[3]).get())
                    } catch let error as RPCError {
                        return .failure(error)
                    } catch {
                        fatalError("Unexpected error \(error)")
                    }
                }()

                await requests.end(id: id, with: result)
                log("<\(id) \(body[2]) | \(body[3])\n")

            case .notification:
                guard
                    body.count == 3,
                    let method = body[1].stringValue,
                    let params = body[2].arrayValue
                else {
                    return .failure(.unexpectedMessage(message))
                }
                log("@\(method): \(params)\n")
                do {
                    try delegate?.session(self,
                                          didReceiveNotification: method,
                                          with: params.map { try Value.from($0).get() })
                } catch let error as RPCError {
                    return .failure(error)
                } catch {
                    fatalError("Unexpected error \(error)")
                }
            }

            return .success(())
        }
    }

    private func log(_ message: String) {
        if debug {
            print(message)
        }
    }
}
