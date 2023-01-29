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

enum BuffersError: Error {
    case editFailed(NvimError)
}

final class Buffers {
    private struct Buffer {
        let handle: BufferHandle
        let name: String?
        var lines: [String]
    }

    private let nvim: Nvim
    private var editedBuffer: BufferHandle = 0
    @Atomic private var buffers: [BufferHandle: Buffer] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private let bufLinesEventPublisher: AnyPublisher<BufLinesEvent, Never>

    init(nvim: Nvim) {
        self.nvim = nvim

        bufLinesEventPublisher = nvim.events
            .subscribeToBufLines()
            .ignoreFailure()

        setupNotifications()
    }

    func subscribeToLines(of buffer: BufferHandle) -> AnyPublisher<BufLinesEvent, Never> {
        bufLinesEventPublisher
            .filter { $0.buf == buffer }
            .eraseToAnyPublisher()
    }

    func edit(name: String, contents: String) -> Async<BufferHandle, BuffersError> {
        activate(name: name)
            .flatMap { buffer in
                if let buffer = buffer {
                    return .success(buffer)
                } else {
                    return self.open(name: name, contents: contents)
                }
            }
    }

    private func activate(name: String) -> Async<BufferHandle?, BuffersError> {
        Async { [self] in
            guard let buffer = buffers.values.first(where: { $0.name == name }) else {
                return .success(nil)
            }

            return nvim.api.cmd("buffer", args: .int(buffer.handle))
                .map { _ in buffer.handle }
                .mapError { .editFailed(.apiFailure($0)) }
        }
    }

    private func open(name: String, contents: String) -> Async<BufferHandle, BuffersError> {
        var buffer: BufferHandle!
        let lines = contents.lines.map { String($0) }

        return nvim.transaction { api in
            api.createBuf(listed: false, scratch: true)
                .flatMap { handle in
                    buffer = handle

                    self.$buffers.write {
                        $0[handle] = Buffer(handle: handle, name: name, lines: lines)
                    }

                    return api.bufSetLines(buffer: buffer, start: 0, end: -1, replacement: lines)
                }
                .flatMap {
                    api.bufAttach(buffer: buffer, sendBuffer: false)
                }
                .flatMap { _ in
                    api.exec("""
                    " Activate the newly created buffer.
                    buffer! \(buffer!)

                    " Detect the filetype using the buffer contents and the
                    " provided name.
                    lua << EOF
                    local ft, _ = vim.filetype.match({ filename = "\(name)", buf = \(buffer!) })
                    if ft then
                        vim.api.nvim_buf_set_option(\(buffer!), "filetype", ft)
                    end
                    EOF

                    " Clear the undo history, to prevent going back to an
                    " empty buffer.
                    let old_undolevels = &undolevels
                    set undolevels=-1
                    exe "normal a \\<BS>\\<Esc>"
                    let &undolevels = old_undolevels
                    unlet old_undolevels
                    """)
                }
        }
        .map { _ in buffer }
        .mapError { BuffersError.editFailed($0) }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        bufLinesEventPublisher
            .sink { [weak self] in self?.onBufLines(event: $0) }
            .store(in: &subscriptions)

        nvim.events.autoCmd(event: "BufEnter", args: "expand('<abuf>')")
            .assertNoFailure()
            .sink { [weak self] data in
                self?.editedBuffer = Int(data.first?.stringValue ?? "0") ?? 0
            }
            .store(in: &subscriptions)
    }

    private func onBufLines(event: BufLinesEvent) {
        $buffers.write { buffers in
            guard var buffer = buffers[event.buf] else {
                return
            }
            buffer.lines = event.applyChanges(in: buffer.lines)
            buffers[event.buf] = buffer
        }
    }
}
