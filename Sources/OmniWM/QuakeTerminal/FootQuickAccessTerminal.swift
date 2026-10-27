// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Darwin
import Foundation

@MainActor @Observable
final class FootQuickAccessTerminal {
    enum Problem: Error, Equatable {
        case notInstalled
        case socketPathTooLong
        case socketUnavailable
        case launchFailed
        case starting
        case serverUnavailable
        case commandRejected
        case noReply
        case displayUnavailable
        case serverExited(Int)

        var message: String {
            switch self {
            case .notInstalled:
                String(
                    localized: "foot for macOS is not installed or is incomplete. Install foot 1.28.0-macos.8 or newer, or choose another terminal."
                )
            case .socketPathTooLong:
                String(
                    localized: "The socket path for foot's server is longer than 103 bytes. Set OMNIWM_SOCKET to a shorter path and restart OmniWM."
                )
            case .socketUnavailable:
                String(localized: "OmniWM could not prepare a private socket for foot's server.")
            case .launchFailed:
                String(localized: "OmniWM could not start foot's server.")
            case .starting:
                String(localized: "foot's server is starting. Press the Quake Terminal shortcut again in a moment.")
            case .serverUnavailable:
                String(localized: "foot's server stopped. Press the Quake Terminal shortcut again to start it.")
            case .commandRejected:
                String(
                    localized: "foot did not accept the Quake Terminal command. Update foot for macOS to 1.28.0-macos.8 or newer."
                )
            case .noReply:
                String(localized: "foot's server did not reply. OmniWM left it running.")
            case .displayUnavailable:
                String(localized: "OmniWM could not find a display area for foot's Quake terminal.")
            case let .serverExited(status):
                String(localized: "foot's server exited with status \(status).")
            }
        }

        var needsSupportedApp: Bool {
            self == .notInstalled || self == .commandRejected
        }
    }

    enum ServerEvent: Sendable, Equatable {
        case ready
        case startupFailed
        case startupTimedOut
        case exited(Int32)
    }

    struct Binaries: Equatable {
        let server: URL
        let client: URL
    }

    struct Environment {
        var binaries: @MainActor () -> Binaries?
        var runClient: @MainActor (URL, [String]) async -> ExternalTerminalProcess.Output?
        var startServer: @MainActor (URL, [String], @escaping @MainActor @Sendable (ServerEvent) -> Void) -> AnyObject?
    }

    private enum ClientResult {
        case reply(FootQuakeReply)
        case unreachable
        case rejected
        case noReply
    }

    static let bundleIdentifier = "io.github.gobijan.foot"
    private static let unreachableStatus: Int32 = 220

    private(set) var problem: Problem?
    @ObservationIgnored var onToggleFailure: (@MainActor (Problem) -> Void)?
    private let environment: Environment
    let socketPath: String
    @ObservationIgnored private let context: @MainActor () -> FootQuakeControlContext?
    @ObservationIgnored private let commands = QuakeCommandQueue()
    @ObservationIgnored private var server: (id: UInt64, handle: AnyObject)?
    @ObservationIgnored private var serverCount: UInt64 = 0
    @ObservationIgnored private var startup: (id: UInt64, continuation: CheckedContinuation<ServerEvent, Never>)?

    init(
        environment: Environment,
        socketPath: String,
        context: @escaping @MainActor () -> FootQuakeControlContext?
    ) {
        self.environment = environment
        self.socketPath = socketPath
        self.context = context
    }

    static func defaultSocketPath() -> String {
        ExternalTerminalProcess.socketPath(directory: "foot-quake")
    }

    var serverArguments: [String] {
        ["--server=\(socketPath)", "--print-pid=1"]
    }

    func clientArguments(_ command: FootQuakeCommand, context: FootQuakeControlContext? = nil) -> [String] {
        ["-s", socketPath, "--quake=\(command.rawValue)"] + (context?.overrides ?? []).flatMap { ["-o", $0] }
    }

    @discardableResult
    func activate() -> Task<Void, Never> {
        commands.enqueue { [weak self] in await self?.prepareServer() }
    }

    @discardableResult
    func toggle() -> Task<Void, Never> {
        commands.enqueue { [weak self] in await self?.toggleServer() }
    }

