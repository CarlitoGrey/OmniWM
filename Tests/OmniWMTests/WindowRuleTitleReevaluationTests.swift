// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class WindowRuleTitleReevaluationTests: XCTestCase {
    func testBundleOnlyEffectsDoNotRequireTitleReevaluation() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])
        engine.rebuild(rules: [
            AppRule(bundleId: "com.test.editor", minWidth: 400, minHeight: 300),
            AppRule(bundleId: "com.test.viewer", layout: .float),
            AppRule(bundleId: "com.test.browser", assignToWorkspace: "2")
        ])

        for bundleId in ["com.test.editor", "com.test.viewer", "com.test.browser", "com.test.other"] {
            XCTAssertFalse(engine.needsTitleReevaluation(for: bundleId), bundleId)
        }
        XCTAssertTrue(engine.needsWindowReevaluation)
    }

    func testBuiltInDynamicRulesRetainTheirAppScopes() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])

        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.valvesoftware.steam.helper"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "COM.VALVESOFTWARE.STEAM.HELPER"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.apple.finder"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "COM.APPLE.FINDER"))
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.valvesoftware.steam"))
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.other"))
    }

    func testEveryAdvancedMatcherKeepsItsMatchingBundleOpen() {
        let cases: [(String, AppRule)] = [
            ("appName", AppRule(bundleId: "com.test.editor", appNameSubstring: "Editor", layout: .float)),
            ("titleSubstring", AppRule(bundleId: "com.test.editor", titleSubstring: "Settings", layout: .float)),
            ("titleRegex", AppRule(bundleId: "com.test.editor", titleRegex: "^Settings$", layout: .float)),
            ("axRole", AppRule(bundleId: "com.test.editor", axRole: kAXWindowRole as String, layout: .float)),
            ("axSubrole", AppRule(bundleId: "com.test.editor", axSubrole: kAXDialogSubrole as String, layout: .float))
        ]

        for (label, rule) in cases {
            let engine = WindowRuleEngine(inputMethodBundleIds: [])
            engine.rebuild(rules: [rule])

            XCTAssertTrue(engine.needsTitleReevaluation(for: "COM.TEST.EDITOR", appName: "My EDITOR"), label)
            XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.other", appName: "My EDITOR"), label)
            XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.other"), label)
        }
    }

    func testKnownAppNameMismatchClosesCombinedScope() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])
        engine.rebuild(rules: [AppRule(
            bundleId: "com.test.editor",
            appNameSubstring: "Editor",
            titleSubstring: "Settings",
            layout: .float
        )])

        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.editor", appName: "My EDITOR"))
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.editor", appName: "Other App"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.editor"))
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.other"))
    }

    func testAppNameOnlyRuleUsesKnownNameAndConservativelyHandlesMissingName() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])
        engine.rebuild(rules: [AppRule(bundleId: "", appNameSubstring: "VMD", layout: .float)])

        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.viewer", appName: "VMD Viewer"))
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.viewer", appName: "Other Viewer"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.viewer"))
    }

    func testGlobalTitleRulesKeepEveryAppOpen() {
        for rule in [
            AppRule(bundleId: "", titleSubstring: "Settings", layout: .float),
            AppRule(bundleId: "", titleRegex: "^Settings$", layout: .float)
        ] {
            let engine = WindowRuleEngine(inputMethodBundleIds: [])
            engine.rebuild(rules: [rule])

            XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.editor", appName: "Editor"))
            XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.other"))
        }
    }

    func testPictureInPictureTitleDemandSurvivesWithoutUserRules() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])
        engine.rebuild(rules: [])

        for bundleId in [
            "org.mozilla.firefox",
            "app.zen-browser.zen",
            "net.librewolf.librewolf",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac"
        ] {
            XCTAssertTrue(engine.needsTitleReevaluation(for: bundleId), bundleId)
            XCTAssertTrue(engine.needsTitleReevaluation(for: bundleId.uppercased()), bundleId)
        }
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.apple.Safari"))
        XCTAssertFalse(engine.needsTitleReevaluation(for: "org.example.browser"))
    }

    func testInvalidIneffectiveAndUnanchoredRulesDoNotOpenGate() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])
        let invalid = AppRule(bundleId: "com.test.editor", titleRegex: "[", layout: .float)
        engine.rebuild(rules: [
            invalid,
            AppRule(bundleId: "com.test.editor", titleSubstring: "Settings"),
            AppRule(bundleId: "", axRole: kAXWindowRole as String, layout: .float)
        ])

        XCTAssertNotNil(engine.invalidRegexMessagesByRuleId[invalid.id])
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.editor"))
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.other"))
    }

    func testUnknownBundleConservativelyKeepsGateOpen() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])

        XCTAssertTrue(engine.needsTitleReevaluation(for: nil))
        XCTAssertTrue(engine.needsTitleReevaluation(for: nil, appName: "Editor"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: ""))
    }

    func testRebuildClearsObsoleteAppScopes() {
        let engine = WindowRuleEngine(inputMethodBundleIds: [])
        let rule = AppRule(bundleId: "com.test.editor", titleSubstring: "Settings", layout: .float)
        engine.rebuild(rules: [rule])
        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.editor"))

        engine.rebuild(rules: [AppRule(bundleId: "com.test.viewer", titleRegex: "Settings", layout: .float)])
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.editor"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.test.viewer"))

        engine.rebuild(rules: [])
        XCTAssertFalse(engine.needsTitleReevaluation(for: "com.test.viewer"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "com.apple.finder"))
        XCTAssertTrue(engine.needsTitleReevaluation(for: "org.mozilla.firefox"))
        XCTAssertTrue(engine.needsWindowReevaluation)
    }
}
