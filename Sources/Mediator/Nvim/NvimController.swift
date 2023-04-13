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
    case invalidCommandArgument(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .deprecatedCommand(name: name, _):
            return "'\(name)' is deprecated"
        case let .invalidCommandArgument(command: command, message: message):
            return "\(command): \(message)"
        }
    }

    var failureReason: String? {
        switch self {
        case let .deprecatedCommand(_, replacement: replacement):
            return replacement
        default:
            return nil
        }
    }
}

protocol NvimControllerDelegate: AnyObject {
    /// Nvim sent a UI event through the `redraw` notification.
    func nvimController(_ nvimController: NvimController, didReceiveUIEvent event: UIEvent)

    /// An error occurred.
    func nvimController(_ nvimController: NvimController, didFailWithError error: Error)

    /// The user requested to synchronize the buffers using `source` as the
    /// source of truth.
    func nvimController(_ nvimController: NvimController, synchronizeFocusedBufferUsing source: BufferHost)

    /// The user requested to change the current buffer host that handles key
    /// input.
    func nvimController(_ nvimController: NvimController, setInput host: BufferHost)

    /// Simulates a key combo or mouse press in the app using an Nvim notation.
    func nvimController(_ nvimController: NvimController, press notation: Notation) -> Bool
}

struct NvimCursor: Equatable {
    /// Buffer the cursor is focused in.
    public var buffer: BufferHandle

    /// The cursor position.
    public var cursor: BufferPosition

    /// The start of the visual area.
    ///
    /// When not in Visual or Select mode, this is the same as the cursor
    /// `position`.
    public var visual: BufferPosition

    public init(
        buffer: BufferHandle,
        cursor: BufferPosition = BufferPosition(),
        visual: BufferPosition = BufferPosition()
    ) {
        self.buffer = buffer
        self.cursor = cursor
        self.visual = visual
    }
}

extension NvimCursor: LogPayloadConvertible {
    public func logPayload() -> [LogKey: LogValueConvertible] {
        ["buffer": buffer, "cursor": cursor, "visual": visual]
    }
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
        let pipe = "/tmp/shadowvim.pipe"
        try? FileManager.default.removeItem(atPath: pipe)

        try nvim.start(
            headless: false,
            listen: Debug.isDebugging ? pipe : nil
        )
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
            nvim.add(command: "SVSetInput", args: .one) { [weak self] params in
                guard let self, let delegate = self.delegate else {
                    return .nil
                }
                guard
                    params.count == 1,
                    case let .string(arg) = params[0],
                    let host = BufferHost(rawValue: arg.lowercased())
                else {
                    throw NvimControllerError.invalidCommandArgument(command: "SVSetInput", message: "Expected a single argument: ui or nvim")
                }

                delegate.nvimController(self, setInput: host)
                return .nil
            }
            .add(to: group)

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
            .receive(on: DispatchQueue.main)
            .sink(
                onFailure: { [unowned self] in
                    delegate?.nvimController(self, didFailWithError: $0)
                },
                receiveValue: { [unowned self] event in
                    delegate?.nvimController(self, didReceiveUIEvent: event)
                }
            )
            .store(in: &subscriptions)

        return nvim.attachUI()
    }

    /// This publisher is used to observe the Neovim mode and cursor position
    /// changes.
    ///
    /// The mode and the cursor must be observed together otherwise it causes
    /// synchronization issue with `flush` called before the cursor is updated.
    lazy var modeAndCursorPublisher: AnyPublisher<(Mode, NvimCursor), NvimError> =
        nvim.autoCmdPublisher(
            name: "mode-cursor",
            for: "ModeChanged", "CursorMoved", "CursorMovedI",
            args: "bufnr()", "mode(1)", "getcharpos('.')", "getcharpos('v')",
            unpack: { params -> (Mode, NvimCursor)? in
                guard
                    params.count == 4,
                    let buffer: BufferHandle = params[0].intValue,
                    let mode = params[1].stringValue,
                    let cursor = BuiltinFunctions.GetposResult(params[2]),
                    let visual = BuiltinFunctions.GetposResult(params[3])
                else {
                    return nil
                }
                return (
                    Mode(rawValue: mode) ?? .normal,
                    NvimCursor(
                        buffer: buffer,
                        cursor: cursor.position,
                        visual: visual.position
                    )
                )
            }
        )

    // MARK: - API

    func editBuffer(name: BufferName, contents: @escaping () -> String) -> Async<NvimBuffer, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return buffers.edit(name: name, contents: contents, with: vim)
    }

    func setLines(_ lines: [String], in buffer: NvimBuffer) -> Async<Void, NvimError> {
        vimAtomic(in: buffer) { vim in
            vim.api.bufGetLines(buffer: buffer.handle, start: 0, end: -1)
                .flatMap { oldLines in
                    let diff = lines.difference(from: oldLines)

                    if let (offset, line) = diff.updatedSingleItem {
                        return vim.api.bufSetLines(start: offset, end: offset + 1, replacement: [line])
                    } else {
                        return withAsyncGroup { group in
                            for change in diff.coalesceChanges() {
                                var start: LineIndex
                                var end: LineIndex
                                var replacement: [String]
                                switch change {
                                case let .insert(index, lines):
                                    start = index
                                    end = index
                                    replacement = lines
                                case let .remove(indices):
                                    start = indices.lowerBound
                                    end = indices.upperBound + 1
                                    replacement = []
                                }
                                vim.api.bufSetLines(buffer: buffer.handle, start: start, end: end, replacement: replacement)
                                    .add(to: group)
                            }
                        }
                    }
                }
        }
    }

    func setCursor(in buffer: NvimBuffer, at position: BufferPosition) -> Async<Void, NvimError> {
        vimAtomic(in: buffer) { vim in
            vim.api.winSetCursor(position: position, failOnInvalidPosition: false)
        }
        .discardResult()
    }

    /// Starts the Neovim Visual mode and selects from the given `start` and
    /// `end` positions.
    func startVisual(in buffer: NvimBuffer, from start: BufferPosition, to end: BufferPosition) -> Async<Void, NvimError> {
        vimAtomic(in: buffer) { vim in
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

    /// Undoes one Nvim change.
    func undo(in buffer: NvimBuffer) -> Async<Void, NvimError> {
        vimAtomic(in: buffer) { vim in
            vim.cmd.undo()
        }
        .discardResult()
    }

    /// Redoes last undone Nvim change.
    func redo(in buffer: NvimBuffer) -> Async<Void, NvimError> {
        vimAtomic(in: buffer) { vim in
            vim.cmd.redo()
        }
        .discardResult()
    }

    /// Paste the content of the system clipboard in the Nvim buffer.
    func paste(_ text: String, in buffer: NvimBuffer) -> Async<Void, NvimError> {
        vimAtomic(in: buffer) { vim in
            vim.api.paste(text)
        }
        .discardResult()
    }

    /// Send input keys to Nvim.
    func input(_ keys: String, in buffer: NvimBuffer) -> Async<Void, NvimError> {
        vimAtomic(in: buffer) { vim in
            vim.api.input(keys)
        }
        .discardResult()
    }

    private func vimAtomic<Result>(in buffer: NvimBuffer, block: @escaping (Vim) -> Async<Result, NvimError>) -> Async<Result, NvimError> {
        guard let vim = nvim.vim else {
            return .failure(.notStarted)
        }

        return vim.atomic(in: buffer, block: block)
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
