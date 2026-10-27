// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Darwin
@testable import OmniWM
import TOML
import XCTest

@MainActor
final class LauncherExecutionTests: XCTestCase {
    func testExplicitShellCannotSilentlyUseAnotherExecutable() {
        XCTAssertThrowsError(try LauncherPaths.shell(.fish, executable: "/bin/zsh"))
        XCTAssertNoThrow(try LauncherPaths.shell(.zsh, executable: "/bin/zsh"))
    }

    func testSystemLoginShellFallsBackToZshForAnUnrecognizedShell() throws {
        let (kind, path) = try LauncherPaths.loginShell("/bin/dash")
        XCTAssertEqual(kind, .zsh)
        XCTAssertEqual(path, "/bin/zsh")
    }

    func testSystemLoginShellThrowsWhenNothingIsExecutable() {
        XCTAssertThrowsError(try LauncherPaths.loginShell(nil))
        XCTAssertThrowsError(try LauncherPaths.loginShell("/no/such/shell"))
    }

    func testLauncherEntryDecodesFromAHandwrittenTableMissingFields() throws {
        let toml = Data("""
        name = "Build"
        command = "swift build"
        """.utf8)
        let decoded = try TOMLDecoder().decode(LauncherEntry.self, from: toml)
        XCTAssertEqual(decoded.name, "Build")
        XCTAssertEqual(decoded.command, "swift build")
        XCTAssertEqual(decoded.kind, .command)
    }

