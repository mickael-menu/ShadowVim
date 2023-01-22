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

import AX
import Combine
import Nvim
import SwiftUI

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
    private var subs: Set<AnyCancellable> = []

    init() throws {
        AXUIElement.systemWide
            .publisher(for: .focusedUIElementChanged)
            .sink(receiveCompletion: { compl in
                print("Compl \(compl)")
            }, receiveValue: { elem in
                print("Created: \(elem.hashValue)")
            })
            .store(in: &subs)

        print(element)
        app
            .publisher(for: .focusedUIElementChanged)
            .sink(receiveCompletion: { compl in
                print("Compl \(compl)")
            }, receiveValue: { elem in
                print("Created: \(elem.hashValue)")
            })
            .store(in: &subs)

        app.publisher(for: .created)
            .assertNoFailure()
            .sink { info in
                print("RECEIVE CREATED \(info)")
            }
            .store(in: &subs)

//        let t1 = try app.get(.title) as String?
//        let w1 = try app.get(.window) as AXElement?
        let (title, win, subrole) = try app.get(.title, .mainWindow, .role) as (String?, AXUIElement?, AXRole?)
        print("received", title, win, subrole)

        app.publisher(for: .focusedUIElementChanged)
            .assertNoFailure()
            .sink { element in
                print("lineForIndex", try? element.get(.lineForIndex, with: 10) as Int?)
            }
            .store(in: &subs)

        app.publisher(for: .focusedUIElementChanged)
            .map {
                $0.publisher(for: .valueChanged)
            }
            .switchToLatest()
            .assertNoFailure()
            .sink { info in
                print("RECEIVE value changed for \(info)")
            }
            .store(in: &subs)
//        let window = try app.mainWindow()!
//        let element = try? app.focusedUIElement()
//        Task {
//            while true {
//                DispatchQueue.main.async {
//                    try? element?.focus()
//                }
//                try await Task.sleep(for: .seconds(5))
//            }
//        }

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
        try! element.set(.value, value: content)
    }

    func getElementLines() -> (String, [any StringProtocol]) {
        guard let value = try? element.get(.value) as String? else {
            return ("", [])
        }
        return (value, value.split(separator: "\n", omittingEmptySubsequences: false))
    }

    private func update(_ lines: [String]) {
        self.lines = lines
        try! element.set(.value, value: lines.joined(separator: "\n"))
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
        try? element.set(.selectedTextRange, value: range)
    }

    var synchronizer: BufferSynchronizer!

    func initialize() async throws {
        try await nvim.api.command("nmap zr <Cmd>call rpcrequest(1, 'SVRefresh')<CR>").get()
        synchronizer = BufferSynchronizer(nvim: nvim, element: element)
        try await synchronizer.edit()

        let events = nvim.events

//        await nvim.api.command("autocmd CmdlineEnter * redir! >/tmp/log")
//        await nvim.api.command("autocmd CmdlineEnter * redir END")
//        await nvim.api.command("autocmd CmdwinLeave * redir END")

        await events.autoCmd(event: "CursorMoved", "CursorMovedI", "ModeChanged", args: "getcursorcharpos()", "mode()")
            .assertNoFailure()
            .receive(on: DispatchQueue.main)
            .sink { params in
                self.onCursorEvent(params: params)
                Task {
                    await self.updateMode(mode: params[1].stringValue ?? "")
                }
            }
            .store(in: &subs)

//        try await events.autoCmd(event: "ModeChanged", args: "mode()") { params in
//            Task {
//                await self.updateMode(mode: params.first?.stringValue ?? "")
//            }
        ////            print("MODE \(params)")
//        }.get().store(in: &subscriptions)

        await events.autoCmd(event: "CmdlineChanged", args: "getcmdline()")
            .assertNoFailure()
            .sink { [weak self] params in
                self?.more = params.first?.stringValue ?? ""
                //            print("MODE \(params)")
            }
            .store(in: &subs)
    }

    private lazy var eventTap = EventTap { [unowned self] type, event in
        guard
            let appFrontmost = try? self.app.get(.frontmost) as Bool?, appFrontmost
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
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                            Task {
//                                print("END")
//                                await nvim.api.command("redir END")
//                                print(try! String(contentsOf: URL(filePath: "/tmp/log")))
//                            }
//                        }

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

    lazy var app: AXUIElement =
        AXUIElement
            .app(bundleID: "com.apple.TextEdit")!
//        .app(bundleID: "com.apple.dt.Xcode")!

    lazy var element: AXUIElement =
        try! app.get(.focusedUIElement)!

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
