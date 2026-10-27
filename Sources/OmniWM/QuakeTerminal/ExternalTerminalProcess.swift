// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC
import Synchronization

enum ExternalTerminalProcess {
    struct Output: Sendable, Equatable {
        let status: Int32
        let data: Data
    }

    static let maximumSocketPathLength = 103
    static let maximumOutputLength: UInt64 = 4096

    static func bundledExecutable(_ name: String, in application: URL?) -> URL? {
        guard let executable = application?.appendingPathComponent("Contents/MacOS/\(name)", isDirectory: false),
              FileManager.default.isExecutableFile(atPath: executable.path)
        else { return nil }
        return executable
    }

    static func socketPath(directory: String) -> String {
        URL(fileURLWithPath: IPCSocketPath.resolvedPath())
            .deletingLastPathComponent()
            .appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent("control.sock", isDirectory: false)
            .path
    }

    static func make(_ executable: URL, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    static func capture(_ executable: URL, _ arguments: [String], deadline: Duration? = nil) async -> Output? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("omniwm-terminal-\(UUID().uuidString).out")
        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            return nil
        }
        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: outputURL)
        } catch {
            CommandCapture.remove(outputURL)
            return nil
        }
        let process = make(executable, arguments)
        process.standardOutput = output
        let capture = CommandCapture(output: output, outputURL: outputURL)
        return await withCheckedContinuation { continuation in
            capture.run(process, deadline: deadline, continuation)
        }
    }
}

private final class CommandCapture: Sendable {
    private struct State {
        var continuation: CheckedContinuation<ExternalTerminalProcess.Output?, Never>?
        var process: Process?
        var deadline: Task<Void, Never>?
    }

    private let state = Mutex(State())
    private let output: FileHandle
    private let outputURL: URL

    init(output: FileHandle, outputURL: URL) {
        self.output = output
        self.outputURL = outputURL
    }

    func run(
        _ process: Process,
        deadline: Duration?,
        _ continuation: CheckedContinuation<ExternalTerminalProcess.Output?, Never>
    ) {
        state.withLock {
            $0.continuation = continuation
            $0.process = process
        }
        process.terminationHandler = { [self] finished in
            finish(status: finished.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            finish(status: nil)
            return
        }
        guard let deadline else { return }
        let timer = Task { [weak self] in
            do {
                try await Task.sleep(for: deadline)
            } catch {
                return
            }
            self?.expire()
        }
        let armed = state.withLock { state in
            guard state.process != nil else { return false }
            state.deadline = timer
            return true
        }
        if !armed {
            timer.cancel()
        }
    }

    private func finish(status: Int32?) {
        let continuation = state.withLock { state in
            state.deadline?.cancel()
            state.deadline = nil
            state.process = nil
            defer { state.continuation = nil }
            return state.continuation
        }
        let result = collect(status: continuation == nil ? nil : status)
        continuation?.resume(returning: result)
    }

    private func expire() {
        let (continuation, process) = state.withLock { state in
            defer {
                state.continuation = nil
                state.deadline = nil
            }
            return (state.continuation, state.process)
        }
        guard let continuation else { return }
        process?.terminate()
        continuation.resume(returning: nil)
    }

    private func collect(status: Int32?) -> ExternalTerminalProcess.Output? {
        defer { Self.remove(outputURL) }
        do {
            try output.close()
            guard let status else { return nil }
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.uint64Value <= ExternalTerminalProcess.maximumOutputLength
            else { return nil }
            return try ExternalTerminalProcess.Output(status: status, data: Data(contentsOf: outputURL))
        } catch {
            Log.terminal.error("Could not read terminal control output: \(error.localizedDescription)")
            return nil
        }
    }

    static func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.terminal.error("Could not remove terminal control output: \(error.localizedDescription)")
        }
    }
}
