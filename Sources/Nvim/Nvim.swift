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

import Combine
import Foundation
import MessagePack
import Toolkit

public enum NvimError: Error {
    /// The process is not started yet.
    case notStarted
    /// The process is already started.
    case alreadyStarted
    /// The process terminated with the given status.
    case terminated(status: Int)

    case apiFailed(APIError)

    /// A low-level RPC error occurred.
    case rpcFailed(RPCError)

    // Nvim sent a notification with an unexpected payload.
    case unexpectedNotificationPayload(event: String, payload: [Value])
    // Nvim sent an unexpected result payload.
    case unexpectedResult(payload: Value)

    case failedToReadAPIInfo
}

public protocol NvimDelegate: AnyObject {
    func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>?
    func nvim(_ nvim: Nvim, didFailWithError error: NvimError)
}

public final class Nvim {
    public typealias RequestHandler = ([Value]) throws -> Value
    typealias RunningStateFactory = (Process, (input: FileHandle, output: FileHandle)) -> RunningState

    public weak var delegate: NvimDelegate?
    private let logger: Logger?
    private let runningStateFactory: RunningStateFactory

    init(
        logger: Logger?,
        runningStateFactory: @escaping RunningStateFactory
    ) {
        self.logger = logger
        self.runningStateFactory = runningStateFactory
    }

    deinit {
        stop()
    }

    // MARK: State

    public var vim: Vim? {
        guard case let .started(state) = state else {
            return nil
        }
        return state.vim
    }

    @Atomic private var state: State = .stopped

    enum State {
        case started(RunningState)
        case stopping(RunningState)
        case stopped
    }

    struct RunningState {
        let process: Process
        let session: RPCSession
        let vim: Vim
        let events: EventDispatcher
        private(set) var requestHandlers: [String: RequestHandler] = [:]

        mutating func addRequestHandler(for request: String, handler: @escaping RequestHandler) {
            precondition(requestHandlers[request] == nil)
            requestHandlers[request] = handler
        }
    }

    /// Starts the Nvim process.
    ///
    /// - Parameter listen: Listen to remote RPC connection on the given pipe or
    ///   TCP address. This can be used to debug the embedded Nvim instance
    ///   using for example: nvim --server /tmp/shadowvim.pipe --remote-ui
    public func start(
        headless: Bool = false,
        listen: String? = nil
    ) throws {
        try $state.write {
            guard case .stopped = $0 else {
                throw NvimError.alreadyStarted
            }

            // Prevent crashes when reading/writing pipes in the `RPCSession` when
            // the nvim process is terminated.
            signal(SIGPIPE, SIG_IGN)

            let input = Pipe()
            let output = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

            var args = [
                "nvim",
                "--embed",
                "-n", // Ignore swap files.

                // Don't load default config and plugins.
                // Commented as this would prevent using packages.
                // "--clean",

                // Using `--cmd` instead of `-c` makes the statements available in the `init.vim`.
                "--cmd", "let g:shadowvim = v:true",
            ]

            if headless {
                args.append("--headless")
            }
            
            if let listen = listen {
                args.append("--listen")
                args.append(listen)
            }

            process.arguments = args
            process.standardInput = input
            process.standardOutput = output
            process.loadEnvironment()

            process.terminationHandler = { [self] _ in
                DispatchQueue.main.async { self.didTerminate() }
            }

            try process.run()

            let state = runningStateFactory(process, (
                input: input.fileHandleForWriting,
                output: output.fileHandleForReading
            ))
            state.session.start(delegate: self)

            $0 = .started(state)
        }
    }

    /// Stops the Nvim process.
    public func stop() {
        $state.write {
            guard case let .started(state) = $0 else {
                return
            }

            if state.process.isRunning {
                state.process.interrupt()
                $0 = .stopping(state)
            } else {
                $0 = .stopped
            }
        }
    }

