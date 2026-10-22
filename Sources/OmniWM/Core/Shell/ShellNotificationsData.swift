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

    init(
        state: String,
        items: [ShellServiceValue] = [],
        apps: [ShellServiceValue] = [],
        complete: Bool = true,
        error: String? = nil,
        action: ShellServiceValue? = nil,
        dismissAll: ShellServiceValue? = nil
    ) {
        self.state = state
        self.items = items
        self.apps = apps
        self.complete = complete
        self.error = error
        self.action = action
        self.dismissAll = dismissAll
    }

    func write(into writer: inout ShellValueWriter) {
        writer.map(7)
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
    }
}
