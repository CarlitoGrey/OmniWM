// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CryptoKit
import Foundation

enum ShellDefaults {
    static let profile = "default"
    private static let manifestName = ".manifest.json"
    private static let reserved: Set<String> = [profile, "widgets", "themes", "shaders", "lib"]
    private static let retiredStyles = ["system"]

    static var bundled: URL? {
        Bundle.module.url(forResource: "ShellDefault", withExtension: nil)
    }

    static var bundledStyles: URL? {
        Bundle.module.url(forResource: "ShellStyles", withExtension: nil)
    }

    static func bundledFile(_ path: String) -> URL? {
        guard let url = bundled?.appendingPathComponent(path), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    static func sync(
        into shellDirectory: URL,
        from source: URL? = bundled,
        styles: URL? = bundledStyles,
        day: String = today
    ) -> [URL] {
        var backups = source.map {
            install($0, into: shellDirectory.appendingPathComponent(profile, isDirectory: true), day: day)
        } ?? []
        guard let styles else { return backups }
        let bundledNames = styleNames(in: styles)
        for style in bundledNames {
            let target = shellDirectory.appendingPathComponent(style, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: target.path)
                || FileManager.default.fileExists(atPath: target.appendingPathComponent(manifestName).path)
            else {
                Log.shell.notice("Kept your shell folder \(style); the bundled \(style) style was not installed")
                continue
            }
            backups += install(styles.appendingPathComponent(style), into: target, day: day)
        }
        for style in retiredStyles where !bundledNames.contains(style) {
            retire(shellDirectory.appendingPathComponent(style, isDirectory: true))
        }
        return backups
    }

    private static func styleNames(in styles: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: styles,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { !reserved.contains($0) }
            .sorted()
    }

    private static func install(_ source: URL, into target: URL, day: String) -> [URL] {
        let manifestURL = target.appendingPathComponent(manifestName)
        let written = readManifest(at: manifestURL) ?? [:]
        var manifest: [String: String] = [:]
        var backups: [URL] = []
        do {
            for path in files(in: source) {
                let bundledURL = source.appendingPathComponent(path)
                let bundledData = try Data(contentsOf: bundledURL)
                let url = target.appendingPathComponent(path)
                let current = try? Data(contentsOf: url)
                let hash = digest(bundledData)
                manifest[path] = hash
                guard current != bundledData else { continue }
                if let current, written[path] != digest(current) {
                    guard written[path] != hash else { continue }
                    let backup = backupURL(for: url, day: day)
                    try FileManager.default.moveItem(at: url, to: backup)
                    backups.append(backup)
                }
                try SettingsFileAccess.ensureDirectoryExists(at: url.deletingLastPathComponent())
                try SettingsFileAccess.writeAtomically(bundledData, at: url)
                if FileManager.default.isExecutableFile(atPath: bundledURL.path) {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
            }
            try removeUnedited(written.filter { manifest[$0.key] == nil }, in: target)
            if manifest != written {
                try SettingsFileAccess.ensureDirectoryExists(at: target)
                try SettingsFileAccess.writeAtomically(JSONEncoder().encode(manifest), at: manifestURL)
            }
        } catch {
            Log.shell.error("Failed to update the shell profile in \(target.path): \(error.localizedDescription)")
        }
        return backups
    }

    private static func retire(_ target: URL) {
        let target = target.resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = target.appendingPathComponent(manifestName)
        guard let written = readManifest(at: manifestURL) else { return }
        do {
            try removeUnedited(written, in: target)
            try FileManager.default.removeItem(at: manifestURL)
        } catch {
            Log.shell.error("Failed to retire the shell profile in \(target.path): \(error.localizedDescription)")
            return
        }
        let entries = FileManager.default.enumerator(at: target, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        for directory in (entries + [target]).sorted(by: { $0.path.count > $1.path.count }) {
            rmdir(directory.path)
        }
    }

    private static func readManifest(at url: URL) -> [String: String]? {
        try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private static func removeUnedited(_ written: [String: String], in target: URL) throws {
        for (path, hash) in written {
            let url = target.appendingPathComponent(path)
            if let current = try? Data(contentsOf: url), digest(current) == hash {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static var today: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    private static func files(in directory: URL) -> [String] {
        let base = directory.standardizedFileURL.path + "/"
        let entries = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { String($0.standardizedFileURL.path.dropFirst(base.count)) }
            .sorted()
    }

    private static func backupURL(for url: URL, day: String) -> URL {
        var candidate = URL(fileURLWithPath: "\(url.path).edited-\(day)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: "\(url.path).edited-\(day)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
