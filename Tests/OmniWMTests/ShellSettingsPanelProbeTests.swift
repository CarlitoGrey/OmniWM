// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ShellSettingsPanelProbeTests: XCTestCase {
    func testMixedCandidatesDistinguishPanelsMissingPanelsAndLoadErrorsWithoutRenderingOrServices() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try source("available", in: directory, code: """
        local function dispatched() error("preview dispatched a service") end
        assert(omniwm.store.set("preview-probe", true))
        assert(omniwm.after(0.01, dispatched))
        assert(omniwm.http({ url = "https://example.test/probe" }, dispatched))
        function render(ctx) error("probe called render") end
        function popout(ctx) error("probe called popout") end
        """)
        try source("missing", in: directory, code: "function render(ctx) error('probe rendered') end")
        try source("broken", in: directory, code: "error('broken probe fixture')")
        try source("no-render", in: directory, code: "function popout(ctx) return ui.box{} end")
        var config = ShellConfig()
        config.directories = [directory]
        let request = ShellSettingsPreview.PanelRequest(
            names: ["available", "broken", "missing", "no-render", "not-installed"],
            config: config, sourceGeneration: 0
        )
        let panels = try await ShellSettingsPreview.probe(request)
        XCTAssertEqual(panels["available"], .available)
        XCTAssertEqual(panels["missing"], .missing)
        for (name, message) in [
            "broken": "broken probe fixture", "no-render": "does not define a render function",
            "not-installed": "is not installed"
        ] {
            guard case let .failed(error)? = panels[name] else {
                XCTFail("\(name) did not report its load error")
                continue
            }
            XCTAssertTrue(error.contains(message), error)
        }
        XCTAssertEqual(panels.count, 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("store").path))
    }

    func testCapabilityIdentityUsesSourcesAndGenerationRatherThanSettings() throws {
        let firstDirectory = try fixture()
        let secondDirectory = try fixture()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        for directory in [firstDirectory, secondDirectory] {
            try source("sample", in: directory, code: "function render(ctx) return ui.box{} end")
        }
        var config = ShellConfig()
        config.directories = [firstDirectory]
        let original = ShellSettingsPreview.PanelRequest(names: ["sample"], config: config, sourceGeneration: 7)
        config.themeName = "another-theme"
        config.widgetSettings["sample"] = [1, 2, 3]
        config.drawers = [.init(id: "tools", edge: .left, widgets: ["sample"], hover: true)]
        XCTAssertEqual(original, .init(names: ["sample"], config: config, sourceGeneration: 7))
        XCTAssertNotEqual(original, .init(names: ["sample"], config: config, sourceGeneration: 8))
        XCTAssertNotEqual(original, .init(names: ["sample", "other"], config: config, sourceGeneration: 7))
        config.directories = [secondDirectory]
        let relocated = ShellSettingsPreview.PanelRequest(names: ["sample"], config: config, sourceGeneration: 7)
        XCTAssertNotEqual(original, relocated)
        XCTAssertNotEqual(original.sources, relocated.sources)
        config.directories = [firstDirectory]
        config.profile = "lake"
        XCTAssertNotEqual(original, .init(names: ["sample"], config: config, sourceGeneration: 7))
    }

    func testCancellationBeforeCapabilityLoadReturnsCancellationInsteadOfPartialResults() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try source("sample", in: directory, code: """
        function render(ctx) return ui.box{} end
        function popout(ctx) return ui.box{} end
        """)
        var config = ShellConfig()
        config.directories = [directory]
        let input = try XCTUnwrap(ShellSettingsPreview.input("sample", config: config))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ShellSettingsPreviewRenderer.shared.panels([input])
        }
        guard case .failure(is CancellationError) = await task.result else {
            return XCTFail("Cancelled capability load published a result")
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
}
