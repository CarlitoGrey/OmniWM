// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Darwin
import Foundation

extension KittyQuickAccessTerminal.Environment {
    static var live: Self {
        Self(
            kittenURL: {
                ExternalTerminalProcess.bundledExecutable(
                    "kitten",
                    in: NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: KittyQuickAccessTerminal.bundleIdentifier
                    )
                )
            },
            runCommand: { executable, arguments in
                let process = ExternalTerminalProcess.make(executable, arguments)
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
            runControl: { executable, arguments in
                await ExternalTerminalProcess.capture(executable, arguments)
            },
            helperURL: {
                Bundle.module.url(forResource: "kitty-quake-control", withExtension: "py")
            },
            startInstance: { executable, arguments, onExit in
                let process = ExternalTerminalProcess.make(executable, arguments)
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
}
