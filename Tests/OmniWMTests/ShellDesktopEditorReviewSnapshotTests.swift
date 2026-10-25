// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import Observation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testContinuousWritesPublishTheSnapshotBeforeTheirPendingValuesDisappear() async throws {
        let fixture = try await fixture()
        fixture.editor.set(59, key: "height", continuous: true)
        let barDrained = await fixture.editor.writes.drain()
        XCTAssertTrue(barDrained)
        XCTAssertEqual(fixture.editor.barSettings.resolved(for: display()).height, 59)
        XCTAssertEqual(fixture.editor.snapshot?.config.barOverride?.settings.height, 59)
        XCTAssertNil(fixture.editor.pending(fixture.editor.barTarget("height"), as: Int?.self) ?? nil)

        fixture.editor.setWidget(.bool(false), widget: "clock", key: "date", continuous: true)
        let widgetDrained = await fixture.editor.writes.drain()
        XCTAssertTrue(widgetDrained)
        XCTAssertEqual(fixture.editor.values(for: "clock")["date"], .bool(false))
        XCTAssertNil(fixture.editor.pending(
            fixture.editor.widgetTarget("clock", key: "date"),
            as: ShellComponentValue.self
        ))

        let monitor = display()
        fixture.editor.setDisplay(monitor, key: "height", value: 53, continuous: true) { $0.height = $1 }
        let displayDrained = await fixture.editor.writes.drain()
        XCTAssertTrue(displayDrained)
        XCTAssertEqual(fixture.editor.monitorSettings(for: monitor).height, 53)
        XCTAssertNil(fixture.editor.pending(fixture.editor.displayTarget(monitor, key: "height"), as: Int.self))
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testASecondShaderSliderKeepsTheFirstDrainedSliderValue() async throws {
        let fixture = try await fixture(style: "matrix")
        let original = try XCTUnwrap(fixture.editor.snapshot?.config.barShader).values
        fixture.editor.setShaderValue(0.61, at: 0)
        let firstDrained = await fixture.editor.writes.drain()
        XCTAssertTrue(firstDrained)
        XCTAssertEqual(fixture.editor.snapshot?.config.barShader?.values[0], Float(0.61))
        fixture.editor.setShaderValue(7, at: 2)
        let secondDrained = await fixture.editor.writes.drain()
        XCTAssertTrue(secondDrained)
        let current = try XCTUnwrap(fixture.editor.snapshot?.config.barShader).values
        XCTAssertEqual(current[0], Float(0.61))
        XCTAssertEqual(current[1], original[1])
        XCTAssertEqual(current[2], 7)
        XCTAssertEqual(current[3], original[3])
        let stored = try await fixture.configuration.previewConfig(profile: "matrix")
        XCTAssertEqual(stored.barShader?.values, current)
    }

    func testDiscreteLaneWriteReloadsTheEditorWithoutAHostedPage() async throws {
        let fixture = try await fixture()
        let name = "launcher"
        XCTAssertNil(fixture.editor.layout?.lane(of: name))
        let changed = observeSnapshot(fixture.editor)
        fixture.editor.add(name, to: .center)
        await changed.wait(1)
        XCTAssertEqual(fixture.editor.layout?.lane(of: name), .center)
        XCTAssertEqual(fixture.editor.selectedWidget, name)
        XCTAssertEqual(fixture.editor.layout?.names(in: .center).last, name)
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testDraftSavePublishesItsStoredValueBeforeReturningAndClearingTheDraft() async throws {
        let fixture = try await fixture()
        let key = await dirtyText(fixture.editor)
        let saved = await fixture.editor.saveDraft(key)
        XCTAssertTrue(saved)
        XCTAssertNil(fixture.editor.draft(key))
        XCTAssertEqual(fixture.editor.values(for: "omniwm")["iconColor"], .string("#123456FF"))
        XCTAssertEqual(fixture.editor.snapshot?.config.profile, "lake")
        XCTAssertEqual(fixture.configuration.config.profile, "default")
    }

    func testUnchangedCleanClockDraftKeepsItsDraftAndRowIdentities() async throws {
        let fixture = try await fixture()
        fixture.editor.beginClocksDraft()
        let key = ShellEditorDraft.Key(widget: "world-clock", option: "zones")
        let original = try XCTUnwrap(fixture.editor.draft(key))
        guard case let .clocks(clocks) = original.value else { return XCTFail("Missing clocks") }
        XCTAssertFalse(clocks.isEmpty)
        await fixture.editor.reload()
        let refreshed = try XCTUnwrap(fixture.editor.draft(key))
        XCTAssertEqual(refreshed, original)
        guard case let .clocks(current) = refreshed.value else { return XCTFail("Missing refreshed clocks") }
        XCTAssertEqual(current.map(\.id), clocks.map(\.id))
        XCTAssertFalse(refreshed.dirty)
    }

    func testCleanTextDraftRefreshesItsBaselineInPlaceWhenTheStoredValueChanges() async throws {
        let fixture = try await fixture()
        fixture.editor.beginTextDraft(widget: "omniwm", key: "iconColor")
        let key = ShellEditorDraft.Key(widget: "omniwm", option: "iconColor")
        let original = try XCTUnwrap(fixture.editor.draft(key))
        try await fixture.configuration.setWidgetValue(
            .string("#AABBCCFF"),
            widget: "omniwm",
            key: "iconColor",
            profile: "lake"
        )
        await fixture.editor.reload()
        let refreshed = try XCTUnwrap(fixture.editor.draft(key))
        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.profile, original.profile)
        XCTAssertEqual(refreshed.original, .text("#AABBCCFF"))
        XCTAssertEqual(refreshed.value, .text("#AABBCCFF"))
        XCTAssertFalse(refreshed.dirty)
        fixture.editor.updateDraft(key, .text("#123456FF"))
        XCTAssertEqual(fixture.editor.draft(key)?.original, .text("#AABBCCFF"))
        XCTAssertTrue(fixture.editor.draft(key)?.dirty == true)
    }

    func testCleanWeatherRefreshUpdatesItsBaselineWithoutReplacingItsIdentity() async throws {
        let fixture = try await fixture()
        await fixture.editor.beginWeatherDraft()
        let original = try XCTUnwrap(fixture.editor.draft(.weather))
        var changed = ShellEditorDraft.Weather(nil)
        changed.city = "Oslo"
        try await fixture.configuration.setWeather(changed.stored)
        await fixture.editor.refreshCleanDrafts()
        let refreshed = try XCTUnwrap(fixture.editor.draft(.weather))
        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.original, .weather(changed))
        XCTAssertEqual(refreshed.value, .weather(changed))
        XCTAssertFalse(refreshed.dirty)
    }

    func testWeatherEditDuringTheRefreshReadKeepsTheNewDirtyValueAndOriginalBaseline() async throws {
        let fixture = try await fixture()
        await fixture.editor.beginWeatherDraft()
        let original = try XCTUnwrap(fixture.editor.draft(.weather))
        var stored = ShellEditorDraft.Weather(nil)
        stored.city = "Oslo"
        try await fixture.configuration.setWeather(stored.stored)
        let gate = Gate()
        let writer = ShellIslandConfigWriter(shellDirectory: fixture.shell, reloadReady: {})
        fixture.configuration.writer = writer
        let held = Task { try await writer.perform { _ in gate.block() } }
        await gate.wait()
        let entered = Events()
        let refresh = Task {
            entered.record()
            await fixture.editor.refreshCleanDrafts()
        }
        await entered.wait(1)
        var edited = stored
        edited.city = "Berlin"
        fixture.editor.updateDraft(.weather, .weather(edited))
        gate.finish()
        try await held.value
        await refresh.value
        let retained = try XCTUnwrap(fixture.editor.draft(.weather))
        XCTAssertEqual(retained.id, original.id)
        XCTAssertEqual(retained.original, original.original)
        XCTAssertEqual(retained.value, .weather(edited))
        XCTAssertTrue(retained.dirty)
    }

    func testCancelledReloadKeepsThePreviousSnapshotWithoutReportingAProblem() async throws {
        let fixture = try await fixture()
        let original = fixture.editor.snapshot
        try await fixture.configuration.set(55, key: "height", profile: "lake")
        let gate = Gate()
        let writer = ShellIslandConfigWriter(shellDirectory: fixture.shell, reloadReady: {})
        fixture.configuration.writer = writer
        let held = Task { try await writer.perform { _ in gate.block() } }
        await gate.wait()
        let entered = Events()
        let reload = Task {
            entered.record()
            await fixture.editor.reload()
        }
        await entered.wait(1)
        reload.cancel()
        gate.finish()
        try await held.value
        await reload.value
        XCTAssertEqual(fixture.editor.snapshot, original)
        XCTAssertNil(fixture.editor.problem)
        await fixture.editor.reload()
        XCTAssertEqual(fixture.editor.barSettings.resolved(for: display()).height, 55)
        XCTAssertNil(fixture.editor.problem)
    }

    private func observeSnapshot(_ editor: ShellDesktopEditor) -> Events {
        let changed = Events()
        withObservationTracking { _ = editor.snapshot } onChange: {
            Task { @MainActor in changed.record() }
        }
        return changed
    }
}
