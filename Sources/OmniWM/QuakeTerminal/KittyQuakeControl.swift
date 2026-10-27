// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

struct KittyQuakeControlContext {
    struct Frame: Encodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ frame: CGRect) {
            x = frame.minX
            y = frame.minY
            width = frame.width
            height = frame.height
        }
    }

    struct Screen: Encodable {
        let frame: Frame
        let visibleFrame: Frame
        let scale: Double

        init(frame: CGRect, visibleFrame: CGRect, scale: CGFloat) {
            self.frame = Frame(frame)
            self.visibleFrame = Frame(visibleFrame)
            self.scale = scale
        }
    }

    let settings: KittyQuakeSettings
    let screen: Screen
    let barBottom: Double?
}

struct KittyQuakeControlRequest: Encodable {
    enum Operation: String, Encodable {
        case apply
        case toggle
    }

    let operation: Operation
    let settings: KittyQuakeSettings
    let screen: KittyQuakeControlContext.Screen
    let barBottom: Double?

    init(operation: Operation, context: KittyQuakeControlContext) {
        self.operation = operation
        settings = context.settings
        screen = context.screen
        barBottom = context.barBottom
    }
}

struct KittyQuakeControlReply: Decodable {
    let opacityNeedsRestart: Bool
}