    private func didTerminate() {
        $state.write {
            switch $0 {
            case let .stopping(state), let .started(state):
                let status = Int(state.process.terminationStatus)
                logger?.i("Nvim process terminated with status \(status)")

                // When resetting Nvim, the status code will be 2. We can ignore it.
                if status != 2 {
                    delegate?.nvim(self, didFailWithError: .terminated(status: status))
                }

                state.session.close()
                $0 = .stopped

            case .stopped:
                break
            }
        }
    }

    // MARK: Events

    /// Observes RPC notifications for the given `event` name.
    ///
    /// When `unpack` is provided, the associated value will be unpacked to
    /// the expected type.
    public func publisher<UnpackedValue>(
        for event: String,
        unpack: @escaping ([Value]) -> UnpackedValue? = { $0 }
    ) -> AnyPublisher<UnpackedValue, NvimError> {
        guard case let .started(state) = state else {
            return .fail(.notStarted)
        }
        return state.events.publisher(for: event, unpack: unpack)
            .eraseToAnyPublisher()
    }

    /// Registers a new Vim autocmd and observes when it is triggered.
    ///
    /// When `unpack` is provided, the argument values will be unpacked to the
    /// expected types.
    public func autoCmdPublisher<UnpackedValue>(
        name: String? = nil,
        for events: String...,
        args: String...,
        unpack: @escaping ([Value]) -> UnpackedValue? = { $0 }
    ) -> AnyPublisher<UnpackedValue, NvimError> {
        guard case let .started(state) = state else {
            return .fail(.notStarted)
        }
        return state.events.autoCmdPublisher(name: name, for: events, args: args, unpack: unpack)
            .eraseToAnyPublisher()
    }

    // MARK: User commands and RPC requests

    /// Adds a new user command executing the given action.
    public func add(
        command: String,
        args: ExCommands.ArgsCardinality = .none,
        action: @escaping RequestHandler
    ) -> Async<Void, NvimError> {
        $state.write { state in
            guard case var .started(runningState) = state else {
                return .failure(.notStarted)
            }

            runningState.addRequestHandler(for: command, handler: action)
            state = .started(runningState)

            return runningState.vim.cmd
                .command(
                    cmd: command,
                    bang: true,
                    args: args,
                    repl: "call rpcrequest(1, '\(command)', <f-args>)"
                )
                .discardResult()
        }
    }

    /// Adds a new RPC request handler.
    public func addRequestHandler(for request: String, handler: @escaping RequestHandler) -> Result<Void, NvimError> {
        $state.write { state in
            guard case var .started(runningState) = state else {
                return .failure(.notStarted)
            }
            runningState.addRequestHandler(for: request, handler: handler)
            state = .started(runningState)
            return .success(())
        }
    }

    // MARK: API metadata

    /// Returns the API metadata for the located Nvim process.
    ///
    /// This is used to check the Nvim version.
    public static func apiInfo(logger: Logger?) throws -> APIMetadata {
        do {
            let (status, output) = Process.launchAndWait("nvim", "--api-info")
            guard
                status == 0,
                let rawMetadata = try MessagePack.unpackAll(output).first,
                let metadata = APIMetadata(messagePackValue: rawMetadata)
            else {
                throw NvimError.failedToReadAPIInfo
            }

            return metadata
        } catch {
            logger?.e(error)
            throw NvimError.failedToReadAPIInfo
        }
    }
}

extension Nvim: RPCSessionDelegate {
    func session(_ session: RPCSession, didFailWithError error: RPCError) {
        delegate?.nvim(self, didFailWithError: .rpcFailed(error))
    }

    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value]) {
        guard case let .started(state) = state else {
            logger?.w("Unhandled notification `\(method)`", ["params": params])
            return
        }

        state.events.dispatch(event: method, data: params)
    }

    func session(_ session: RPCSession, didReceiveRequest method: String, with params: [Value]) -> Result<Value, Error>? {
        guard
            case let .started(state) = state,
            let handler = state.requestHandlers[method]
        else {
            return delegate?.nvim(self, didRequest: method, with: params)
        }

        do {
            return try .success(handler(params))
        } catch {
            return .failure(error)
        }
    }
}
