// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testDrawerImageRequestsIgnoreHoverSettingsAndIncludeChromeAndMembers() async throws {
        let fixture = try await drawerFixture()
        let editor = fixture.editor
        let added = await editor.addDrawer(name: "tools", edge: .left, widget: "clock")
        XCTAssertTrue(added)
        let original = try drawerImageRequest(fixture)
        await drawerEdit(fixture) { editor.setDrawer("tools", key: "edge", value: "bottom") }
        XCTAssertEqual(try drawerImageRequest(fixture), original)
        await drawerEdit(fixture) { editor.setDrawer("tools", key: "hover", value: true) }
        XCTAssertEqual(try drawerImageRequest(fixture), original)
        await drawerEdit(fixture) { editor.setDrawer("tools", key: "close", value: "leave") }
        XCTAssertEqual(try drawerImageRequest(fixture), original)
        await drawerEdit(fixture) { editor.setDrawer("tools", key: "width", value: 440.0) }
        XCTAssertEqual(try drawerImageRequest(fixture), original)
        editor.setDrawer("tools", key: "reach", value: 41.0, continuous: true)
        let drained = await editor.writes.drain()
        XCTAssertTrue(drained)
        XCTAssertEqual(try drawerImageRequest(fixture), original)
        let stored = try XCTUnwrap(editor.drawer("tools"))
        XCTAssertEqual(stored.edge, .bottom)
        XCTAssertTrue(stored.hover)
        XCTAssertTrue(stored.closesOnLeave)
        XCTAssertEqual(stored.width, 440)
        XCTAssertEqual(stored.reach, 41)
        await drawerEdit(fixture) { editor.setDrawer("tools", key: "chrome", value: false) }
        let chrome = try drawerImageRequest(fixture)
        XCTAssertNotEqual(chrome, original)
        let memberAdded = await editor.addDrawerWidget("weather", to: "tools")
        XCTAssertTrue(memberAdded)
        XCTAssertNotEqual(try drawerImageRequest(fixture), chrome)
        XCTAssertEqual(editor.drawerMembers("tools"), ["clock", "weather"])
    }

    private func drawerImageRequest(_ fixture: Fixture) throws -> ShellSettingsPreview.Request {
        ShellSettingsPreview.Request(
            config: try XCTUnwrap(fixture.editor.drawerPreviewConfig), surface: .drawer("tools"),
            style: .init(), scale: 1, dark: false, fullWidth: false,
            sourceGeneration: fixture.configuration.sourceGeneration
        )
    }
}
