// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
import QuartzCore

struct SpatialCameraTransform: Equatable, Sendable {
    var scale: CGFloat = 1.0
    var translation: CGPoint = .zero
    var anchor: CGPoint = .zero

    static let identity = SpatialCameraTransform()

    var affineTransform: CGAffineTransform {
        CGAffineTransform(translationX: anchor.x + translation.x, y: anchor.y + translation.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -anchor.x, y: -anchor.y)
    }

    var caTransform3D: CATransform3D {
        CATransform3DMakeAffineTransform(affineTransform)
    }

    func project(point: CGPoint) -> CGPoint {
        point.applying(affineTransform)
    }

    func project(rect: CGRect) -> CGRect {
        rect.applying(affineTransform)
    }

    func unproject(point: CGPoint) -> CGPoint {
        point.applying(affineTransform.inverted())
    }
}

enum SpatialCameraSettlement: Equatable, Sendable {
    case focusedWindow
    case overviewGrid
}

struct SpatialCameraConfig: Equatable, Sendable {
    var minScale: CGFloat = 0.20
    var maxScale: CGFloat = 1.0
    var overviewScale: CGFloat = 0.35
    var rubberBandResistance: CGFloat = 0.35
    var snapToFocusThreshold: CGFloat = 0.75
    var velocityThreshold: CGFloat = 0.50
}

final class SpatialCameraViewport: @unchecked Sendable {
    let config: SpatialCameraConfig
    private(set) var current: SpatialCameraTransform
    private(set) var isTracking = false
    private var initialTouchSpan: CGFloat?
    private var initialScale: CGFloat = 1.0
    private static let minimumGestureScale: CGFloat = 0.01
    private static let maximumGestureScale: CGFloat = 100
    private var gestureScale: CGFloat = 1.0

    init(config: SpatialCameraConfig = .init(), initial: SpatialCameraTransform = .identity) {
        self.config = config
        current = initial
    }

    func beginGesture(anchor: CGPoint) {
        isTracking = true
        rebaseAnchor(to: anchor)
        gestureScale = current.scale
        initialTouchSpan = nil
    }

    func updateMagnify(delta: CGFloat, anchor: CGPoint? = nil) {
        guard isTracking else { return }
        if let anchor { rebaseAnchor(to: anchor) }
        guard delta.isFinite else { return }
        setGestureScale(gestureScale * (1.0 + delta))
    }

    func updatePan(delta: CGPoint) {
        guard isTracking else { return }
        current.translation.x += delta.x
        current.translation.y += delta.y
    }

    func updateTouchSpan(distance: CGFloat, center: CGPoint) {
        guard isTracking else { return }
        rebaseAnchor(to: center)
        guard let baseline = initialTouchSpan, baseline > 0 else {
            initialTouchSpan = distance
            initialScale = gestureScale
            return
        }
        guard distance.isFinite else { return }
        setGestureScale(initialScale * distance / baseline)
    }

    func endGesture(velocity: CGFloat = 0) -> SpatialCameraSettlement {
        isTracking = false
        initialTouchSpan = nil
        let target: SpatialCameraSettlement
        if velocity > config.velocityThreshold {
            target = .focusedWindow
        } else if velocity < -config.velocityThreshold {
            target = .overviewGrid
        } else if current.scale >= config.snapToFocusThreshold {
            target = .focusedWindow
        } else {
            target = .overviewGrid
        }
        return target
    }

    func settle(at settlement: SpatialCameraSettlement) {
        isTracking = false
        initialTouchSpan = nil
        switch settlement {
        case .focusedWindow:
            current.scale = config.maxScale
            current.translation = .zero
        case .overviewGrid:
            current.scale = config.overviewScale
            current.translation = .zero
        }
    }

    private func setGestureScale(_ raw: CGFloat) {
        gestureScale = min(max(raw, Self.minimumGestureScale), Self.maximumGestureScale)
        current.scale = applyRubberBanding(gestureScale)
    }

    private func rebaseAnchor(to anchor: CGPoint) {
        let pull = 1.0 - current.scale
        current.translation.x += (current.anchor.x - anchor.x) * pull
        current.translation.y += (current.anchor.y - anchor.y) * pull
        current.anchor = anchor
    }

    private func applyRubberBanding(_ raw: CGFloat) -> CGFloat {
        if raw > config.maxScale {
            let overflow = raw - config.maxScale
            return config.maxScale + (overflow * config.rubberBandResistance) / (1.0 + overflow)
        } else if raw < config.minScale {
            let underflow = config.minScale - raw
            return config.minScale - (underflow * config.rubberBandResistance) / (1.0 + underflow)
        }
        return raw
    }
}
