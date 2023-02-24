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

public protocol NvimProcessDelegate: AnyObject {
    func nvimProcess(_ nvimProcess: NvimProcess, didTerminateWithStatus status: Int)
}

public enum NvimProcessError: Error {
    case failedToReadAPIInfo
}

public final class NvimProcess {
    /// Returns the API metadata for the available Nvim process.
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
                throw NvimProcessError.failedToReadAPIInfo
            }

            return metadata
        } catch {
            logger?.e(error)
            throw NvimProcessError.failedToReadAPIInfo
        }
    }

    /// Starts a new Nvim process.
    public static func start(logger: Logger?) throws -> NvimProcess {
        // Prevent crashes when reading/writing pipes in the `RPCSession` when
        // the nvim process is terminated.
        signal(SIGPIPE, SIG_IGN)

        let input = Pipe()
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        process.arguments = [
            "nvim",
            "--headless",
            "--embed",
            "-n", // Ignore swap files.
            // This will prevent using packages.
//            "--clean", // Don't load default config and plugins.
            // Using `--cmd` instead of `-c` makes the statements available in the `init.vim`.
            "--cmd", "let g:shadowvim = v:true",
        ]

        process.standardInput = input
        process.standardOutput = output
        process.loadEnvironment()

        try process.run()

        return NvimProcess(
            process: process,
            input: input.fileHandleForWriting,
            output: output.fileHandleForReading,
            logger: logger
        )
    }

    public let process: Process
    public let input: FileHandle
    public let output: FileHandle
    public weak var delegate: NvimProcessDelegate?

    private var isRunning: Bool = true
    private let logger: Logger?

    public init(
        process: Process,
        input: FileHandle,
        output: FileHandle,
        logger: Logger?
    ) {
        self.process = process
        self.input = input
        self.output = output
        self.logger = logger

        process.terminationHandler = { [self] _ in
            DispatchQueue.main.async { self.didTerminate() }
        }
    }

    deinit {
        stop()
    }

    /// Stops the Nvim process.
    public func stop() {
        guard isRunning else {
            return
        }
        if process.isRunning {
            process.interrupt()
        }
    }

    private func didTerminate() {
        let status = Int(process.terminationStatus)
        logger?.i("Nvim process terminated with status \(status)")

        guard isRunning else {
            return
        }
        isRunning = false
        delegate?.nvimProcess(self, didTerminateWithStatus: status)
    }
}
