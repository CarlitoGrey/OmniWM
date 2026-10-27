// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM

extension ShellNetworkPermissions {
    convenience init(allowing hosts: Set<String>, for principals: ShellWidgetPrincipal...) {
        var decisions = ShellPermissionDecisions()
        for principal in principals { decisions.setNetwork(.allowed, hosts: hosts, for: principal) }
        self.init(decisions: decisions)
    }
}

extension ShellHTTPPolicy {
    static let testPrincipal = ShellWidgetPrincipal(role: .bar, name: "test", source: "/shell/widgets/test")

    static func approved(_ hosts: Set<String>) -> ShellHTTPPolicy {
        .widget(testPrincipal, hosts: hosts, permissions: ShellNetworkPermissions(allowing: hosts, for: testPrincipal))
    }
}
