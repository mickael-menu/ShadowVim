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

public enum RPCError: LocalizedError {
    case unexpectedMessage(Value)
    case unexpectedMessagePackValue(MessagePackValue)
    case unknownRequestId(UInt64)
    case responseError(Value)
    case ioFailure(Error)
    case unpackFailure(Error)
    case noHandlerForRequest(method: String)

    public var errorDescription: String? {
        var description = String(reflecting: self)
        switch self {
        case let .unexpectedMessage(value), let .responseError(value):
            description += ": \(value)"
        case let .unknownRequestId(id):
            description += ": \(id)"
        case let .ioFailure(error), let .unpackFailure(error):
            description += ": \(error.localizedDescription)"
        case let .noHandlerForRequest(method: method):
            description += ": \(method)"
        case .unexpectedMessagePackValue:
            break
        }

        return description
    }
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

final class RPCSession {
    let input: FileHandle
    let output: FileHandle
    let debug: Bool = false

    weak var delegate: RPCSessionDelegate?

    init(
        input: FileHandle,
        output: FileHandle,
        delegate: RPCSessionDelegate? = nil
    ) {
        self.input = input
        self.output = output
        self.delegate = delegate
    }

    func run() async {
        precondition(!Thread.isMainThread)
        var data = output.availableData
        while data.count > 0, !Task.isCancelled {
            do {
                for message in try MessagePack.unpackAll(data) {
                    await Value.from(message)
                        .flatMap { await receive(message: $0) }
                        .onError { delegate?.session(self, didReceiveError: $0) }
                }
            } catch {
                delegate?.session(self, didReceiveError: .unpackFailure(error))
            }
            data = output.availableData
        }
    }

    func request(method: String, params: [Value]) async -> Result<Value, RPCError> {
        await withCheckedContinuation { continuation in
            let id = $requests.write {
                $0.start(for: continuation)
            }

            let request = MessagePackValue([
                RPCType.request.value, // message type
                .uint(id), // request ID
                .string(method), // method name
                .array(params.map(\.messagePackValue)), // method arguments.
            ])
            let data = MessagePack.pack(request)
            log(">\(method)(\(params))\n")
            do {
                try input.write(contentsOf: data)
            } catch {
                endRequest(id: id, with: .failure(.ioFailure(error)))
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
            try input.write(contentsOf: data)
            return .success(())
        } catch {
            return .failure(.ioFailure(error))
        }
    }

    private func receive(message: Value) async -> Result<Void, RPCError> {
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

    @Atomic private var requests = Requests()

    struct Requests {
        typealias Continuation = CheckedContinuation<Result<Value, RPCError>, Never>

        private var lastRequestId: RPCMessageID = 0
        private var requests: [RPCMessageID: Continuation] = [:]

        mutating func start(for continuation: Continuation) -> RPCMessageID {
            lastRequestId += 1
            requests[lastRequestId] = continuation
            return lastRequestId
        }

        mutating func end(id: RPCMessageID, with result: Result<Value, RPCError>) -> Result<Void, RPCError> {
            guard let continuation = requests.removeValue(forKey: id) else {
                return .failure(.unknownRequestId(id))
            }
            continuation.resume(returning: result)
            return .success(())
        }
    }

    func endRequest(id: RPCMessageID, with result: Result<Value, RPCError>) {
        $requests
            .write { $0.end(id: id, with: result) }
            .onError { delegate?.session(self, didReceiveError: $0) }
    }

    private func log(_ message: String) {
        if debug {
            print(message)
        }
    }
}
