// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

struct ExternalQuakeDisplay: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat
    let topBarBottom: CGFloat?

    static func monitor(at point: CGPoint, in monitors: [Monitor]) -> Monitor? {
        point.monitorApproximation(in: monitors) ?? monitors.first(where: \.isMain) ?? monitors.first
    }

    var panelArea: CGRect? {
        let bottom = visibleFrame.minY
        let top = min(visibleFrame.maxY, topBarBottom ?? .infinity)
        guard visibleFrame.minX.isFinite, bottom.isFinite, visibleFrame.width.isFinite, top.isFinite,
              visibleFrame.width > 0, top > bottom
        else { return nil }
        return CGRect(x: visibleFrame.minX, y: bottom, width: visibleFrame.width, height: top - bottom)
    }
}

extension ExternalQuakeDisplay {
    @MainActor
    init(monitor: Monitor, topBarBottom: CGFloat?) {
        let screen = NSScreen.screens.first(where: { $0.displayId == monitor.displayId })
        self.init(
            frame: screen?.frame ?? monitor.frame,
            visibleFrame: screen?.visibleFrame ?? monitor.visibleFrame,
            scale: screen?.backingScaleFactor ?? 1,
            topBarBottom: topBarBottom
        )
    }
}
