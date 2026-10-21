// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceSwipeBackdropTests: XCTestCase {
    func testNativeBlackCaptureTakesPrecedenceOverValidWallpaperFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(NSBitmapImageRep(cgImage: makeImage()).representation(using: .png, properties: [:]))
            .write(to: url)
        let wallpaper = OverviewWallpaperCache()
        wallpaper.desktopImageURL = { _ in url }
        let black = try makeImage(color: CGColor(gray: 0, alpha: 1))
        wallpaper.captureWallpaper = { _ in black }
        let backdrop = WorkspaceSwipeBackdrop(wallpaperCache: wallpaper)

        let image = try XCTUnwrap(backdrop.image(for: monitor))
        let pixel = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(pixel.redComponent, 0)
        XCTAssertEqual(pixel.greenComponent, 0)
        XCTAssertEqual(pixel.blueComponent, 0)
        XCTAssertEqual(pixel.alphaComponent, 1)
    }

    func testMissingWallpaperFileUsesAndCachesRealDesktopImage() throws {
        let wallpaper = OverviewWallpaperCache()
        wallpaper.desktopImageURL = { _ in URL(fileURLWithPath: "/nonexistent/swipe-wallpaper.png") }
        let image = try makeImage()
        var captures = 0
        wallpaper.captureWallpaper = { _ in
            captures += 1
            return image
        }
        let backdrop = WorkspaceSwipeBackdrop(wallpaperCache: wallpaper)

        XCTAssertTrue(backdrop.image(for: monitor) === image)
        XCTAssertTrue(backdrop.image(for: monitor) === image)
        XCTAssertEqual(captures, 1)
    }

    func testMissingOrCroppedDesktopImageCannotBecomeBackdrop() throws {
        let missingCache = OverviewWallpaperCache()
        missingCache.desktopImageURL = { _ in nil }
        missingCache.captureWallpaper = { _ in nil }
        XCTAssertNil(WorkspaceSwipeBackdrop(wallpaperCache: missingCache).image(for: monitor))

        let croppedImage = try makeImage(width: 1)
        let croppedCache = OverviewWallpaperCache()
        croppedCache.desktopImageURL = { _ in nil }
        croppedCache.captureWallpaper = { _ in croppedImage }
        XCTAssertNil(WorkspaceSwipeBackdrop(wallpaperCache: croppedCache).image(for: monitor))
    }

    func testWallpaperSelectionExcludesBackstopOtherDisplaysAndAppWindows() {
        let frame = CGRect(x: 0, y: 0, width: 4, height: 3)
        let desktop = CGWindowLevelForKey(.desktopWindow)
        let windows = [
            window(1, level: desktop - 3, frame: frame),
            window(2, level: desktop - 1, frame: frame.offsetBy(dx: 4, dy: 0)),
            window(3, level: 0, frame: frame),
            window(4, level: desktop - 1, frame: frame)
        ]
        XCTAssertEqual(SkyLight.wallpaperWindow(in: windows, frame: frame)?.id, 4)
        XCTAssertNil(SkyLight.wallpaperWindow(in: Array(windows.prefix(3)), frame: frame))
    }

    func testLiveWallpaperAboveTheDesktopIsPreferredAndCropped() throws {
        let frame = CGRect(x: 0, y: 0, width: 4, height: 3)
        let live = frame.insetBy(dx: -1, dy: -1)
        let desktop = CGWindowLevelForKey(.desktopWindow)
        let icons = CGWindowLevelForKey(.desktopIconWindow)
        let windows = [
            window(1, level: icons, frame: frame),
            window(2, level: desktop + 1, frame: live),
            window(3, level: desktop - 1, frame: frame)
        ]
        let match = try XCTUnwrap(SkyLight.wallpaperWindow(in: windows, frame: frame))
        XCTAssertEqual(match.id, 2)
        XCTAssertEqual(match.frame, live)

        let image = try makeImage(width: 12, height: 10)
        let cropped = try XCTUnwrap(SkyLight.crop(image, from: live, to: frame))
        XCTAssertEqual(cropped.width, 8)
        XCTAssertEqual(cropped.height, 6)
        XCTAssertTrue(SkyLight.crop(image, from: frame, to: frame) === image)

        let fractional = CGRect(x: -0.25, y: -0.25, width: 6, height: 5)
        let offset = try XCTUnwrap(SkyLight.crop(image, from: fractional, to: frame))
        XCTAssertEqual(offset.width, 8)
        XCTAssertEqual(offset.height, 6)

        let clipped = try makeImage(width: 8, height: 6)
        XCTAssertTrue(SkyLight.crop(clipped, from: live, to: frame) === clipped)
        XCTAssertNil(SkyLight.crop(try makeImage(width: 7, height: 6), from: live, to: frame))
    }

    func testCaptureBridgeRejectsMalformedResultsAndRetainsImage() throws {
        XCTAssertNil(SkyLight.firstCapturedImage(in: [] as CFArray))
        XCTAssertNil(SkyLight.firstCapturedImage(in: ["not an image"] as CFArray))
        let image = try autoreleasepool {
            try XCTUnwrap(SkyLight.firstCapturedImage(in: [try makeImage()] as CFArray))
        }
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 3)
    }

    private var monitor: Monitor {
        let frame = CGRect(x: 0, y: 0, width: 4, height: 3)
        return Monitor(
            id: .init(displayId: 999), displayId: 999, frame: frame, visibleFrame: frame,
            hasNotch: false, name: "Backdrop test"
        )
    }

    private func window(_ id: UInt32, level: Int32, frame: CGRect) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowLayer as String: level,
            kCGWindowBounds as String: frame.dictionaryRepresentation
        ]
    }

    private func makeImage(
        width: Int = 4,
        height: Int = 3,
        color: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    ) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
