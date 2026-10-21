// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum KeyEquivalent {
    static func matches(
        _ letter: String,
        ansiKeyCode: Int,
        keyCode: UInt16,
        charactersIgnoringModifiers: String?
    ) -> Bool {
        if let typed = charactersIgnoringModifiers?.lowercased(), typed.count == 1, typed.allSatisfy(\.isASCII) {
            return typed == letter
        }
        return keyCode == UInt16(ansiKeyCode)
    }
}