    func testConfigurationRoundtripIncludesSavedEntriesAndShells() throws {
        var export = SettingsExport.defaults()
        var entry = LauncherEntry()
        entry.kind = .script
        entry.name = "Build"
        entry.path = "~/scripts/build.nu"
        entry.arguments = ["a b", "x'y", "雪"]
        entry.shell = .nushell
        entry.terminal = .builtIn
        export.launcher.entries = [entry]
        export.launcher.appFolders = ["~/Tools"]
        export.launcher.cliFolders = ["~/bin"]
        export.launcher.shell = .fish
        export.launcher.shellExecutable = "/custom/fish"
        export.launcher.terminal = .ghostty
        let decoded = try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(export))
        XCTAssertEqual(decoded.launcher, export.launcher)
    }

    func testProcessReportsFailureAndDrainsBoundedOutput() async throws {
        let large = String(repeating: "a", count: 100_000)
        let result = try await LauncherProcess.run(
            executable: "/usr/bin/printf", arguments: ["%s", large], environment: [:], outputLimit: 4096
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.count, 4096)
        XCTAssertTrue(result.truncated)
        let failure = try await LauncherProcess.run(
            executable: "/bin/sh", arguments: ["-c", "printf failure >&2; exit 7"], environment: [:]
        )
        XCTAssertEqual(failure.status, 7)
        XCTAssertEqual(String(decoding: failure.output, as: UTF8.self), "failure")
    }

    func testProcessDeadlineReportsFailure() async throws {
        do {
            _ = try await LauncherProcess.run(
                executable: "/bin/sleep",
                arguments: ["30"],
                environment: [:],
                deadline: 0.1
            )
            XCTFail("An unfinished process must not succeed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("in time"))
        }
    }

    func testDetachedChildDoesNotKeepParentRunOpen() async throws {
        let result = try await LauncherProcess.run(
            executable: "/bin/sh", arguments: ["-c", "sleep 30 & printf '%s' $!"],
            environment: ["PATH": "/usr/bin:/bin"], deadline: 2
        )
        let pid = try XCTUnwrap(Int32(String(decoding: result.output, as: UTF8.self)))
        defer { _ = kill(pid, SIGTERM) }
        XCTAssertEqual(result.status, 0)
    }

    func testDeadlineReapsProcessThatIgnoresTermination() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-pid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await LauncherProcess.run(
                executable: "/bin/sh",
                arguments: [
                    "-c",
                    "printf '%s' $$ > \(LauncherLaunchRequest.quote(file.path)); trap '' TERM; while :; do :; done"
                ],
                environment: [:], deadline: 1
            )
            XCTFail("The deadline must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("in time"))
        }
        let pid = try XCTUnwrap(Int32(String(contentsOf: file, encoding: .utf8)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testTerminalHelperPreservesArgumentsDirectoryAndExitStatus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcher ' 雪 \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let arguments = ["a b", "x'y", "\"quoted\"", "$HOME; false", "雪", "line\nbreak"]
        let request = LauncherLaunchRequest(
            executable: "/usr/bin/printf", arguments: ["%s\\0"] + arguments,
            directory: directory.path, environment: ["PATH": "/usr/bin:/bin"]
        )
        let helper = try request.makeTerminalHelper()
        let result = try await LauncherProcess.run(
            executable: "/bin/sh", arguments: [helper.path], environment: request.environment
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(
            result.output.split(separator: 0).prefix(arguments.count).map { String(decoding: $0, as: UTF8.self) },
            arguments
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: helper.deletingLastPathComponent().path))
        let cwd = LauncherLaunchRequest(
            executable: "/bin/pwd",
            arguments: [],
            directory: directory.path,
            environment: [:]
        )
        let cwdHelper = try cwd.makeTerminalHelper()
        let cwdResult = try await LauncherProcess.run(
            executable: "/bin/sh",
            arguments: [cwdHelper.path],
            environment: [:]
        )
        XCTAssertTrue(String(decoding: cwdResult.output, as: UTF8.self)
            .hasPrefix(directory.resolvingSymlinksInPath().path + "\n"))
        let failure = LauncherLaunchRequest(
            executable: "/bin/sh", arguments: ["-c", "exit 9"], directory: directory.path, environment: [:]
        )
        let failureHelper = try failure.makeTerminalHelper()
        let failureResult = try await LauncherProcess.run(
            executable: "/bin/sh",
            arguments: [failureHelper.path],
            environment: [:]
        )
        XCTAssertEqual(failureResult.status, 9)
    }

    func testReusedTerminalReceivesCapturedEnvironmentWithoutPersistingIt() async throws {
        let value = "quotes ' \" $HOME; 雪\n" + String(repeating: "v", count: 80_000)
        let request = LauncherLaunchRequest(
            executable: "/bin/sh", arguments: ["-c", "printf '%s\\n%s' \"$OMNIWM_TRANSFER_TEST\" \"$TERM\"; exit 7"],
            directory: "/private/tmp", environment: [
                "PATH": "/usr/bin:/bin",
                "OMNIWM_TRANSFER_TEST": value,
                "TERM": "dumb"
            ]
        )
        let transfer = try LauncherEnvironmentTransfer(request: request)
        let helper = try request.makeTerminalHelper(holdOutput: false, transfer: transfer)
        let helperText = try String(contentsOf: helper, encoding: .utf8)
        XCTAssertFalse(helperText.contains(value))
        async let delivered: Void = transfer.waitForDelivery()
        let result = try await LauncherProcess.run(
            executable: "/bin/sh", arguments: [helper.path], environment: [
                "OMNIWM_TRANSFER_TEST": "stale",
                "TERM": "xterm-256color"
            ],
            deadline: 10, outputLimit: 100_000
        )
        try await delivered
        XCTAssertEqual(result.status, 7)
        XCTAssertTrue(String(decoding: result.output, as: UTF8.self).hasPrefix(value + "\nxterm-256color"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transfer.endpoint))
        XCTAssertFalse(FileManager.default.fileExists(atPath: helper.deletingLastPathComponent().path))
    }

    func testRealNushellFishZshAndBothBashVersions() async throws {
        guard ProcessInfo.processInfo.environment["OMNIWM_RUN_LAUNCHER_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set OMNIWM_RUN_LAUNCHER_LIVE_TESTS=1 for installed-shell checks")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let shells: [(LauncherShell, String, String)] = [
            (
                .nushell,
                root.appendingPathComponent(".cache/flake-tools/bin/nu").path,
                "let omniwm_value = 'nushell'; /usr/bin/printf '%s' $omniwm_value"
            ),
            (
                .fish,
                root.appendingPathComponent(".cache/flake-tools/bin/fish").path,
                "set omniwm_value fish; /usr/bin/printf '%s' $omniwm_value"
            ),
            (.zsh, "/bin/zsh", "omniwm_value=zsh; /usr/bin/printf '%s' \"$omniwm_value\""),
            (.bash, "/bin/bash", "omniwm_value=bash; /usr/bin/printf '%s' \"$omniwm_value\""),
            (.bash, "/opt/homebrew/bin/bash", "omniwm_value=bash; /usr/bin/printf '%s' \"$omniwm_value\"")
        ]
        for (shell, executable, command) in shells {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable), executable)
            var configuration = LauncherConfiguration()
            configuration.shell = shell
            configuration.shellExecutable = executable
            configuration.terminal = .background
            let environment = try await LauncherEnvironmentCache.shared.environment(for: configuration, refresh: true)
            XCTAssertFalse(environment.values["PATH", default: ""].isEmpty)
            let catalog = await LauncherExecutableCatalog.scan(environment: environment.values)
            XCTAssertTrue(catalog.contains { $0.name == "printf" }, executable)
            XCTAssertTrue(catalog.contains { $0.name == "nix" }, executable)
            XCTAssertTrue(catalog.contains { $0.name == "brew" }, executable)
            var entry = LauncherEntry()
            entry.name = shell.rawValue
            entry.command = command
            let request = try await LauncherLaunchRequest.prepare(entry: entry, configuration: configuration)
            let result = try await LauncherProcess.run(
                executable: request.executable, arguments: request.arguments,
                environment: request.environment, directory: request.directory
            )
            XCTAssertEqual(result.status, 0, executable)
            XCTAssertEqual(String(decoding: result.output, as: UTF8.self), shell.rawValue, executable)
        }
    }
}
