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

extension Value {
    static func from(_ value: MessagePackValue) -> Result<Value, RPCError> {
        do {
            switch value {
            case .nil:
                return .success(.nil)
            case let .bool(b):
                return .success(.bool(b))
            case let .int(i):
                return .success(.int(Int(i)))
            case let .uint(i):
                return .success(.int(Int(i)))
            case let .float(f):
                return .success(.double(Double(f)))
            case let .double(d):
                return .success(.double(d))
            case let .string(s):
                return .success(.string(s))
            case let .binary(b):
                guard let s = String(data: b, encoding: .utf8) else {
                    return .failure(.unexpectedMessagePackValue(value))
                }
                return .success(.string(s))
            case let .array(a):
                return try .success(.array(a.map { try Value.from($0).get() }))
            case let .map(m):
                return try .success(.dict(m.reduce(into: [:]) { d, i in
                    d[try Value.from(i.key).get()] = try Value.from(i.value).get()
                }))

            // MessagePack-RPC extensions as defined in `nvim_get_api_info()`
            //
            // ```
            // types = {
            //   Buffer = {
            //     id = 0,
            //     prefix = "nvim_buf_"
            //   },
            //   Window = {
            //     id = 1,
            //     prefix = "nvim_win_"
            //   },
            //   Tabpage = {
            //     id = 2,
            //     prefix = "nvim_tabpage_"
            //   }
            // }
            // ```
            case let .extended(type, data):
                guard let wrappedValue = try? MessagePack.unpackFirst(data).intValue else {
                    return .failure(.unexpectedMessagePackValue(value))
                }

                switch type {
                case 0:
                    return .success(.buffer(BufferHandle(wrappedValue)))
                case 1:
                    return .success(.buffer(WindowHandle(wrappedValue)))
                case 2:
                    return .success(.buffer(TabpageHandle(wrappedValue)))
                default:
                    return .failure(.unexpectedMessagePackValue(value))
                }
            }
        } catch let error as RPCError {
            return .failure(error)
        } catch {
            fatalError("Unexpected error \(error)")
        }
    }

    var messagePackValue: MessagePackValue {
        switch self {
        case .nil:
            return .nil
        case let .bool(b):
            return .bool(b)
        case let .int(i):
            return .int(Int64(i))
        case let .double(d):
            return .double(d)
        case let .string(s):
            return .string(s)
        case let .array(a):
            return .array(a.map(\.messagePackValue))
        case let .dict(d):
            return .map(d.reduce(into: [:]) { d, i in
                d[i.key.messagePackValue] = i.value.messagePackValue
            })
        case let .buffer(b):
            return .extended(0, MessagePack.pack(.uint(UInt64(b))))
        case let .window(w):
            return .extended(1, MessagePack.pack(.uint(UInt64(w))))
        case let .tabpage(t):
            return .extended(2, MessagePack.pack(.uint(UInt64(t))))
        }
    }
}
