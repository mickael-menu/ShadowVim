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
import Nvim
import Toolkit

/// Manages the Nvim buffers.
public final class NvimBuffers {
    public private(set) var editedBuffer: BufferHandle = 0

    @Published private(set) var buffers: [BufferHandle: NvimBuffer] = [:]
    private let bufLinesPublisher: AnyPublisher<BufLinesEvent, Never>

    private var subscriptions: Set<AnyCancellable> = []
    private let logger: Logger?

    public init(nvim: Nvim, logger: Logger?) {
        self.logger = logger

        bufLinesPublisher = nvim.bufLinesPublisher()
            .breakpointOnError()
            .ignoreFailure()

        nvim.autoCmdPublisher(for: "BufEnter", args: "expand('<abuf>')")
            .assertNoFailure()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.editedBuffer = Int(data.first?.stringValue ?? "0") ?? 0
            }
            .store(in: &subscriptions)
    }

    func edit(name: String, contents: @autoclosure () -> String, with vim: Vim) -> Async<NvimBuffer, NvimError> {
        if let (_, buffer) = buffers.first(where: { $0.value.name == name }) {
            return activate(buffer: buffer.handle, with: vim)
                .map { _ in buffer }
        } else {
            return create(name: name, contents: contents(), with: vim)
        }
    }

    private func create(name: String, contents: String, with vim: Vim) -> Async<NvimBuffer, NvimError> {
        var buffer: NvimBuffer!
        let lines = contents.lines.map { String($0) }

        return vim.transaction { vim in
            vim.editNoWrite(name: name)
                .flatMap { [self] handle in
                    precondition(Thread.isMainThread)
                    buffer = makeBuffer(handle: handle, name: name)
                    // Reset the content, in case it's different from the file.
                    return vim.api.bufSetLines(buffer: handle, start: 0, end: -1, replacement: lines)
                }
                .flatMap {
                    vim.api.bufAttach(buffer: buffer.handle, sendBuffer: true)
                }
                .flatMap { _ in
                    // Clear the undo history, to prevent going back to an
                    // empty buffer.
                    vim.clearUndoHistory()
                }
                .map { _ in buffer }
        }
    }

    private func makeBuffer(handle: BufferHandle, name: String) -> NvimBuffer {
        precondition(buffers[handle] == nil)

        let buffer = NvimBuffer(
            handle: handle,
            name: name,
            delegate: self,
            linesEventPublisher: bufLinesPublisher
                .filter { $0.buf == handle }
                .eraseToAnyPublisher()
        )
        buffers[handle] = buffer

        return buffer
    }

    private func activate(buffer: BufferHandle, with vim: Vim) -> Async<Void, NvimError> {
        guard editedBuffer != buffer else {
            return .success(())
        }

        return vim.api.cmd("buffer", args: .int(buffer))
            .discardResult()
            .onSuccess { self.editedBuffer = buffer }
    }
}

extension NvimBuffers: BufferDelegate {
    func buffer(_ buffer: NvimBuffer, activateWith vim: Vim) -> Async<Void, NvimError> {
        activate(buffer: buffer.handle, with: vim)
    }
}

private extension Vim {
    func editNoWrite(name: String) -> Async<BufferHandle, NvimError> {
        transaction { vim in
            vim.api.exec(
                """
                edit \(name)

                set buftype=nowrite
                set bufhidden=hide
                set noswapfile
                """
            )
            .flatMap { _ in vim.api.getCurrentBuf() }
        }
    }

    func clearUndoHistory() -> Async<Void, NvimError> {
        // This snippet is from the Vim help.
        // :help undo-remarks
        api.exec(
            """
            let old_undolevels = &undolevels
            set undolevels=-1
            exe "normal a \\<BS>\\<Esc>"
            let &undolevels = old_undolevels
            unlet old_undolevels
            """
        ).discardResult()
    }
}
