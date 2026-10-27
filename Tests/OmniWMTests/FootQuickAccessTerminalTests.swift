// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Darwin
import Foundation
@testable import OmniWM
import XCTest

@MainActor
private final class FakeFootProcesses {
    static let hidden = ExternalTerminalProcess.Output(status: 0, data: Data("hidden\n".utf8))
    static let visible = ExternalTerminalProcess.Output(status: 0, data: Data("visible\n".utf8))
    static let unreachable = ExternalTerminalProcess.Output(status: 220, data: Data())

    var binaries: FootQuickAccessTerminal.Binaries? = FootQuickAccessTerminal.Binaries(
        server: URL(fileURLWithPath: "/virtual/foot.app/Contents/MacOS/foot"),
        client: URL(fileURLWithPath: "/virtual/foot.app/Contents/MacOS/footclient")
    )
    var settings = FootQuakeSettings()
    var animationDuration = 0.2
    var area: CGRect? = CGRect(x: -800, y: 100, width: 800, height: 932)
    var replies: [ExternalTerminalProcess.Output?] = []
    var fallbackReply: ExternalTerminalProcess.Output? = FakeFootProcesses.hidden
    var startSucceeds = true
    var suspendedCommand: String?
    private(set) var clients: [[String]] = []
    private(set) var starts: [[String]] = []
    private(set) var serverEvents: [@MainActor @Sendable (FootQuickAccessTerminal.ServerEvent) -> Void] = []
    private var suspended: CheckedContinuation<ExternalTerminalProcess.Output?, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var context: FootQuakeControlContext? {
        area.map { FootQuakeControlContext(settings: settings, area: $0, animationDuration: animationDuration) }
    }

    var environment: FootQuickAccessTerminal.Environment {
        FootQuickAccessTerminal.Environment(
            binaries: { [self] in binaries },
            runClient: { [self] _, arguments in await runClient(arguments) },
            startServer: { [self] _, arguments, onEvent in
                starts.append(arguments)
                serverEvents.append(onEvent)
                notifyWaiters()
                return startSucceeds ? NSObject() : nil
            }
        )
    }

    var eventCount: Int {
        clients.count + starts.count
    }

    var commands: [String] {
        clients.compactMap { $0.first { $0.hasPrefix("--quake=") }?.replacingOccurrences(of: "--quake=", with: "") }
    }

