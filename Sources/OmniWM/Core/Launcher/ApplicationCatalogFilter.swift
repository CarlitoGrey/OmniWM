// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum ApplicationCatalogFilter {
    static let finderPath = "/System/Library/CoreServices/Finder.app"

    static func roots(home: String, extraFolders: [String] = []) -> [String] {
        [
            "/Applications",
            "/System/Applications",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
            "/AppleInternal/Applications",
            "/System/Library/CoreServices/Applications",
            home + "/Applications",
            "/Users/Shared",
            home + "/.nix-profile/Applications",
            home + "/.local/state/nix/profile/Applications",
            "/etc/profiles/per-user/" + URL(fileURLWithPath: home).lastPathComponent + "/Applications",
            "/run/current-system/Applications",
            "/run/current-system/sw/Applications",
            "/nix/var/nix/profiles/default/Applications"
        ] + extraFolders.map(LauncherPaths.expanded)
    }

    static func isCatalogPath(_ path: String, home: String, extraFolders: [String] = []) -> Bool {
        guard path.hasSuffix(".app") else { return false }
        if path == finderPath { return true }
        let parent = (path as NSString).deletingLastPathComponent
        if parent == home + "/Downloads" { return true }
        let roots = roots(home: home, extraFolders: extraFolders)
        if roots.contains(parent) { return true }
        let grandparent = (parent as NSString).deletingLastPathComponent
        return roots.contains(grandparent) && !isBundleDirectory(parent)
    }

    static func scannedBundlePaths(
        home: String,
        extraFolders: [String] = [],
        fileManager: FileManager = .default
    ) -> [String] {
        var paths: [String] = []
        for root in roots(home: home, extraFolders: extraFolders) {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(entry)
                if isApplicationCandidate(path) {
                    paths.append(path)
                    continue
                }
                var isDirectory: ObjCBool = false
                guard !isBundleDirectory(path),
                      fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      let children = try? fileManager.contentsOfDirectory(atPath: path)
                else {
                    continue
                }
                paths += children.map { (path as NSString).appendingPathComponent($0) }.filter(isApplicationCandidate)
            }
        }
        return paths
    }

    static func resolvedBundleURL(_ path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        if isFinderAlias(url) {
            guard let target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) else {
                return nil
            }
            url = target
        }
        url = url.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app", Bundle(url: url)?.bundleIdentifier != nil else { return nil }
        return url
    }

    private static func isApplicationCandidate(_ path: String) -> Bool {
        path.hasSuffix(".app") || isFinderAlias(URL(fileURLWithPath: path))
    }

    static func isFinderAlias(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isAliasFile == true && values.isSymbolicLink != true
    }

    private static func isBundleDirectory(_ path: String) -> Bool {
        ["app", "appex", "bundle", "framework", "plugin", "xpc"].contains((path as NSString).pathExtension.lowercased())
    }
}
