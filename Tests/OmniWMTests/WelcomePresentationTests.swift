// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import SwiftUI
import XCTest

@MainActor
final class WelcomePresentationTests: XCTestCase {
    func testFirstRunPresentsGetStartedAndRecordsTheFlagAfterPresentation() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }

        fixture.finishLaunchOverlay()

        let window = try XCTUnwrap(fixture.presenter.window)
        XCTAssertEqual(fixture.recorder.flagsAtPresentation, [false])
        XCTAssertTrue(fixture.runtimeState.welcomePresented)
        XCTAssertTrue(fixture.reloadedRuntimeState().welcomePresented)
        XCTAssertEqual(try fixture.view().reason, .firstRun)
        XCTAssertEqual(WelcomeReason.firstRun.primaryActionTitle, "Get Started")
        XCTAssertEqual(window.title, "Welcome to OmniWM")
        XCTAssertEqual(window.styleMask, [.titled, .closable, .resizable])
        XCTAssertEqual(window.collectionBehavior, [.moveToActiveSpace])
        XCTAssertEqual(window.contentMinSize, WelcomeView.minimumSize)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, WelcomeView.minimumSize)
        XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask)
    }

    func testLaterRunPresentsNothingAndSchedulesTheDisplayGuideEvaluation() {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.runtimeState.welcomePresented = true

        fixture.finishLaunchOverlay()

        XCTAssertNil(fixture.presenter.window)
        XCTAssertTrue(fixture.recorder.flagsAtPresentation.isEmpty)
        XCTAssertNotNil(fixture.delegate.monitorSetupEvaluationTask)
    }

    func testShowingTheWelcomeCancelsAQueuedEvaluationAndTheEvaluatorLeavesTheGuideAlone() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.runtimeState.welcomePresented = true
        fixture.delegate.startMonitorSetupPresentationObservation()
        fixture.finishLaunchOverlay()
        let queued = try XCTUnwrap(fixture.delegate.monitorSetupEvaluationTask)

        fixture.reopen()

        XCTAssertTrue(queued.isCancelled)
        XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask)
        fixture.evaluateDisplayGuide()
        XCTAssertEqual(fixture.settings.monitorSetupStatus, .notPresented)
        XCTAssertNotNil(fixture.delegate.monitorSetupScreenObserver)
        XCTAssertNotNil(fixture.presenter.window)
    }

    func testScreenChangeWhileTheWelcomeIsVisibleQueuesAndPresentsNoGuide() {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.delegate.startMonitorSetupPresentationObservation()
        fixture.finishLaunchOverlay()

        fixture.delegate.scheduleMonitorSetupEvaluation()
        fixture.evaluateDisplayGuide()

        XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask)
        XCTAssertEqual(fixture.settings.monitorSetupStatus, .notPresented)
        XCTAssertNotNil(fixture.delegate.monitorSetupScreenObserver)
    }

    func testClosingTheFirstRunWelcomeSchedulesTheEvaluation() throws {
        for close in [Fixture.Close.primaryButton, .escape, .closeButton] {
            let fixture = Fixture()
            defer { fixture.cleanup() }
            fixture.finishLaunchOverlay()

            try fixture.close(close)

            XCTAssertNil(fixture.presenter.window, "\(close)")
            XCTAssertNotNil(fixture.delegate.monitorSetupEvaluationTask, "\(close)")
        }
    }

    func testClosingAReopenedWelcomeNeverSchedulesTheEvaluation() throws {
        for close in [Fixture.Close.primaryButton, .escape, .closeButton] {
            let fixture = Fixture()
            defer { fixture.cleanup() }
            fixture.runtimeState.welcomePresented = true
            fixture.finishLaunchOverlay()

            fixture.reopen()
            try fixture.close(close)

            XCTAssertNil(fixture.presenter.window, "\(close)")
            XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask, "\(close)")
        }
    }

    func testReopenedWelcomeAfterASettingsDepartureNeverSchedulesTheEvaluation() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.finishLaunchOverlay()
        try fixture.view().onOpenSettings(.styles)

        fixture.reopen()
        try fixture.close(.primaryButton)

        XCTAssertEqual(fixture.recorder.routes, [.init(section: .styles, welcomeVisible: false)])
        XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask)
    }

    func testSettingsDepartureHoldsTheGuideForTheRestOfTheLaunch() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.delegate.startMonitorSetupPresentationObservation()
        fixture.finishLaunchOverlay()

        try fixture.view().onOpenSettings(.hotkeys)

        XCTAssertNil(fixture.presenter.window)
        XCTAssertEqual(fixture.recorder.routes, [.init(section: .hotkeys, welcomeVisible: false)])
        XCTAssertNil(fixture.delegate.monitorSetupScreenObserver)
        XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask)
        XCTAssertEqual(fixture.settings.monitorSetupStatus, .notPresented)
        XCTAssertEqual(fixture.reloadedRuntimeState().monitorSetupStatus, .notPresented)
    }

    func testAScreenChangeQueuedBeforeASettingsDepartureNeverRestartsTheGuide() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.finishLaunchOverlay()

        try fixture.view().onOpenSettings(.styles)
        fixture.delegate.scheduleMonitorSetupEvaluation()

        XCTAssertNil(fixture.delegate.monitorSetupScreenObserver)
        XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask)
        XCTAssertEqual(fixture.settings.monitorSetupStatus, .notPresented)
    }

    func testMenuReopenShowsDoneWithoutChangingTheFlag() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = StatusMenuModel(settings: fixture.settings, controller: fixture.controller)
        model.openWelcomeAction = { settings, controller in
            XCTAssertIdentical(settings, fixture.settings)
            XCTAssertIdentical(controller, fixture.controller)
            fixture.reopen()
        }

        model.openWelcome()

        XCTAssertEqual(try fixture.view().reason, .reopened)
        XCTAssertEqual(WelcomeReason.reopened.primaryActionTitle, "Done")
        XCTAssertFalse(fixture.runtimeState.welcomePresented)
        try fixture.close(.primaryButton)
        XCTAssertFalse(fixture.runtimeState.welcomePresented)
        XCTAssertNil(fixture.delegate.monitorSetupEvaluationTask)
    }

    func testMenuClickWhileTheFirstRunWelcomeIsOpenKeepsGetStartedAndItsGuideBehavior() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.finishLaunchOverlay()
        let window = try XCTUnwrap(fixture.presenter.window)

        fixture.reopen()

        XCTAssertIdentical(fixture.presenter.window, window)
        XCTAssertEqual(fixture.recorder.flagsAtPresentation, [false, true])
        XCTAssertEqual(try fixture.view().reason, .firstRun)
        try fixture.close(.primaryButton)
        XCTAssertNotNil(fixture.delegate.monitorSetupEvaluationTask)
    }

    func testEachControlClosesTheWelcomeAndRoutesToItsSettingsSection() throws {
        XCTAssertEqual(WelcomeFeature.allCases.map(\.destination), [nil, .hotkeys, .quakeTerminal, .network])
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let sections: [SettingsSection] = [.styles, .hotkeys, .quakeTerminal, .network]

        for section in sections {
            fixture.reopen()
            try fixture.view().onOpenSettings(section)
        }

        XCTAssertEqual(fixture.recorder.routes, sections.map { Fixture.Route(section: $0, welcomeVisible: false) })
    }

    func testBoundShortcutsShowTheirDisplayStringAndTryItSentence() throws {
        let bindings = HotkeyBindingRegistry.defaults()
        let menu = try displayString("openMenuAnywhere", in: bindings)
        let palette = try displayString("openCommandPalette", in: bindings)
        let quake = try displayString("toggleQuakeTerminal", in: bindings)

        XCTAssertEqual(
            content(.barMenus, bindings),
            WelcomeFeatureContent(
                shortcut: .assigned(menu),
                detail: "The Apple button on the bar opens the Apple menu, and the app name opens that app's menus. Menu Anywhere opens them at the pointer; try it in another app."
            )
        )
        XCTAssertEqual(
            content(.commandPalette, bindings),
            WelcomeFeatureContent(
                shortcut: .assigned(palette),
                detail: "Search windows, apps, files, the clipboard, app menus and OmniWM commands. Press \(palette) to try it now."
            )
        )
        XCTAssertEqual(
            content(.quakeTerminal, bindings),
            WelcomeFeatureContent(
                shortcut: .assigned(quake),
                detail: "A terminal that drops down over any app, on any Space. Choose Ghostty, Kitty or foot. Press \(quake) to try it now."
            )
        )
        XCTAssertEqual(
            content(.widgetPermissions, bindings),
            WelcomeFeatureContent(
                shortcut: nil,
                detail: "Widgets ask the first time they contact a server, and programs ask before they run. Weather and Lyrics have their own switches."
            )
        )
    }

    func testUnassignedOrMissingShortcutsShowUnassignedWithoutTryIt() throws {
        let unassigned = HotkeySettingsDisplayModel.displayString(for: HotkeyTrigger.unassigned)
        let cleared = HotkeyBindingRegistry.defaults().map { binding in
            ["openMenuAnywhere", "openCommandPalette", "toggleQuakeTerminal"].contains(binding.id)
                ? HotkeyBinding(id: binding.id, command: binding.command, trigger: .unassigned)
                : binding
        }

        for bindings in [cleared, []] {
            XCTAssertEqual(
                content(.barMenus, bindings),
                WelcomeFeatureContent(
                    shortcut: .unassigned(unassigned),
                    detail: "The Apple button on the bar opens the Apple menu, and the app name opens that app's menus. Menu Anywhere opens them at the pointer."
                )
            )
            XCTAssertEqual(
                content(.commandPalette, bindings),
                WelcomeFeatureContent(
                    shortcut: .unassigned(unassigned),
                    detail: "Search windows, apps, files, the clipboard, app menus and OmniWM commands."
                )
            )
            XCTAssertEqual(
                content(.quakeTerminal, bindings),
                WelcomeFeatureContent(
                    shortcut: .unassigned(unassigned),
                    detail: "A terminal that drops down over any app, on any Space. Choose Ghostty, Kitty or foot."
                )
            )
        }
    }

    func testDisabledQuakeKeepsItsBindingAndPointsToItsSettings() throws {
        let bindings = HotkeyBindingRegistry.defaults()
        let quake = try displayString("toggleQuakeTerminal", in: bindings)

        XCTAssertEqual(
            WelcomeFeature.quakeTerminal.content(bindings: bindings, quakeEnabled: false),
            WelcomeFeatureContent(
                shortcut: .assigned(quake),
                detail: "A terminal that drops down over any app, on any Space. Choose Ghostty, Kitty or foot. Turn it on in Quake Terminal Settings."
            )
        )
    }

    func testContentFitsTheMinimumWindowSize() {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let bindings = HotkeyBindingRegistry.defaults()

        for (hotkeys, quakeEnabled) in [(bindings, true), (bindings, false), ([], true), ([], false)] {
            fixture.settings.hotkeyBindings = hotkeys
            fixture.settings.quakeTerminal.enabled = quakeEnabled
            for reason in [WelcomeReason.firstRun, .reopened] {
                let view = WelcomeView(settings: fixture.settings, reason: reason, onOpenSettings: { _ in }, onDone: {})
                let fitted = NSHostingController(rootView: view.fixedSize(horizontal: false, vertical: true))
                    .sizeThatFits(in: CGSize(width: WelcomeView.minimumSize.width, height: 10_000))
                XCTAssertEqual(fitted, WelcomeView.minimumSize, "\(hotkeys.count) bindings, Quake \(quakeEnabled)")
            }
        }
    }

    private func content(_ feature: WelcomeFeature, _ bindings: [HotkeyBinding]) -> WelcomeFeatureContent {
        feature.content(bindings: bindings, quakeEnabled: true)
    }

    private func displayString(_ id: String, in bindings: [HotkeyBinding]) throws -> String {
        let binding = try XCTUnwrap(bindings.first { $0.id == id })
        XCTAssertFalse(binding.binding.isUnassigned, id)
        return HotkeySettingsDisplayModel.displayString(for: binding.binding)
    }
}

