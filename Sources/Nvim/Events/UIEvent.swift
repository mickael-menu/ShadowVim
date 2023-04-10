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

public extension Nvim {
    /// Subscribes a new handler for the `redraw` event.
    /// https://neovim.io/doc/user/ui.html
    func redrawPublisher() -> AnyPublisher<UIEvent, NvimError> {
        publisher(
            for: "redraw",
            unpack: { params in
                params.compactMap { payload in
                    guard let payload = payload.arrayValue else {
                        return nil
                    }
                    return UIEvent(payload: payload)
                }
            }
        )
        .flatMap(\.publisher)
        .eraseToAnyPublisher()
    }
}

/// UI update events sent with the `redraw` notification.
///
/// https://neovim.io/doc/user/ui.html#ui-events
public enum UIEvent: Equatable {
    // MARK: Global Events

    // https://neovim.io/doc/user/ui.html#ui-global

    /// Editor mode changed.
    ///
    /// The mode parameter is a string representing the current mode. `idx` is
    /// an index into the array emitted in the `modeInfoSet` event.
    case modeChange(mode: String, idx: Int)

    /// Set mode properties. The current mode is given by the `idx` field of
    /// the `modeChange` event.
    ///
    /// `cursorStyleEnabled` is a boolean indicating if the UI should set the
    /// cursor style
    case modeInfoSet(cursorStyleEnabled: Bool, info: [ModeInfo])

    /// Notify the user with an audible bell.
    case bell

    /// Notify the user with a visual bell.
    case visualBell

    /// Nvim is done redrawing the screen.
    case flush

    // MARK: Cmdline Events

    // https://neovim.io/doc/user/ui.html#ui-cmdline

    // MARK: Message/Dialog Events

    // https://neovim.io/doc/user/ui.html#ui-messages

    /// Display a message to the user.
    ///
    /// `replaceLast` decides how multiple messages should be displayed:
    ///    - `false` Display the message together with all previous messages
    ///    that are still visible.
    ///    - `true` Replace the message in the most-recent `msgShow` call, but
    ///    any other visible message should still remain.
    case msgShow(kind: UIMessageKind, content: UIAttributedText, replaceLast: Bool)

    /// Clear all messages currently displayed by `msgShow`.
    case msgClear

    init?(payload: [Value]) {
        guard
            payload.count == 2,
            let key = payload[0].stringValue,
            let params = payload[1].arrayValue
        else {
            return nil
        }

        switch key {
        case "mode_info_set":
            guard
                params.count == 2,
                let cursorStyleEnabled = params[0].boolValue,
                let info = params[1].arrayValue
            else {
                return nil
            }

            self = .modeInfoSet(
                cursorStyleEnabled: cursorStyleEnabled,
                info: info.compactMap { ModeInfo(payload: $0) }
            )

        case "mode_change":
            guard
                params.count == 2,
                let mode = params[0].stringValue,
                let idx = params[1].intValue
            else {
                return nil
            }
            self = .modeChange(mode: mode, idx: idx)

        case "bell":
            self = .bell

        case "visual_bell":
            self = .visualBell

        case "flush":
            self = .flush

        case "msg_show":
            guard
                params.count == 3,
                let kind = params[0].stringValue,
                let content = UIAttributedText(payload: params[1]),
                let replaceLast = params[2].boolValue
            else {
                return nil
            }
            self = .msgShow(kind: UIMessageKind(rawValue: kind) ?? .unknown, content: content, replaceLast: replaceLast)

        case "msg_clear":
            self = .msgClear

        default:
            return nil
        }
    }
}

public enum UIMessageKind: String, Equatable {
    case unknown = ""

    /// `confirm()` or `:confirm` dialog
    case confirm

    /// `:substitute` confirm dialog `:s_c`
    case confirmSub = "confirm_sub"

    /// Error (errors, internal error, `:throw`, ...)
    case emsg

    /// `:echo` message
    case echo

    /// `:echomsg` message
    case echomsg

    /// `:echoerr` message
    case echoerr

    /// Error in `:lua` code
    case luaError = "lua_error"

    /// Error response from `rpcrequest()`
    case rpcError = "rpc_error"

    /// Press-enter prompt after a multiple messages
    case returnPrompt = "return_prompt"

    /// Quickfix navigation message
    case quickfix

    /// Search count message ("S" flag of 'shortmess')
    case searchCount = "search_count"

    /// Warning ("search hit BOTTOM", W10, ...)
    case wmsg
}

public typealias UIAttributeID = Int

/// A string composed of chunks with Nvim attributes.
public struct UIAttributedText: Equatable {
    public struct Chunk: Equatable {
        public let attrID: UIAttributeID
        public let text: String
    }

    public var chunks: [Chunk] = []

    /// Returns the concatenated chunks, without attribute styling.
    public var string: String {
        chunks.map(\.text).joined()
    }

    public init?(payload: Value) {
        guard let chunks = payload.arrayValue else {
            return nil
        }

        for chunk in chunks {
            guard
                let chunk = chunk.arrayValue,
                chunk.count == 2,
                let attrID = chunk[0].intValue,
                let text = chunk[1].stringValue
            else {
                return nil
            }
            self.chunks.append(Chunk(attrID: attrID, text: text))
        }
    }
}

public struct ModeInfo: Equatable {
    /// Mode descriptive name.
    public let name: String

    /// Mode code name.
    public let shortName: String

    public init?(payload: Value) {
        guard
            let dict = payload.dictValue,
            let name = dict[.string("name")]?.stringValue,
            let shortName = dict[.string("short_name")]?.stringValue
        else {
            return nil
        }

        self.name = name
        self.shortName = shortName
    }
}
