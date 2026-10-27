// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CryptoKit
import Foundation
@testable import OmniWM

extension ShellNetworkPermissions {
    func approveProvider(_ configuration: ShellProviderConfiguration) {
        guard let digest = configuration.sha256 else { return }
        var decisions = ShellPermissionDecisions()
        decisions.setProgram(.allowed, for: ShellProviderApproval(
            principal: configuration.principal, command: configuration.command, sha256: digest
        ))
        update(decisions: decisions)
    }

    static func approvingProvider(folder: URL, names: [String] = ["child"], command: [String] = ["provider"]) throws
        -> ShellNetworkPermissions
    {
        var decisions = ShellPermissionDecisions()
        for name in names {
            let configuration = try ShellProviderConfiguration.fixture(widget: name, folder: folder, command: command)
            decisions.setProgram(.allowed, for: ShellProviderApproval(
                principal: configuration.principal, command: command, sha256: configuration.sha256!
            ))
        }
        return ShellNetworkPermissions(decisions: decisions)
    }
}

extension ShellProviderConfiguration {
    static func fixture(
        widget: String = "fixture", instance: String = "child", folder: URL,
        command: [String], options: Data = Data("{}".utf8)
    ) throws -> ShellProviderConfiguration {
        let bytes = try Data(contentsOf: folder.appendingPathComponent(command[0]))
        return ShellProviderConfiguration(
            widget: widget, instance: instance, folder: folder, command: command, options: options,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        )
    }

    var unapproved: ShellProviderConfiguration {
        ShellProviderConfiguration(
            widget: widget, instance: instance, folder: folder, command: command, options: options,
            sha256: nil, principal: principal
        )
    }

    static var mock: ShellProviderConfiguration {
        ShellProviderConfiguration(
            widget: "child", instance: "child", folder: URL(fileURLWithPath: "/fixture/provider"),
            command: ["provider"], options: Data("{}".utf8), sha256: String(repeating: "0", count: 64)
        )
    }
}