    @discardableResult
    func hide() -> Task<Void, Never> {
        commands.invalidatePresentations()
        return commands.enqueue(presentation: false) { [weak self] in await self?.hideVisiblePanel() }
    }

    private func prepareServer() async {
        let generation = commands.presentationGeneration
        let result = await readyServer()
        guard commands.presentationGeneration == generation else { return }
        switch result {
        case .success: problem = nil
        case let .failure(failure): problem = failure
        }
    }

    private func toggleServer() async {
        let generation = commands.presentationGeneration
        let result = await readyServer()
        guard commands.presentationGeneration == generation else { return }
        switch result {
        case let .success(binaries): await send(.toggle, binaries)
        case let .failure(failure): report(failure)
        }
    }

    private func hideVisiblePanel() async {
        guard let binaries = environment.binaries(), prepareSocket() == nil,
              case .reply(.visible) = await run(.status, binaries)
        else { return }
        await send(.hide, binaries)
    }

    private func readyServer() async -> Result<Binaries, Problem> {
        guard let binaries = environment.binaries() else { return .failure(.notInstalled) }
        if let failure = prepareSocket() { return .failure(failure) }
        switch await run(.status, binaries) {
        case .reply: return .success(binaries)
        case .unreachable where server == nil: break
        case let result: return .failure(failure(of: result, unreachable: .starting))
        }
        if let failure = await startServer(binaries) { return .failure(failure) }
        switch await run(.status, binaries) {
        case .reply: return .success(binaries)
        case let result: return .failure(failure(of: result, unreachable: .commandRejected))
        }
    }

    private func send(_ command: FootQuakeCommand, _ binaries: Binaries) async {
        guard let context = context() else {
            report(.displayUnavailable)
            return
        }
        if case .reply = await run(command, binaries, context: context) {
            problem = nil
            return
        }
        let probe = await run(.status, binaries)
        report(failure(of: probe, unreachable: server == nil ? .serverUnavailable : .starting))
    }

    private func run(
        _ command: FootQuakeCommand,
        _ binaries: Binaries,
        context: FootQuakeControlContext? = nil
    ) async -> ClientResult {
        guard let output = await environment.runClient(binaries.client, clientArguments(command, context: context))
        else { return .noReply }
        if let reply = FootQuakeReply(output) { return .reply(reply) }
        return output.status == Self.unreachableStatus ? .unreachable : .rejected
    }

    private func failure(of result: ClientResult, unreachable: Problem) -> Problem {
        switch result {
        case .reply,
             .rejected: .commandRejected
        case .unreachable: unreachable
        case .noReply: .noReply
        }
    }

    private func startServer(_ binaries: Binaries) async -> Problem? {
        serverCount &+= 1
        let id = serverCount
        guard let handle = environment.startServer(binaries.server, serverArguments, { [weak self] event in
            self?.serverEvent(event, from: id)
        }) else { return .launchFailed }
        server = (id, handle)
        let event: ServerEvent = await withCheckedContinuation { startup = (id, $0) }
        switch event {
        case .ready: return nil
        case .startupFailed: return .launchFailed
        case .startupTimedOut: return .starting
        case let .exited(status): return .serverExited(Int(status))
        }
    }

    private func serverEvent(_ event: ServerEvent, from id: UInt64) {
        if case let .exited(status) = event, server?.id == id {
            server = nil
            if status != 0 {
                problem = .serverExited(Int(status))
            }
        }
        guard let waiting = startup, waiting.id == id else { return }
        startup = nil
        waiting.continuation.resume(returning: event)
    }

    private func prepareSocket() -> Problem? {
        guard socketPath.utf8.count <= ExternalTerminalProcess.maximumSocketPathLength else {
            return .socketPathTooLong
        }
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            Log.terminal.error("Failed to prepare foot's server socket directory: \(error.localizedDescription)")
            return .socketUnavailable
        }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0
        else { return .socketUnavailable }
        guard lstat(socketPath, &info) == 0 else { return errno == ENOENT ? nil : .socketUnavailable }
        return info.st_mode & S_IFMT == S_IFSOCK ? nil : .socketUnavailable
    }

    private func report(_ failure: Problem) {
        problem = failure
        onToggleFailure?(failure)
    }
}
