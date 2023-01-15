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
//

import Nvim
import SwiftUI

import AXSwift

private var subscriptions: [EventSubscription] = []

final class AppViewModel: ObservableObject {
    private let process: NvimProcess
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
        process = try NvimProcess.start()

        DispatchQueue.global(qos: .userInteractive).async { [self] in
            try! self.eventTap.run()
        }
    }

    private func update(event: BufLinesEvent, control: [String]) {
        update(event)
//        assert(lines == control)
    }

    private func update(_ event: BufLinesEvent) {
        print("\(event)")
        if let lastLine = event.lastLine {
            print("\n")
//            applyBufLinesEvent(event: event, to: &lines)
//            var i = 0
//            for lineIndex in event.firstLine...lastLine {
//                i += 1
//            }

//            replaceLines(in: element.element, startLine: startLine, endLine: endLine - 1, newLines: newLines)

            let (content, lines) = getElementLines()
            
            if event.lineData.isEmpty {
                if event.firstLine == event.lastLine {
                    return
                }
                var range = lineIndexesToRange(in: lines, startLine: event.firstLine, endLine: lastLine)
                print("SET SELECTED RANGE \(event.firstLine) ... \(lastLine): \(range)")
                if event.firstLine > 0 {
                    range = CFRange(location: range.location - 1, length: range.length + 1)
                } else if lastLine < lines.count {
                    range = CFRange(location: range.location, length: range.length + 1)
                }
                try! element.setAttribute(.selectedTextRange, value: range)
                try! element.setAttribute(.selectedText, value: "")

            } else {
                let range: CFRange
                if event.firstLine >= lines.count {
                    range = CFRange(location: content.count, length: 0)
                } else {
                    range = lineIndexesToRange(in: lines, startLine: event.firstLine, endLine: lastLine)
                    print("SET SELECTED RANGE \(event.firstLine) ... \(lastLine): \(range)")
                    //                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
                }
                
                var replacement = event.lineData.joined(separator: "\n")
                if event.firstLine == lastLine {
                    if event.firstLine >= lines.count {
                        replacement = "\n" + replacement
                    } else {
                        replacement += "\n"
                    }
                }
                
                try! element.setAttribute(.selectedTextRange, value: range)
                try! self.element.setAttribute(.selectedText, value: replacement)
                //                try! self.element.setAttribute(.value, value: self.lines.joined(separator: "\n"))
//                            })
                //            try! element.setAttribute(.value, value: lines.joined(separator: "\n"))
            }
                        
//            try? element.setAttribute(.selectedTextRange, value: CFRange(location: 5, length: 0))
        } else {
            update(event.lineData)
        }
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

    func lineIndexesToRange(in lines: [any StringProtocol], startLine: Int, endLine: Int) -> CFRange {
        var startIndex = 0
        var endIndex = 0
        var count = 0
        for (i, line) in lines.enumerated() {
            if i == startLine {
                startIndex = count
                //                startIndex += lines[i].startIndex.encodedOffset
                endIndex = startIndex
            }
            if i < endLine {
                endIndex = count + line.count
                //                endIndex += lines[i].endIndex.encodedOffset
            }
            if i == endLine {
                break
            }
            count += line.count + 1
            //            if i > startLine && i < endLine {
            //                endIndex += lines[i].count + 1
            //            }
        }
        print("Create start: \(startIndex) - end: \(endIndex)")
        return CFRangeMake(startIndex, endIndex - startIndex)
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
    
    private func setCursor(line lineIndex: Int, char: Int) {
    }

    func applyBufLinesEvent(event: BufLinesEvent, to lines: inout [String]) {
        let startLine = event.firstLine
        let endLine = event.lastLine ?? startLine + event.lineData.count - 1
        let newLines = event.lineData
        lines.replaceSubrange(startLine ..< endLine, with: newLines)
    }

    func replaceLines(in element: AXUIElement, startLine: Int, endLine: Int, newLines: [String]) {
        var newLines = newLines

        var error: CFError?
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == AXError.success else {
            print("Failed to get the element's value.")
            return
        }

        guard let stringValue = value as? String else {
            print("Failed to cast the element's value to a string.")
            return
        }

        let lines = stringValue.split(separator: "\n")
        var newString = ""
        for (i, line) in lines.enumerated() {
            if i >= startLine, i <= endLine {
                newString += newLines.removeFirst() + "\n"
            } else {
                newString += line + "\n"
            }
        }
        if newLines.count > 0 {
            newString += newLines.joined(separator: "\n")
        }

        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newString as CFTypeRef) == AXError.success else {
            print("Failed to set the element's value.")
            return
        }
    }
        
    enum Mode {
        case normal
        case insert
    }
    
    private func onCursorEvent(params: [Value], mode: Mode) {
        guard
            let params = params.first?.arrayValue,
            params.count == 5,
            var lnum = params[1].intValue,
            var col = params[2].intValue
        else {
            return
        }
        lnum -= 1
        col -= 1
        print("onCursorEvent \(lnum):\(col)")

        let (_, lines) = getElementLines()
        var count = 0
        for (i, line) in lines.enumerated() {
            if i == lnum {
                count += col
                break
            }
            count += line.count + 1
        }
                
        let length: Int = {
            switch mode {
            case .normal:
                return 1
            case .insert:
                return 0
            }
        }()
        var range = CFRange(location: count, length: length)
        try! element.setAttribute(.selectedTextRange, value: range)
    }

    func initialize() async throws {
        buffer = try await nvim.buffer().get()

        print("WIN WIDTH \(try await nvim.api.winGetWidth().get())")

        let document = try! (element.attribute(.window) as UIElement?)?.attribute(.document) as String?
        let url = URL(string: document!)!
        try! await nvim.api.bufSetName(name: url.path).get()
        
        await buffer?.attach(
            sendBuffer: true,
            onLines: { event in
//                guard let lines = try? await self.buffer?.getLines().get() else {
//                    return
//                }
                DispatchQueue.main.sync {
                    self.update(event)
                }
            }
        )

        let events = nvim.events

        try await events.autoCmd(event: "CursorMoved", args: "getcursorcharpos()") { params in
            DispatchQueue.main.sync {
                self.onCursorEvent(params: params, mode: .normal)
            }
//            print("MOVED \(lnum):\(col)")
        }.get().store(in: &subscriptions)

        try await events.autoCmd(event: "CursorMovedI", args: "getcursorcharpos()") { params in
            DispatchQueue.main.sync {
                self.onCursorEvent(params: params, mode: .insert)
            }
//            print("MOVED \(params)")
//            Task { [self] in
////                print("WIN CURSOR \(try? await self.nvim.api.winGetCursor().get())")
//            }
        }.get().store(in: &subscriptions)

        try await events.autoCmd(event: "ModeChanged", args: "mode()") { params in
            Task {
                await self.updateMode(mode: params.first?.stringValue ?? "")
            }
//            print("MODE \(params)")
        }.get().store(in: &subscriptions)

        try await events.autoCmd(event: "CmdlineChanged", args: "getcmdline()") { [weak self] params in
            self?.more = params.first?.stringValue ?? ""
//            print("MODE \(params)")
        }.get().store(in: &subscriptions)
    }

    private lazy var eventTap = EventTap { [unowned self] type, event in
        switch type {
        case .keyDown:
            guard !event.flags.contains(.maskCommand) else {
                break
            }

            // See `nvim.paste` "Faster than nvim_input()."

            Task {
                switch event.getIntegerValueField(.keyboardEventKeycode) {
//                case 0x35:
//                    try await nvim.input("<ESC>")
//                case 0x24:
//                    try await nvim.input("<CR>")
                default:
                    let maxStringLength: Int = 4
                    var actualStringLength: Int = 0
                    var unicodeString = [UniChar](repeating: 0, count: Int(maxStringLength))
                    event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
                    let character = String(utf16CodeUnits: &unicodeString, count: Int(actualStringLength))
                    await nvim.api.input(character)

                    // REQUIRES Neovim 0.9
                    let sl = try await nvim.api.evalStatusline("%S").get()
                    self.cmd = sl
                    //                    print(sl)

//                    try await self.updateText(character)
                }
            }
            return nil
        default:
            break
        }
        return event
    }

    lazy var element: UIElement = {
//        let app = Application(NSRunningApplication.current)
//        let app = Application.allForBundleID("com.apple.TextEdit").first
        let app = Application.allForBundleID("com.apple.dt.Xcode").first
        let element = try! (app!.attribute(.focusedUIElement) as UIElement?)!

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
        let lines: [String] = (try? await self.buffer?.getLines().get()) ?? []
        return lines.joined(separator: "\n")
    }
}

@main
struct PhantomVimApp: App {
    @StateObject private var viewModel = try! AppViewModel()
    @State private var text: String = ""

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading) {
                Button(action: { Task { text = await viewModel.getContent() } }, label: { Text("Refresh")})
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
