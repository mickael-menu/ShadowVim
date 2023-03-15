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
import Combine
import Foundation
import Nvim
import Toolkit

enum NvimControllerError: LocalizedError {
    case deprecatedCommand(name: String, replacement: String)

    var errorDescription: String? {
        switch self {
        case let .deprecatedCommand(name: name, _):
            return "'\(name)' is deprecated"
        }
    }

    var failureReason: String? {
        switch self {
        case let .deprecatedCommand(_, replacement: replacement):
            return replacement
        }
    }
}

protocol NvimControllerDelegate: AnyObject {
    /// An error occurred.
    func nvimController(_ nvimController: NvimController, didFailWithError error: Error)

    /// The user requested to synchronize the buffers using `source` as the
    /// source of truth.
    func nvimController(_ nvimController: NvimController, synchronizeFocusedBufferUsing source: BufferHost)

    /// Simulates a key combo or mouse press in the app using an Nvim notation.
    func nvimController(_ nvimController: NvimController, press notation: Notation) -> Bool
}

/// Manages the Nvim instance and offers a high-level API to manipulate it.
final class NvimController {
    weak var delegate: NvimControllerDelegate?

    private let nvim: Nvim
    private let buffers: NvimBuffers
    private let logger: Logger?
    private var subscriptions: Set<AnyCancellable> = []
    private let enableKeysPassthrough: () -> Void
    private let resetShadowVim: () -> Void

    init(
        nvim: Nvim,
        buffers: NvimBuffers,
        logger: Logger?,
        enableKeysPassthrough: @escaping () -> Void,
        resetShadowVim: @escaping () -> Void
    ) {
        self.nvim = nvim
        self.buffers = buffers
        self.logger = logger
        self.enableKeysPassthrough = enableKeysPassthrough
        self.resetShadowVim = resetShadowVim

        nvim.delegate = self
    }

    func start() async throws {
        try nvim.start(headless: false)
        buffers.start()

        try await setupUserCommands()
            .flatMap { self.attachUI() }
            .async()
    }

    func stop() {
        nvim.stop()
        subscriptions.removeAll()
    }

    private func setupUserCommands() -> Async<Void, NvimError> {
        withAsyncGroup { group in
            nvim.add(command: "SVSynchronizeUI") { [weak self] _ in
                if let self {
                    self.delegate?.nvimController(self, synchronizeFocusedBufferUsing: .nvim)
                }
                return .nil
            }
            .add(to: group)

            nvim.add(command: "SVSynchronizeNvim") { [weak self] _ in
                if let self {
                    self.delegate?.nvimController(self, synchronizeFocusedBufferUsing: .ui)
                }
                return .nil
            }
            .add(to: group)

            nvim.add(command: "SVPressKeys", args: .one) { [weak self] _ in
                if let self = self {
                    let error = NvimControllerError.deprecatedCommand(name: "SVPressKeys", replacement: "Use 'SVPress' in your Neovim configuration instead.")
                    self.delegate?.nvimController(self, didFailWithError: error)
                }
                return .bool(false)
            }
            .add(to: group)

            nvim.add(command: "SVPress", args: .one) { [weak self] params in
                guard
                    let self,
                    let delegate = self.delegate,
                    params.count == 1,
                    case let .string(notation) = params[0]
                else {
                    return .bool(false)
                }
                return .bool(delegate.nvimController(self, press: notation))
            }
            .add(to: group)

            nvim.add(command: "SVEnableKeysPassthrough") { [weak self] _ in
                self?.enableKeysPassthrough()
                return .nil
            }
            .add(to: group)

            nvim.add(command: "SVReset") { [weak self] _ in
                self?.resetShadowVim()
                return .nil
            }
            .add(to: group)
        }
    }

    private func attachUI() -> Async<Void, NvimError> {
        // Must be observed before attaching the UI, as the user configuration
        // might perform blocking prompts.
        nvim.redrawPublisher()
            .assertNoFailure()
            .sink { [unowned self] event in
                switch event {
                case .flush:
                    break
                default:
                    print(event)
                }
            }
            .store(in: &subscriptions)

        return nvim.attachUI()
    }

    /// This publisher is used to observe the Neovim selection and mode
    /// changes.
    func cursorPublisher() -> AnyPublisher<(BufferHandle, Cursor), NvimError> {
        nvim.autoCmdPublisher(
            for: "ModeChanged", "CursorMoved", "CursorMovedI",
            args: "bufnr()", "mode()", "getcharpos('.')", "getcharpos('v')",
            unpack: { params -> (BufferHandle, Cursor)? in
                guard
                    params.count == 4,
                    let buffer: BufferHandle = params[0].intValue,
                    let mode = params[1].stringValue,
                    let position = BuiltinFunctions.GetposResult(params[2]),
                    let visual = BuiltinFunctions.GetposResult(params[3])
                else {
                    return nil
                }

                let cursor = Cursor(
                    mode: Mode(rawValue: mode) ?? .normal,
                    position: position.position,
                    visual: visual.position
                )
                return (buffer, cursor)
            }
        )
    }

