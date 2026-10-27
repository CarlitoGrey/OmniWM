// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

struct QuakePlacementOverride: Codable, Equatable {
    static let defaultOverride = QuakePlacementOverride(position: .top, widthPercent: 100, heightPercent: 50)

    var position: QuakeTerminalPosition
    var widthPercent: Double
    var heightPercent: Double

    func normalized() -> QuakePlacementOverride {
        QuakePlacementOverride(
            position: position,
            widthPercent: QuakeTerminalGeometryPolicy.normalizedDimensionPercent(widthPercent),
            heightPercent: QuakeTerminalGeometryPolicy.normalizedDimensionPercent(heightPercent)
        )
    }
}

enum QuakeOpacityOverride {
    static let defaultOverride = 0.85

    static func normalized(_ opacity: Double) -> Double {
        opacity.isFinite ? min(max(opacity, 0), 1) : defaultOverride
    }
}
