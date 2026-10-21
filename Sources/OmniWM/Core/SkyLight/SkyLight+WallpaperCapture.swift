// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

extension SkyLight {
    func captureWallpaper(in frame: CGRect) -> CGImage? {
        guard let capture = surfaces.captureWindowList,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let wallpaper = Self.wallpaperWindow(in: windows, frame: frame)
        else { return nil }
        var windowId = wallpaper.id
        guard let images = capture(getMainConnectionID(), &windowId, 1, (1 << 11) | (1 << 9) | (1 << 19))?
            .takeRetainedValue(),
            let image = Self.firstCapturedImage(in: images)
        else { return nil }
        return Self.crop(image, from: wallpaper.frame, to: frame)
    }

    static func wallpaperWindow(in windows: [[String: Any]], frame: CGRect) -> (id: UInt32, frame: CGRect)? {
        let levels = (CGWindowLevelForKey(.desktopWindow) - 1) ..< CGWindowLevelForKey(.desktopIconWindow)
        for window in windows {
            guard let level = window[kCGWindowLayer as String] as? Int32,
                  levels.contains(level),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let windowFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  windowFrame.contains(frame),
                  let windowId = window[kCGWindowNumber as String] as? UInt32
            else { continue }
            return (windowId, windowFrame)
        }
        return nil
    }

    static func crop(_ image: CGImage, from windowFrame: CGRect, to frame: CGRect) -> CGImage? {
        if windowFrame == frame || covers(image, frame) { return image }
        guard covers(image, windowFrame) else { return nil }
        let scale = CGFloat(image.width) / windowFrame.width
        let rect = CGRect(
            x: ((frame.minX - windowFrame.minX) * scale).rounded(),
            y: ((frame.minY - windowFrame.minY) * scale).rounded(),
            width: (frame.width * scale).rounded(),
            height: (frame.height * scale).rounded()
        )
        return image.cropping(to: rect)
    }

    private static func covers(_ image: CGImage, _ rect: CGRect) -> Bool {
        guard rect.width > 0 else { return false }
        let scale = CGFloat(image.width) / rect.width
        return scale >= 1 && abs(scale - scale.rounded()) < 0.01
            && Int((rect.height * scale).rounded()) == image.height
    }

    nonisolated static func firstCapturedImage(in images: CFArray) -> CGImage? {
        guard CFArrayGetCount(images) == 1,
              let pointer = CFArrayGetValueAtIndex(images, 0)
        else { return nil }
        let value = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(value) == CGImage.typeID else { return nil }
        return unsafeDowncast(value, to: CGImage.self)
    }
}
