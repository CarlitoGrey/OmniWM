// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Darwin
import Foundation

extension ShellProvider {
    func refreshTrust(
        _ configuration: ShellProviderConfiguration, refreshWatches: Bool = false,
        configurationChanged: Bool = false
    ) {
        watchExecutable(nil, configuration: configuration, refresh: refreshWatches)
        do {
            let resolved = try resolveDeclaration(configuration)
            watchExecutable(resolved.executable, configuration: configuration)
            let approval = try executableApproval(configuration, executable: resolved.executable)
            let decision = permissions.decide(approval)
            guard configuration.principal == approval.principal, configuration.sha256 == approval.sha256,
                  decision == .allowed
            else {
                reportApproval(approval)
                if decision == .allowed, lifecycle.phase == .terminal, lifecycle.configuration == nil { return }
                reject(configuration, status: .notApproved, reason: .trust(approval, decision))
                return
            }
            lastReportedApproval = nil
            lastRejection = nil
            if configurationChanged || lifecycle.configuration != configuration {
                perform(lifecycle.reconcile(configuration))
            }
        } catch {
            let message = String(error.localizedDescription.prefix(1024))
            reject(configuration, status: .failed(message), reason: .failure(configuration, message))
            if let identity = lifecycle.identity {
                diagnostics(identity, ShellProviderDiagnostics.Line(
                    text: message, truncated: false, suppressed: 0
                ))
            }
        }
    }

    private func reject(
        _ configuration: ShellProviderConfiguration, status: ShellProviderInbox.Status, reason: Rejection
    ) {
        guard lastRejection != reason || lifecycle.phase != .terminal || lifecycle.configuration != nil else { return }
        lastRejection = reason
        perform(lifecycle.refuse(configuration, status: status))
    }

    func reportApproval(_ approval: ShellProviderApproval) {
        let revision = permissions.snapshot.revision
        if revision != approvalRevision {
            approvalRevision = revision
            lastReportedApproval = nil
        }
        guard permissions.decide(approval) == .notApproved, lastReportedApproval != approval else { return }
        lastReportedApproval = approval
        trustNeeded(approval)
    }

    func stopExecutableWatches() {
        for watch in executableWatches { watch.cancel() }
        executableWatches.removeAll()
        executableWatchPaths.removeAll()
    }

    private func watchExecutable(
        _ executable: URL?, configuration: ShellProviderConfiguration, refresh: Bool = false
    ) {
        guard let command = configuration.command.first else { return }
        let requested = configuration.folder.appendingPathComponent(command)
        var paths = Set([
            requested.path,
            requested.deletingLastPathComponent().path,
            configuration.folder.path,
            configuration.folder.deletingLastPathComponent().path
        ])
        if let executable {
            paths.insert(executable.path)
            paths.insert(executable.deletingLastPathComponent().path)
        } else if !refresh, !executableWatches.isEmpty {
            return
        }
        guard refresh || paths != executableWatchPaths else { return }
        stopExecutableWatches()
        executableWatchPaths = paths
        for path in paths {
            let descriptor = open(path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                Task { await self?.executableChanged() }
            }
            source.setCancelHandler { _ = Darwin.close(descriptor) }
            executableWatches.append(source)
            source.resume()
        }
    }

    private func executableChanged() {
        guard let declaration else { return }
        refreshTrust(declaration, refreshWatches: true)
    }
}
