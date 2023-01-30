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

    @discardableResult
    static func launchAndWait(_ args: String...) -> Result {
        launchAndWait(args: args)
    }

    static func launch(_ args: String...) -> Async<Result, Never> {
        Async { completion in
            completion(.success(launchAndWait(args: args)))
        }
    }

    private static func launchAndWait(args: [String]) -> Result {
        let task = Process()
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
}
