// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
@testable import OmniWM
import OmniWMScriptHost
import OmniWMShellCore
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

    private func styledWidget(
        _ config: ShellConfig,
        shell: URL,
        scale: CGFloat = 2,
        dark: Bool = false
    ) throws -> ShellRenderedWidget {
        let sourceURL = try XCTUnwrap(config.widget("notifications"))
        let source = try ShellWidgetSourceLoader.build(.init(
            name: "notifications", shellDirectory: shell, sourceURL: sourceURL,
            directories: config.directories, profile: config.profile
        ))
        let resources = ShellResources(motion: MotionPolicy(animationsEnabled: false))
        resources.palette.refresh(
            theme: config.theme,
            appearance: try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
        )
        return try ShellRenderedWidget(
            name: "notifications", source: source.main, directories: config.directories,
            modules: source.modules, chunk: source.chunk, scale: scale, resources: resources
        )
    }

    private func export(_ widget: ShellRenderedWidget, name: String, dark: Bool = false) throws {
        guard let directory = ProcessInfo.processInfo.environment["OMNIWM_SHELL_SNAPSHOTS"] else { return }
        try ShellBundledWidgetTests.writeSnapshot(
            widget.surface,
            name: "notifications-\(name)",
            dark: dark,
            directory: directory
        )
    }

    private func click(_ title: String, in widget: ShellRenderedWidget, last: Bool = false) throws {
        let labels = widget.surface.layout.core.elements { widget.text.string($0.text) == title }.sorted {
            CGRect(widget.surface.layout.core.absoluteFrame(of: $0)).minY
                < CGRect(widget.surface.layout.core.absoluteFrame(of: $1)).minY
        }
        var target = try XCTUnwrap(last ? labels.last : labels.first, title)
        while widget.surface.layout.core.content(of: target).action == 0 {
            target = widget.surface.layout.core.parent(of: target)
            guard target.slot >= 0 else { return XCTFail("No action for \(title)") }
        }
        let action = widget.surface.layout.core.content(of: target).action
        var frame = CGRect(widget.surface.layout.core.absoluteFrame(of: target))
        let bounds = CGRect(origin: .zero, size: widget.surface.size)
        if !bounds.contains(frame) {
            let scroll = try XCTUnwrap(widget.surface.layout.core.elements { $0.scrolls }.first)
            let viewport = CGRect(widget.surface.layout.core.absoluteFrame(of: scroll)).intersection(bounds)
            XCTAssertTrue(widget.surface.scroll(
                at: CGPoint(x: viewport.midX, y: viewport.midY), event: ShellEvent(button: .none),
                content: CGPoint(x: 0, y: frame.midY - viewport.midY)
            ))
            frame = CGRect(widget.surface.layout.core.absoluteFrame(of: target))
        }
        XCTAssertTrue(bounds.contains(frame), title)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let delivered = widget.actions.count
        widget.surface.press(at: point)
        widget.surface.release(at: point)
        XCTAssertEqual(widget.actions.count, delivered + 1, title)
        XCTAssertEqual(widget.actions.last, action, title)
        _ = widget.invoke(action, view: OMNI_VIEW_POPOUT)
        widget.layoutPopout()
    }

    func testNotificationProfilesFitBaseAndEnlargedBarsAtBothScalesAndOrientations() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let profiles = ShellProfiles.names(in: shell)
        XCTAssertEqual(profiles.count, 8)
        let counts = (0 ..< 256).map { item("item-\($0)") }
        for profile in profiles {
            var problems: [String] = []
            let config = try XCTUnwrap(ShellConfig.load(profile: profile, shellDirectory: shell, problems: &problems))
            XCTAssertEqual(problems, [], profile)
            let base = config.barOverride?.settings.height ?? 24
            for dark in [false, true] {
                for scale in [CGFloat(1), 2] {
                    let widget = try styledWidget(config, shell: shell, scale: scale, dark: dark)
                    set(widget, state: "ready", items: counts)
                    for height in [base, base * 1.5] {
                        for vertical in [false, true] {
                            var bar = ShellBarData()
                            bar.style.height = height
                            bar.style.vertical = vertical
                            bar.style.position = vertical ? "left" : "top"
                            widget.render(bar)
                            let name = "\(profile)-\(height)-\(vertical ? "vertical" : "horizontal")-\(scale)-\(dark ? "dark" : "light")"
                            let bounds = CGRect(origin: .zero, size: widget.surface.size)
                            XCTAssertTrue(bounds.width.isFinite && bounds.height.isFinite, name)
                            XCTAssertGreaterThan(bounds.width, 0, name)
                            XCTAssertGreaterThan(bounds.height, 0, name)
                            XCTAssertLessThanOrEqual(vertical ? bounds.width : bounds.height, height, name)
                            for leaf in widget.surface.layout.core.elements(matching: { $0.text != 0 }) {
                                let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: leaf))
                                XCTAssertTrue(bounds.contains(frame), name)
                            }
                            let target = try XCTUnwrap(widget.surface.layout.core
                                .elements { $0.action == OMNI_ACTION_POPOUT }.first)
                            let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: target))
                            widget.surface.press(at: CGPoint(x: frame.midX, y: frame.midY))
                            widget.surface.release(at: CGPoint(x: frame.midX, y: frame.midY))
                            XCTAssertEqual(widget.actions.last, UInt32(OMNI_ACTION_POPOUT), name)
                            XCTAssertTrue(widget.strings().contains("256"), name)
                            if scale == 2, height == base { try export(widget, name: name, dark: dark) }
                        }
                    }
                }
            }
        }
    }

    func testNotificationProfilesKeepStorageStatesAndDeliveredDetailsPaging() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in ShellProfiles.names(in: shell) {
            var problems: [String] = []
            let config = try XCTUnwrap(ShellConfig.load(profile: profile, shellDirectory: shell, problems: &problems))
            XCTAssertEqual(problems, [], profile)
            let widget = try styledWidget(config, shell: shell)
            var bar = ShellBarData()
            bar.style.height = config.barOverride?.settings.height ?? 24
            widget.render(bar)
            for state in ["accessDenied", "empty"] {
                set(widget, state: state)
                widget.layoutPopout()
                let strings = widget.strings(OMNI_VIEW_POPOUT)
                XCTAssertEqual(
                    strings.contains(ShellLocalizer.string("No retained notifications", [])),
                    state == "empty",
                    profile
                )
                for action in ["notifications refresh", "notifications settings"] {
                    let target = try XCTUnwrap(widget.surface.layout.core
                        .elements { widget.text.string($0.action) == action }.first)
                    let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: target))
                    XCTAssertTrue(CGRect(origin: .zero, size: widget.surface.size).contains(frame), profile)
                    widget.surface.press(at: CGPoint(x: frame.midX, y: frame.midY))
                    widget.surface.release(at: CGPoint(x: frame.midX, y: frame.midY))
                    XCTAssertEqual(widget.clicks.last?.action, action, profile)
                }
                try export(widget, name: "\(profile)-\(state)")
            }
            var items = (0 ..< 9).map { item("item-\($0)", body: "Notification body \($0) ✓ 中文 العربية 👩🏽‍💻") }
            items[0]["metadata"] = Dictionary(uniqueKeysWithValues: (0 ..< 40).map { (
                String(format: "field%02d", $0),
                "Metadata \($0)"
            ) })
            set(widget, state: "ready", items: items)
            widget.layoutPopout()
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("Notification body 0 ✓ 中文 العربية 👩🏽‍💻"), profile)
            let bounds = CGRect(origin: .zero, size: widget.surface.size)
            XCTAssertGreaterThanOrEqual(bounds.width, 392, profile)
            XCTAssertLessThanOrEqual(bounds.width, 480, profile)
            try export(widget, name: "\(profile)-ready")
            try click(ShellLocalizer.string("Details", []), in: widget)
            XCTAssertTrue(
                widget.strings(OMNI_VIEW_POPOUT).contains { $0.contains("actions.1.textInputButtonTitle: Send reply") },
                profile
            )
            try export(widget, name: "\(profile)-details")
            try click(ShellLocalizer.string("Next", []), in: widget)
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains { $0.contains("metadata.field") }, profile)
            try click(ShellLocalizer.string("Next", []), in: widget, last: true)
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("Notification body 8 ✓ 中文 العربية 👩🏽‍💻"), profile)
            try export(widget, name: "\(profile)-last-page")
        }
    }
}
