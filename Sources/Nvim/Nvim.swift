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

import AppKit
import Foundation
import Toolkit

public enum NvimError: Error {
    case processStopped
    case apiFailure(APIError)
    case rpcFailure(RPCError)
}

public protocol NvimDelegate: AnyObject {
    func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>?
    func nvim(_ nvim: Nvim, didFailWithError error: NvimError)
}

public class Nvim {
    
    /// Starts a new Nvim process.
    public static func start(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        delegate: NvimDelegate? = nil
    ) throws -> Nvim {
        let input = Pipe()
        let output = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "nvim",
            "--headless",
            "--embed",
            "-n", // Ignore swap files.
            "--clean", // Don't load default config and plugins.
            "-u", configURL().path,
        ]
        process.standardInput = input
        process.standardOutput = output
        process.environment = [
            "PATH": "$PATH:$HOME/bin"
                // MacPorts: https://guide.macports.org/#installing.shell.postflight
                + ":/usr/local/bin"
                // Homebrew: https://docs.brew.sh/FAQ#why-should-i-install-homebrew-in-the-default-location
                + ":/opt/homebrew/bin:/opt/local/bin"
                // XDG: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
                + ":$HOME/.local/bin",
        ]
        try process.run()

        return Nvim(
            process: process,
            session: RPCSession(
                input: input.fileHandleForWriting,
                output: output.fileHandleForReading
            ),
            delegate: delegate
        )
    }

    /// Locates ShadowVim's default configuration file.
    ///
    /// Precedence:
    ///   1. $XDG_CONFIG_HOME/svim/init.vim
    ///   2. $XDG_CONFIG_HOME/svim/init.lua
    ///   3. ~/.config/svim/init.vim
    ///   4. ~/.config/svim/init.lua
    ///
    /// See https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
    private static func configURL() -> URL {
        var configDir = ProcessInfo.processInfo
            .environment["XDG_CONFIG_HOME"] ?? "~/.config"
        configDir = NSString(string: configDir).expandingTildeInPath

        let configBase = URL(fileURLWithPath: configDir, isDirectory: true)
            .appendingPathComponent("svim/init", isDirectory: false)
        let vimlConfig = configBase.appendingPathExtension("vim")
        let luaConfig = configBase.appendingPathExtension("lua")

        return ((try? vimlConfig.checkResourceIsReachable()) ?? false)
            ? vimlConfig
            : luaConfig
    }

    public let api: API
    public let events: EventDispatcher
    public weak var delegate: NvimDelegate?
    private let process: Process
    private let session: RPCSession
    private var isStopped = false

    /// The API lock is used to protect calls to `api`.
    ///
    /// Using the shared `api` property, each call is in its own transaction.
    /// If you need to perform a sequence of `API` calls in a single atomic
    /// transaction, use `transaction()`.
    private let apiLock: AsyncLock

    private init(process: Process, session: RPCSession, delegate: NvimDelegate? = nil) {
        let apiLock = AsyncLock()
        let api = API(
            session: session,
            requestCallbacks: RPCRequestCallbacks(
                prepare: { apiLock.acquire() },
                onSent: { apiLock.release() }
            )
        )

        self.api = api
        self.process = process
        self.session = session
        self.events = EventDispatcher(api: api)
        self.delegate = delegate
        self.apiLock = apiLock

        session.start(delegate: self)
    }
        
    deinit {
        stop()
    }

    /// Stops the Nvim process.
    public func stop() {
        guard !isStopped else {
            return
        }
        isStopped = true
        session.close()
        process.interrupt()
    }

    /// Performs a sequence of `API` calls in a single atomic transaction.
    ///
    /// You must return an `Async` object completed when the transaction is
    /// done.
    public func transaction<Value>(
        _ block: @escaping (API) -> APIAsync<Value>
    ) -> Async<Value, NvimError> {
        guard !isStopped else {
            return .failure(.processStopped)
        }
        
        return apiLock.acquire()
            .setFailureType(to: APIError.self)
            .flatMap { [self] in
                block(API(session: session))
            }
            .mapError { NvimError.apiFailure($0) }
            .onCompletion { [self] _ in
                apiLock.release()
            }
    }
}

extension Nvim: RPCSessionDelegate {
    func session(_ session: RPCSession, didFailWithError error: RPCError) {
        delegate?.nvim(self, didFailWithError: .rpcFailure(error))
    }

    func session(_ session: RPCSession, didReceiveNotification method: String, with params: [Value]) {
        events.dispatch(event: method, data: params)
    }

    func session(_ session: RPCSession, didReceiveRequest method: String, with params: [Value]) -> Result<Value, Error>? {
        delegate?.nvim(self, didRequest: method, with: params)
    }
}
