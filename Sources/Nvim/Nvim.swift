//
//  main.swift
//  PhantomVim
//
//  Created by Mickaël Menu on 07/01/2023.
//

import Foundation
import MessagePack
import AppKit

public struct RuntimeError: Error {
    let message: String
}

public enum NeoVimError: Error {
    case notStarted
    case alreadyStarted
    case rpc(RPCError)
    case api(APIError)
    case runtime(RuntimeError)
    
    static func wrap(_ error: Error) -> NeoVimError {
        switch error {
        case let error as RuntimeError:
            return .runtime(error)
        case let error as RPCResponseError:
            return .api(APIError(from: error))
        case let error as RPCError:
            return .rpc(error)
        default:
            preconditionFailure("Unknown error type for \(error)")
        }
    }
}

public enum APIError: Error {
    case exception(message: String)
    case validation(message: String)
    case unknown(RPCResponseError)
       
    init(from error: RPCResponseError) {
        guard
            case let .array(array) = error.value,
            array.count == 2,
            case let .uint(type) = array[0],
            case let .string(message) = array[1]
        else {
            self = .unknown(error)
            return
        }
        
        // https://github.com/neovim/neovim/blob/266a1c61b97313f2a516140fc691dd8be8eed47a/src/nvim/api/private/defs.h#L26-L31
        switch type {
        case 0:
            self = .exception(message: message)
        case 1:
            self = .validation(message: message)
        default:
            self = .unknown(error)
        }
    }
}

public struct LinesEvent {
    public let buffer: BufferHandle
    public let changedTick: UInt64?
    public let firstLine: LineIndex
    public let lastLine: LineIndex?
    public let lineData: [String]
    public let more: Bool
    
    init?(from params: [MessagePackValue]) {
        guard
            params.count == 6,
            case let .uint(buffer) = params[0],
            case let .uint(firstLine) = params[2],
            case let .array(lineData) = params[4],
            case let .bool(more) = params[5]
        else {
            return nil
        }
                
        switch params[1] {
        case .nil:
            self.changedTick = nil
        case let .uint(changedTick):
            self.changedTick = changedTick
        default:
            return nil
        }
                
        switch params[3] {
        case let .int(lastLine):
            self.lastLine = (lastLine >= 0) ? LineIndex(lastLine) : nil
        case let .uint(lastLine):
            self.lastLine = lastLine
        default:
            return nil
        }
        
        self.buffer = buffer
        self.firstLine = firstLine
        
        self.lineData = lineData
            .compactMap {
                guard case let .string(data) = $0 else {
                    return nil
                }
                return data
            }
        self.more = more
    }
}

public typealias BufferHandle = UInt64
public typealias LineIndex = UInt64

