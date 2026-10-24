// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

enum HiddenBarMenuGuard {
    struct WindowInfo {
        let layer: Int
        let ownerPID: pid_t
        let title: String?
        var bounds: CGRect = .zero
    }

    static func isMenuOpen(
        windows: [WindowInfo],
        menuOwnerPIDs: Set<pid_t>,
        menuBarFrames: [CGRect] = []
    ) -> Bool {
        guard !menuOwnerPIDs.isEmpty else { return false }
        let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let menuLevels: Set<Int> = [popUpLevel, popUpLevel - 1]
        let statusBarLevel = Int(CGWindowLevelForKey(.statusWindow))
        return windows.contains { window in
            guard menuOwnerPIDs.contains(window.ownerPID) else { return false }
            if menuLevels.contains(window.layer), window.title?.isEmpty ?? true { return true }
            return window.layer == statusBarLevel && !window.bounds.isEmpty && !menuBarFrames.isEmpty
                && !menuBarFrames.contains { $0.contains(window.bounds) }
        }
    }

    static func isAnyMenuOpen(menuOwnerPIDs: Set<pid_t>, menuBarFrames: [CGRect]) -> Bool? {
        guard !menuOwnerPIDs.isEmpty else { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let windows = list.compactMap { info -> WindowInfo? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t
            else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            return WindowInfo(
                layer: layer, ownerPID: pid, title: info[kCGWindowName as String] as? String, bounds: bounds
            )
        }
        return isMenuOpen(windows: windows, menuOwnerPIDs: menuOwnerPIDs, menuBarFrames: menuBarFrames)
    }
}
