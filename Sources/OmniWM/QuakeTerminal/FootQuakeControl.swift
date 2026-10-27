// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

struct FootQuakeControlContext {
    let settings: FootQuakeSettings
    let area: CGRect
    let animationDuration: Double

    var overrides: [String] {
        var overrides: [String] = []
        if let placement = settings.placement {
            overrides.append("macos-quake-position=\(placement.position.rawValue)")
            overrides.append("macos-quake-size=\(placement.widthPercent)x\(placement.heightPercent)")
        }
        if let opacity = settings.opacity {
            overrides.append("macos-quake-alpha=\(opacity)")
        }
        if let autoHide = settings.autoHide {
            overrides.append("macos-quake-auto-hide=\(autoHide ? "yes" : "no")")
        }
        overrides.append("macos-quake-dim=\(settings.dim)")
        overrides.append("macos-quake-animation-duration=\(animationDuration)")
        overrides.append("macos-quake-area=\(area.minX),\(area.minY),\(area.width),\(area.height)")
        return overrides
    }
}

enum FootQuakeCommand: String {
    case toggle
    case hide
    case status
}

enum FootQuakeReply {
    case visible
    case hidden

    init?(_ output: ExternalTerminalProcess.Output) {
        guard output.status == 0 else { return nil }
        switch String(decoding: output.data, as: UTF8.self) {
        case "visible\n": self = .visible
        case "hidden\n": self = .hidden
        default: return nil
        }
    }
}
