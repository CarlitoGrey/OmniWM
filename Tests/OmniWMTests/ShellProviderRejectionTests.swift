// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ShellProviderRejectionTests: XCTestCase {
    private func fixture(in directory: URL) throws -> ShellProviderConfiguration {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("provider")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: executable.path,
            contents: Data("#!/usr/bin/perl\nwhile (<STDIN>) {}\n".utf8),
            attributes: [.posixPermissions: 0o755]
        ))
        return try .fixture(widget: "fixture", folder: directory, command: ["provider"])
    }

    func testRepeatedDeniedAndManagedBlockedChecksRetainTheirRefusedIdentity() async throws {
        for decision in [ShellNetworkDecision.denied, .blocked] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let known = try fixture(in: directory)
            let approval = ShellProviderApproval(
                principal: known.principal, command: known.command, sha256: try XCTUnwrap(known.sha256)
            )
            var saved = ShellPermissionDecisions()
            var managed = ShellManagedPolicy()
            if decision == .denied { saved.setProgram(.denied, for: approval) }
            else { managed.providersAllowed = false }
            let permissions = ShellNetworkPermissions(decisions: saved, managed: managed)
            let inbox = ShellProviderInbox()
            let owner = ShellServiceOwner(generation: 773, owner: 1, epoch: 1)
            let provider = ShellProvider(owner: owner, inbox: inbox, permissions: permissions)
            await provider.reconcile(known.unapproved)
            let first = try XCTUnwrap(inbox.binding(for: owner))
            XCTAssertEqual(first.status, .notApproved)
            XCTAssertTrue(first.terminal)
            for _ in 0 ..< 3 {
                await provider.reconcile(known.unapproved)
                XCTAssertEqual(inbox.binding(for: owner)?.identity, first.identity)
            }
            await provider.close()
        }
    }

    func testAnApprovedSnapshotDoesNotCreateAnExtraStaleRefusedIncarnation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let known = try fixture(in: directory)
        let permissions = ShellNetworkPermissions()
        let inbox = ShellProviderInbox()
        let owner = ShellServiceOwner(generation: 774, owner: 1, epoch: 1)
        let provider = ShellProvider(owner: owner, inbox: inbox, permissions: permissions)
        await provider.reconcile(known.unapproved)
        let refused = try XCTUnwrap(inbox.binding(for: owner))
        XCTAssertEqual(refused.status, .notApproved)
        permissions.approveProvider(known)
        await provider.reconcile(known.unapproved)
        XCTAssertEqual(inbox.binding(for: owner)?.identity, refused.identity)
        await provider.reconcile(known)
        let running = try XCTUnwrap(inbox.binding(for: owner))
        XCTAssertEqual(running.identity.incarnation, refused.identity.incarnation + 1)
        XCTAssertEqual(running.status, .running)
        await provider.close()
    }

    func testMissingUnapprovedExecutableReportsItsActualFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ShellProviderConfiguration(
            widget: "fixture", instance: "child", folder: directory, command: ["missing"],
            options: Data("{}".utf8), sha256: nil
        )
        let inbox = ShellProviderInbox()
        let owner = ShellServiceOwner(generation: 775, owner: 1, epoch: 1)
        let provider = ShellProvider(owner: owner, inbox: inbox)
        await provider.reconcile(configuration)
        let binding = try XCTUnwrap(inbox.binding(for: owner))
        guard case let .failed(message) = binding.status else {
            await provider.close()
            return XCTFail("Expected the launch failure, got \(binding.status)")
        }
        XCTAssertTrue(message.contains("executable"), message)
        XCTAssertTrue(binding.terminal)
        await provider.close()
    }
}
