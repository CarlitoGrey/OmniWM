// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import Observation

struct LauncherExecutable: Identifiable, Sendable {
    let name: String
    let path: String
    var id: String {
        path
    }

    var entry: LauncherEntry {
        var entry = LauncherEntry()
        entry.name = name
        entry.kind = .executable
        entry.path = path
        return entry
    }
}

@MainActor @Observable
final class LauncherExecutableCatalog {
    static let shared = LauncherExecutableCatalog()
    private(set) var entries: [LauncherExecutable] = []
    private(set) var isLoading = false
    private(set) var failure: String?
    @ObservationIgnored var onChanged: (@MainActor () -> Void)?
    private var configuration: LauncherConfiguration?
    private var generation = 0

    func refresh(configuration: LauncherConfiguration, force: Bool = false) {
        var key = configuration
        key.entries = []
        key.appFolders = []
        key.terminal = .terminal
        guard force || self.configuration != key else { return }
        self.configuration = key
        generation &+= 1
        let generation = generation
        isLoading = true
        failure = nil
        entries = []
        Task { [weak self] in
            do {
                let environment = try await LauncherEnvironmentCache.shared.environment(
                    for: configuration,
                    refresh: force
                )
                let entries = await Self.scan(environment: environment.values)
                guard let self, self.generation == generation else { return }
                self.entries = entries
                self.isLoading = false
                self.onChanged?()
            } catch {
                guard let self, self.generation == generation else { return }
                self.failure = error.localizedDescription
                self.isLoading = false
                self.onChanged?()
            }
        }
    }

    func matching(_ query: String) -> [LauncherExecutable] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return Array(entries.lazy.filter { entry in
            terms.allSatisfy { entry.name.localizedStandardContains($0) }
        }.prefix(200))
    }

    nonisolated static func scan(environment: [String: String]) async -> [LauncherExecutable] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var names: Set<String> = []
                var entries: [LauncherExecutable] = []
                let manager = FileManager.default
                for folder in (environment["PATH"] ?? "").split(separator: ":") where folder.hasPrefix("/") {
                    guard let files = try? manager.contentsOfDirectory(atPath: String(folder)) else { continue }
                    for name in files.sorted() where !name.hasPrefix(".") && !names.contains(name) {
                        let path = String(folder) + "/" + name
                        var directory: ObjCBool = false
                        guard manager.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue,
                              manager.isExecutableFile(atPath: path) else { continue }
                        names.insert(name)
                        entries.append(LauncherExecutable(name: name, path: path))
                    }
                }
                continuation.resume(returning: entries.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                })
            }
        }
    }
}
