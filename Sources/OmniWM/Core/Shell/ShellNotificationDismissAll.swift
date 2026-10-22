// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

enum ShellNotificationDismissAll {
    static func perform(
        _ requests: [ShellNotificationActionRequest],
        begin: () -> ShellNotificationActionOutcome?,
        dismiss: (ShellNotificationActionRequest) -> ShellNotificationActionOutcome,
        finish: (ShellNotificationActionOutcome) -> ShellNotificationActionOutcome,
        progress: (ShellNotificationActionOutcome) -> Void
    ) -> ShellNotificationActionOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard !requests.isEmpty else { return .dispatched }
        if let failure = begin() { return finish(failure) }
        for request in requests {
            guard !Task.isCancelled else { return finish(.cancelled) }
            guard request.operation == .dismiss else { return finish(.unsupported) }
            let outcome = dismiss(request)
            if outcome == .cancelled { return finish(.cancelled) }
            progress(outcome)
            if outcome == .historyClosed { return finish(.historyClosed) }
        }
        return finish(.dispatched)
    }
}
