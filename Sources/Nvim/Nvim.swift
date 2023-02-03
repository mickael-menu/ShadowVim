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
import Combine
import Foundation
import Toolkit

public enum NvimError: Error {
    case processStopped(status: Int)
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
        logger: Logger?,
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
        let nvim = Nvim(
            process: process,
            session: RPCSession(
                logger: logger?.domain("rpc"),
                input: input.fileHandleForWriting,
                output: output.fileHandleForReading
            ),
            logger: logger,
            delegate: delegate
        )
        
        try process.run()
        DispatchQueue.global().async {
            process.waitUntilExit()
            nvim.stop()
            logger?.w("Nvim closed with status \(process.terminationStatus)")
            nvim.delegate?.nvim(nvim, didFailWithError: .processStopped(status: Int(process.terminationStatus)))
        }
        
        return nvim
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
    private let logger: Logger?
    private var isStopped = false
    private var subscriptions: Set<AnyCancellable> = []

    private init(process: Process, session: RPCSession, logger: Logger?, delegate: NvimDelegate? = nil) {
        let api = API(session: session, logger: logger?.domain("api"))
        self.api = api
        self.process = process
        self.logger = logger
        self.session = session
        events = EventDispatcher(api: api, logger: logger?.domain("events"))
        self.delegate = delegate

        NotificationCenter.default
            .publisher(for: Process.didTerminateNotification, object: process)
            .sink { [weak self] _ in
                self?.didTerminate()
            }
            .store(in: &subscriptions)

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
        process.interrupt()
        didTerminate()
    }

    private func didTerminate() {
        guard !isStopped else {
            return
        }
        isStopped = true
        session.close()
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
