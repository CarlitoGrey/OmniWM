// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import Synchronization

struct ShellWidgetPrincipal: Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case root
        case bar
        case component
    }

    let role: Role
    let name: String
    let source: String
}

extension ShellWidgetPrincipal {
    init(role: Role, name: String, folder: URL) {
        self.init(role: role, name: name, source: folder.resolvingSymlinksInPath().standardizedFileURL.path)
    }
}

enum ShellNetworkDecision: Equatable, Sendable {
    case allowed
    case denied
    case blocked
    case notApproved

    var failure: ShellHTTPFailure? {
        switch self {
        case .allowed: nil
        case .denied: ShellHTTPFailure("network_denied")
        case .blocked: ShellHTTPFailure("network_blocked")
        case .notApproved: ShellHTTPFailure("network_not_approved")
        }
    }
}

struct ShellNetworkApproval: Equatable, Sendable {
    struct Key: Hashable, Sendable {
        let principal: ShellWidgetPrincipal
        let hosts: Set<String>
    }

    let key: Key
    let purpose: String?
}

final class ShellHTTPDeclarations: Sendable {
    private let policies = Mutex<[String?: ShellHTTPPolicy]>([:])

    subscript(owner: String?) -> ShellHTTPPolicy {
        policies.withLock { $0[owner] } ?? .denied
    }

    func update(
        _ source: ShellWidgetSource,
        components: [ShellComponentInstance],
        permissions: ShellNetworkPermissions
    ) {
        var next: [String?: ShellHTTPPolicy] = [nil: .root(source, permissions: permissions)]
        for instance in components {
            next[instance.id] = .resolve(
                component: instance.id,
                instances: [instance],
                descriptors: source.componentDescriptors,
                permissions: permissions
            )
        }
        policies.withLock { $0 = next }
    }
}

final class ShellNetworkPermissions: Sendable {
    struct Hosts: Equatable, Sendable {
        var allowed: Set<String> = []
        var denied: Set<String> = []
    }

    struct Snapshot: Equatable, Sendable {
        var revision: UInt64 = 0
        var widgets: [ShellWidgetPrincipal: Hosts] = [:]
        var managed = ShellManagedPolicy()

        func decide(_ host: String, for principal: ShellWidgetPrincipal) -> ShellNetworkDecision {
            if managed.blocks(host) { return .blocked }
            let user = widgets[principal]
            if user?.denied.contains(host) == true { return .denied }
            return managed.allowedHosts.contains(host) || user?.allowed.contains(host) == true ? .allowed : .notApproved
        }
    }

    private let state: Mutex<Snapshot>

    init(
        decisions: ShellPermissionDecisions = ShellPermissionDecisions(),
        managed: ShellManagedPolicy = ShellManagedPolicy()
    ) {
        state = Mutex(Snapshot(widgets: Self.widgets(decisions), managed: managed))
    }

    var snapshot: Snapshot {
        state.withLock { $0 }
    }

    func decide(_ host: String, for principal: ShellWidgetPrincipal) -> ShellNetworkDecision {
        state.withLock { $0.decide(host, for: principal) }
    }

    func undecided(
        _ hosts: Set<String>,
        for principal: ShellWidgetPrincipal
    ) -> (revision: UInt64, hosts: Set<String>) {
        state.withLock { state in (state.revision, hosts.filter { state.decide($0, for: principal) == .notApproved }) }
    }

    @discardableResult
    func update(decisions: ShellPermissionDecisions? = nil, managed: ShellManagedPolicy? = nil) -> Bool {
        let widgets = decisions.map(Self.widgets)
        return state.withLock { state in
            var next = state
            if let widgets { next.widgets = widgets }
            if let managed { next.managed = managed }
            guard next != state else { return false }
            next.revision &+= 1
            state = next
            return true
        }
    }

    private static func widgets(_ decisions: ShellPermissionDecisions) -> [ShellWidgetPrincipal: Hosts] {
        decisions.widgets.reduce(into: [:]) { result, widget in
            result[widget.principal, default: Hosts()].allowed
                .formUnion(widget.allowed.map(ShellHTTPPolicy.canonicalHost))
            result[widget.principal, default: Hosts()].denied
                .formUnion(widget.denied.map(ShellHTTPPolicy.canonicalHost))
        }
    }
}
