// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@MainActor
final class QuakeCommandQueue {
    private var tail: Task<Void, Never>?
    private(set) var presentationGeneration: UInt64 = 0

    func invalidatePresentations() {
        presentationGeneration &+= 1
    }

    func enqueue(
        presentation: Bool = true,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let previous = tail
        let generation = presentationGeneration
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !presentation || self.presentationGeneration == generation else { return }
            await operation()
        }
        tail = task
        return task
    }
}
