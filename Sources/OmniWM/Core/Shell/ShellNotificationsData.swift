// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

struct ShellNotificationsData: Equatable, Sendable, ShellValueWritable {
    let state: String
    let items: [ShellServiceValue]
    let apps: [ShellServiceValue]
    let complete: Bool
    let error: String?

    init(
        state: String,
        items: [ShellServiceValue] = [],
        apps: [ShellServiceValue] = [],
        complete: Bool = true,
        error: String? = nil
    ) {
        self.state = state
        self.items = items
        self.apps = apps
        self.complete = complete
        self.error = error
    }

    func write(into writer: inout ShellValueWriter) {
        writer.map(5)
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
    }
}
