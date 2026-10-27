// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

@MainActor @Observable
final class KittyQuickAccessTerminal {
    enum Problem: Error, Equatable {
        case notInstalled
        case starting
        case launchFailed
        case socketUnavailable
        case commandRejected
        case controlsUnavailable
        case opacityNeedsRestart
        case instanceExited(Int)

        var message: String {
            switch self {
            case .notInstalled:
                String(localized: "Kitty is not installed. Install the kitty app, or choose Ghostty.")
            case .starting:
                String(localized: "Kitty is starting. Press the Quake Terminal shortcut again in a moment.")
            case .launchFailed:
                String(localized: "OmniWM could not start Kitty's quick-access terminal.")
            case .socketUnavailable:
                String(localized: "OmniWM could not prepare Kitty's remote control socket.")
            case .commandRejected:
                String(localized: "Kitty did not accept the Quake Terminal command.")
            case .controlsUnavailable:
                String(localized: "OmniWM could not prepare Kitty's panel controls.")
            case .opacityNeedsRestart:
                String(
                    localized: "Live opacity needs a new Kitty Quake session. Close the Kitty panel when ready, then reopen it; OmniWM will not restart its shells."
                )
            case let .instanceExited(status):
                String(localized: "Kitty's quick-access terminal exited with status \(status).")
            }
        }

        var interruptsToggle: Bool {
            switch self {
            case .notInstalled,
                 .starting,
                 .launchFailed,
                 .socketUnavailable,
                 .commandRejected,
                 .controlsUnavailable: true
            case .instanceExited,
                 .opacityNeedsRestart: false
            }
        }
    }

    struct CommandOutput: Sendable {
        let status: Int32
        let data: Data
    }

    struct Environment {
        var kittenURL: @MainActor () -> URL?
        var runCommand: @MainActor (URL, [String]) async -> Int32?
        var runControl: @MainActor (URL, [String]) async -> CommandOutput?
        var helperURL: @MainActor () -> URL?
        var startInstance: @MainActor (URL, [String], @escaping @MainActor @Sendable (Int32) -> Void) -> AnyObject?
        var isInstanceRunning: @MainActor (String) -> Bool?
    }

    static let bundleIdentifier = "net.kovidgoyal.kitty"
    static let instanceGroup = "omniwm-quake"
    static let maximumSocketPathLength = 103

    private(set) var problem: Problem?
    @ObservationIgnored var onToggleFailure: (@MainActor (Problem) -> Void)?
    private let environment: Environment
    let socketPath: String
    @ObservationIgnored private var instance: AnyObject?
    @ObservationIgnored private var commandTail: Task<Void, Never>?
    @ObservationIgnored private var presentationGeneration: UInt64 = 0
    @ObservationIgnored private var settingsRevision: UInt64 = 0
    @ObservationIgnored private let context: @MainActor () -> KittyQuakeControlContext?

    init(
        environment: Environment,
        socketPath: String,
        context: @escaping @MainActor () -> KittyQuakeControlContext?
    ) {
        self.environment = environment
        self.socketPath = socketPath
        self.context = context
    }

    static func defaultSocketPath() -> String {
        URL(fileURLWithPath: IPCSocketPath.resolvedPath())
            .deletingLastPathComponent()
            .appendingPathComponent("kitty-quake", isDirectory: true)
            .appendingPathComponent("control.sock", isDirectory: false)
            .path
    }

    var instanceArguments: [String] {
        [
            "quick-access-terminal",
            "--instance-group=\(Self.instanceGroup)",
            "-o", "start_as_hidden=yes",
            "-o", "kitty_override=allow_remote_control=socket-only",
            "-o", "kitty_override=dynamic_background_opacity=yes",
            "--", "--listen-on=unix:\(socketPath)"
        ]
    }

    var probeArguments: [String] {
        ["@", "--to", "unix:\(socketPath)", "ls"]
    }

    func visibilityArguments(_ action: String) -> [String] {
        ["@", "--to", "unix:\(socketPath)", "resize-os-window", "--action=\(action)", "--match=all"]
    }

    @discardableResult
    func activate() -> Task<Void, Never> {
        enqueue { await $0.ensureInstance() }
    }

    @discardableResult
    func toggle() -> Task<Void, Never> {
        enqueue { await $0.toggleInstance() }
    }

    @discardableResult
    func applySettings() -> Task<Void, Never> {
        settingsRevision &+= 1
        let revision = settingsRevision
        return enqueue {
            guard $0.settingsRevision == revision else { return }
            await $0.applyInstanceSettings(revision: revision)
        }
    }

    @discardableResult
    func hide() -> Task<Void, Never> {
        presentationGeneration &+= 1
        return enqueue(presentation: false) { await $0.hideInstance() }
    }

