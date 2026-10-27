// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

enum QuakeTerminalProvider: String, CaseIterable, Codable {
    case ghostty
    case kitty
    case foot

    var displayName: String {
        switch self {
        case .ghostty: "Ghostty"
        case .kitty: "Kitty"
        case .foot: "foot"
        }
    }
}
