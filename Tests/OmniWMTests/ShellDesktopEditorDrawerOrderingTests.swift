// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testDrawerResetDrainsBothContinuousDepthValuesBeforeRemovingTheOverride() async throws {
        let fixture = try await drawerFixture()
        let original = try XCTUnwrap(fixture.editor.drawer("dashboard"))
        let gate = Gate()
        let writer = ShellIslandConfigWriter(shellDirectory: fixture.shell, reloadReady: {})
        fixture.configuration.writer = writer
        let held = Task { try await writer.perform { _ in gate.block() } }
        await gate.wait()
        defer { gate.finish() }
        fixture.editor.setDrawer("dashboard", key: "reach", value: 31.0, continuous: true)
        await waitForSaving(fixture.configuration)
        fixture.editor.setDrawer("dashboard", key: "reach", value: 61.0, continuous: true)
        fixture.editor.resetDrawer("dashboard")
        XCTAssertEqual(fixture.saves.count, 0)
        gate.finish()
        try await held.value
        await fixture.saves.wait(3)
        let drained = await fixture.editor.writes.drain()
        XCTAssertTrue(drained)
        await fixture.editor.reload()
        XCTAssertEqual(fixture.editor.drawer("dashboard"), original)
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testDrawerDepthDrainsBeforeSelectionSurfaceStyleAndDiscreteEdits() async throws {
        for transition in 0 ..< 4 {
            let fixture = try await drawerFixture()
            let added = await fixture.editor.addDrawer(name: "tools", edge: .left, widget: "clock")
            XCTAssertTrue(added)
            let gate = Gate()
            let writer = ShellIslandConfigWriter(shellDirectory: fixture.shell, reloadReady: {})
            fixture.configuration.writer = writer
            let held = Task { try await writer.perform { _ in gate.block() } }
            await gate.wait()
            defer { gate.finish() }
            fixture.editor.setDrawer("tools", key: "reach", value: 43.0, continuous: true)
            await waitForSaving(fixture.configuration)
            let entered = Events()
            var completed = false
            let next = Task {
                entered.record()
                let changed = await drawerTransition(transition, fixture: fixture)
                completed = true
                return changed
            }
            await entered.wait(1)
            XCTAssertFalse(completed)
            XCTAssertEqual(fixture.editor.selectedDrawer, "tools")
            XCTAssertEqual(fixture.editor.surface, .drawers)
            XCTAssertEqual(fixture.editor.selectedStyle, "celestial")
            gate.finish()
            try await held.value
            let changed = await next.value
            XCTAssertTrue(changed)
            let stored = try await fixture.configuration.previewConfig(profile: "celestial")
            XCTAssertEqual(stored.drawers.first { $0.id == "tools" }?.reach, 43)
            XCTAssertEqual(fixture.configuration.config.profile, "default")
        }
    }

    private func drawerTransition(_ transition: Int, fixture: Fixture) async -> Bool {
        switch transition {
        case 0:
            return await fixture.editor.selectDrawer("dashboard")
        case 1:
            return await fixture.editor.selectSurface(.bar)
        case 2:
            return await fixture.editor.selectStyle("lake")
        default:
            return await fixture.editor.addDrawerWidget("weather", to: "tools")
        }
    }
}