    private func enqueue(
        presentation: Bool = true,
        _ operation: @escaping @MainActor @Sendable (KittyQuickAccessTerminal) async -> Void
    ) -> Task<Void, Never> {
        let previous = commandTail
        let generation = presentationGeneration
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            guard !presentation || self.presentationGeneration == generation else { return }
            await operation(self)
        }
        commandTail = task
        return task
    }

    private func ensureInstance() async {
        let generation = presentationGeneration
        guard let kitten = environment.kittenURL() else {
            problem = .notInstalled
            return
        }
        let reached = await runRemote(kitten, probeArguments)
        guard presentationGeneration == generation else { return }
        if reached {
            problem = nil
            return
        }
        guard instance == nil else { return }
        problem = startInstance(kitten)
    }

    private func toggleInstance() async {
        let generation = presentationGeneration
        guard let kitten = environment.kittenURL() else {
            report(.notInstalled)
            return
        }
        if FileManager.default.fileExists(atPath: socketPath) {
            let result = await runControl(.toggle, kitten: kitten)
            guard presentationGeneration == generation else { return }
            switch result {
            case let .success(reply):
                problem = reply.opacityNeedsRestart ? .opacityNeedsRestart : nil
                return
            case .failure(.controlsUnavailable):
                report(.controlsUnavailable)
                return
            case .failure:
                break
            }
            let reached = await runRemote(kitten, probeArguments)
            guard presentationGeneration == generation else { return }
            if reached {
                report(.commandRejected)
                return
            }
        }
        if instance == nil {
            report(startInstance(kitten) ?? .starting)
            return
        }
        report(.starting)
    }

    private func applyInstanceSettings(revision: UInt64) async {
        let generation = presentationGeneration
        guard FileManager.default.fileExists(atPath: socketPath), let kitten = environment.kittenURL() else { return }
        let result = await runControl(.apply, kitten: kitten)
        guard presentationGeneration == generation, settingsRevision == revision else { return }
        switch result {
        case let .success(reply):
            problem = reply.opacityNeedsRestart ? .opacityNeedsRestart : nil
        case let .failure(failure):
            problem = failure
        }
    }

    private func runControl(
        _ operation: KittyQuakeControlRequest.Operation,
        kitten: URL
    ) async -> Result<KittyQuakeControlReply, Problem> {
        guard let helper = environment.helperURL(),
              let context = context() else { return .failure(.controlsUnavailable) }
        let arguments: [String]
        do {
            let data = try JSONEncoder().encode(KittyQuakeControlRequest(operation: operation, context: context))
            guard let payload = String(data: data, encoding: .utf8) else { return .failure(.controlsUnavailable) }
            arguments = ["@", "--to", "unix:\(socketPath)", "kitten", "--match=all", helper.path, payload]
        } catch {
            Log.terminal.error("Could not encode Kitty panel settings: \(error.localizedDescription)")
            return .failure(.controlsUnavailable)
        }
        guard let output = await environment.runControl(kitten, arguments), output.status == 0 else {
            return .failure(.commandRejected)
        }
        do {
            return try .success(JSONDecoder().decode(KittyQuakeControlReply.self, from: output.data))
        } catch {
            Log.terminal.error("Kitty returned an invalid control reply: \(error.localizedDescription)")
            return .failure(.commandRejected)
        }
    }

    private func hideInstance() async {
        guard let kitten = environment.kittenURL() else { return }
        guard FileManager.default.fileExists(atPath: socketPath) else { return }
        let reached = await runRemote(kitten, visibilityArguments("hide"))
        if !reached {
            report(.commandRejected)
        }
    }

    private func runRemote(_ kitten: URL, _ arguments: [String]) async -> Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        return await environment.runCommand(kitten, arguments) == 0
    }

    private func startInstance(_ kitten: URL) -> Problem? {
        guard let running = environment.isInstanceRunning("panel-\(Self.instanceGroup)")
        else { return .socketUnavailable }
        guard !running else { return .commandRejected }
        guard prepareSocketPath() else { return .socketUnavailable }
        let handle = environment.startInstance(kitten, instanceArguments) { [weak self] status in
            self?.instanceDidExit(status)
        }
        guard let handle else { return .launchFailed }
        instance = handle
        return nil
    }

    private func prepareSocketPath() -> Bool {
        guard socketPath.utf8.count <= Self.maximumSocketPathLength else { return false }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: URL(fileURLWithPath: socketPath).deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
            )
            if fileManager.fileExists(atPath: socketPath) {
                try fileManager.removeItem(atPath: socketPath)
            }
            return true
        } catch {
            Log.terminal.error("Failed to prepare the Kitty remote control socket: \(error.localizedDescription)")
            return false
        }
    }

    private func instanceDidExit(_ status: Int32) {
        instance = nil
        if status != 0 {
            problem = .instanceExited(Int(status))
        }
    }

    private func report(_ problem: Problem) {
        self.problem = problem
        if problem.interruptsToggle {
            onToggleFailure?(problem)
        }
    }
}
