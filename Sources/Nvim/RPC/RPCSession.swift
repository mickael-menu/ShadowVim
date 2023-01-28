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
import MessagePack
import Toolkit

public enum RPCError: Error {
    case unexpectedMessage(Value)
    case unexpectedMessagePackValue(MessagePackValue)
    case unknownRequestId(UInt64)
    case responseError(Value)
    case ioFailure(Error)
    case unpackFailure(Error)
    case noHandlerForRequest(method: String)
}

public typealias RPCMessageID = UInt64

enum RPCType: Int {
    case request = 0
    case response = 1
    case notification = 2

    var value: MessagePackValue {
        .uint(UInt64(rawValue))
    }
}

protocol RPCSessionDelegate: AnyObject {
    func session(_ session: RPCSession, didReceiveRequest method: String, with params: [Value]) -> Result<Value, Error>?

    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value])

    func session(_ session: RPCSession, didReceiveError error: RPCError)
}

struct RPCRequestCallbacks {
    var prepare: () -> Async<Void, Never> = { .success(()) }
    var onSent: () -> Void = {}
    var onAnswered: () -> Void = {}
}

/// Represents a MessagePack-RPC on-going session.
///
/// It can receive and send messages to the server.
///
/// Note that Swift async tasks are not used because the order of execution
/// is important when interacting with Nvim. We want the input keys and events
/// be sent in the proper order.
final class RPCSession {
    typealias RequestCompletion = (Result<Value, RPCError>) -> Void

    private let _send: (Data) throws -> Void
    private let _receive: () -> Data
    private var receiveTask: Task<Void, Never>?
    private let debug: Bool = false

    weak var delegate: RPCSessionDelegate?
    private var isClosed: Bool = false

    init(
        send: @escaping (Data) throws -> Void,
        receive: @escaping () -> Data
    ) {
        _send = send
        _receive = receive
    }

    convenience init(
        input: FileHandle,
        output: FileHandle
    ) {
        self.init(
            send: { try input.write(contentsOf: $0) },
            receive: { output.availableData }
        )
    }

    deinit {
        close()
    }

    func close() {
        guard !isClosed else {
            return
        }
        isClosed = true
        receiveTask?.cancel()
    }

    // MARK: - Receive

    func start(delegate: RPCSessionDelegate? = nil) {
        precondition(receiveTask == nil)

        self.delegate = delegate

        receiveTask = Task.detached(priority: .high) { [unowned self] in
            var data = receive()
            while data.count > 0, !Task.isCancelled {
                do {
                    for message in try MessagePack.unpackAll(data) {
                        Value.from(message)
                            .flatMap { receive(message: $0) }
                            .onError { delegate?.session(self, didReceiveError: $0) }
                    }
                } catch {
                    delegate?.session(self, didReceiveError: .unpackFailure(error))
                }
                data = receive()
            }
        }
    }

    func respond(to requestID: RPCMessageID, with result: Result<Value, Error>) -> Result<Void, RPCError> {
        let response = MessagePackValue([
            RPCType.response.value, // message type
            .uint(requestID), // request ID
            result.error.map { .string($0.localizedDescription) } ?? .nil, // error
            result.value?.messagePackValue ?? .nil, // result
        ])
        let data = MessagePack.pack(response)

        do {
            try send(data)
            return .success(())
        } catch {
            return .failure(.ioFailure(error))
        }
    }

    private func receive(message: Value) -> Result<Void, RPCError> {
        guard
            let body = message.arrayValue,
            let intType = body.first?.intValue,
            let type = RPCType(rawValue: intType)
        else {
            return .failure(.unexpectedMessage(message))
        }

        switch type {
        case .request:
            guard
                body.count == 4,
                let id = body[1].intValue.map(RPCMessageID.init),
                let method = body[2].stringValue,
                let params = body[3].arrayValue
            else {
                return .failure(.unexpectedMessage(message))
            }
            log(">\(id) \(method)(\(params))\n")

            guard
                let delegate = delegate,
                let result = delegate.session(self, didReceiveRequest: method, with: params)
            else {
                let error = RPCError.noHandlerForRequest(method: method)
                _ = respond(to: id, with: .failure(error))
                return .failure(error)
            }
            return respond(to: id, with: result)

        case .response:
            guard
                body.count == 4,
                let id = body[1].intValue.map(RPCMessageID.init)
            else {
                return .failure(.unexpectedMessage(message))
            }

            let result: Result<Value, RPCError> = {
                let err = body[2]
                guard err.isNil else {
                    return .failure(.responseError(err))
                }
                return .success(body[3])
            }()

            endRequest(id: id, with: result)
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
            delegate?.session(self, didReceiveNotification: method, with: params)
        }

        return .success(())
    }

    private func receive() -> Data {
        guard !isClosed else {
            return Data()
        }
        return _receive()
    }

    // MARK: - Send

    private let sendQueue = DispatchQueue(label: "menu.mickael.RPCSession", qos: .userInitiated)
    private var nextMessageId: RPCMessageID = 0
    private var requests: [RPCMessageID: RequestCompletion] = [:]

    /// Send the RPC request `method` to the server, with the given `params`.
    ///
    /// Note: This is not an async method, because we need to guarantee that
    /// every request is sent in order.
    func request(
        method: String,
        params: [ValueConvertible],
        callbacks: RPCRequestCallbacks
    ) -> Async<Value, RPCError> {
        callbacks.prepare().setFailureType(to: RPCError.self)
            .asyncMap(on: sendQueue) { [self] _, completion in
                let id = nextMessageId
                nextMessageId += 1
                requests[id] = completion

                let request = MessagePackValue([
                    RPCType.request.value, // message type
                    .uint(id), // request ID
                    .string(method), // method name
                    .array(params.map(\.nvimValue.messagePackValue)), // method arguments.
                ])
                let data = MessagePack.pack(request)

                log(">\(method)(\(params))\n")
                do {
                    try send(data)
                } catch {
                    endRequest(id: id, with: .failure(.ioFailure(error)))
                }

                callbacks.onSent()
            }
            .onCompletion { _ in callbacks.onAnswered() }
    }

    func endRequest(id: RPCMessageID, with result: Result<Value, RPCError>) {
        guard let completion = requests.removeValue(forKey: id) else {
            delegate?.session(self, didReceiveError: .unknownRequestId(id))
            return
        }
        completion(result)
    }

    private func send(_ data: Data) throws {
        guard !isClosed else {
            return
        }
        return try _send(data)
    }

    // MARK: - Toolkit

    private func log(_ message: String) {
        if debug {
            print(message)
        }
    }
}
