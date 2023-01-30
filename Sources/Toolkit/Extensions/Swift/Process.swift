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
    @discardableResult
    static func launchAndWait(_ args: String...) -> Int {
        launchAndWait(args: args)
    }

    static func launch(_ args: String...) -> Async<Int, Never> {
        Async { completion in
            completion(.success(launchAndWait(args: args)))
        }
    }

    private static func launchAndWait(args: [String]) -> Int {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = args
        task.launch()
        task.waitUntilExit()
        return Int(task.terminationStatus)
    }
}
