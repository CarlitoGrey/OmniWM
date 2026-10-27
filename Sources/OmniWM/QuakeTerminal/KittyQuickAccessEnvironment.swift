// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Darwin
import Foundation

extension KittyQuickAccessTerminal.Environment {
    static var live: Self {
        Self(
            kittenURL: {
                guard let app = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: KittyQuickAccessTerminal.bundleIdentifier
                ) else { return nil }
                let kitten = app.appendingPathComponent("Contents/MacOS/kitten", isDirectory: false)
                return FileManager.default.isExecutableFile(atPath: kitten.path) ? kitten : nil
            },
            runCommand: { executable, arguments in
                let process = makeProcess(executable, arguments)
                let status: Int32? = await withCheckedContinuation { continuation in
                    process.terminationHandler = { finished in
                        continuation.resume(returning: finished.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(returning: nil)
                    }
                }
                withExtendedLifetime(process) {}
                return status
            },
            runControl: runControl,
            helperURL: {
                Bundle.module.url(forResource: "kitty-quake-control", withExtension: "py")
            },
            startInstance: { executable, arguments, onExit in
                let process = makeProcess(executable, arguments)
                process.terminationHandler = { finished in
                    let status = finished.terminationStatus
                    Task { @MainActor in onExit(status) }
                }
                do {
                    try process.run()
                    return process
                } catch {
                    process.terminationHandler = nil
                    Log.terminal.error("Failed to start the Kitty quick-access terminal: \(error.localizedDescription)")
                    return nil
                }
            },
            isInstanceRunning: instanceIsRunning
        )
    }

    private static func runControl(_ executable: URL, _ arguments: [String]) async -> KittyQuickAccessTerminal
        .CommandOutput?
    {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("omniwm-kitty-\(UUID().uuidString).json")
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
            removeOutput(outputURL)
            return nil
        }
        let process = makeProcess(executable, arguments)
        process.standardOutput = output
        let result: KittyQuickAccessTerminal.CommandOutput? = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                defer { removeOutput(outputURL) }
                do {
                    try output.close()
                    let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                    guard let size = attributes[.size] as? NSNumber, size.uint64Value <= 4096 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let data = try Data(contentsOf: outputURL)
                    continuation.resume(returning: .init(status: finished.terminationStatus, data: data))
                } catch {
                    Log.terminal.error("Could not read Kitty control output: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                do {
                    try output.close()
                } catch {
                    Log.terminal.error("Could not close Kitty control output: \(error.localizedDescription)")
                }
                removeOutput(outputURL)
                continuation.resume(returning: nil)
            }
        }
        withExtendedLifetime(process) {}
        return result
    }

    private nonisolated static func removeOutput(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.terminal.error("Could not remove Kitty control output: \(error.localizedDescription)")
        }
    }

    private static func instanceIsRunning(_ group: String) -> Bool? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count)
        guard length > 0, length <= buffer.count else { return nil }
        let directory = String(decoding: buffer.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let path = URL(fileURLWithPath: directory)
            .appendingPathComponent("kitty-ipc-\(geteuid())-\(group).lock").path
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return errno == ENOENT ? false : nil }
        defer { close(descriptor) }
        var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        guard fcntl(descriptor, F_GETLK, &lock) == 0 else { return nil }
        return lock.l_type != F_UNLCK
    }

    private static func makeProcess(_ executable: URL, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