    func waitForEvents(_ count: Int) async {
        while eventCount < count {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func resumeClient(_ output: ExternalTerminalProcess.Output?) {
        suspended?.resume(returning: output)
        suspended = nil
    }

    private func runClient(_ arguments: [String]) async -> ExternalTerminalProcess.Output? {
        clients.append(arguments)
        notifyWaiters()
        if let command = suspendedCommand, arguments.contains("--quake=\(command)") {
            suspendedCommand = nil
            return await withCheckedContinuation { suspended = $0 }
        }
        return replies.isEmpty ? fallbackReply : replies.removeFirst()
    }

    private func notifyWaiters() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

@MainActor
private final class ServerEventLog {
    private(set) var events: [FootQuickAccessTerminal.ServerEvent] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record(_ event: FootQuickAccessTerminal.ServerEvent) {
        events.append(event)
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    func waitForEvents(_ count: Int) async {
        while events.count < count {
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}

@MainActor
final class FootQuickAccessTerminalTests: XCTestCase {
    func testToggleSendsExplicitSizeAlphaAutoHideDimAndAreaToTheOwnedSocket() async throws {
        let (terminal, fake) = makeTerminal()
        fake.settings = FootQuakeSettings(
            autoHide: false,
            opacity: 0.5,
            placement: .init(position: .bottom, widthPercent: 75, heightPercent: 40)
        )
        fake.replies = [FakeFootProcesses.hidden, FakeFootProcesses.visible]

        await terminal.toggle().value

        XCTAssertEqual(fake.clients, [
            ["-s", terminal.socketPath, "--quake=status"],
            [
                "-s", terminal.socketPath, "--quake=toggle",
                "-o", "macos-quake-position=bottom",
                "-o", "macos-quake-size=75.0x40.0",
                "-o", "macos-quake-alpha=0.5",
                "-o", "macos-quake-auto-hide=no",
                "-o", "macos-quake-dim=0.0",
                "-o", "macos-quake-animation-duration=0.2",
                "-o", "macos-quake-area=-800.0,100.0,800.0,932.0"
            ]
        ])
        XCTAssertTrue(fake.starts.isEmpty)
        XCTAssertNil(terminal.problem)
    }

    func testUnsetOverridesAreOmittedWhileDimAndAreaAreAlwaysSent() async throws {
        let (terminal, fake) = makeTerminal()
        await terminal.toggle().value
        fake.settings = FootQuakeSettings(autoHide: true, dim: 0.35)
        await terminal.toggle().value

        XCTAssertEqual(fake.commands, ["status", "toggle", "status", "toggle"])
        XCTAssertEqual(Array(fake.clients[1].dropFirst(3)), [
            "-o", "macos-quake-dim=0.0",
            "-o", "macos-quake-animation-duration=0.2",
            "-o", "macos-quake-area=-800.0,100.0,800.0,932.0"
        ])
        XCTAssertEqual(Array(fake.clients[3].dropFirst(3)), [
            "-o", "macos-quake-auto-hide=yes",
            "-o", "macos-quake-dim=0.35",
            "-o", "macos-quake-animation-duration=0.2",
            "-o", "macos-quake-area=-800.0,100.0,800.0,932.0"
        ])
        XCTAssertEqual(terminal.serverArguments, ["--server=\(terminal.socketPath)", "--print-pid=1"])
    }

    func testReadyServerAtTheOwnedSocketIsReusedWithoutStartingAChild() async {
        let (terminal, fake) = makeTerminal()
        await terminal.activate().value
        await terminal.toggle().value

        XCTAssertEqual(fake.commands, ["status", "status", "toggle"])
        XCTAssertTrue(fake.starts.isEmpty)
        XCTAssertNil(terminal.problem)
    }

    func testColdFirstToggleWaitsForPIDReadinessThenShowsOnce() async {
        let (terminal, fake) = makeTerminal()
        fake.replies = [FakeFootProcesses.unreachable, FakeFootProcesses.hidden, FakeFootProcesses.visible]

        let toggle = terminal.toggle()
        await fake.waitForEvents(2)
        XCTAssertEqual(fake.starts, [terminal.serverArguments])
        XCTAssertEqual(fake.commands, ["status"])
        fake.serverEvents[0](.ready)
        await toggle.value

        XCTAssertEqual(fake.commands, ["status", "status", "toggle"])
        XCTAssertEqual(fake.starts.count, 1)
        XCTAssertNil(terminal.problem)
    }

    func testPrematureExitAndMalformedPIDAreReportedWithoutPresenting() async {
        for (event, expected) in [
            (FootQuickAccessTerminal.ServerEvent.exited(1), FootQuickAccessTerminal.Problem.serverExited(1)),
            (.startupFailed, .launchFailed)
        ] {
            let (terminal, fake) = makeTerminal()
            fake.fallbackReply = FakeFootProcesses.unreachable
            var reported: [FootQuickAccessTerminal.Problem] = []
            terminal.onToggleFailure = { reported.append($0) }

            let toggle = terminal.toggle()
            await fake.waitForEvents(2)
            fake.serverEvents[0](event)
            await toggle.value

            XCTAssertEqual(reported, [expected])
            XCTAssertEqual(terminal.problem, expected)
            XCTAssertEqual(fake.commands, ["status"])
        }
    }

    func testStartupDeadlineKeepsTheLiveChildAndNeverLaunchesADuplicate() async {
        let (terminal, fake) = makeTerminal()
        fake.fallbackReply = FakeFootProcesses.unreachable
        var reported: [FootQuickAccessTerminal.Problem] = []
        terminal.onToggleFailure = { reported.append($0) }

        let activation = terminal.activate()
        await fake.waitForEvents(2)
        let toggle = terminal.toggle()
        fake.serverEvents[0](.startupTimedOut)
        await activation.value
        await toggle.value

        XCTAssertEqual(terminal.problem, .starting)
        XCTAssertEqual(reported, [.starting])
        XCTAssertEqual(fake.starts.count, 1)
        XCTAssertEqual(fake.commands, ["status", "status"])
    }

    func testFailedOrUnansweredCommandsAreNeverRetried() async {
        let cases: [([ExternalTerminalProcess.Output?], FootQuickAccessTerminal.Problem)] = [
            ([FakeFootProcesses.hidden, nil, nil], .noReply),
            ([FakeFootProcesses.hidden, .init(status: 1, data: Data()), FakeFootProcesses.hidden], .commandRejected),
            (
                [FakeFootProcesses.hidden, .init(status: 0, data: Data("maybe\n".utf8)), FakeFootProcesses.visible],
                .commandRejected
            ),
            (
                [FakeFootProcesses.hidden, FakeFootProcesses.unreachable, FakeFootProcesses.unreachable],
                .serverUnavailable
            ),
            ([.init(status: 2, data: Data())], .commandRejected),
            ([nil], .noReply)
        ]
        for (replies, expected) in cases {
            let (terminal, fake) = makeTerminal()
            fake.replies = replies
            var reported: [FootQuickAccessTerminal.Problem] = []
            terminal.onToggleFailure = { reported.append($0) }

            await terminal.toggle().value

            XCTAssertEqual(reported, [expected])
            XCTAssertLessThanOrEqual(fake.commands.filter { $0 == "toggle" }.count, 1)
            XCTAssertEqual(fake.clients.count, replies.count)
            XCTAssertTrue(fake.starts.isEmpty)
        }
    }

    func testFailedLaunchIsReportedVisibly() async {
        let (terminal, fake) = makeTerminal()
        fake.fallbackReply = FakeFootProcesses.unreachable
        fake.startSucceeds = false
        var reported: [FootQuickAccessTerminal.Problem] = []
        terminal.onToggleFailure = { reported.append($0) }

        await terminal.toggle().value

        XCTAssertEqual(reported, [.launchFailed])
        XCTAssertEqual(fake.starts.count, 1)
        XCTAssertEqual(fake.commands, ["status"])
    }

    func testCrashThenExplicitToggleStartsAFreshServerAndAStaleExitCannotRetireIt() async {
        let (terminal, fake) = makeTerminal()
        fake.replies = [FakeFootProcesses.unreachable, FakeFootProcesses.hidden, FakeFootProcesses.visible]
        let first = terminal.toggle()
        await fake.waitForEvents(2)
        fake.serverEvents[0](.ready)
        await first.value
        fake.serverEvents[0](.exited(9))
        XCTAssertEqual(terminal.problem, .serverExited(9))

        fake.replies = [FakeFootProcesses.unreachable, FakeFootProcesses.hidden, FakeFootProcesses.visible]
        let restart = terminal.toggle()
        await fake.waitForEvents(6)
        XCTAssertEqual(fake.starts.count, 2)
        fake.serverEvents[1](.ready)
        await restart.value
        XCTAssertNil(terminal.problem)

        fake.serverEvents[0](.exited(3))
        XCTAssertNil(terminal.problem)
        fake.fallbackReply = FakeFootProcesses.unreachable
        var reported: [FootQuickAccessTerminal.Problem] = []
        terminal.onToggleFailure = { reported.append($0) }
        await terminal.toggle().value

        XCTAssertEqual(reported, [.starting])
        XCTAssertEqual(fake.starts.count, 2)
    }

    func testMissingAppOrUnsafeSocketNeverSpawnsAnything() async throws {
        let root = makeDirectory()
        let longPath = root.appendingPathComponent(String(repeating: "x", count: 104)).path
        let fileDirectory = root.appendingPathComponent("file", isDirectory: true)
        let openDirectory = root.appendingPathComponent("open", isDirectory: true)
        let linkedDirectory = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fileDirectory.path)
        let plainFile = fileDirectory.appendingPathComponent("control.sock").path
        XCTAssertTrue(FileManager.default.createFile(atPath: plainFile, contents: Data()))
        try FileManager.default.createDirectory(
            at: openDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: fileDirectory)

        let cases: [(String?, FootQuickAccessTerminal.Problem)] = [
            (nil, .notInstalled),
            (longPath, .socketPathTooLong),
            (plainFile, .socketUnavailable),
            (openDirectory.appendingPathComponent("control.sock").path, .socketUnavailable),
            (linkedDirectory.appendingPathComponent("control.sock").path, .socketUnavailable)
        ]
        for (socketPath, expected) in cases {
            let fake = FakeFootProcesses()
            if socketPath == nil {
                fake.binaries = nil
            }
            let terminal = FootQuickAccessTerminal(
                environment: fake.environment,
                socketPath: socketPath ?? root.appendingPathComponent("foot-quake/control.sock").path,
                context: { fake.context }
            )
            var reported: [FootQuickAccessTerminal.Problem] = []
            terminal.onToggleFailure = { reported.append($0) }

            await terminal.activate().value
            XCTAssertEqual(terminal.problem, expected)
            await terminal.toggle().value
            await terminal.hide().value

            XCTAssertEqual(reported, [expected])
            XCTAssertEqual(fake.eventCount, 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: longPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plainFile))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: openDirectory.path)[.posixPermissions] as? Int,
            0o755
        )
    }

    func testPreparedSocketDirectoryIsPrivateAndAnExistingSocketIsNeverDeleted() async throws {
        let (terminal, fake) = makeTerminal()
        await terminal.activate().value
        let directory = URL(fileURLWithPath: terminal.socketPath).deletingLastPathComponent().path
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? Int, 0o700)
        do {
            _ = try IPCServer.makeListeningSocket(at: terminal.socketPath)
        }
        fake.fallbackReply = FakeFootProcesses.unreachable

        let toggle = terminal.toggle()
        await fake.waitForEvents(3)
        fake.serverEvents[0](.exited(1))
        await toggle.value
        await terminal.hide().value

        var info = stat()
        XCTAssertEqual(lstat(terminal.socketPath, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(terminal.problem, .serverExited(1))
    }

    func testPendingStartupThenDeselectionNeverShowsAndSendsNoHideForAHiddenPanel() async {
        let (terminal, fake) = makeTerminal()
        fake.replies = [FakeFootProcesses.unreachable]

        let toggle = terminal.toggle()
        await fake.waitForEvents(2)
        let hide = terminal.hide()
        fake.serverEvents[0](.ready)
        await toggle.value
        await hide.value

        XCTAssertEqual(fake.commands, ["status", "status", "status"])
        XCTAssertTrue(fake.clients.allSatisfy { !$0.contains("-o") })
    }

    func testHideFollowsAnInflightToggleAndDropsQueuedPresentations() async {
        let (terminal, fake) = makeTerminal()
        fake.suspendedCommand = "toggle"
        fake.fallbackReply = FakeFootProcesses.visible

        let toggle = terminal.toggle()
        await fake.waitForEvents(2)
        let staleToggle = terminal.toggle()
        let hide = terminal.hide()
        fake.resumeClient(FakeFootProcesses.visible)
        await toggle.value
        await staleToggle.value
        await hide.value

        XCTAssertEqual(fake.commands, ["status", "toggle", "status", "hide"])
        XCTAssertEqual(Array(fake.clients[3].suffix(6)), [
            "-o", "macos-quake-dim=0.0",
            "-o", "macos-quake-animation-duration=0.2",
            "-o", "macos-quake-area=-800.0,100.0,800.0,932.0"
        ])
        XCTAssertNil(terminal.problem)
    }

    func testQueuedToggleEncodesTheLatestSettingsWhenItRuns() async throws {
        let (terminal, fake) = makeTerminal()
        fake.suspendedCommand = "toggle"

        let first = terminal.toggle()
        await fake.waitForEvents(2)
        let second = terminal.toggle()
        fake.settings.dim = 0.4
        fake.resumeClient(FakeFootProcesses.visible)
        await first.value
        await second.value

        XCTAssertEqual(fake.commands, ["status", "toggle", "status", "toggle"])
        XCTAssertTrue(fake.clients[1].contains("macos-quake-dim=0.0"))
        XCTAssertTrue(try XCTUnwrap(fake.clients.last).contains("macos-quake-dim=0.4"))
    }

    func testAnimationDurationIsSentWithTheCurrentValue() async throws {
        let (terminal, fake) = makeTerminal()
        fake.animationDuration = 0
        await terminal.toggle().value

        XCTAssertTrue(try XCTUnwrap(fake.clients.last).contains("macos-quake-animation-duration=0.0"))
        XCTAssertFalse(fake.clients[0].contains { $0.hasPrefix("macos-quake-animation-duration") })
    }

    func testMissingDisplayAreaBlocksPresentationVisibly() async {
        let (terminal, fake) = makeTerminal()
        fake.area = nil
        var reported: [FootQuickAccessTerminal.Problem] = []
        terminal.onToggleFailure = { reported.append($0) }

        await terminal.toggle().value

        XCTAssertEqual(reported, [.displayUnavailable])
        XCTAssertEqual(fake.commands, ["status"])
    }

    func testDiscoveryUsesOnlyTheBundledServerAndClient() throws {
        let root = makeDirectory()
        let application = root.appendingPathComponent("Apps With Spaces/foot.app", isDirectory: true)
        let executables = application.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let decoy = root.appendingPathComponent("decoy bin", isDirectory: true)
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
        try makeExecutable(decoy.appendingPathComponent("footclient"))
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "\(decoy.path):\(path)", 1)
        defer { setenv("PATH", path, 1) }

        XCTAssertNil(FootQuickAccessTerminal.Binaries(application: application))
        try makeExecutable(executables.appendingPathComponent("foot"))
        XCTAssertNil(FootQuickAccessTerminal.Binaries(application: application))
        let client = executables.appendingPathComponent("footclient")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: client.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o644]
        ))
        XCTAssertNil(FootQuickAccessTerminal.Binaries(application: application))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: client.path)

