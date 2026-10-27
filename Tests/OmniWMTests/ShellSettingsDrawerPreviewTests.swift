// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import OmniWMScriptHost
import XCTest

@MainActor
final class ShellSettingsDrawerPreviewTests: XCTestCase {
    func testDrawerUsesUniquePopoutsSkipsMissingAndPanelLessMembersAndComposesChromeOnce() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try source("red", in: directory, code: """
        function render(ctx) return ui.box{ w = 200, h = 100, fill = '#00FF00' } end
        function popout(ctx) return ui.box{ w = 20, h = 10, fill = '#FF0000' } end
        """)
        try source("blue", in: directory, code: """
        function render(ctx) return ui.box{ w = 200, h = 100, fill = '#00FF00' } end
        function popout(ctx) return ui.box{ w = 10, h = 20, fill = '#0000FF' } end
        """)
        try source("bar-only", in: directory, code: "function render(ctx) return ui.box{ w = 300, h = 300 } end")
        try source("empty", in: directory, code: """
        function render(ctx) return ui.box{ w = 400, h = 400 } end
        function popout(ctx) return ui.box{ w = 0, h = 0 } end
        """)
        var config = ShellConfig()
        config.directories = [directory]
        let members = ["red", "not-installed", "red", "bar-only", "empty", "blue"]
        for chrome in [false, true] {
            var drawer = ShellDrawerConfig(id: "tools", edge: .right, widgets: members, hover: true)
            drawer.chrome = chrome
            config.drawers = [drawer]
            for scale: CGFloat in [1, 2] {
                let image = try await ShellSettingsPreview.render(request(config, scale: scale))
                XCTAssertEqual(image.width, Int((chrome ? 44 : 20) * scale))
                XCTAssertEqual(image.height, Int((chrome ? 66 : 42) * scale))
                XCTAssertEqual(try pixelCount([255, 0, 0, 255], in: image), 200 * Int(scale * scale))
                XCTAssertEqual(try pixelCount([0, 0, 255, 255], in: image), 200 * Int(scale * scale))
                XCTAssertEqual(try pixelCount([0, 255, 0, 255], in: image), 0)
                if chrome { XCTAssertGreaterThan(try opaquePixelCount(image), 400 * Int(scale * scale)) }
            }
        }
    }

    func testAllSkippedOrZeroSizedMembersReportNothingToShow() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try source("bar-only", in: directory, code: "function render(ctx) return ui.box{} end")
        try source("empty", in: directory, code: """
        function render(ctx) return ui.box{} end
        function popout(ctx) return ui.box{ w = 0, h = 0 } end
        """)
        try source("zero", in: directory, code: """
        function render(ctx) return ui.box{} end
        function popout(ctx) return ui.box{ w = 0, h = 0 } end
        """)
        var config = ShellConfig()
        config.directories = [directory]
        for members in [["not-installed", "bar-only", "empty"], ["zero"]] {
            config.drawers = [.init(id: "tools", edge: .left, widgets: members, hover: false)]
            do {
                _ = try await ShellSettingsPreview.render(request(config))
                XCTFail("Empty drawer unexpectedly produced an image")
            } catch let error as ShellScriptFailure {
                XCTAssertEqual(error.message, "This drawer has nothing to show.")
            }
        }
    }

    func testPopoutPreviewQueuesButNeverDispatchesMessagesOrServices() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try source("sample", in: directory, code: """
        local dispatched = false
        local function execute()
            dispatched = true
            omniwm.run("switch-workspace 2")
        end
        assert(omniwm.store.set("drawer-preview", true))
        assert(omniwm.after(0.01, execute))
        assert(omniwm.http({ url = "https://example.test/drawer-preview" }, execute))
        function render(ctx) error("drawer called bar render") end
        function popout(ctx)
            return ui.text{ text = if dispatched then "Dispatched" else ctx.data.clock, onClick = execute }
        end
        """)
        var config = ShellConfig()
        config.directories = [directory]
        let input = try XCTUnwrap(ShellSettingsPreview.input("sample", config: config))
        let trees = try await ShellSettingsPreviewRenderer.shared.render(
            inputs: [input], values: ShellSettingsPreviewSamples.values(
                style: .init(), islandSize: nil, dark: false, scale: 1
            ), settings: [:], expanded: nil, popout: true
        )
        let tree = try XCTUnwrap(trees.first)
        let text = ShellTextStore()
        text.ingest(tree.strings, count: tree.stringCount)
        XCTAssertEqual(trees.count, 1)
        XCTAssertTrue(text.strings.contains("16:42"))
        XCTAssertFalse(text.strings.contains("Dispatched"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("store").path))
    }

    func testDrawerSuppressesOnlyTheRootPopoverOrGlassMaterialAndKeepsDefaultRasterBehavior() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        for material in ["popover", "glass"] {
            try source("sample", in: directory, code: """
            local function content()
                return ui.box{ w = 24, h = 24, material = "\(material)", fill = '#FF000040',
                    ui.box{ w = 10, h = 10, material = "glass", fill = '#0000FF40' } }
            end
            function render(ctx) return content() end
            function popout(ctx) return content() end
            """)
            var config = ShellConfig()
            config.directories = [directory]
            var drawer = ShellDrawerConfig(id: "tools", edge: .left, widgets: ["sample"], hover: false)
            drawer.chrome = false
            config.drawers = [drawer]
            let input = try XCTUnwrap(ShellSettingsPreview.input("sample", config: config))
            let trees = try await ShellSettingsPreviewRenderer.shared.render(
                inputs: [input], values: [:], settings: [:], expanded: nil, popout: true
            )
            try assertMaterialSuppression(XCTUnwrap(trees.first), directory: directory)
            let defaultImages = try await ShellSettingsPreviewRaster.render(
                trees, theme: config.theme, dark: false, scale: 1, limit: nil
            )
            let explicitImages = try await ShellSettingsPreviewRaster.render(
                trees, theme: config.theme, dark: false, scale: 1, limit: nil, rootMaterial: true
            )
            XCTAssertEqual(
                try pixels(XCTUnwrap(defaultImages.first).image),
                try pixels(XCTUnwrap(explicitImages.first).image)
            )
            let suppressed = try await ShellSettingsPreviewRaster.render(
                trees, theme: config.theme, dark: false, scale: 1, limit: nil, rootMaterial: false
            )
            let actual = try await ShellSettingsPreview.render(request(config))
            XCTAssertEqual(try pixels(actual), try pixels(XCTUnwrap(suppressed.first).image))
        }
    }

    func testRetainedImageContextSeparatesDrawersAndIslandAndKeepsChromeChangesTogether() {
        var config = ShellConfig()
        config.drawers = [
            .init(id: "first", edge: .left, widgets: ["clock"], hover: true),
            .init(id: "second", edge: .left, widgets: ["clock"], hover: true)
        ]
        let first = ShellDesktopPreview.context(for: request(config, id: "first"))
        XCTAssertNotEqual(first, ShellDesktopPreview.context(for: request(config, id: "second")))
        for expanded in [false, true] {
            let island = ShellSettingsPreview.Request(
                config: config, surface: .island(expanded: expanded), style: .init(),
                scale: 1, dark: false, fullWidth: false, sourceGeneration: 0
            )
            XCTAssertNotEqual(first, ShellDesktopPreview.context(for: island))
        }
        config.drawers[0].chrome.toggle()
        XCTAssertEqual(first, ShellDesktopPreview.context(for: request(config, id: "first")))
    }

    private func assertMaterialSuppression(_ tree: ShellSettingsPreviewRenderer.Tree, directory: URL) throws {
        let text = ShellTextStore()
        text.ingest(tree.strings, count: tree.stringCount)
        let surface = ShellWidgetSurface(
            scale: 1, resources: ShellResources(motion: MotionPolicy(animationsEnabled: false)),
            directories: [directory]
        )
        surface.text = text
        XCTAssertTrue(surface.layout.apply(tree.wire, text: text))
        surface.drawsRootMaterial = true
        let ordinary = paints(surface.commands(text: text))
        surface.drawsRootMaterial = false
        let drawerPaints = paints(surface.commands(text: text))
        let root = surface.layout.core.rootHandle.slot
        XCTAssertEqual(drawerPaints[root], 0)
        XCTAssertEqual(ordinary.keys.sorted(), drawerPaints.keys.sorted())
        for (slot, value) in ordinary where slot != root {
            XCTAssertEqual(drawerPaints[slot], value)
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            XCTAssertNotEqual(ordinary[root], 0)
            XCTAssertTrue(drawerPaints.contains { $0.key != root && $0.value != 0 })
        }
    }

    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func source(_ name: String, in directory: URL, code: String) throws {
        let folder = directory.appendingPathComponent("widgets/\(name)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try code.write(to: folder.appendingPathComponent("init.luau"), atomically: true, encoding: .utf8)
    }

    private func request(_ config: ShellConfig, id: String = "tools", scale: CGFloat = 1) -> ShellSettingsPreview
        .Request
    {
        .init(
            config: config,
            surface: .drawer(id),
            style: .init(),
            scale: scale,
            dark: false,
            fullWidth: false,
            sourceGeneration: 0
        )
    }

    private func paints(_ commands: [ShellLayerCommand]) -> [Int32: UInt8] {
        var materials: [Int32: UInt8] = [:]
        for command in commands {
            if case let .paint(slot, paint, _) = command { materials[slot] = paint.material }
        }
        return materials
    }

    private func pixels(_ image: CGImage) throws -> Data {
        try XCTUnwrap(image.dataProvider?.data) as Data
    }

    private func pixelCount(_ color: [UInt8], in image: CGImage) throws -> Int {
        let data = try pixels(image)
        return stride(from: 0, to: data.count, by: 4).filter { Array(data[$0 ..< $0 + 4]) == color }.count
    }

    private func opaquePixelCount(_ image: CGImage) throws -> Int {
        let data = try pixels(image)
        return stride(from: 3, to: data.count, by: 4).filter { data[$0] == 255 }.count
    }
}
