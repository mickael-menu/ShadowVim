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
import MessagePack
import Toolkit

/// API metadata for the available Nvim process.
///
/// This is used to check the Nvim version.
public struct APIMetadata {
    public let rawMetadata: [String: Value]

    public init?(messagePackValue: MessagePackValue) {
        guard let rawMetadata = try? Value.from(messagePackValue).get().dictValue else {
            return nil
        }

        self.init(rawMetadata: rawMetadata.reduce(into: [:]) { dict, v in
            guard let key = v.key.stringValue else {
                return
            }
            dict[key] = v.value
        })
    }

    public init(rawMetadata: [String: Value]) {
        self.rawMetadata = rawMetadata
    }

    public var version: Version? {
        guard
            let components = rawMetadata["version"]?.dictValue,
            let major = components[.string("major")]?.intValue,
            let minor = components[.string("minor")]?.intValue,
            let patch = components[.string("patch")]?.intValue
        else {
            return nil
        }

        return Version(major: major, minor: minor, patch: patch)
    }
}
