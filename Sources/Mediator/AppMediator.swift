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

public protocol AppMediatorDelegate: AnyObject {
    func appMediator(_ mediator: AppMediator, didFailWithError error: Error)
}

// FIXME: Dealloc on terminated process
public final class AppMediator {
    public weak var delegate: AppMediatorDelegate?

    private let app: NSRunningApplication
    private let appElement: AXUIElement
    private let nvimProcess: NvimProcess
    private var nvim: Nvim { nvimProcess.nvim }
    private let buffers: Buffers

    private var synchronizers: [String: BufferSynchronizer] = [:]
    private var currentBuffer: BufferSynchronizer?

    private var subscriptions: Set<AnyCancellable> = []

    init(app: NSRunningApplication, delegate: AppMediatorDelegate?) throws {
        self.app = app
        self.delegate = delegate
        appElement = AXUIElement.app(app)
        nvimProcess = try NvimProcess.start()
        buffers = Buffers(nvim: nvimProcess.nvim)
        nvim.delegate = self

        if let focusedElement = appElement[.focusedUIElement] as AXUIElement? {
            focusedUIElementDidChange(focusedElement)
        }

        appElement.publisher(for: .focusedUIElementChanged)
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.appMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] element in
                    focusedUIElementDidChange(element)
                }
            )
            .store(in: &subscriptions)

        nvim.events.autoCmd(event: "CursorMoved", "CursorMovedI", "ModeChanged", args: "getcursorcharpos()", "mode()")
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] error in
                    delegate?.appMediator(self, didFailWithError: error)
                },
                receiveValue: { [unowned self] params in
                    self.onCursorEvent(params: params)
                    //                Task {
                    //                    await self?.updateMode(mode: params[1].stringValue ?? "")
                    //                }
                }
            )
            .store(in: &subscriptions)

        //        var pos: CursorPosition = (0, 0)
        //        var selection: CFRange = element[.selectedTextRange] ?? CFRange(location: 0, length: 0)
        //        selection = CFRange(location: selection.location, length: 1) // Normal mode
        //        pos.row = element[.lineForIndex] ?? 0
        //        pos.col = element[.lineForIndex] ?? 0
//
//        nvim.events.autoCmd(event: "CmdlineChanged", args: "getcmdline()")
//            .assertNoFailure()
//            .sink { [weak self] params in
//                self?.more = params.first?.stringValue ?? ""
//            }
//            .store(in: &subscriptions)
    }

    deinit {
        nvimProcess.stop()
        subscriptions.removeAll()
    }

    private func focusedUIElementDidChange(_ element: AXUIElement) {
        guard
            element.isSourceEditor,
            let name = element.document()
        else {
            currentBuffer = nil
            return
        }

        buffers.edit(name: name, contents: element[.value] ?? "")
            .logFailure()
            .get { [self] handle in
                let buffer = synchronizers.getOrPut(name) {
                    BufferSynchronizer(nvim: nvim, buffer: handle, element: element, name: name, buffers: buffers)
                }

                buffer.element = element
                currentBuffer = buffer
            }
    }

    public func handle(_ event: CGEvent) -> CGEvent? {
        precondition(app.isActive)

        guard
            // Check that we're still the focused app. Useful when the Spotlight
            // modal is opened.
            isFocused,
            let bufferElement = currentBuffer?.element,
            bufferElement.hashValue == (appElement[.focusedUIElement] as AXUIElement?)?.hashValue
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
                switch event.keyCode {
                case .escape:
                    return "<Esc>"
                case .enter:
                    return "<Enter>"
                case .leftArrow:
                    return "<Left>"
                case .rightArrow:
                    return "<Right>"
                case .downArrow:
                    return "<Down>"
                case .upArrow:
                    return "<Up>"
                default:
                    return event.character
                }
            }()

            nvim.api.input(input)
                .discardResult()
                .get(onFailure: { [self] in
                    delegate?.appMediator(self, didFailWithError: $0)
                })

            return nil

        default:
            break
        }

        return event
    }

    private var isFocused: Bool {
        let focusedAppPid = try? AXUIElement.systemWide.focusedApplication()?.pid()
        return app.processIdentifier == focusedAppPid
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
