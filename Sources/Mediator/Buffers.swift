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

final class Buffers {
    private struct Buffer {
        let handle: BufferHandle
        let name: String?
        var lines: [String]
    }

    public private(set) var editedBuffer: BufferHandle = 0
    @Atomic private var buffers: [BufferHandle: Buffer] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private let bufLinesEventPublisher: AnyPublisher<BufLinesEvent, APIError>

    init(events: EventDispatcher) {
        bufLinesEventPublisher = events.bufLinesPublisher()

        setupNotifications(using: events)
    }

    func linesPublisher(for buffer: BufferHandle) -> AnyPublisher<BufLinesEvent, APIError> {
        bufLinesEventPublisher
            .filter { $0.buf == buffer }
            .eraseToAnyPublisher()
    }

    func edit(name: String, contents: String, with api: API) -> APIAsync<BufferHandle> {
        api.transaction { [self] api in
            activate(name: name, with: api)
                .flatMap { buffer in
                    if let buffer = buffer {
                        return .success(buffer)
                    } else {
                        return self.open(name: name, contents: contents, with: api)
                    }
                }
        }
    }

    func edit(buffer: BufferHandle, with api: API) -> APIAsync<Void> {
        guard editedBuffer != buffer else {
            return .success(())
        }

        return api.cmd("buffer", args: .int(buffer))
            .discardResult()
            .onSuccess { self.editedBuffer = buffer }
    }

    private func activate(name: String, with api: API) -> APIAsync<BufferHandle?> {
        Async { [self] in
            guard let buffer = buffers.values.first(where: { $0.name == name }) else {
                return .success(nil)
            }

            return edit(buffer: buffer.handle, with: api)
                .map { _ in buffer.handle }
        }
    }

    private func open(name: String, contents: String, with api: API) -> APIAsync<BufferHandle> {
        var buffer: BufferHandle!
        let lines = contents.lines.map { String($0) }

        return api.transaction { api in
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
    }

    // MARK: - Notifications

    private func setupNotifications(using events: EventDispatcher) {
        bufLinesEventPublisher
            .ignoreFailure()
            .sink { [weak self] in self?.onBufLines(event: $0) }
            .store(in: &subscriptions)

        events.autoCmdPublisher(for: "BufEnter", args: "expand('<abuf>')")
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
