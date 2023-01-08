//
//  main.swift
//  PhantomVim
//
//  Created by Mickaël Menu on 07/01/2023.
//

import Foundation
import MessagePack
import AppKit

func nvim(url: URL = URL(fileURLWithPath: "/opt/homebrew/bin/nvim")) throws {
    let task = Process()
    task.executableURL = url
    task.arguments = ["--headless", "--embed", "--clean"]

    let inPipe = Pipe()
    task.standardInput = inPipe
    let outPipe = Pipe()
    task.standardOutput = outPipe
    
    task.launch()


    let semaphore = DispatchSemaphore(value: 0)
    
    let session = RPCSession(input: inPipe.fileHandleForWriting, output: outPipe.fileHandleForReading)
    Task {
        do {
            try await session.run()
        } catch {
            print("Error \(error)")
        }
       
        semaphore.signal()
    }
    Task {
        print(try await session.send(method: "nvim_input", params: .string("ihello")))
        print(try await session.send(method: "nvim_buf_attach", params: .int(0), .bool(true), .map([:])))
    }
    
    
    Task {
        try await Task.sleep(for: .seconds(1))
        async let a = try session.send(method: "nvim_input", params: .string("<ESC>x"))
        async let b = try session.send(method: "nvim_input", params: .string("it"))
        let _ = try await [a, b]
        Task {
            try await Task.sleep(for: .seconds(1))
            print(try await session.send(method: "nvim_input", params: .string("<ESC>x")))
            Task {
                try await Task.sleep(for: .seconds(1))
                print(try await session.send(method: "nvim_input", params: .string("<ESC>x")))
            }
        }
    }
        
    semaphore.wait()
}
