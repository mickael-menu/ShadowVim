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

import AppKit
import AX
import Combine
import Foundation
import Nvim
import Toolkit

// FIXME: Dealloc on terminated process
public final class AppMediator {
    /// Global shared instances per `pid`.
    @Atomic private static var sharedInstances: [pid_t: AppMediator] = [:]

    /// Gets the shared instance for the given application, creating it if needed.
    public static func shared(for app: NSRunningApplication) throws -> AppMediator {
        if let instance = sharedInstances[app.processIdentifier] {
            return instance
        }

        return try $sharedInstances.write {
            // In very unlikely case the instance was created after the previous read.
            if let instance = $0[app.processIdentifier] {
                return instance
            }
            let instance = try AppMediator(app: app)
            $0[app.processIdentifier] = instance
            return instance
        }
    }

    private let app: NSRunningApplication
    private let element: AXUIElement
    private let nvimProcess: NvimProcess
    private var nvim: Nvim { nvimProcess.nvim }
    private var synchronizer: BufferSynchronizer?
    private var textArea: AXUIElement?
    private var subscriptions: Set<AnyCancellable> = []

    private init(app: NSRunningApplication) throws {
        self.app = app
        element = AXUIElement.app(app)
        nvimProcess = try NvimProcess.start()
        nvim.delegate = self
        
        Task {
            guard
                let textArea = try? element.get(.focusedUIElement) as AXUIElement?,
                (try? textArea.role()) == .textArea
            else {
                return
            }

            await nvim.events.autoCmd(event: "CursorMoved", "CursorMovedI", "ModeChanged", args: "getcursorcharpos()", "mode()")
                .assertNoFailure()
                .receive(on: DispatchQueue.main)
                .sink { params in
                    self.onCursorEvent(params: params)
                    Task {
                        await self.updateMode(mode: params[1].stringValue ?? "")
                    }
                }
                .store(in: &subscriptions)

            await nvim.events.autoCmd(event: "CmdlineChanged", args: "getcmdline()")
                .assertNoFailure()
                .sink { [weak self] params in
                    self?.more = params.first?.stringValue ?? ""
                    //            print("MODE \(params)")
                }
                .store(in: &subscriptions)
                        
            self.textArea = textArea
            self.synchronizer = BufferSynchronizer(nvim: nvim, element: textArea)
            try await synchronizer?.edit()
        }
    }

    public func handle(_ event: CGEvent) -> CGEvent? {
        precondition(app.isActive)

        switch event.type {
        case .keyDown:
            guard !event.flags.contains(.maskCommand) else {
                break
            }

            // FIXME: See `nvim.paste` "Faster than nvim_input()."

            Task {
                let input: String = {
                    switch event.getIntegerValueField(.keyboardEventKeycode) {
                    case 0x35:
                        return "<Esc>"
                    case 0x24:
                        return "<Enter>"
                    case 0x7B:
                        return "<Left>"
                    case 0x7C:
                        return "<Right>"
                    case 0x7D:
                        return "<Down>"
                    case 0x7E:
                        return "<Up>"
                    default:
                        let maxStringLength: Int = 4
                        var actualStringLength: Int = 0
                        var unicodeString = [UniChar](repeating: 0, count: Int(maxStringLength))
                        event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
                        return String(utf16CodeUnits: &unicodeString, count: Int(actualStringLength))
                    }
                }()

                await nvim.api.input(input)
                    .onError { print($0) } // FIXME: better error handling

                // REQUIRES Neovim 0.9
//                let sl = try await nvim.api.evalStatusline("%S").get()
//                self.cmd = sl
                //                    print(sl)

                //                    try await self.updateText(character)
            }
            return nil

        default:
            break
        }

        return event
    }

    enum Mode: String {
        case normal = "n"
        case insert = "i"
    }

    private func onCursorEvent(params: [Value]) {
        guard
            params.count == 2,
            let cursorParams = params[0].arrayValue,
            cursorParams.count == 5,
            var lnum = cursorParams[1].intValue,
            var col = cursorParams[2].intValue
        else {
            return
        }
        lnum -= 1
        col -= 1

        let (_, lines) = getElementLines()
        var count = 0
        for (i, line) in lines.enumerated() {
            if i == lnum {
                count += col
                break
            }
            count += line.count + 1
        }

        let mode = params[1].stringValue.flatMap(Mode.init(rawValue:)) ?? .normal
        setCursor(position: count, mode: mode)
    }

    private func setCursor(position: Int, mode: Mode) {
        guard let textArea = textArea else {
            return
        }
        let length: Int = {
            switch mode {
            case .normal:
                return 1
            case .insert:
                return 0
            }
        }()
        let range = CFRange(location: position, length: length)
        try? textArea.set(.selectedTextRange, value: range)
    }

    private func getElementLines() -> (String, [any StringProtocol]) {
        guard let value = try? textArea?.get(.value) as String? else {
            return ("", [])
        }
        return (value, value.split(separator: "\n", omittingEmptySubsequences: false))
    }
        
        private var cmd: String = "" {
            didSet { Task { await updateCmdline() } }
        }

        private var more: String = "" {
            didSet { Task { await updateCmdline() } }
        }

        @Published private(set) var cmdline: String = ""

        @Published private(set) var mode: String = ""

        @MainActor
        private func updateCmdline() {
            cmdline = cmd + more
        }

        @MainActor
        private func updateMode(mode: String) {
            self.mode = mode
            more = ""
        }
    
    func getContent() async -> String {
        let lines: [String] = (try? await nvim.buffer().getLines().get()) ?? []
        return lines.joined(separator: "\n")
    }
}

extension AppMediator: NvimDelegate {
    public func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>? {
        switch method {
        case "SVRefresh":
            Task {
                let content = await getContent()
                try! element.set(.value, value: content)
            }
            return .success(.bool(true))
        default:
            return nil
        }
    }
}
