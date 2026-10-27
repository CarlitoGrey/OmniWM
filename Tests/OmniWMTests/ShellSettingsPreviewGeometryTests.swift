// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class ShellSettingsPreviewGeometryTests: XCTestCase {
    func testNotchedDisplayUsesItsWidthAndAllFourFullWidthZones() async throws {
        let config = try fixture()
        let monitor = monitor()
        let settings = settings()
        let positions: [(WorkspaceBarFullWidthNotchMode, Int, Int)] = [
            (.rightOfNotch, 868, 896), (.leftOfNotch, 684, 712),
            (.splitAroundNotch, 712, 868), (.moveBelowMenuBar, 776, 804)
        ]
        for (mode, first, second) in positions {
            settings.fullWidthNotchMode = mode
            let image = try await ShellSettingsPreview.render(request(config, settings: settings, monitor: monitor))
            XCTAssertEqual(image.width, 1600, mode.rawValue)
            XCTAssertEqual(image.height, 32, mode.rawValue)
            XCTAssertEqual(try columns(of: [255, 0, 0, 255], in: image), Array(4 ..< 24), mode.rawValue)
            XCTAssertEqual(try columns(of: [0, 255, 0, 255], in: image), Array(first ..< first + 20), mode.rawValue)
            XCTAssertEqual(try columns(of: [0, 0, 255, 255], in: image), Array(second ..< second + 20), mode.rawValue)
            XCTAssertEqual(try columns(of: [255, 255, 0, 255], in: image), Array(1576 ..< 1596), mode.rawValue)
        }
    }

    func testVerticalDisplayUsesItsVisibleHeightAsTheBarLength() async throws {
        let config = try fixture()
        let monitor = monitor()
        let settings = settings()
        for position: WorkspaceBarPosition in [.left, .right] {
            settings.position = position
            let request = request(config, settings: settings, monitor: monitor)
            XCTAssertTrue(request.style.vertical)
            let image = try await ShellSettingsPreview.render(request)
            XCTAssertEqual(image.width, 32)
            XCTAssertEqual(image.height, 956)
        }
    }

    func testFillLeftOfNotchUsesMenuBarHeightForWidgetsAndComposition() async throws {
        var config = try fixture(responsive: true)
        config.center = []
        config.trailing = []
        let settings = settings()
        settings.fullWidth = false
        settings.height = 60
        settings.notchMode = .fillLeftOfNotch
        let request = request(config, settings: settings, monitor: monitor())
        XCTAssertEqual(request.style.height, 44)
        let image = try await ShellSettingsPreview.render(request)
        XCTAssertEqual(image.width, 732)
        XCTAssertEqual(image.height, 44)
    }

    func testNoDisplayKeepsSchematicLengthsAndSequentialFloatingLayout() async throws {
        let config = try fixture()
        let settings = settings()
        let style = ShellSettingsPreview.style(settings: settings, config: config)
        for fullWidth in [false, true] {
            let request = ShellSettingsPreview.Request(
                config: config, surface: .bar, style: style, scale: 1, dark: false,
                fullWidth: fullWidth, sourceGeneration: 0
            )
            XCTAssertNil(request.display)
            let image = try await ShellSettingsPreview.render(request)
            XCTAssertEqual(image.width, fullWidth ? 960 : 112)
            XCTAssertEqual(image.height, 32)
            let first = fullWidth ? 456 : 32
            let second = fullWidth ? 484 : 60
            let last = fullWidth ? 936 : 88
            XCTAssertEqual(try columns(of: [255, 0, 0, 255], in: image), Array(4 ..< 24))
            XCTAssertEqual(try columns(of: [0, 255, 0, 255], in: image), Array(first ..< first + 20))
            XCTAssertEqual(try columns(of: [0, 0, 255, 255], in: image), Array(second ..< second + 20))
            XCTAssertEqual(try columns(of: [255, 255, 0, 255], in: image), Array(last ..< last + 20))
        }
    }

    private func fixture(responsive: Bool = false) throws -> ShellConfig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewGeometry-\(UUID())")
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        for (name, color) in [("first", "#FF0000"), ("second", "#00FF00"), ("third", "#0000FF"), ("last", "#FFFF00")] {
            let folder = directory.appendingPathComponent("widgets/\(name)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let height = responsive ? "ctx.data.bar.style.height" : "12"
            try "function render(ctx) return ui.box{ w = 20, h = \(height), fill = \"\(color)\" } end".write(
                to: folder.appendingPathComponent("init.luau"), atomically: true, encoding: .utf8
            )
        }
        var config = ShellConfig()
        config.directories = [directory]
        config.leading = ["first"]
        config.center = ["second", "third"]
        config.trailing = ["last"]
        return config
    }

    private func settings() -> WorkspaceBarSettings {
        let settings = WorkspaceBarSettings()
        settings.fullWidth = true
        settings.position = .overlappingMenuBar
        settings.height = 32
        settings.transparentBackground = true
        return settings
    }

    private func monitor() -> Monitor {
        Monitor(
            id: .init(displayId: 93_417), displayId: 93_417,
            frame: CGRect(x: 100, y: 200, width: 1600, height: 1000),
            visibleFrame: CGRect(x: 100, y: 200, width: 1600, height: 956),
            hasNotch: true, notchRange: 840 ... 960, notchHeight: 44, name: "Preview display"
        )
    }

    private func request(
        _ config: ShellConfig, settings: WorkspaceBarSettings, monitor: Monitor
    ) -> ShellSettingsPreview.Request {
        ShellSettingsPreview.Request(
            config: config, surface: .bar,
            style: ShellSettingsPreview.style(settings: settings, config: config, monitor: monitor),
            scale: 1, dark: false, fullWidth: false, sourceGeneration: 0,
            display: ShellSettingsPreview.display(settings: settings, config: config, monitor: monitor)
        )
    }

    private func columns(of color: [UInt8], in image: CGImage) throws -> [Int] {
        let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
        let row = image.height / 2 * image.bytesPerRow
        return (0 ..< image.width).filter { x in
            Array(bytes[(row + x * 4) ..< (row + x * 4 + 4)]) == color
        }
    }
}
