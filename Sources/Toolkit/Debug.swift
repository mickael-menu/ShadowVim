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
            info += String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            if status != 0 {
                info += "exit status: \(status)"
            }

            info += "\n\n"
        }

        func defaults(_ key: String) {
            run("defaults", "read", "-app", "Xcode", key)
        }

        // macOS version
        run("sw_vers", "-productVersion")
        // Platform
        run("uname", "-m")
        // Neovim path
        run("whereis", "nvim")
        // Neovim version
        run("nvim", "--version")
        // Xcode version
        run("xcodebuild", "-version")
        // Xcode settings
        defaults("KeyBindingsMode")
        defaults("DVTTextAutoCloseBlockComment")
        defaults("DVTTextAutoInsertCloseBrace")
        defaults("DVTTextEditorTrimTrailingWhitespace")
        defaults("DVTTextEnableTypeOverCompletions")
        defaults("DVTTextIndentCaseInC")
        defaults("DVTTextUsesSyntaxAwareIndenting")

        return info
    }
}
