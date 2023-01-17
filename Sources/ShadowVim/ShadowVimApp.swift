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

import Nvim
import SwiftUI

import AXSwift

private var subscriptions: [EventSubscription] = []

final class AppViewModel: ObservableObject {
    private var process: NvimProcess!
    private var buffer: Buffer?

    private var nvim: Nvim { process.nvim }

//    @Published private(set) var content: String = ""
    private var cmd: String = "" {
        didSet { Task { await updateCmdline() } }
    }

    private var more: String = "" {
        didSet { Task { await updateCmdline() } }
    }

    @Published private(set) var cmdline: String = ""

    @Published private(set) var mode: String = ""

    private var lines: [String] = []

    init() throws {
        process = try NvimProcess.start(
            onRequest: { [unowned self] method, _ in
                switch method {
                case "SVRefresh":
                    Task {
                        print("Refresh")
                        await self.refresh()
                    }
                    return .success(.bool(true))
                default:
                    return nil
                }
            }
        )

        Task {
            try! await self.eventTap.run()
        }
    }

    @MainActor
    func refresh() async {
        let content = await getContent()
        try! element.setAttribute(.value, value: content)
    }

    private func update(_ event: BufLinesEvent) throws {
        print("\(event)")
        print("\n")

        let content = (try element.attribute(.value) as String?) ?? ""
        guard let (range, replacement) = event.changes(in: content) else {
            return
        }

        let cfRange = range.cfRange(in: content)
        try element.setAttribute(.selectedTextRange, value: cfRange)
        try element.setAttribute(.selectedText, value: replacement)
    }

    func getElementLines() -> (String, [any StringProtocol]) {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element.element, kAXValueAttribute as CFString, &value) == AXError.success else {
            print("Failed to get the element's value.")
            return ("", [])
        }
        guard let stringValue = value as? String else {
            print("Failed to cast the element's value to a string.")
            return ("", [])
        }

        return (stringValue, stringValue.split(separator: "\n", omittingEmptySubsequences: false))
    }

    private func update(_ lines: [String]) {
        self.lines = lines
        try! element.setAttribute(.value, value: lines.joined(separator: "\n"))
    }

    @MainActor
    private func updateCmdline() {
        cmdline = cmd + more
    }

    @MainActor
    private func updateMode(mode: String) {
        self.mode = mode
        more = ""
    }

    private func setCursor(line lineIndex: Int, char: Int) {}

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
        let length: Int = {
            switch mode {
            case .normal:
                return 1
            case .insert:
                return 0
            }
        }()
        let range = CFRange(location: position, length: length)
        try? element.setAttribute(.selectedTextRange, value: range)
    }

    var synchronizer: BufferSynchronizer!

    func initialize() async throws {
        try await nvim.api.command("nmap zr <Cmd>call rpcrequest(1, 'SVRefresh')<CR>").get()
        synchronizer = BufferSynchronizer(nvim: nvim, element: element)
        try await synchronizer.edit()

//        buffer = try await nvim.buffer().get()
//
//        print("WIN WIDTH \(try await nvim.api.winGetWidth().get())")
//
        ////        let document = try! (element.attribute(.window) as UIElement?)?.attribute(.document) as String?
        ////        let url = URL(string: document!)!
        ////        try! await nvim.api.bufSetName(name: url.path).get()
//
//        await buffer?.attach(
//            sendBuffer: true,
//            onLines: { event in
        ////                guard let lines = try? await self.buffer?.getLines().get() else {
        ////                    return
        ////                }
//                DispatchQueue.main.sync {
//                    try! self.update(event)
//                }
//            }
//        )

        let events = nvim.events

        try await events.autoCmd(event: "CursorMoved", "CursorMovedI", "ModeChanged", args: "getcursorcharpos()", "mode()") { params in
            DispatchQueue.main.sync {
                self.onCursorEvent(params: params)
            }

            Task {
                await self.updateMode(mode: params[1].stringValue ?? "")
            }
        }.get().store(in: &subscriptions)

//        try await events.autoCmd(event: "ModeChanged", args: "mode()") { params in
//            Task {
//                await self.updateMode(mode: params.first?.stringValue ?? "")
//            }
        ////            print("MODE \(params)")
//        }.get().store(in: &subscriptions)

        try await events.autoCmd(event: "CmdlineChanged", args: "getcmdline()") { [weak self] params in
            self?.more = params.first?.stringValue ?? ""
//            print("MODE \(params)")
        }.get().store(in: &subscriptions)
    }

    private lazy var eventTap = EventTap { [unowned self] type, event in
        guard
            let appFrontmost = try? self.app.attribute(.frontmost) as Bool?, appFrontmost
        else {
            return event
        }

        switch type {
        case .keyDown:
            guard !event.flags.contains(.maskCommand) else {
                break
            }

            // See `nvim.paste` "Faster than nvim_input()."

            Task {
                let input: String = {
                    switch event.getIntegerValueField(.keyboardEventKeycode) {
                    case 0x35:
                        return "<ESC>"
                    case 0x24:
                        return "<CR>"
                    case 0x7B:
                        return "<left>"
                    case 0x7C:
                        return "<right>"
                    case 0x7D:
                        return "<down>"
                    case 0x7E:
                        return "<up>"
                    default:
                        let maxStringLength: Int = 4
                        var actualStringLength: Int = 0
                        var unicodeString = [UniChar](repeating: 0, count: Int(maxStringLength))
                        event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
                        return String(utf16CodeUnits: &unicodeString, count: Int(actualStringLength))
                    }
                }()

                try await nvim.api.input(input).get()

                // REQUIRES Neovim 0.9
                let sl = try await nvim.api.evalStatusline("%S").get()
                self.cmd = sl
                //                    print(sl)

//                    try await self.updateText(character)
            }
            return nil
        default:
            break
        }
        return event
    }

    lazy var app: Application =
//        Application(NSRunningApplication.current)
//        Application.allForBundleID("com.apple.TextEdit")[0]
        Application.allForBundleID("com.apple.dt.Xcode")[0]

    lazy var element: UIElement = {
        let element = try! (app.attribute(.focusedUIElement) as UIElement?)!

//        Task {
//            while true {
//                try await Task.sleep(for: .seconds(2))
//                let position = try! element.attribute(.position) as CGPoint?
//                print(position)
//            }
//        }
        return element
    }()

    @MainActor
    func updateText(_ char: String) throws {
        //                    print("FOCUS \(try! app?.attribute(.focusedUIElement) as AXUIElement?)")
        //                    print("APP \(app)")
        //                    print("WINDOW \(try! app?.windows()?.first)")
    }

    func getContent() async -> String {
        let lines: [String] = (try? await buffer?.getLines().get()) ?? []
        return lines.joined(separator: "\n")
    }
}

@main
struct ShadowVimApp: App {
    @StateObject private var viewModel = try! AppViewModel()
    @State private var text: String = ""

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading) {
                Button(action: { Task { text = await viewModel.getContent() } }, label: { Text("Refresh") })
                TextEditor(
                    text: $text
                )
                .lineLimit(nil)
                .font(.body.monospaced())
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: 400, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .task {
                    do {
                        try await viewModel.initialize()
                    } catch {
                        print(error)
                    }
                }
                HStack {
                    Text(viewModel.mode).font(.title2)
                    Text(viewModel.cmdline)
                    Spacer()
                }
            }.padding()
        }
    }
}
