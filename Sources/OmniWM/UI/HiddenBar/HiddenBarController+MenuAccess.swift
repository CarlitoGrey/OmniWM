// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

extension HiddenBarController {
    static func live(
        settings: SettingsStore,
        menuBarHold: MenuBarAutohideHold,
        stateDirectory: URL
    ) -> HiddenBarController {
        HiddenBarController(
            settings: settings,
            hider: .live(in: stateDirectory),
            setMenuAccess: { menuBarHold.setMenuAccess($0) },
            menuBarHiddenByBar: { menuBarHold.hidesMenuBar }
        )
    }

    func resolveRevealedItems(
        for bundleID: String,
        owner: HiddenBarActivationOwner,
        clicking key: MenuBarItemKey? = nil
    ) async -> [ResolvedMenuBarItem]? {
        let items = await resolveItems(for: bundleID, owner: owner)
        guard !holdsMenuAccess,
              Self.needsMenuAccess(for: items, clicking: key, covers: coversPoint),
              acquireMenuAccess()
        else { return items }
        return await resolveItems(for: bundleID, owner: owner)
    }

    nonisolated static func needsMenuAccess(
        for items: [ResolvedMenuBarItem]?,
        clicking key: MenuBarItemKey?,
        covers: (CGPoint) -> Bool
    ) -> Bool {
        guard let items, !items.isEmpty else { return true }
        guard let key else { return false }
        guard let target = items.first(where: { $0.key == key }) else { return true }
        return !covers(CGPoint(x: target.bounds.midX, y: target.bounds.midY))
    }

    func takeMenuAccessForReveal() -> Bool {
        menuBarHiddenByBar() || acquireMenuAccess()
    }

    private func acquireMenuAccess() -> Bool {
        if !holdsMenuAccess {
            holdsMenuAccess = setMenuAccess(true)
        }
        return holdsMenuAccess
    }

    private func resolveItems(
        for bundleID: String,
        owner: HiddenBarActivationOwner
    ) async -> [ResolvedMenuBarItem]? {
        if let resolveOverride {
            return await resolveOverride(bundleID, owner)
        }
        let snapshot = HiddenBarRunningAppsSnapshot.current()
        let candidates = snapshot.candidates.filter { $0.bundleID == bundleID && $0.pid == owner.pid }
        guard !candidates.isEmpty else { return nil }
        let resolution = await itemService.resolveItems(
            candidates: candidates,
            bundleIDs: [bundleID],
            allowEmptyBundleIDs: owner.allowsAuthoritativeEmpty ? [bundleID] : []
        )
        guard !Task.isCancelled, temporarilyRevealed.contains(bundleID),
              let items = resolution.itemsByBundleID[bundleID]
        else { return nil }
        return items
    }

    func resolveRevealedItemsForTests(
        _ bundleID: String,
        pid: pid_t,
        clicking key: MenuBarItemKey?
    ) async -> [ResolvedMenuBarItem]? {
        await resolveRevealedItems(
            for: bundleID,
            owner: HiddenBarActivationOwner(pid: pid, allowsAuthoritativeEmpty: false),
            clicking: key
        )
    }
}