@MainActor
private final class Fixture {
    enum Close {
        case primaryButton
        case escape
        case closeButton
    }

    struct Route: Equatable {
        let section: SettingsSection
        let welcomeVisible: Bool
    }

    final class Recorder {
        var flagsAtPresentation: [Bool] = []
        var routes: [Route] = []
    }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("OmniWMWelcome-\(UUID().uuidString)", isDirectory: true)
    let recorder = Recorder()
    let runtimeState: RuntimeStateStore
    let settings: SettingsStore
    let controller: WMController
    let presenter: HostedWindowPresenter
    let delegate: AppDelegate

    init() {
        let recorder = recorder
        let runtimeState = RuntimeStateStore(directory: root.appendingPathComponent("state"), deferSaves: false)
        let presenter = HostedWindowPresenter(ownedWindowRegistry: OwnedWindowRegistry()) { _ in
            recorder.flagsAtPresentation.append(runtimeState.welcomePresented)
        }
        self.runtimeState = runtimeState
        self.presenter = presenter
        settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config"),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: runtimeState,
            autosaveEnabled: false
        )
        controller = WMController(
            settings: settings,
            clipboardHistoryDirectory: root.appendingPathComponent("clipboard"),
            diagnosticsDirectory: root.appendingPathComponent("diagnostics"),
            ownedWindowRegistry: OwnedWindowRegistry()
        )
        delegate = AppDelegate()
        delegate.welcomeWindowController = WelcomeWindowController(presenter: presenter) { _, _, section in
            recorder.routes.append(Route(section: section, welcomeVisible: presenter.window != nil))
        }
    }

    func finishLaunchOverlay() {
        delegate.startMonitorSetupPresentationObservation()
        delegate.launchOverlayDidFinish(runtimeState: runtimeState, controller: controller)
    }

    func reopen() {
        delegate.presentWelcome(settings: settings, controller: controller, reason: .reopened)
    }

    func view() throws -> WelcomeView {
        try XCTUnwrap((presenter.window?.contentViewController as? NSHostingController<WelcomeView>)?.rootView)
    }

    func close(_ close: Close) throws {
        let window = try XCTUnwrap(presenter.window)
        switch close {
        case .primaryButton:
            try view().onDone()
        case .escape:
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
            ))
            XCTAssertTrue(window.performKeyEquivalent(with: event))
        case .closeButton:
            try XCTUnwrap(window.standardWindowButton(.closeButton)).performClick(nil)
        }
    }

    func evaluateDisplayGuide() {
        let bootstrap = AppBootstrapState()
        bootstrap.settings = settings
        bootstrap.controller = controller
        let previous = AppDelegate.sharedBootstrap
        AppDelegate.sharedBootstrap = bootstrap
        defer { AppDelegate.sharedBootstrap = previous }
        let displays = (0 ..< 2).map { index in
            let frame = CGRect(x: CGFloat(index) * 1_000, y: 0, width: 1_000, height: 900)
            return Monitor(
                id: .init(displayId: CGDirectDisplayID(index + 1)),
                displayId: CGDirectDisplayID(index + 1),
                frame: frame,
                visibleFrame: frame,
                hasNotch: false,
                name: "Display \(index + 1)"
            )
        }
        XCTAssertTrue(MonitorSetupPresentationPolicy.shouldAutomaticallyPresent(
            status: settings.monitorSetupStatus, monitors: displays, launchOverlayFinished: true
        ))
        delegate.evaluateMonitorSetupPresentation(monitors: displays)
    }

    func reloadedRuntimeState() -> RuntimeStateStore {
        RuntimeStateStore(directory: root.appendingPathComponent("state"), deferSaves: false)
    }

    func cleanup() {
        presenter.close()
        delegate.stopMonitorSetupPresentationObservation()
        try? FileManager.default.removeItem(at: root)
    }
}
