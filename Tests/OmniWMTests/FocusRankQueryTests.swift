// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class FocusRankQueryTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let tokens: [WindowToken]
        let router: IPCQueryRouter

        func focus(_ index: Int) {
            _ = controller.workspaceManager.setManagedFocus(tokens[index], in: workspaceId)
        }

        func windows(
            selectors: IPCQuerySelectors = IPCQuerySelectors(),
            fields: [String] = ["window-id", "focus-rank"],
            sort: IPCQuerySort? = nil
        ) -> [IPCWindowQuerySnapshot] {
            router.windowsResult(IPCQueryRequest(name: .windows, selectors: selectors, fields: fields, sort: sort))
                .windows
        }
    }

    private func makeFixture(windowCount: Int = 3) throws -> Fixture {
        let controller = WindowAdmissionTestSupport.controller(prefix: "FocusRankQueryTests")
        let frame = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let monitor = Monitor(
            id: .init(displayId: 1),
            displayId: 1,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Focus Rank"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let tokens = (1 ... windowCount).map { WindowToken(pid: 880_200, windowId: 880_200 + $0) }
        for token in tokens {
            _ = controller.workspaceManager.addWindow(
                WindowAdmissionTestSupport.axRef(for: token),
                pid: token.pid,
                windowId: token.windowId,
                to: workspaceId
            )
        }
        let router = IPCQueryRouter(controller: controller, appVersion: nil, sessionToken: "focus-rank-tests")
        router.windowOrderedInProvider = { _ in true }
        return Fixture(controller: controller, workspaceId: workspaceId, tokens: tokens, router: router)
    }

    func testFocusRankCountsFromMostRecentlyFocusedAndOmitsNeverFocusedWindows() throws {
        let fixture = try makeFixture()
        fixture.focus(0)
        fixture.focus(2)

        let ranks = Dictionary(uniqueKeysWithValues: fixture.windows().map { ($0.windowId, $0.focusRank) })
        XCTAssertEqual(ranks[880_203], 0)
        XCTAssertEqual(ranks[880_201], 1)
        XCTAssertEqual(ranks[880_202], .some(nil))

        let encoded = try IPCWire.makeEncoder().encode(fixture.windows(fields: ["focus-rank"]))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self).components(separatedBy: "focusRank").count - 1, 2)
    }

    func testFocusRankIsOmittedUnlessRequestedAndListedInCatalog() throws {
        let fixture = try makeFixture()
        fixture.focus(0)
        XCTAssertNil(fixture.windows(fields: ["window-id"]).first?.focusRank)
        XCTAssertTrue(IPCAutomationManifest.windowFieldCatalog.contains("focus-rank"))
    }

    func testFocusRankStaysGlobalWhenSelectorsNarrowTheResult() throws {
        let fixture = try makeFixture()
        fixture.focus(0)
        fixture.focus(1)

        let opaqueId = try XCTUnwrap(fixture.windows(fields: ["id", "window-id"]).first { $0.windowId == 880_201 }?.id)
        let only = fixture.windows(selectors: IPCQuerySelectors(window: opaqueId))
        XCTAssertEqual(only.map(\.focusRank), [1])
    }

    func testSortMRUOrdersRankedWindowsFirstThenUnrankedInLayoutOrder() throws {
        let fixture = try makeFixture(windowCount: 4)
        let layoutOrder = fixture.windows().map(\.windowId)
        fixture.focus(1)
        fixture.focus(3)

        let sorted = fixture.windows(sort: .mru).map(\.windowId)
        let unranked = layoutOrder.filter { $0 != 880_202 && $0 != 880_204 }
        XCTAssertEqual(sorted, [880_204, 880_202] + unranked)
    }

    func testRefocusMovesWindowToFrontAndClosedWindowsLeaveTheHistory() throws {
        let fixture = try makeFixture()
        fixture.focus(0)
        fixture.focus(1)
        fixture.focus(2)
        fixture.focus(0)
        XCTAssertEqual(fixture.windows(sort: .mru).map(\.windowId), [880_201, 880_203, 880_202])

        _ = fixture.controller.workspaceManager.removeWindow(pid: 880_200, windowId: 880_203)
        let ranks = fixture.windows(sort: .mru).map { [$0.windowId, $0.focusRank] }
        XCTAssertEqual(ranks, [[880_201, 0], [880_202, 1]])
    }

    func testFocusRankCoversMoreThanThirtyTwoWindows() throws {
        let fixture = try makeFixture(windowCount: 34)
        for index in 0 ..< 34 { fixture.focus(index) }
        let ranks = Dictionary(uniqueKeysWithValues: fixture.windows().map { ($0.windowId, $0.focusRank) })
        XCTAssertEqual(ranks[880_201], 33)
    }

    func testNativeFocusOfManagedWindowOutsideOmniWMUpdatesRankButUnmanagedDoesNot() throws {
        let fixture = try makeFixture()
        fixture.focus(0)
        fixture.focus(1)
        _ = fixture.controller.workspaceManager.recordExternalFocus(pid: 880_200, windowId: 880_201)
        _ = fixture.controller.workspaceManager.recordExternalFocus(pid: 880_200, windowId: 999_999)
        XCTAssertEqual(fixture.windows(sort: .mru).map(\.windowId), [880_201, 880_202, 880_203])
    }
}
