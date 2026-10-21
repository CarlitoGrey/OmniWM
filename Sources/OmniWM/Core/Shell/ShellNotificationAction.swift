// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct ShellNotificationActionRequest: Equatable, Sendable {
    enum Operation: Equatable, Sendable {
        case dismiss
        case reply(text: String, title: String, sendTitle: String)
    }

    let bundle: String
    let id: UUID
    let peers: Set<UUID>
    let operation: Operation
}

enum ShellNotificationActionOutcome: String, Sendable {
    case dispatched
    case dispatchedPanelOpen
    case notFound
    case denied
    case unavailable
    case ambiguous
    case unsupported
    case failed
    case failedPanelOpen
    case cancelled
    case timeout
}
