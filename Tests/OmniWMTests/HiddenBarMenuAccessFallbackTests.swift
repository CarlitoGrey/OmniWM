// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class HiddenBarMenuAccessFallbackTests: XCTestCase {
    private struct Case {
        let first: [ResolvedMenuBarItem]?
        let covered: Bool
        let clicking: Bool
        let reveals: Bool
    }

    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAMenuBarOurBarHidesIsRevealedOnlyForAnItemThatNeedsIt() async {
        let key = MenuBarItemKey(bundleID: "app", ordinal: 0)
        let item = ResolvedMenuBarItem(
            key: key,
            pid: 42,
            bounds: CGRect(x: 1100, y: 0, width: 40, height: 24),
            semanticIdentity: nil
        )
        let cases: [String: Case] = [
            "resolved under our bar": Case(first: [item], covered: true, clicking: true, reveals: false),
            "read as a menu while uncovered": Case(first: [item], covered: false, clicking: false, reveals: false),
            "nothing resolved": Case(first: nil, covered: true, clicking: false, reveals: true),
            "no items while hidden": Case(first: [], covered: true, clicking: true, reveals: true),
            "clicked while uncovered": Case(first: [item], covered: false, clicking: true, reveals: true)
        ]
        for (name, testCase) in cases {
            var accesses: [Bool] = []
            var resolves = 0
            let hiddenBar = HiddenBarController(
                settings: settings(),
                setMenuAccess: { accesses.append($0)
                    return true
                },
                menuBarHiddenByBar: { true },
                coversPoint: { _ in testCase.covered },
                resolveItems: { _, _ in
                    resolves += 1
                    return resolves == 1 ? testCase.first : [item]
                }
            )
            hiddenBar.startReconcealForTests(revealedBundleIDs: ["app"])
            XCTAssertEqual(accesses, [], name)

            let items = await hiddenBar.resolveRevealedItemsForTests(
                "app",
                pid: 42,
                clicking: testCase.clicking ? key : nil
            )

            XCTAssertEqual(items?.map(\.key), [key], name)
            XCTAssertEqual(accesses, testCase.reveals ? [true] : [], name)
            XCTAssertEqual(resolves, testCase.reveals ? 2 : 1, name)
            hiddenBar.cleanup()
            XCTAssertEqual(accesses, testCase.reveals ? [true, false] : [], name)
        }
    }

    func testACoveredItemIsPressedAndNeverClicked() {
        let covered = HiddenBarClickForwarder.activationCandidate(pid: 1, covered: true, electron: false)
        XCTAssertTrue(covered.useAXPress)
        guard case .unavailable = MenuBarItemLocator.fallback(for: covered, frame: .zero) else {
            return XCTFail("a covered item must not be clicked when its press fails")
        }
        let uncovered = HiddenBarClickForwarder.activationCandidate(pid: 1, covered: false, electron: false)
        XCTAssertFalse(uncovered.useAXPress)
        guard case .clickFrame = MenuBarItemLocator.fallback(for: uncovered, frame: .zero) else {
            return XCTFail("an uncovered item is still clicked")
        }
        XCTAssertTrue(HiddenBarClickForwarder.activationCandidate(pid: 1, covered: false, electron: true).useAXPress)
    }

    private func settings() -> SettingsStore {
        SettingsStore(
            persistence: SettingsFilePersistence(directory: directory, startWatching: false, deferSaves: false),
            runtimeState: RuntimeStateStore(directory: directory, deferSaves: false),
            autosaveEnabled: false
        )
    }
}
