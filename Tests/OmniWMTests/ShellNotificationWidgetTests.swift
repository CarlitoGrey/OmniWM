// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import OmniWMScriptHost
import XCTest

@MainActor
final class ShellNotificationWidgetTests: XCTestCase {
    private func write(_ value: Any, into writer: inout ShellValueWriter) {
        switch value {
        case let value as String: writer.string(value)
        case let value as Bool: writer.bool(value)
        case let value as Int: writer.number(Double(value))
        case let value as Double: writer.number(value)
        case let value as Data: writer.string(bytes: value)
        case let value as [Any]:
            writer.array(value.count)
            for item in value { write(item, into: &writer) }
        case let value as [String: Any]:
            writer.map(value.count)
            for key in value.keys.sorted() {
                writer.key(key)
                if let item = value[key] { write(item, into: &writer) }
            }
        default: writer.null()
        }
    }

    private func set(_ widget: ShellRenderedWidget, state: String, items: [[String: Any]] = [], complete: Bool = true) {
        widget.set("notifications") {
            write([
                "state": state, "complete": complete, "items": items,
                "apps": [["bundle": "com.example.fixture", "name": "Fixture App"]]
            ], into: &$0)
        }
    }

    private func item(_ id: String = "fixture", body: String = "Fixture body") -> [String: Any] {
        let binary = Data("DO-NOT-DISPLAY-BINARY".utf8)
        return [
            "id": id, "bundle": "com.example.fixture", "title": "Fixture title ✓", "subtitle": "Fixture subtitle",
            "body": body, "date": 1_000_000.0, "requestId": "request-1", "thread": "conversation-1",
            "category": "message", "attachments": [[
                "id": "image-1",
                "type": "public.png",
                "available": false,
                "path": "/fixture/retained.png"
            ]],
            "actions": [[
                "id": "reply",
                "title": "Reply ✓",
                "options": 0,
                "textInputButtonTitle": "Send reply",
                "textInputPlaceholder": "Write a reply"
            ]],
            "userInfo": ["nested": ["value": "preserved", "type": "data", "title": "Ordinary data title"]],
            "communication": [
                "sender": ["displayName": "Fixture Sender"],
                "displayName": "Fixture Conversation",
                "identifier": "conversation-1",
                "recipients": [["displayName": "Fixture Recipient"]]
            ],
            "metadata": [
                "blob": ["type": "data", "byteLength": binary.count, "bytes": binary],
                "unknownBinary": Data([0xFF, 0, 0x80])
            ]
        ]
    }

    func testFailuresRemainDistinctFromAnEmptyRetainedList() throws {
        let widget = try ShellRenderedWidget("notifications")
        for state in ["accessDenied", "unavailable", "queryError", "malformed", "incomplete"] {
            set(widget, state: state, complete: state != "incomplete")
            let tree = widget.renderPopout()
            XCTAssertFalse(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string(
                "No retained notifications",
                []
            )))
            XCTAssertTrue(tree.map { widget.text.string($0.content.action) }.contains("notifications settings"))
        }
        set(widget, state: "empty")
        _ = widget.renderPopout()
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("No retained notifications", [])))
    }

    func testFullUnicodeBodyAndReadOnlyMetadataRemainAccessible() throws {
        let widget = try ShellRenderedWidget("notifications")
        let body = String(repeating: "Body ✓ 中文 العربية 👩🏽‍💻 e\u{301}\n", count: 192) + "END-fixture"
        set(widget, state: "ready", items: [item(body: body)])
        let tree = widget.renderPopout()
        let text = widget.strings(OMNI_VIEW_POPOUT)
        XCTAssertEqual(text.filter { $0.contains("Body ✓") }.joined(), body)
        XCTAssertTrue(text.contains("Fixture Sender"))
        XCTAssertTrue(text.contains("Fixture Conversation"))
        XCTAssertTrue(text.contains("Fixture Recipient"))
        XCTAssertTrue(text.contains("/fixture/retained.png"))
        let details = try XCTUnwrap(tree.first { $0.content.action & OMNI_ACTION_HANDLER != 0 })
        _ = widget.invoke(details.content.action, view: OMNI_VIEW_POPOUT)
        let expanded = widget.renderPopout()
        let metadata = widget.strings(OMNI_VIEW_POPOUT).joined(separator: "\n")
        XCTAssertTrue(metadata.contains("actions.1.id: reply"))
        XCTAssertTrue(metadata.contains("actions.1.textInputButtonTitle: Send reply"))
        XCTAssertTrue(metadata.contains("userInfo.nested.value: preserved"))
        XCTAssertTrue(metadata.contains("userInfo.nested.title: Ordinary data title"))
        XCTAssertFalse(metadata.contains("DO-NOT-DISPLAY-BINARY"))
        XCTAssertFalse(expanded.map { widget.text.string($0.content.action) }
            .contains { $0.hasPrefix("notifications reply") })
    }

    func testLargeMetadataTextIsPagedWithoutLosingItsEnd() throws {
        let widget = try ShellRenderedWidget("notifications")
        var notification = item()
        var metadata = try XCTUnwrap(notification["metadata"] as? [String: Any])
        metadata["largeScalar"] = String(repeating: "A", count: 20_000) + "END-metadata"
        notification["metadata"] = metadata
        notification["communication"] = [String: Any]()
        notification["userInfo"] = [String: Any]()
        set(widget, state: "ready", items: [notification])
        let initial = widget.renderPopout()
        let details = try XCTUnwrap(initial.first { $0.content.action & OMNI_ACTION_HANDLER != 0 })
        _ = widget.invoke(details.content.action, view: OMNI_VIEW_POPOUT)
        var page = widget.renderPopout()
        XCTAssertFalse(widget.strings(OMNI_VIEW_POPOUT).contains { $0.contains("END-metadata") })
        for _ in 0 ..< 2 {
            XCTAssertLessThan(page.count, 256)
            let next = try XCTUnwrap(page.last { $0.content.action & OMNI_ACTION_HANDLER != 0 })
            _ = widget.invoke(next.content.action, view: OMNI_VIEW_POPOUT)
            page = widget.renderPopout()
        }
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains { $0.contains("END-metadata") })
    }

    func testPaginationReachesEveryRetainedItem() throws {
        let widget = try ShellRenderedWidget("notifications")
        let items = (0 ..< 9).map { item("item-\($0)", body: "Item body \($0)") }
        set(widget, state: "ready", items: items)
        let first = widget.renderPopout()
        XCTAssertFalse(widget.strings(OMNI_VIEW_POPOUT).contains("Item body 8"))
        let next = try XCTUnwrap(first.last { $0.content.action & OMNI_ACTION_HANDLER != 0 })
        _ = widget.invoke(next.content.action, view: OMNI_VIEW_POPOUT)
        _ = widget.renderPopout()
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("Item body 8"))
    }
}
