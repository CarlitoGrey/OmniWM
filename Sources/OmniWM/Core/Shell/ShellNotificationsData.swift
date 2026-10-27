// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

struct ShellNotificationsData: Equatable, Sendable, ShellValueWritable {
    let state: String
    let items: [ShellServiceValue]
    var apps: [ShellServiceValue]
    let complete: Bool
    let error: String?
    var action: ShellServiceValue?
    var dismissAll: ShellServiceValue?
    var dispatched: [String]
    var kept: Int

    init(
        state: String,
        items: [ShellServiceValue] = [],
        apps: [ShellServiceValue] = [],
        complete: Bool = true,
        error: String? = nil,
        action: ShellServiceValue? = nil,
        dismissAll: ShellServiceValue? = nil,
        dispatched: [String] = [],
        kept: Int = 0
    ) {
        self.state = state
        self.items = items
        self.apps = apps
        self.complete = complete
        self.error = error
        self.action = action
        self.dismissAll = dismissAll
        self.dispatched = dispatched
        self.kept = kept
    }

    func write(into writer: inout ShellValueWriter) {
        writer.map(9)
        writer.key("state")
        writer.string(state)
        writer.key("complete")
        writer.bool(complete)
        writer.key("items")
        ShellServiceValue.array(items).write(to: &writer)
        writer.key("apps")
        ShellServiceValue.array(apps).write(to: &writer)
        writer.key("error")
        error.map { writer.string($0) } ?? writer.null()
        writer.key("action")
        (action ?? .null).write(to: &writer)
        writer.key("dismissAll")
        (dismissAll ?? .null).write(to: &writer)
        writer.key("dispatched")
        ShellServiceValue.array(dispatched.map(ShellServiceValue.text)).write(to: &writer)
        writer.key("kept")
        writer.number(Double(kept))
    }
}