    // MARK: - API

    func editBuffer(name: BufferName, contents: @escaping () -> String) -> Async<NvimBuffer, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return buffers.edit(name: name, contents: contents, with: vim)
    }

    func setLines(in buffer: NvimBuffer, diff: CollectionDifference<String>) -> Async<Void, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return vim.atomic(in: buffer) { vim in
            withAsyncGroup { group in
                for change in diff {
                    var start: LineIndex
                    var end: LineIndex
                    var replacement: [String]
                    switch change {
                    case let .insert(offset: offset, element: element, _):
                        start = offset
                        end = offset
                        replacement = [element]
                    case let .remove(offset: offset, _, _):
                        start = offset
                        end = offset + 1
                        replacement = []
                    }
                    vim.api.bufSetLines(buffer: buffer.handle, start: start, end: end, replacement: replacement)
                        .add(to: group)
                }
            }
        }
    }

    func setCursor(in buffer: NvimBuffer, at position: BufferPosition) -> Async<Void, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return vim.atomic(in: buffer) { vim in
            vim.api.winSetCursor(position: position, failOnInvalidPosition: false)
        }
        .discardResult()
    }

    /// Starts the Neovim Visual mode and selects from the given `start` and
    /// `end` positions.
    func startVisual(in buffer: NvimBuffer, from start: BufferPosition, to end: BufferPosition) -> Async<Void, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return vim.atomic(in: buffer) { vim in
            vim.cmd(
                """
                " Exit the current mode, hopefully.
                execute "normal! \\<Ignore>\\<Esc>"
                normal! \(start.line)G\(start.column)|v\(end.line)G\(end.column)|",
                """
            )
        }
        .discardResult()
    }

    /// Exits the Neovim Visual mode (character, line or block-wise).
    func stopVisual() -> Async<Void, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return vim.cmd(
            """
            if mode() =~ "^[vV\\<C-v>]$"
                execute "normal! \\<Ignore>\\<Esc>"
            endif
            """
        )
        .discardResult()
    }

    // MARK: - Input handling

    private let cmdZ = KeyCombo(.z, modifiers: .command)
    private let cmdShiftZ = KeyCombo(.z, modifiers: [.command, .shift])
    private let cmdV = KeyCombo(.v, modifiers: [.command])

    func handle(_ event: KeyEvent, in buffer: NvimBuffer) -> Bool {
        switch event.keyCombo {
        case cmdZ:
            nvim.vim?.atomic(in: buffer) { vim in
                vim.cmd.undo()
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

        case cmdShiftZ:
            nvim.vim?.atomic(in: buffer) { vim in
                vim.cmd.redo()
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

        case cmdV:
            // We override the system paste behavior to improve performance and
            // nvim's undo history.
            guard let text = NSPasteboard.get() else {
                break
            }
            nvim.vim?.atomic(in: buffer) { vim in
                vim.api.paste(text)
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()

        default:
            let mods = event.keyCombo.modifiers

            // Passthrough for ⌘-based keyboard shortcuts.
            guard
                !mods.contains(.command)
            else {
                return false
            }

            nvim.vim?.atomic(in: buffer) { vim in
                // If the user pressed control, we send the key combo as is to
                // be able to remap this keyboard shortcut in Nvim.
                // Otherwise, we send the unicode character for this event.
                // See Documentation/Research/Keyboard.md.
                if
                    !mods.contains(.control),
                    !event.keyCombo.key.isNonPrintableCharacter,
                    let character = event.character
                {
                    return vim.api.input(character)
                } else {
                    return vim.api.input(event.keyCombo)
                }
            }
            .discardResult()
            .forwardErrorToDelegate(of: self)
            .run()
        }
        return true
    }
}

extension NvimController: NvimDelegate {
    func nvim(_ nvim: Nvim, didRequest method: String, with data: [Value]) -> Result<Value, Error>? {
        logger?.w("Received unknown RPC request", ["method": method, "data": data])
        return nil
    }

    func nvim(_ nvim: Nvim, didFailWithError error: NvimError) {
        delegate?.nvimController(self, didFailWithError: error)
    }
}

private extension Async {
    func forwardErrorToDelegate(of nvimController: NvimController) -> Async<Success, Never> {
        map(
            success: { val, compl in compl(.success(val)) },
            failure: { error, _ in
                nvimController.delegate?.nvimController(nvimController, didFailWithError: error)
            }
        )
    }
}
