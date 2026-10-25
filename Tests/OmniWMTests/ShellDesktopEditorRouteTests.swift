// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testWidgetRoutesSelectAvailableWidgetsOutsideTheBarAndSurviveReload() async throws {
        let fixture = try await fixture()
        try await fixture.configuration.editBar(profile: "lake") { $0.remove("volume") }
        await fixture.editor.reload()
        XCTAssertNil(fixture.editor.layout?.lane(of: "volume"))
        XCTAssertNotNil(fixture.editor.layout?.source(of: "volume"))
        await fixture.editor.open(SettingsRoute(section: .styles, itemID: "volume"))
        XCTAssertEqual(fixture.editor.selectedWidget, "volume")
        await fixture.editor.reload()
        XCTAssertEqual(fixture.editor.selectedWidget, "volume")
        await fixture.editor.open(SettingsRoute(section: .menuBar, itemID: "clock"))
        XCTAssertEqual(fixture.editor.selectedWidget, "volume")
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testEveryBarGroupRouteClearsTheWidgetSelection() async throws {
        let fixture = try await fixture()
        for tab in ["lanes", "placement", "appearance", "behavior", "apps"] {
            await fixture.editor.open(SettingsRoute(section: .styles, itemID: "clock"))
            XCTAssertEqual(fixture.editor.selectedWidget, "clock")
            await fixture.editor.open(SettingsRoute(section: .styles, tab: tab))
            XCTAssertNil(fixture.editor.selectedWidget, tab)
        }
    }

    func testBarGroupRouteWaitsForTheWidgetDraftToBeDiscarded() async throws {
        let fixture = try await fixture()
        let key = await dirtyText(fixture.editor)
        await fixture.editor.open(SettingsRoute(section: .styles, tab: "appearance"))
        XCTAssertEqual(fixture.editor.selectedWidget, "omniwm")
        XCTAssertEqual(fixture.editor.pendingTransition, .destination(.init(
            surface: .bar, widget: nil, component: nil, group: "appearance"
        )))
        XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
        await fixture.editor.resolve(.discard)
        XCTAssertNil(fixture.editor.selectedWidget)
        XCTAssertNil(fixture.editor.draft(key))
        XCTAssertNil(fixture.editor.pendingTransition)
    }

    func testCancelingTheEditorLeaveDisarmsTheRequestedMonitorSetup() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        let initial = SettingsRoute(section: .styles, itemID: "omniwm")
        navigation.proceed(to: initial)
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        let key = await dirtyText(fixture.editor)
        navigation.requestMonitorSetupPresentation()
        XCTAssertEqual(fixture.editor.pendingTransition, .leave(SettingsRoute(section: .monitors)))
        XCTAssertEqual(navigation.route, initial)
        XCTAssertFalse(navigation.consumeMonitorSetupPresentationRequest())
        await fixture.editor.resolve(.cancel)
        XCTAssertEqual(navigation.route, initial)
        XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
        XCTAssertFalse(navigation.hasPendingMonitorSetupPresentation)
        navigation.proceed(to: SettingsRoute(section: .monitors))
        XCTAssertFalse(navigation.consumeMonitorSetupPresentationRequest())
    }

    func testCancelingTheEditorLeaveDoesNotInstallAnAppRuleDraft() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        let initial = SettingsRoute(section: .styles, itemID: "omniwm")
        navigation.proceed(to: initial)
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        let key = await dirtyText(fixture.editor)
        let appRule = AppRuleDraft()
        navigation.presentRuleDraft(appRule)
        XCTAssertEqual(fixture.editor.pendingTransition, .leave(SettingsRoute(section: .appRules)))
        XCTAssertEqual(navigation.route, initial)
        XCTAssertNil(navigation.ruleEditorState.requestedDraft)
        await fixture.editor.resolve(.cancel)
        XCTAssertEqual(navigation.route, initial)
        XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
        XCTAssertNil(navigation.ruleEditorState.requestedDraft)
        navigation.proceed(to: SettingsRoute(section: .appRules))
        XCTAssertNil(navigation.ruleEditorState.requestedDraft)
    }

    func testDiscardingTheEditorDraftInstallsTheRequestedAppRuleOnlyAfterNavigation() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        navigation.proceed(to: SettingsRoute(section: .styles))
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        _ = await dirtyText(fixture.editor)
        let appRule = AppRuleDraft()
        navigation.presentRuleDraft(appRule)
        XCTAssertNil(navigation.ruleEditorState.requestedDraft)
        await fixture.editor.resolve(.discard)
        XCTAssertEqual(navigation.route, SettingsRoute(section: .appRules))
        XCTAssertEqual(navigation.ruleEditorState.requestedDraft?.id, appRule.id)
        XCTAssertNil(fixture.editor.pendingTransition)
    }

    func testCancelingAWidgetRouteRestoresTheAcceptedRouteSoSearchCanRequestItAgain() async throws {
        let fixture = try await fixture()
        let navigation = SettingsNavigationModel()
        let original = SettingsRoute(section: .styles, itemID: "omniwm")
        navigation.proceed(to: original)
        fixture.editor.attach(navigation)
        defer { fixture.editor.detach() }
        let key = await dirtyText(fixture.editor)
        let destination = SettingsRoute(section: .styles, itemID: "clock")
        navigation.request(destination)
        await fixture.editor.open(navigation.route)
        XCTAssertEqual(fixture.editor.pendingTransition, .destination(.init(
            surface: .bar, widget: "clock", component: nil, group: nil
        )))
        await fixture.editor.resolve(.cancel)
        XCTAssertEqual(fixture.editor.selectedWidget, "omniwm")
        XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
        XCTAssertEqual(navigation.route, original)
        let previous = navigation.route
        navigation.request(destination)
        if navigation.route != previous { await fixture.editor.open(navigation.route) }
        XCTAssertEqual(fixture.editor.pendingTransition, .destination(.init(
            surface: .bar, widget: "clock", component: nil, group: nil
        )))
    }
}
