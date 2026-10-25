// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct ShellEditorSnapshot: Equatable, Sendable {
    let config: ShellConfig
    let layout: ShellBarLayout
    let schemas: [String: ShellRootSettings]
    let themes: [String]
}

@MainActor
final class ShellEditorSnapshotCache {
    private struct Entry {
        let generation: UInt64
        let metadata: [String: SettingsFileAccess.Fingerprint]?
        let snapshot: ShellEditorSnapshot
    }

    private var entries: [String: Entry] = [:]

    func snapshot(
        for config: ShellConfig,
        metadata: [String: SettingsFileAccess.Fingerprint]?,
        generation: UInt64,
        writer: ShellIslandConfigWriter,
        catalog: ShellConfigurationCatalogLoader
    ) async throws -> ShellEditorSnapshot {
        let previous = entries[config.profile].flatMap {
            $0.metadata == metadata && $0.snapshot.config.directories == config.directories ? $0.snapshot : nil
        }
        if let previous, previous.config == config, entries[config.profile]?.generation == generation {
            return previous
        }
        let listing = try await writer.perform { directory in
            (ShellBarLayout(config: config, shellDirectory: directory), ShellProfiles.themes(of: config))
        }
        let schemas = if let previous { previous.schemas } else {
            try await catalog.settings(
                widgets: listing.0.widgets.map(\.name) + config.leading + config.center + config.trailing,
                directories: config.directories
            )
        }
        let snapshot = ShellEditorSnapshot(config: config, layout: listing.0, schemas: schemas, themes: listing.1)
        entries[config.profile] = Entry(generation: generation, metadata: metadata, snapshot: snapshot)
        return snapshot
    }
}