public actor NeoVim {

    public init() {}
        
    private var state: State = .stopped
        
    private enum State {
        case stopped
        case started(StartedState)
        case failure(NeoVimError)
    }

    private class StartedState {
        let process: Process
        let session: RPCSession
        let sessionTask: Task<(), Error>
        var notificationHandlers: [NotificationHandler] = []
        var notificationSubscriptionNextId = 0
        
        init(process: Process, session: RPCSession, sessionTask: Task<(), Error>) {
            self.process = process
            self.session = session
            self.sessionTask = sessionTask
        }
    }
        
    private struct NotificationHandler {
        let id: Int
        let notification: String
        let handler: ([MessagePackValue]) -> Void
    }
        
    public class NotificationSubscription {
        private let onCancel: () -> Void
        
        fileprivate init(onCancel: @escaping () -> Void) {
            self.onCancel = onCancel
        }
        
        deinit {
            onCancel()
        }
    }

    public func start(executableURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/nvim")) throws {
        switch state {
        case .stopped, .failure:
            let input = Pipe()
            let output = Pipe()
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--headless", "--embed", "--clean"]
            process.standardInput = input
            process.standardOutput = output
            try process.run()

            let session = RPCSession(
                input: input.fileHandleForWriting,
                output: output.fileHandleForReading,
                onNotification: { [unowned self] m, p in
                    self.onRPCNotification(method: m, params: p)
                }
            )
            state = .started(.init(
                process: process,
                session: session,
                sessionTask: Task {
                    do {
                        try await session.run()
                    } catch {
                        self.state = .failure(.wrap(error))
                    }
                }
            ))

        case .started(session: _):
            throw NeoVimError.alreadyStarted
        }
    }
    
    private func onRPCNotification(method: String, params: [MessagePackValue]) {
        guard let state = try? requireStarted() else {
            return
        }
        
        state.notificationHandlers
            .filter { $0.notification == method }
            .forEach { $0.handler(params) }
    }

    public func on(_ notification: String, handler: @escaping ([MessagePackValue]) -> Void) throws -> NotificationSubscription {
        let state = try requireStarted()
        
        let id = state.notificationSubscriptionNextId
        state.notificationSubscriptionNextId += 1
                
        let subscription = NotificationSubscription(onCancel: { [weak self] in
            guard let self else {
                return
            }
            Task {
                guard let state = try? await self.requireStarted() else {
                    return
                }
                state.notificationHandlers.removeAll { $0.id == id }
            }
        })
        
        state.notificationHandlers.append(NotificationHandler(
            id: id,
            notification: notification,
            handler: handler
        ))
        
        return subscription
    }
    
//    try await nvim.command("autocmd CursorMoved * call rpcnotify(0, 'moved')")
//    try await nvim.command("autocmd ModeChanged * call rpcnotify(0, 'mode', mode())")
//    try await nvim.command("autocmd CmdlineChanged * call rpcnotify(0, 'cmdline', getcmdline())")
    public func createAutocmd(on events: String..., args: String..., handler: @escaping ([MessagePackValue]) -> Void) async throws -> NotificationSubscription {
        let id = "autocmd-\(UUID().uuidString)"
        var argsList = ""
        if !args.isEmpty {
            argsList = ", " + args.joined(separator: ", ")
        }
                
        try await subscribe(event: id)
        try await request("nvim_create_autocmd",
            with:
                .array(events.map { .string($0) }),
                               .map([.string("command"): .string("call rpcnotify(0, '\(id)'\(argsList))")])
        )
               
        return try on(id, handler: handler)
    }

    public func stop() throws {
        let state = try requireStarted()
        state.sessionTask.cancel()
        state.process.terminate()
        self.state = .stopped
    }
    
    @discardableResult
    public func command(_ command: String) async throws -> MessagePackValue {
        try await request("nvim_command", with: .string(command))
    }

    /// - Parameter handle: Handle of the buffer, or 0 for the current buffer.
    public func buffer(_ handle: BufferHandle = 0) async throws -> Buffer {
        var handle = handle
        if handle == 0 {
            guard
                case let .uint(buf) = try await request("nvim_get_current_buf"),
                buf > 0
            else {
                throw NeoVimError.runtime(RuntimeError(message: "Unexpected nvim_get_current_buf result"))
            }
            handle = buf
        }
        return Buffer(nvim: self, handle: handle)
    }
    
    @discardableResult
    public func input(_ keys: String) async throws -> UInt64 {
        try await request("nvim_input", with: .string(keys))
            .uint64Value ?? 0
    }
    
    public func subscribe(event: String) async throws {
        try await request("nvim_subscribe", with: .string(event))
    }
    
    public func unsubscribe(event: String) async throws {
        try await request("nvim_unsubscribe", with: .string(event))
    }

    @discardableResult
    public func request(_ method: String, with params: MessagePackValue...) async throws -> MessagePackValue {
        do {
            let res = try await requireSession()
                .send(method: method, params: params)
            if
                case .extended(_, let data) = res,
                let unpackedRes = try? MessagePack.unpackFirst(data)
            {
                return unpackedRes
            } else {
                return res
            }
        } catch {
            throw NeoVimError.wrap(error)
        }
    }

    fileprivate func requireSession() throws -> RPCSession {
        try requireStarted().session
    }

    private func requireStarted() throws -> StartedState {
        guard case let .started(state) = state else {
            throw NeoVimError.notStarted
        }
        return state
    }

    private func requireNoFailure() throws {
        if case .failure(let error) = state {
            throw error
        }
    }
}

public class Buffer {
    private let nvim: NeoVim
    public let handle: BufferHandle
    
    private var onLinesHandle: NeoVim.NotificationSubscription?
    
    init(nvim: NeoVim, handle: UInt64) {
        precondition(handle > 0)
        self.nvim = nvim
        self.handle = handle
    }

    @discardableResult
    public func attach(
        sendBuffer: Bool,
        options: [MessagePackValue: MessagePackValue] = [:],
        onLines: @escaping (LinesEvent) -> Void
    ) async throws -> Bool {
        onLinesHandle = try await nvim
            .on("nvim_buf_lines_event") { [weak self] params in
                guard
                    let event = LinesEvent(from: params),
                    event.buffer == self?.handle
                else {
                    return
                }
                onLines(event)
            }
        
        return try await nvim
            .request("nvim_buf_attach", with: .uint(handle), .bool(sendBuffer), .map(options))
            .boolValue ?? false
    }
}

//var buffer: Buffer!
//
//func nvim(url: URL = URL(fileURLWithPath: "/opt/homebrew/bin/nvim")) throws {
//    Task {
//        let nvim = NeoVim()
//        do {
//            try await nvim.start(executableURL: url)
//            try await nvim.input("ihello")
//            buffer = try await nvim.buffer()
//            try await buffer.attach(
//                sendBuffer: true,
//                onLines: { print("\($0)") }
//            )
//            try await nvim.input(" world")
//            try await nvim.input("<ESC>bx")
//
//            try await Task.sleep(for: .seconds(1))
//            async let a = try await nvim.input("<ESC>x")
//            async let b = try await nvim.input("it")
//            let _ = try await [a, b]
//            try await Task.sleep(for: .seconds(1))
//            print(try await nvim.input("<ESC>x"))
//            try await Task.sleep(for: .seconds(1))
//            print(try await nvim.input("<ESC>x"))
//
//        } catch {
//            print(error)
//        }
//    }
//}
