// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testIslandRoutesSelectTheirSurfaceGroupAndInstanceWithoutLosingTheBarSelection() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        navigation.proceed(to: SettingsRoute(section: .styles))
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        let selected = await fixture.editor.selectWidget("clock")
        XCTAssertTrue(selected)
        for group in ["appearance", "interaction", "placement"] {
            let route = SettingsRoute(section: .styles, tab: "island", anchor: group)
            await fixture.editor.open(route)
            XCTAssertEqual(fixture.editor.surface, .island)
            XCTAssertEqual(fixture.editor.group, group)
            XCTAssertNil(fixture.editor.selectedComponent)
            XCTAssertEqual(fixture.editor.selectedWidget, "clock")
            XCTAssertEqual(navigation.route, route)
        }
        let component = SettingsRoute(section: .styles, tab: "island", itemID: "london")
        navigation.searchText = "Clock"
        await fixture.editor.open(component)
        XCTAssertEqual(fixture.editor.selectedComponent, "london")
        XCTAssertEqual(navigation.route, component)
        XCTAssertEqual(navigation.searchText, "Clock")
        for tab in ["lanes", "placement", "appearance", "behavior", "apps"] {
            await fixture.editor.open(SettingsRoute(section: .styles, tab: tab))
            XCTAssertEqual(fixture.editor.surface, .bar)
            XCTAssertNil(fixture.editor.selectedWidget)
            XCTAssertEqual(fixture.editor.selectedComponent, "london")
            XCTAssertEqual(fixture.editor.group, tab)
        }
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testDirtyBarToIslandRouteIsAtomicAndCancelAllowsTheSameSearchResultAgain() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        navigation.proceed(to: SettingsRoute(section: .styles))
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        let key = await dirtyText(fixture.editor)
        let original = fixture.editor.destination
        let originalRoute = navigation.route
        let route = SettingsRoute(section: .styles, tab: "island", anchor: "interaction", itemID: "london")
        navigation.request(route)
        navigation.searchText = "Island"
        await fixture.editor.open(navigation.route)
        XCTAssertEqual(fixture.editor.destination, original)
        XCTAssertEqual(fixture.editor.pendingTransition, .destination(.init(
            surface: .island, widget: "omniwm", component: "london", group: "interaction"
        )))
        XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
        await fixture.editor.resolve(.cancel)
        XCTAssertEqual(fixture.editor.destination, original)
        XCTAssertEqual(navigation.route, originalRoute)
        XCTAssertEqual(navigation.searchText, "Island")
        navigation.request(route)
        await fixture.editor.open(navigation.route)
        XCTAssertNotNil(fixture.editor.pendingTransition)
        let reflected = Events()
        observeRoute(navigation, changed: reflected)
        let saves = fixture.saves.count
        await fixture.editor.resolve(.discard)
        await reflected.wait(1)
        XCTAssertEqual(reflected.count, 1)
        XCTAssertEqual(fixture.saves.count, saves)
        XCTAssertEqual(fixture.editor.surface, .island)
        XCTAssertEqual(fixture.editor.selectedComponent, "london")
        XCTAssertNil(fixture.editor.pendingTransition)
        XCTAssertNil(fixture.editor.draft(key))
    }

    func testDirtyIslandToBarRoutePersistsTheCapturedComponentOnceAndReflectsTheDestination() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        navigation.proceed(to: SettingsRoute(section: .styles, tab: "island", itemID: "london"))
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        await fixture.editor.open(navigation.route)
        fixture.editor.beginComponentTextDraft("london", key: "label")
        let key = ShellEditorDraft.Key.component("london", option: "label")
        fixture.editor.updateDraft(key, .text("Work clock"))
        let original = fixture.editor.destination
        let retainedRoute = navigation.route
        let route = SettingsRoute(section: .styles, tab: "appearance", itemID: "clock")
        navigation.request(route)
        await fixture.editor.open(navigation.route)
        XCTAssertEqual(fixture.editor.destination, original)
        XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
        await fixture.editor.resolve(.cancel)
        XCTAssertEqual(navigation.route, retainedRoute)
        XCTAssertEqual(fixture.editor.destination, original)
        navigation.request(route)
        await fixture.editor.open(navigation.route)
        let reflected = Events()
        observeRoute(navigation, changed: reflected)
        let saves = fixture.saves.count
        await fixture.editor.resolve(.save)
        await reflected.wait(1)
        XCTAssertEqual(fixture.saves.count, saves + 1)
        XCTAssertEqual(reflected.count, 1)
        XCTAssertEqual(navigation.route, SettingsRoute(section: .styles, itemID: "clock"))
        XCTAssertEqual(fixture.editor.surface, .bar)
        XCTAssertEqual(fixture.editor.selectedWidget, "clock")
        XCTAssertEqual(fixture.editor.selectedComponent, "london")
        XCTAssertNil(fixture.editor.draft(key))
        XCTAssertNil(fixture.editor.pendingTransition)
        let config = try await fixture.configuration.previewConfig(profile: "lake")
        XCTAssertEqual(config.island?.components.first { $0.id == "london" }?.options["label"], .string("Work clock"))
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testMissingIslandInstancesFallBackBeforeAndAfterTheSnapshotArrives() async throws {
        let fixture = try await fixture()
        let route = SettingsRoute(section: .styles, tab: "island", anchor: "placement", itemID: "missing-instance")
        await fixture.editor.open(route)
        XCTAssertEqual(fixture.editor.surface, .island)
        XCTAssertNil(fixture.editor.selectedComponent)
        XCTAssertEqual(fixture.editor.group, "placement")
        let unloaded = ShellDesktopEditor(
            configuration: fixture.configuration, settings: fixture.editor.settings,
            controller: fixture.editor.controller
        )
        XCTAssertNil(unloaded.snapshot)
        await unloaded.open(route)
        XCTAssertEqual(unloaded.surface, .island)
        XCTAssertEqual(unloaded.selectedComponent, "missing-instance")
        await unloaded.reload()
        XCTAssertNil(unloaded.selectedComponent)
        XCTAssertEqual(unloaded.surface, .island)
        XCTAssertEqual(unloaded.group, "placement")
    }

    func testDirectSurfaceAndComponentSelectionsReflectCanonicalRoutesWithoutClearingSearch() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        navigation.proceed(to: SettingsRoute(section: .styles))
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        navigation.searchText = "Clock"
        let changed = await fixture.editor.selectSurface(.island)
        XCTAssertTrue(changed)
        XCTAssertEqual(navigation.route, SettingsRoute(section: .styles, tab: "island"))
        let selected = await fixture.editor.selectComponent("london")
        XCTAssertTrue(selected)
        XCTAssertEqual(navigation.route, SettingsRoute(section: .styles, tab: "island", itemID: "london"))
        fixture.editor.beginComponentTextDraft("london", key: "label")
        let key = ShellEditorDraft.Key.component("london", option: "label")
        fixture.editor.updateDraft(key, .text("Primary"))
        let rejected = await fixture.editor.selectComponent("tokyo")
        XCTAssertFalse(rejected)
        XCTAssertEqual(fixture.editor.selectedComponent, "london")
        await fixture.editor.resolve(.cancel)
        XCTAssertEqual(navigation.route, SettingsRoute(section: .styles, tab: "island", itemID: "london"))
        XCTAssertEqual(navigation.searchText, "Clock")
    }
}
