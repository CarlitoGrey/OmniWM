// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ShellNotificationAppNameTests: XCTestCase {
    @MainActor
    private final class Gate {
        var snapshot: ShellNotificationsData
        let names: [String: String]
        var lookups: [String] = []

        init(_ snapshot: ShellNotificationsData, names: [String: String] = [:]) {
            self.snapshot = snapshot
            self.names = names
        }

        func read(_: URL) -> ShellNotificationsData {
            snapshot
        }

        func name(_ bundle: String) -> String? {
            lookups.append(bundle)
            return names[bundle]
        }
    }

    private func item(_ bundle: String, body: String = "Retained body") -> ShellServiceValue {
        .object(["id": .text(UUID().uuidString.lowercased()), "bundle": .text(bundle), "body": .text(body)])
    }

    private func controller(_ gate: Gate) async throws -> ShellNotificationsController {
        let controller = ShellNotificationsController(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("uncreated/db"),
            load: { await gate.read($0) }, resolveName: { gate.name($0) }
        )
        controller.setListening(true)
        await (try XCTUnwrap(controller.task)).value
        return controller
    }

    func testRetainedAppNameResolvesOnceAndPreservesMetadataAcrossReads() async throws {
        let bundle = "com.example.notifications"
        let unused = "com.example.unused"
        let metadata: ShellServiceValue = .object(["columns": .object(["opaque": .bytes([0, 255, 1])])])
        let source = ShellNotificationsData(state: "ready", items: [item(bundle), item(bundle)], apps: [
            .object(["bundle": .text(bundle), "metadata": metadata]), .object(["bundle": .text(unused)])
        ])
        let gate = Gate(source, names: [bundle: "Readable App"])
        let controller = try await controller(gate)
        defer { controller.setListening(false) }
        XCTAssertEqual(gate.lookups, [bundle])
        XCTAssertEqual(controller.current.apps, [
            .object(["bundle": .text(bundle), "name": .text("Readable App"), "metadata": metadata]),
            .object(["bundle": .text(unused)])
        ])
        XCTAssertEqual(controller.current.items, source.items)

        gate.snapshot = ShellNotificationsData(
            state: "ready",
            items: [item(bundle, body: "Updated body")],
            apps: source.apps
        )
        controller.refresh()
        await (try XCTUnwrap(controller.task)).value
        XCTAssertEqual(gate.lookups, [bundle])
        XCTAssertEqual(controller.current.apps.first?.fields?["name"]?.string, "Readable App")
        XCTAssertEqual(controller.current.items, gate.snapshot.items)
    }

    func testExistingNamesAndUnknownBundlesKeepTheirFallbackWithoutRepeatedLookups() async throws {
        let known = "com.example.named"
        let unknown = "com.example.missing"
        let blank = "com.example.blank"
        let source = ShellNotificationsData(state: "ready", items: [item(known), item(unknown), item(blank)], apps: [
            .object(["bundle": .text(known), "name": .text("Existing Name")]),
            .object(["bundle": .text(unknown)]), .object(["bundle": .text(blank)])
        ])
        let gate = Gate(source, names: [known: "Unused Replacement", blank: ""])
        let controller = try await controller(gate)
        defer { controller.setListening(false) }
        XCTAssertEqual(gate.lookups, [unknown, blank])
        XCTAssertEqual(controller.current.apps, source.apps)
        controller.refresh()
        await (try XCTUnwrap(controller.task)).value
        XCTAssertEqual(gate.lookups, [unknown, blank])
        XCTAssertEqual(controller.current.apps, source.apps)
    }

    func testNewRetainedBundleResolvesWhenItsFirstNotificationArrives() async throws {
        let bundle = "com.example.arrival"
        let apps: [ShellServiceValue] = [.object(["bundle": .text(bundle)])]
        let gate = Gate(.init(state: "empty", apps: apps), names: [bundle: "Arrival App"])
        let controller = try await controller(gate)
        defer { controller.setListening(false) }
        XCTAssertTrue(gate.lookups.isEmpty)
        gate.snapshot = .init(state: "ready", items: [item(bundle)], apps: apps)
        controller.refresh()
        await (try XCTUnwrap(controller.task)).value
        XCTAssertEqual(gate.lookups, [bundle])
        XCTAssertEqual(controller.current.apps.first?.fields?["name"]?.string, "Arrival App")
    }
}
