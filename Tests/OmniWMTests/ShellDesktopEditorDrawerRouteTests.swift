// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testDrawerRoutesSelectTheCapturedIdAndMissingIdsFallBackAfterLoading() async throws {
        let fixture = try await drawerFixture()
        let added = await fixture.editor.addDrawer(name: "tools", edge: .right, widget: "clock")
        XCTAssertTrue(added)
        let navigation = SettingsNavigationModel()
        navigation.proceed(to: SettingsRoute(section: .styles))
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        navigation.request(SettingsRoute(section: .styles, tab: "drawers", itemID: "tools"))
        await fixture.editor.open(navigation.route)
        XCTAssertEqual(fixture.editor.selectedDrawer, "tools")
        XCTAssertEqual(navigation.route, SettingsRoute(section: .styles, tab: "drawers", itemID: "tools"))
        await fixture.editor.open(SettingsRoute(section: .styles, tab: "drawers", itemID: "missing"))
        XCTAssertEqual(fixture.editor.selectedDrawer, "dashboard")
        _ = try await fixture.configuration.selectProfile("celestial")
        let cold = ShellDesktopEditor(
            configuration: fixture.configuration, settings: fixture.editor.settings,
            controller: fixture.editor.controller
        )
        await cold.open(SettingsRoute(section: .styles, tab: "drawers", itemID: "missing"))
        XCTAssertEqual(cold.selectedDrawer, "missing")
        await cold.reload()
        XCTAssertEqual(cold.selectedDrawer, "dashboard")
    }

    func testDirtyBarAndIslandDraftsCancelDrawerRoutesWithoutChangingContext() async throws {
        for island in [false, true] {
            let fixture = try await fixture()
            let navigation = SettingsNavigationModel()
            navigation.proceed(to: SettingsRoute(section: .styles))
            fixture.editor.attach(navigation)
            defer { fixture.editor.detach() }
            let key: ShellEditorDraft.Key
            if island {
                await fixture.editor.open(SettingsRoute(section: .styles, tab: "island", itemID: "london"))
                fixture.editor.beginComponentTextDraft("london", key: "label")
                key = .component("london", option: "label")
                fixture.editor.updateDraft(key, .text("Home"))
            } else { key = await dirtyText(fixture.editor) }
            let original = fixture.editor.destination
            let route = navigation.route
            navigation.request(SettingsRoute(section: .styles, tab: "drawers", itemID: "tools"))
            await fixture.editor.open(navigation.route)
            XCTAssertEqual(fixture.editor.destination, original)
            XCTAssertNotNil(fixture.editor.pendingTransition)
            XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
            await fixture.editor.resolve(.cancel)
            XCTAssertEqual(fixture.editor.destination, original)
            XCTAssertEqual(navigation.route, route)
            XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
            XCTAssertEqual(fixture.saves.count, 0)
        }
    }
}
