// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import Synchronization

extension FootQuickAccessTerminal.Environment {
    static var live: Self {
        Self(
            binaries: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: FootQuickAccessTerminal.bundleIdentifier)
                    .flatMap(FootQuickAccessTerminal.Binaries.init(application:))
            },
            runClient: { executable, arguments in
                await ExternalTerminalProcess.capture(executable, arguments, deadline: .seconds(2))
            },
            startServer: { executable, arguments, onEvent in
                FootServerStartup.launch(executable, arguments, deadline: .seconds(5), onEvent: onEvent)
            }
        )
    }
}

extension FootQuickAccessTerminal.Binaries {
    init?(application: URL) {
        guard let server = ExternalTerminalProcess.bundledExecutable("foot", in: application),
              let client = ExternalTerminalProcess.bundledExecutable("footclient", in: application)
        else { return nil }
        self.init(server: server, client: client)
    }
}

final class FootServerStartup: Sendable {
    typealias Event = FootQuickAccessTerminal.ServerEvent

    private struct State {
        var reader: FileHandle?
        var pending = true
        var pid: Int32 = 0
        var line = Data()
        var deadline: Task<Void, Never>?
    }

    private static let maximumLineLength = 32
    private let state: Mutex<State>
    private let onEvent: @MainActor @Sendable (Event) -> Void

    private init(reader: FileHandle, onEvent: @escaping @MainActor @Sendable (Event) -> Void) {
        state = Mutex(State(reader: reader))
        self.onEvent = onEvent
    }

    static func launch(
        _ executable: URL,
        _ arguments: [String],
        deadline: Duration,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) -> Process? {
        let output = Pipe()
        let process = ExternalTerminalProcess.make(executable, arguments)
        process.standardOutput = output
        let startup = FootServerStartup(reader: output.fileHandleForReading, onEvent: onEvent)
        process.terminationHandler = { finished in
            startup.exited(finished.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            startup.abandon()
            Log.terminal.error("Failed to start foot's server: \(error.localizedDescription)")
            return nil
        }
        startup.begin(pid: process.processIdentifier, deadline: deadline)
        return process
    }

    private func begin(pid: Int32, deadline: Duration) {
        state.withLock { state in
            guard state.pending, let reader = state.reader else { return }
            state.pid = pid
            state.deadline = Task { [weak self] in
                do {
                    try await Task.sleep(for: deadline)
                } catch {
                    return
                }
                self?.expire()
            }
            reader.readabilityHandler = { handle in
                self.receive(handle.availableData)
            }
        }
    }

    private func receive(_ data: Data) {
        let event: Event? = state.withLock { state in
            guard !data.isEmpty else {
                Self.closeReader(&state)
                return nil
            }
            guard state.pending else { return nil }
            state.line.append(data)
            guard let newline = state.line.firstIndex(of: UInt8(ascii: "\n")) else {
                guard state.line.count > Self.maximumLineLength, Self.settle(&state) else { return nil }
                return .startupFailed
            }
            let pid = Int32(String(decoding: state.line[..<newline], as: UTF8.self))
            guard Self.settle(&state) else { return nil }
            return pid == state.pid ? .ready : .startupFailed
        }
        if let event {
            deliver(event)
        }
    }

    private func exited(_ status: Int32) {
        state.withLock { _ = Self.settle(&$0) }
        deliver(.exited(status))
    }

    private func expire() {
        if state.withLock({ Self.settle(&$0) }) {
            deliver(.startupTimedOut)
        }
    }

    private func abandon() {
        state.withLock {
            _ = Self.settle(&$0)
            Self.closeReader(&$0)
        }
    }

    private func deliver(_ event: Event) {
        let onEvent = onEvent
        Task { @MainActor in onEvent(event) }
    }

    private static func settle(_ state: inout State) -> Bool {
        guard state.pending else { return false }
        state.pending = false
        state.deadline?.cancel()
        state.deadline = nil
        return true
    }

    private static func closeReader(_ state: inout State) {
        guard let reader = state.reader else { return }
        state.reader = nil
        reader.readabilityHandler = nil
        do {
            try reader.close()
        } catch {
            Log.terminal.error("Could not close foot's server startup output: \(error.localizedDescription)")
        }
    }
}
