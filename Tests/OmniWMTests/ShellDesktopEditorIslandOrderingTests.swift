// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testIslandRemovalDrainsBothContinuousValuesBeforeRemovingTheComponent() async throws {
        let fixture = try await islandFixture()
        let gate = Gate()
        let writer = ShellIslandConfigWriter(shellDirectory: fixture.shell, reloadReady: {})
        fixture.configuration.writer = writer
        let held = Task { try await writer.perform { _ in gate.block() } }
        await gate.wait()
        defer { gate.finish() }
        fixture.editor.setComponentOption("agenda", key: "leadMinutes", value: .number(10), continuous: true)
        await waitForSaving(fixture.configuration)
        fixture.editor.setComponentOption("agenda", key: "leadMinutes", value: .number(20), continuous: true)
        fixture.editor.removeComponent("agenda")
        XCTAssertEqual(
            fixture.editor.pending(
                fixture.editor.componentTarget("agenda", key: "leadMinutes"),
                as: ShellComponentValue.self
            ),
            .number(20)
        )
        XCTAssertEqual(fixture.saves.count, 0)
        gate.finish()
        try await held.value
        await fixture.saves.wait(3)
        let drained = await fixture.editor.writes.drain()
        XCTAssertTrue(drained)
        await fixture.editor.reload()
        XCTAssertTrue(fixture.editor.writes.failures.isEmpty)
        XCTAssertNil(fixture.editor.problem)
        XCTAssertNil(fixture.editor.component("agenda"))
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testIslandComponentSliderDrainsBeforeADiscreteEditToTheSameOption() async throws {
        let fixture = try await islandFixture()
        let gate = Gate()
        let writer = ShellIslandConfigWriter(shellDirectory: fixture.shell, reloadReady: {})
        fixture.configuration.writer = writer
        let held = Task { try await writer.perform { _ in gate.block() } }
        await gate.wait()
        defer { gate.finish() }
        fixture.editor.setComponentOption("agenda", key: "leadMinutes", value: .number(10), continuous: true)
        await waitForSaving(fixture.configuration)
        fixture.editor.setComponentOption("agenda", key: "leadMinutes", value: .number(20), continuous: true)
        fixture.editor.setComponentOption("agenda", key: "leadMinutes", value: .number(30))
        XCTAssertEqual(fixture.saves.count, 0)
        gate.finish()
        try await held.value
        await fixture.saves.wait(3)
        let drained = await fixture.editor.writes.drain()
        XCTAssertTrue(drained)
        await fixture.editor.reload()
        XCTAssertEqual(fixture.editor.component("agenda")?.options["leadMinutes"], .number(30))
    }

    func testPendingIslandWritesDrainBeforeEverySelectionContextChanges() async throws {
        let transitions: [ShellDesktopEditor.Transition] = [
            .surface(.bar), .component("tokyo"), .widget("clock"),
            .destination(.init(surface: .bar, widget: "clock", component: "london", group: nil))
        ]
        for transition in transitions {
            let fixture = try await islandFixture()
            _ = await fixture.editor.selectComponent("london")
            let original = fixture.editor.destination
            let held = HeldWrite()
            fixture.editor.writes.submit(30, for: fixture.editor.islandRootTarget("radius"), write: held.write)
            await held.entered.wait(1)
            let entered = Events()
            var completed = false
            let selection = Task {
                entered.record()
                let changed = await fixture.editor.request(transition)
                completed = true
                return changed
            }
            await entered.wait(1)
            XCTAssertFalse(completed, "\(transition)")
            XCTAssertEqual(fixture.editor.destination, original, "\(transition)")
            held.finish()
            let changed = await selection.value
            XCTAssertTrue(changed, "\(transition)")
            XCTAssertNotEqual(fixture.editor.destination, original, "\(transition)")
        }
    }

    func testFailureDuringIslandWriteDrainBlocksEverySelectionContext() async throws {
        let transitions: [ShellDesktopEditor.Transition] = [
            .surface(.bar), .component("tokyo"), .widget("clock"),
            .destination(.init(surface: .bar, widget: "clock", component: "london", group: nil))
        ]
        for transition in transitions {
            let fixture = try await islandFixture()
            _ = await fixture.editor.selectComponent("london")
            let original = fixture.editor.destination
            let target = fixture.editor.islandRootTarget("radius")
            let held = HeldWrite()
            fixture.editor.writes.submit(30, for: target, write: held.write)
            await held.entered.wait(1)
            let entered = Events()
            let selection = Task {
                entered.record()
                return await fixture.editor.request(transition)
            }
            await entered.wait(1)
            held.finish(failing: true)
            let changed = await selection.value
            XCTAssertFalse(changed, "\(transition)")
            XCTAssertEqual(fixture.editor.destination, original, "\(transition)")
            XCTAssertNotNil(fixture.editor.problem)
            XCTAssertNotNil(fixture.editor.writes.failure(for: target))
        }
    }

    func testFailedIslandWriteBlocksRemovalUntilDiscarded() async throws {
        let fixture = try await islandFixture()
        let target = fixture.editor.islandRootTarget("radius")
        let held = HeldWrite()
        fixture.editor.writes.submit(30, for: target, write: held.write)
        await held.entered.wait(1)
        held.finish(failing: true)
        let drained = await fixture.editor.writes.drain()
        XCTAssertFalse(drained)
        let before = try document(fixture)
        let outcome = Events()
        fixture.configuration.onSave = { _ in outcome.record() }
        observeProblem(fixture.editor, changed: outcome)
        fixture.editor.removeComponent("london")
        await outcome.wait(1)
        XCTAssertEqual(try document(fixture), before)
        XCTAssertNotNil(fixture.editor.component("london"))
        XCTAssertNotNil(fixture.editor.problem)
        XCTAssertNotNil(fixture.editor.writes.failure(for: target))
        fixture.editor.writes.discard(target)
        let next = outcome.count + 1
        fixture.editor.removeComponent("london")
        await outcome.wait(next)
        await fixture.editor.reload()
        XCTAssertNil(fixture.editor.component("london"))
        XCTAssertTrue(fixture.editor.writes.failures.isEmpty)
    }

    func testRemovingAComponentDropsOnlyItsDraftsAfterTheWriteSucceeds() async throws {
        let fixture = try await islandFixture()
        fixture.editor.beginComponentTextDraft("london", key: "label")
        fixture.editor.beginComponentTextDraft("tokyo", key: "label")
        let removed = ShellEditorDraft.Key.component("london", option: "label")
        let retained = ShellEditorDraft.Key.component("tokyo", option: "label")
        fixture.editor.updateDraft(removed, .text("Home"))
        let other = fixture.editor.draft(retained)
        await islandEdit(fixture) { fixture.editor.removeComponent("london") }
        XCTAssertNil(fixture.editor.draft(removed))
        XCTAssertEqual(fixture.editor.draft(retained), other)
        XCTAssertNil(fixture.editor.component("london"))
    }
}
