// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct NetworkPermissionsPage: Equatable {
    static let widgetsAnchor = "Widgets"
    static let programsAnchor = "Programs"
    static let servicesAnchor = "Built-in Services"

    enum HostState: Equatable {
        case notAsked
        case allowed
        case denied
        case allowedByOrganization
        case blockedByOrganization
    }

    enum ProgramState: Equatable {
        case notAsked
        case needsApproval(ShellProviderApproval)
        case allowed(ShellProviderApproval)
        case denied
        case blockedByOrganization
    }

    struct Host: Equatable, Identifiable {
        let name: String
        let declaredByShellConfig: Bool
        let state: HostState

        var id: String {
            name
        }

        var decision: ShellPermissionDecisions.HostDecision? {
            switch state {
            case .allowed: .allowed
            case .denied: .denied
            case .notAsked,
                 .allowedByOrganization,
                 .blockedByOrganization: nil
            }
        }
    }

    struct Widget: Equatable, Identifiable {
        let principal: ShellWidgetPrincipal
        let title: String
        let purpose: String?
        let hosts: [Host]

        var id: String {
            NetworkPermissionsPage.anchor(principal.role, principal.name)
        }
    }

    struct Program: Equatable, Identifiable {
        let id: String
        let key: ShellProviderApproval.Key
        let title: String
        let state: ProgramState
    }

    let widgets: [Widget]
    let programs: [Program]

    static func anchor(_ role: ShellWidgetPrincipal.Role, _ name: String) -> String {
        "\(role.rawValue):\(name)"
    }

    init(
        config: ShellConfig,
        schemas: [String: ShellRootSettings],
        catalog: ShellConfigurationCatalog?,
        permissions: ShellNetworkPermissions.Snapshot,
        pending: [ShellPermissionPrompts.Request]
    ) {
        let descriptors = catalog?.entries.compactMap(\.descriptor) ?? []
        let instances = config.island?.components ?? []
        var widgets = schemas.values.filter { !$0.network.isEmpty }.map { schema in
            let principal = ShellWidgetPrincipal(
                role: schema.widget == config.island?.root ? .root : .bar, name: schema.widget, source: schema.source
            )
            return Widget(
                principal: principal, title: ShellBarLayout.title(of: schema.widget), purpose: schema.purpose,
                hosts: Self.hosts(declared: schema.network, extended: [], for: principal, permissions)
            )
        }
        for descriptor in descriptors {
            let extended = instances.filter { $0.widget == descriptor.widget }
                .flatMap { $0.capabilities?.network ?? [] }
            guard !descriptor.capabilities.network.isEmpty || !extended.isEmpty else { continue }
            widgets.append(Widget(
                principal: descriptor.principal, title: descriptor.title, purpose: descriptor.capabilities.purpose,
                hosts: Self.hosts(
                    declared: descriptor.capabilities.network, extended: extended,
                    for: descriptor.principal, permissions
                )
            ))
        }
        self.widgets = widgets.sorted { ($0.title, $0.id) < ($1.title, $1.id) }
        let widgetIDs = Set(self.widgets.map(\.id))
        programs = descriptors.compactMap { descriptor in
            guard descriptor.capabilities.provider, let command = descriptor.providerCommand else { return nil }
            let key = ShellProviderApproval.Key(principal: descriptor.principal, command: command)
            let anchor = Self.anchor(.component, descriptor.widget)
            return Program(
                id: widgetIDs.contains(anchor) ? "program." + anchor : anchor, key: key, title: descriptor.title,
                state: Self.state(of: key, permissions, pending: pending)
            )
        }
    }

    private static func hosts(
        declared: [String],
        extended: [String],
        for principal: ShellWidgetPrincipal,
        _ permissions: ShellNetworkPermissions.Snapshot
    ) -> [Host] {
        let declared = Set(declared.map(ShellHTTPPolicy.canonicalHost))
        return declared.union(extended.map(ShellHTTPPolicy.canonicalHost)).sorted().map { host in
            let state: HostState = switch permissions.decide(host, for: principal) {
            case .blocked: .blockedByOrganization
            case .denied: .denied
            case .notApproved: .notAsked
            case .allowed: permissions.widgets[principal]?.allowed.contains(host) == true
                ? .allowed : .allowedByOrganization
            }
            return Host(name: host, declaredByShellConfig: !declared.contains(host), state: state)
        }
    }

    private static func state(
        of key: ShellProviderApproval.Key,
        _ permissions: ShellNetworkPermissions.Snapshot,
        pending: [ShellPermissionPrompts.Request]
    ) -> ProgramState {
        guard permissions.managed.providersAllowed else { return .blockedByOrganization }
        for case let .program(approval) in pending where approval.key == key {
            return .needsApproval(approval)
        }
        guard let stored = permissions.programs[key] else { return .notAsked }
        if stored.denied { return .denied }
        guard let digest = stored.sha256 else { return .notAsked }
        return .allowed(ShellProviderApproval(principal: key.principal, command: key.command, sha256: digest))
    }
}
