// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import Observation

@MainActor @Observable
final class ShellPermissionSettings {
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onDecisionsChange: (() -> Void)?

    private(set) var decisions = ShellPermissionDecisions() {
        didSet {
            guard decisions != oldValue else { return }
            onDecisionsChange?()
            onChange?()
        }
    }

    func setNetwork(
        _ decision: ShellPermissionDecisions.HostDecision?,
        hosts: some Sequence<String>,
        for principal: ShellWidgetPrincipal
    ) {
        decisions.setNetwork(decision, hosts: hosts, for: principal)
    }

    func export() -> ShellPermissionDecisions {
        decisions
    }

    func setProgram(_ decision: ShellPermissionDecisions.HostDecision?, for approval: ShellProviderApproval) {
        decisions.setProgram(decision, for: approval)
    }

    func setServiceEnabled(_ enabled: Bool, service: ShellBuiltInService) {
        switch service {
        case .weather: decisions.services.weather = enabled
        case .lyrics: decisions.services.lyrics = enabled
        }
    }

    func apply(_ values: ShellPermissionDecisions) {
        decisions = values
    }
}

struct ShellPermissionDecisions: Codable, Equatable, Sendable {
    enum HostDecision: Sendable {
        case allowed
        case denied
    }

    struct Widget: Codable, Equatable, Sendable {
        var role: ShellWidgetPrincipal.Role
        var name: String
        var source: String
        var allowed: [String] = []
        var denied: [String] = []

        var principal: ShellWidgetPrincipal {
            ShellWidgetPrincipal(role: role, name: name, source: source)
        }
    }

    struct Program: Codable, Equatable, Sendable {
        var name: String
        var source: String
        var command: [String]
        var sha256: String?
        var denied = false
    }

    struct Services: Codable, Equatable, Sendable {
        var weather = true
        var lyrics = true
    }

    var widgets: [Widget] = []
    var programs: [Program] = []
    var services = Services()

    mutating func setProgram(_ decision: HostDecision?, for approval: ShellProviderApproval) {
        let index = programs.firstIndex {
            $0.name == approval.principal.name && $0.source == approval.principal.source && $0.command == approval
                .command
        }
        programs.removeAll {
            $0.name == approval.principal.name && $0.source == approval.principal.source && $0.command == approval
                .command
        }
        guard let decision else { return }
        programs.insert(Program(
            name: approval.principal.name, source: approval.principal.source,
            command: approval.command, sha256: approval.sha256, denied: decision == .denied
        ), at: index ?? programs.endIndex)
    }

    mutating func setNetwork(
        _ decision: HostDecision?,
        hosts: some Sequence<String>,
        for principal: ShellWidgetPrincipal
    ) {
        let hosts = Set(hosts.map(ShellHTTPPolicy.canonicalHost))
        let index = widgets.firstIndex { $0.principal == principal }
        let existing = widgets.filter { $0.principal == principal }
        widgets.removeAll { $0.principal == principal }
        var entry = Widget(role: principal.role, name: principal.name, source: principal.source)
        entry.allowed = Self.hosts(existing.flatMap(\.allowed), replacing: hosts, with: decision == .allowed)
        entry.denied = Self.hosts(existing.flatMap(\.denied), replacing: hosts, with: decision == .denied)
        guard !entry.allowed.isEmpty || !entry.denied.isEmpty else { return }
        widgets.insert(entry, at: index ?? widgets.endIndex)
    }

    private static func hosts(_ hosts: [String], replacing changed: Set<String>, with included: Bool) -> [String] {
        Set(hosts.map(ShellHTTPPolicy.canonicalHost)).subtracting(changed).union(included ? changed : []).sorted()
    }
}

extension ShellPermissionDecisions {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgets = try container.decodeIfPresent([Widget].self, forKey: .widgets) ?? []
        programs = try container.decodeIfPresent([Program].self, forKey: .programs) ?? []
        services = try container.decodeIfPresent(Services.self, forKey: .services) ?? Services()
    }
}

extension ShellPermissionDecisions.Widget {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ShellWidgetPrincipal.Role.self, forKey: .role)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(String.self, forKey: .source)
        allowed = try container.decodeIfPresent([String].self, forKey: .allowed) ?? []
        denied = try container.decodeIfPresent([String].self, forKey: .denied) ?? []
    }
}

extension ShellPermissionDecisions.Program {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(String.self, forKey: .source)
        command = try container.decode([String].self, forKey: .command)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        denied = try container.decodeIfPresent(Bool.self, forKey: .denied) ?? false
    }
}

extension ShellPermissionDecisions.Services {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weather = try container.decodeIfPresent(Bool.self, forKey: .weather) ?? true
        lyrics = try container.decodeIfPresent(Bool.self, forKey: .lyrics) ?? true
    }
}
