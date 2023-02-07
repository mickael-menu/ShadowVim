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

import ApplicationServices
import Foundation
import Toolkit

/// Returns whether the current process is a trusted accessibility client.
///
/// - Parameter prompt: Indicates whether the user will be informed if the
/// current process is untrusted. This could be used, for example, on
/// application startup to always warn a user if accessibility is not enabled
/// for the current process. Prompting occurs asynchronously and does not
/// affect the return value.
@discardableResult
public func isProcessTrusted(prompt: Bool = false) -> Bool {
    AXIsProcessTrustedWithOptions([
        kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt,
    ] as CFDictionary)
}

public func setLogger(_ logger: Logger?) {
    axLogger = logger
}

var axLogger: Logger?
