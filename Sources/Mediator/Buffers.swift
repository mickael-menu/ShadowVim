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

/// Represents the current state of a Nvim buffer.
struct Buffer {
    /// Nvim buffer handle.
    let handle: BufferHandle

    /// Name of the buffer.
    var name: String?

    /// Current content lines.
    var lines: [String] = []

    /// Previous content lines, before receiving the last `BufLinesEvent`.
    var oldLines: [String] = []

    /// Last `BufLinesEvent` that was emitted by this buffer.
    var lastLinesEvent: BufLinesEvent?
}

/// Manages the Nvim buffers.
final class Buffers {
    public private(set) var editedBuffer: BufferHandle = 0

    @Published private(set) var buffers: [BufferHandle: Buffer] = [:]

    private var subscriptions: Set<AnyCancellable> = []
    private let logger: Logger?

    init(events: EventDispatcher, logger: Logger?) {
        self.logger = logger

        setupNotifications(using: events)
    }

    /// Publisher to observes the changes of the buffer with given `handle`.
    func publisher(for handle: BufferHandle) -> AnyPublisher<Buffer, Never> {
        $buffers
            .compactMap { $0[handle] }
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
                .flatMap { [self] handle in
                    precondition(Thread.isMainThread)
                    buffer = handle
                    buffers[handle] = Buffer(handle: handle, name: name, lines: lines)

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
        events.bufLinesPublisher()
            .receive(on: DispatchQueue.main)
            .breakpointOnError()
            .ignoreFailure()
            .sink { [unowned self] event in
                guard var buffer = buffers[event.buf] else {
                    logger?.w("Received BufLinesEvent for an unknown buffer")
                    return
                }

                buffer.oldLines = buffer.lines
                buffer.lines = event.applyChanges(in: buffer.lines)
                buffer.lastLinesEvent = event
                buffers[event.buf] = buffer
            }
            .store(in: &subscriptions)

        events.autoCmdPublisher(for: "BufEnter", args: "expand('<abuf>')")
            .assertNoFailure()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.editedBuffer = Int(data.first?.stringValue ?? "0") ?? 0
            }
            .store(in: &subscriptions)
    }
}
