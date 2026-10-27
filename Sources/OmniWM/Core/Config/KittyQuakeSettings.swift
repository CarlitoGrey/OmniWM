// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

struct KittyQuakeSettings: Codable, Equatable {
    var autoHide: Bool?
    var opacity: Double?
    var placement: QuakePlacementOverride?

    var isNative: Bool {
        autoHide == nil && opacity == nil && placement == nil
    }

    func normalized() -> KittyQuakeSettings {
        KittyQuakeSettings(
            autoHide: autoHide,
            opacity: opacity.map(QuakeOpacityOverride.normalized),
            placement: placement?.normalized()
        )
    }
}
