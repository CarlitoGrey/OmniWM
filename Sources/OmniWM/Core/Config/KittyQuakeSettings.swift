// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

struct KittyQuakeSettings: Codable, Equatable {
    struct Placement: Codable, Equatable {
        static let defaultOverride = Placement(position: .top, widthPercent: 100, heightPercent: 50)

        var position: QuakeTerminalPosition
        var widthPercent: Double
        var heightPercent: Double

        func normalized() -> Placement {
            Placement(
                position: position,
                widthPercent: QuakeTerminalGeometryPolicy.normalizedDimensionPercent(widthPercent),
                heightPercent: QuakeTerminalGeometryPolicy.normalizedDimensionPercent(heightPercent)
            )
        }
    }

    static let defaultOpacityOverride = 0.85

    var autoHide: Bool?
    var opacity: Double?
    var placement: Placement?

    var isNative: Bool {
        autoHide == nil && opacity == nil && placement == nil
    }

    func normalized() -> KittyQuakeSettings {
        KittyQuakeSettings(
            autoHide: autoHide,
            opacity: opacity.map { $0.isFinite ? min(max($0, 0), 1) : Self.defaultOpacityOverride },
            placement: placement?.normalized()
        )
    }
}
