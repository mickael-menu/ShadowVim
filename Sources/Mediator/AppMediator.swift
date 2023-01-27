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
    private let buffers: Buffers

    private var synchronizers: [String: BufferSynchronizer] = [:]
    private var currentBuffer: BufferSynchronizer?

    private var subscriptions: Set<AnyCancellable> = []

    private init(app: NSRunningApplication) throws {
        self.app = app
        element = AXUIElement.app(app)
        nvimProcess = try NvimProcess.start()
        buffers = Buffers(nvim: nvimProcess.nvim)
        nvim.delegate = self

        if let focusedElement = element[.focusedUIElement] as AXUIElement? {
            focusedUIElementDidChange(focusedElement)
        }

        element.publisher(for: .focusedUIElementChanged)
            .assertNoFailure()
            .sink { [weak self] element in
//                print(element.hashValue, element[.role] as AXRole?, element[.description] as String?)
                self?.focusedUIElementDidChange(element)
            }
            .store(in: &subscriptions)

        nvim.events.autoCmd(event: "CursorMoved", "CursorMovedI", "ModeChanged", args: "getcursorcharpos()", "mode()")
            .assertNoFailure()
            .receive(on: DispatchQueue.main)
            .sink { params in
                self.onCursorEvent(params: params)
                Task {
                    await self.updateMode(mode: params[1].stringValue ?? "")
                }
            }
            .store(in: &subscriptions)

        nvim.events.autoCmd(event: "CmdlineChanged", args: "getcmdline()")
            .assertNoFailure()
            .sink { [weak self] params in
                self?.more = params.first?.stringValue ?? ""
            }
            .store(in: &subscriptions)
    }

    private func focusedUIElementDidChange(_ element: AXUIElement) {
//        print("Focused element \(element[.role] as AXRole?)")
        guard
            element.isValid,
            element[.role] == AXRole.textArea,
            element[.description] == "Source Editor"
        else {
            currentBuffer = nil
            return
        }

        let name = name(for: element)
        buffers.edit(name: name, contents: element[.value] ?? "")
            .assertNoFailure()
            .get { [self] handle in
                let buffer = synchronizers.getOrPut(
                    key: name,
                    defaultValue: BufferSynchronizer(nvim: nvim, buffer: handle, element: element, name: name, buffers: buffers)
                )

                buffer.element = element
                currentBuffer = buffer
            }
    }

    func name(for element: AXUIElement) -> String {
        if
            let window = try? element.get(.window) as AXUIElement?,
            let documentPath = try? window.get(.document) as String?,
            let documentURL = URL(string: documentPath)
        {
            return documentURL
                .resolvingSymlinksInPath()
                .path
                .replacingOccurrences(of: "/", with: "%")
                .replacingOccurrences(of: ":", with: "%")
        } else {
            return UUID().uuidString
        }
    }

    public func handle(_ event: CGEvent) -> CGEvent? {
        precondition(app.isActive)

        guard
            let bufferElement = currentBuffer?.element,
            bufferElement.hashValue == (element[.focusedUIElement] as AXUIElement?)?.hashValue
        else {
            return event
        }

        switch event.type {
        case .keyDown:
            guard !event.flags.contains(.maskCommand) else {
                break
            }

            // FIXME: See `nvim.paste` "Faster than nvim_input()."

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

            nvim.api.input(input)
                .discardResult()
                // FIXME: better error handling
                .get(onFailure: { print($0) })

            // REQUIRES Neovim 0.9
//                let sl = try await nvim.api.evalStatusline("%S").get()
//                self.cmd = sl

            //                    try await self.updateText(character)
            return nil

        default:
            break
        }

        return event
    }

    private func onCursorEvent(params: [Value]) {
        guard
            let buffer = currentBuffer,
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

        let (_, lines) = buffer.lines()
        var count = 0
        for (i, line) in lines.enumerated() {
            if i == lnum {
                count += col
                break
            }
            count += line.count + 1
        }

        let mode = params[1].stringValue.flatMap(Mode.init(rawValue:)) ?? .normal
        buffer.setCursor(position: count, mode: mode)
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
}

extension AppMediator: NvimDelegate {
    public func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>? {
        switch method {
        case "SVRefresh":
//            Task {
//                let content = await getContent()
//                try! element.set(.value, value: content)
//            }
            return .success(.bool(true))
        default:
            return nil
        }
    }
}
