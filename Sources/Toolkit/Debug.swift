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

/// Indicates whether the app is running without release optimizations.
private let debug: Bool = {
    var isDebug = false
    func set(debug: Bool) -> Bool {
        isDebug = debug
        return isDebug
    }
    // assert:
    // "Condition is only evaluated in playgrounds and -Onone builds."
    // so isDebug is never changed to true in Release builds
    assert(set(debug: true))
    return isDebug
}()

public enum Debug {
    public static var isDebugging: Bool { debug }

    public static func printCallStack() {
        Thread.callStackSymbols.forEach { print($0) }
    }

    /// Returns information about the OS and ShadowVim version.
    public static func info() async -> String {
        var info = ""

        let bundleInfo = Bundle.main.infoDictionary ?? [:]
        let releaseVersion = (bundleInfo["CFBundleShortVersionString"] as? String) ?? ""
        let buildVersion = (bundleInfo["CFBundleVersion"] as? String) ?? ""

        info += "ShadowVim \(releaseVersion) (\(buildVersion))\n\n"

        func run(_ args: String...) {
            info += "$ " + args.joined(separator: " ") + "\n"

            let (status, output) = Process.launchAndWait(args)
            info += output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if status != 0 {
                info += "exit status: \(status)"
            }

            info += "\n\n"
        }

        // macOS version
        run("sw_vers", "-productVersion")
        // Platform
        run("uname", "-m")
        // Xcode version
        run("xcodebuild", "-version")
        // Neovim version
        run("nvim", "--version")

        return info
    }
}
