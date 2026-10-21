// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ShellNotificationDiagnosticsTests: XCTestCase {
    private actor Loader {
        var snapshot: ShellNotificationsData

        init(_ snapshot: ShellNotificationsData) {
            self.snapshot = snapshot
        }

        func read(_: URL) -> ShellNotificationsData {
            snapshot
        }

        func replace(_ snapshot: ShellNotificationsData) {
            self.snapshot = snapshot
        }
    }

    private let bundle = "com.example.DiagnosticsFixture"

    private func controller(
        _ loader: Loader,
        outcome: ShellNotificationActionOutcome = .dispatched
    ) -> ShellNotificationsController {
        ShellNotificationsController(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("uncreated/db"),
            load: { await loader.read($0) }, perform: { _ in outcome }
        )
    }

    func testUnchangedManualRefreshAndCoalescedReadAreRecorded() async throws {
        ShellNotificationTrace.shared.beginCapture()
        defer { ShellNotificationTrace.shared.endCapture() }
        let loader = Loader(.init(state: "empty"))
        let controller = controller(loader)
        defer { controller.setListening(false) }
        controller.setListening(true)
        let initial = try XCTUnwrap(controller.task)
        controller.refresh()
        controller.refresh()
        await initial.value
        await controller.task?.value
        controller.refresh()
        await controller.task?.value

        let trace = ShellNotificationTrace.shared.dump()
        XCTAssertTrue(trace.contains("ev=read.coalesced source=manual"))
        XCTAssertTrue(trace.contains("read=2 generation=1 source=coalesced"))
        XCTAssertTrue(trace.contains("read=3 generation=1 source=manual"))
        XCTAssertTrue(trace.contains("changed=false state=empty complete=true items=0 apps=0"))
        XCTAssertTrue(controller.diagnosticsSummary.contains("read=3 readInFlight=false queued=false"))
        XCTAssertTrue(controller.diagnosticsSummary.contains("source=manual"))
        XCTAssertTrue(controller.diagnosticsSummary.contains("changed=false"))
    }

    func testNativeDispatchIsSeparateFromDatabaseRemovalAndDoesNotRecordContents() async throws {
        ShellNotificationTrace.shared.beginCapture()
        defer { ShellNotificationTrace.shared.endCapture() }
        let id = try XCTUnwrap(UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB"))
        let privateMarker = "PRIVATE_NOTIFICATION_REPLY_中文"
        let item: ShellServiceValue = .object([
            "id": .text(id.uuidString), "bundle": .text(bundle),
            "title": .text(privateMarker), "body": .text(privateMarker),
            "actions": .array([.object([
                "title": .text(privateMarker), "textInputButtonTitle": .text(privateMarker)
            ])])
        ])
        let loader = Loader(.init(state: "ready", items: [item]))
        let controller = controller(loader)
        defer { controller.setListening(false) }
        controller.setListening(true)
        await controller.task?.value
        XCTAssertTrue(controller.perform(.reply(bundle: bundle, id: id, text: privateMarker)))
        await controller.actionTask?.value
        await controller.task?.value
        XCTAssertTrue(controller.diagnosticsSummary.contains("outcome=dispatched"))
        XCTAssertTrue(controller.diagnosticsSummary.contains("targetRetained=true"))
        await loader.replace(.init(state: "empty"))
        controller.refresh(.filesystem)
        await controller.task?.value
        XCTAssertTrue(controller.diagnosticsSummary.contains("targetRetained=false"))

        let trace = ShellNotificationTrace.shared.dump()
        XCTAssertTrue(trace.contains("ev=action.native.end target=\(id.uuidString.lowercased()) outcome=dispatched"))
        XCTAssertTrue(trace.contains("targetRetained=true"))
        XCTAssertTrue(trace.contains("targetRetained=false"))
        XCTAssertFalse(trace.contains(privateMarker))
        XCTAssertFalse(controller.diagnosticsSummary.contains(privateMarker))
        XCTAssertFalse(trace.contains(privateMarker.utf8.map { String(format: "%02x", $0) }.joined()))
    }

    func testCaptureIsRegisteredAndInactiveFieldsAreNotEvaluated() {
        ShellNotificationTrace.shared.endCapture()
        ShellNotificationTrace.shared.beginCapture()
        ShellNotificationTrace.record("test.active")
        ShellNotificationTrace.shared.endCapture()
        var evaluated = false
        func fields() -> String {
            evaluated = true
            return "inactive"
        }
        ShellNotificationTrace.record("test.inactive", fields: fields())
        XCTAssertFalse(evaluated)
        XCTAssertTrue(TraceCaptureResources.defaultRecorders.contains { $0.sectionTitle == "Shell Notification Trace" })
        XCTAssertTrue(ShellNotificationTrace.shared.dump().contains("test.active"))
        XCTAssertFalse(ShellNotificationTrace.shared.dump().contains("test.inactive"))
    }
}
