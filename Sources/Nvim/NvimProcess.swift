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

public class NvimProcess {
    public static func start(executableURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/nvim")) throws -> NvimProcess {
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
            output: output.fileHandleForReading
        )

        return NvimProcess(
            nvim: Nvim(session: session),
            process: process,
            sessionTask: Task {
                await session.run()
            }
        )
    }

    public let nvim: Nvim

    private let process: Process
    private let sessionTask: Task<Void, Error>

    init(nvim: Nvim, process: Process, sessionTask: Task<Void, Error>) {
        self.nvim = nvim
        self.process = process
        self.sessionTask = sessionTask
    }

    public func stop() {
        sessionTask.cancel()
        process.terminate()
    }
}