        XCTAssertEqual(
            FootQuickAccessTerminal.Binaries(application: application),
            FootQuickAccessTerminal.Binaries(server: executables.appendingPathComponent("foot"), client: client)
        )
    }

    func testLiveServerStartupSettlesOnceOnPIDMalformedOutputExitOrDeadline() async throws {
        let shell = URL(fileURLWithPath: "/bin/sh")
        let cases: [(String, Duration, FootQuickAccessTerminal.ServerEvent?)] = [
            ("echo $$; exec /bin/sleep 30", .seconds(30), .ready),
            ("echo not-a-pid; exec /bin/sleep 30", .seconds(30), .startupFailed),
            ("exec /bin/sleep 30", .milliseconds(50), .startupTimedOut),
            ("exit 3", .seconds(30), nil)
        ]
        for (script, deadline, startupEvent) in cases {
            let log = ServerEventLog()
            let process = try XCTUnwrap(FootServerStartup.launch(shell, ["-c", script], deadline: deadline) {
                log.record($0)
            })
            if let startupEvent {
                await log.waitForEvents(1)
                XCTAssertEqual(log.events, [startupEvent], script)
                process.terminate()
            }
            await log.waitForEvents(startupEvent == nil ? 1 : 2)
            XCTAssertEqual(
                log.events,
                (startupEvent.map { [$0] } ?? []) + [.exited(startupEvent == nil ? 3 : SIGTERM)],
                script
            )
        }
    }

    func testLiveStartupReportsAFailedLaunch() {
        XCTAssertNil(FootServerStartup.launch(
            URL(fileURLWithPath: "/nonexistent/foot"),
            [],
            deadline: .seconds(5)
        ) { _ in XCTFail("A failed launch must not report events") })
    }

    func testLiveClientCaptureReturnsBoundedRepliesAndSettlesItsDeadline() async throws {
        let printf = URL(fileURLWithPath: "/usr/bin/printf")
        let visible = await ExternalTerminalProcess.capture(printf, ["visible\n"], deadline: .seconds(30))
        XCTAssertEqual(visible.flatMap(FootQuakeReply.init), .visible)
        let unreachable = await ExternalTerminalProcess.capture(
            URL(fileURLWithPath: "/bin/sh"),
            ["-c", "exit 220"],
            deadline: .seconds(30)
        )
        XCTAssertEqual(unreachable, .init(status: 220, data: Data()))
        let oversized = await ExternalTerminalProcess.capture(
            printf,
            ["%s", String(repeating: "x", count: 5000)],
            deadline: .seconds(30)
        )
        XCTAssertNil(oversized)
        let unanswered = await ExternalTerminalProcess.capture(
            URL(fileURLWithPath: "/bin/sleep"),
            ["30"],
            deadline: .milliseconds(50)
        )
        XCTAssertNil(unanswered)
        let missing = await ExternalTerminalProcess.capture(
            URL(fileURLWithPath: "/nonexistent/footclient"),
            [],
            deadline: .seconds(30)
        )
        XCTAssertNil(missing)
    }

    func testControllerRoutesFootSelectionAndSettingsEditsSendNothing() async throws {
        let (controller, root) = makeController()
        let (terminal, fake) = makeTerminal(directory: root)
        controller.footQuickAccessTerminal = terminal
        controller.settings.quakeTerminal.provider = .foot
        controller.settings.quakeTerminal.enabled = true
        controller.setQuakeTerminalEnabled(true)
        await fake.waitForEvents(1)
        XCTAssertEqual(controller.appliedQuakeTerminalSelection, .foot)
        XCTAssertNil(controller.quakeTerminalController.window)

        controller.settings.quakeTerminal.foot.dim = 0.5
        controller.settings.quakeTerminal.foot.placement = .defaultOverride
        controller.setQuakeTerminalEnabled(true)
        fake.replies = [FakeFootProcesses.hidden, FakeFootProcesses.visible]
        controller.toggleQuakeTerminal()
        await fake.waitForEvents(3)
        XCTAssertEqual(fake.commands, ["status", "status", "toggle"])
        XCTAssertTrue(fake.starts.isEmpty)
        XCTAssertNil(controller.quakeTerminalController.window)

        fake.replies = [FakeFootProcesses.visible, FakeFootProcesses.hidden]
        controller.settings.quakeTerminal.enabled = false
        controller.setQuakeTerminalEnabled(false)
        await fake.waitForEvents(5)
        XCTAssertNil(controller.appliedQuakeTerminalSelection)
        XCTAssertEqual(fake.commands, ["status", "status", "toggle", "status", "hide"])
        controller.toggleQuakeTerminal()
        await terminal.hide().value
        XCTAssertEqual(fake.commands, ["status", "status", "toggle", "status", "hide", "status"])
    }

    func testControllerFootContextUsesTheSharedExternalDisplay() throws {
        let (controller, _) = makeController()
        controller.settings.quakeTerminal.foot.dim = 0.25
        guard let display = controller.externalQuakeDisplay() else {
            XCTAssertNil(controller.footQuakeControlContext())
            XCTAssertNil(controller.kittyQuakeControlContext())
            return
        }
        let context = try XCTUnwrap(controller.footQuakeControlContext())
        XCTAssertEqual(context.area, display.panelArea)
        XCTAssertEqual(context.settings.dim, 0.25)
        XCTAssertEqual(controller.kittyQuakeControlContext()?.barBottom, display.topBarBottom.map(Double.init))
    }

    private func makeTerminal(directory: URL? = nil) -> (FootQuickAccessTerminal, FakeFootProcesses) {
        let root = directory ?? makeDirectory()
        let fake = FakeFootProcesses()
        let terminal = FootQuickAccessTerminal(
            environment: fake.environment,
            socketPath: root.appendingPathComponent("foot-quake/control.sock", isDirectory: false).path,
            context: { fake.context }
        )
        XCTAssertLessThanOrEqual(terminal.socketPath.utf8.count, ExternalTerminalProcess.maximumSocketPathLength)
        return (terminal, fake)
    }

    private func makeExecutable(_ url: URL) throws {
        XCTAssertTrue(FileManager.default.createFile(
            atPath: url.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        ))
    }

    private func makeDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ofq-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeSettings(root: URL) -> SettingsStore {
        SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config"),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(directory: root.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
    }

    private func makeController() -> (WMController, URL) {
        let root = makeDirectory()
        let controller = WMController(
            settings: makeSettings(root: root),
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        addTeardownBlock { @MainActor in
            controller.hasStartedServices = false
            controller.workspaceBarManager.cleanup()
            controller.layoutRefreshController.resetState()
            controller.mouseEventHandler.cleanup()
            controller.surfaceReconciler.cleanup()
            controller.axManager.cleanup()
            await controller.workspaceBarManager.flushShellForQuit()
        }
        return (controller, root)
    }
}
