// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

struct FootQuakeSettings: Codable, Equatable {
    var autoHide: Bool?
    var opacity: Double?
    var placement: QuakePlacementOverride?
    var dim = 0.0

    var isDefault: Bool {
        autoHide == nil && opacity == nil && placement == nil && dim == 0
    }

    func normalized() -> FootQuakeSettings {
        FootQuakeSettings(
            autoHide: autoHide,
            opacity: opacity.map(QuakeOpacityOverride.normalized),
            placement: placement?.normalized(),
            dim: dim.isFinite ? min(max(dim, 0), 1) : 0
        )
    }
}

extension FootQuakeSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoHide = try container.decodeIfPresent(Bool.self, forKey: .autoHide)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity)
        placement = try container.decodeIfPresent(QuakePlacementOverride.self, forKey: .placement)
        dim = try container.decodeIfPresent(Double.self, forKey: .dim) ?? 0
    }
}
