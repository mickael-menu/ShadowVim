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

public extension Process {
    typealias Result = (status: Int, output: String?)

    static func launch(_ args: String...) -> Async<Result, Never> {
        Async { completion in
            completion(.success(launchAndWait(args)))
        }
    }

    @discardableResult
    static func launchAndWait(_ args: String...) -> Result {
        launchAndWait(args)
    }

    @discardableResult
    static func launchAndWait(_ args: [String]) -> Result {
        let task = Process()
        task.loadEnvironment()
        task.launchPath = "/usr/bin/env"
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return (
            status: Int(task.terminationStatus),
            output: String(data: data, encoding: .utf8)
        )
    }

    /// Loads this `Process` environment with the app environment and additional
    /// `PATH`s to start Nvim.
    func loadEnvironment() {
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        let home = env["HOME"] ?? ""

        env["PATH"] = "\(path):\(home)/bin"
            // MacPorts: https://guide.macports.org/#installing.shell.postflight
            + ":/usr/local/bin"
            // Homebrew: https://docs.brew.sh/FAQ#why-should-i-install-homebrew-in-the-default-location
            + ":/opt/homebrew/bin:/opt/local/bin"
            // XDG: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
            + ":\(home)/.local/bin"

        environment = env
    }
}
