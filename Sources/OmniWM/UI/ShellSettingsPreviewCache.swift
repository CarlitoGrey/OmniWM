// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

@MainActor
final class ShellSettingsPreviewCache {
    enum Priority: Int, Comparable {
        case thumbnail
        case main

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Slot: Hashable {
        let id: String
        var priority = Priority.main
    }

    private struct Waiter {
        let slot: Slot?
        let continuation: CheckedContinuation<CGImage, any Error>
    }

    private struct Job {
        let id = UUID()
        let request: ShellSettingsPreview.Request
        let order: UInt64
        var waiters: [UUID: Waiter]
        var task: Task<Void, Never>?

        var priority: Priority {
            waiters.values.map { $0.slot?.priority ?? .main }.max() ?? .thumbnail
        }
    }

    static let shared = ShellSettingsPreviewCache()
    static let maximumBytes = 32 << 20
    private let render: @MainActor (ShellSettingsPreview.Request) async throws -> CGImage
    private var entries: [(ShellSettingsPreview.Request, CGImage)] = []
    private var jobs: [Job] = []
    private var running: UUID?
    private var order: UInt64 = 0
    private(set) var retainedBytes = 0
    var count: Int {
        entries.count
    }

    init(render: @escaping @MainActor (ShellSettingsPreview.Request) async throws -> CGImage = ShellSettingsPreview
        .render)
    {
        self.render = render
    }

    func image(for request: ShellSettingsPreview.Request, slot: Slot? = nil) async throws -> CGImage {
        try Task.checkCancellation()
        let waiter = UUID()
        if let index = entries.firstIndex(where: { $0.0 == request }) {
            if let slot { detach(slot, keeping: waiter) }
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.1
        }
        return try await withTaskCancellationHandler {
            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                CGImage,
                any Error
            >) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let registered = Waiter(slot: slot, continuation: continuation)
                if let index = jobs.firstIndex(where: { $0.request == request }) {
                    jobs[index].waiters[waiter] = registered
                } else {
                    order += 1
                    jobs.append(Job(request: request, order: order, waiters: [waiter: registered]))
                }
                if let slot { detach(slot, keeping: waiter) }
                admit()
            }
            try Task.checkCancellation()
            return image
        } onCancel: {
            Task { @MainActor in self.cancel(waiter) }
        }
    }

    private func admit() {
        guard running == nil,
              let index = jobs.indices.filter({ jobs[$0].task == nil }).max(by: {
                  (jobs[$0].priority, jobs[$1].order) < (jobs[$1].priority, jobs[$0].order)
              })
        else { return }
        let id = jobs[index].id
        let request = jobs[index].request
        running = id
        jobs[index].task = Task { [weak self, render] in
            let result: Result<CGImage, any Error>
            do {
                let image = try await render(request)
                try Task.checkCancellation()
                result = .success(image)
            } catch {
                result = .failure(error)
            }
            self?.complete(id, result: result)
        }
    }

    private func cancel(_ waiter: UUID) {
        guard let index = jobs.firstIndex(where: { $0.waiters[waiter] != nil }),
              let removed = jobs[index].waiters.removeValue(forKey: waiter)
        else { return }
        dropIfAbandoned(index)
        removed.continuation.resume(throwing: CancellationError())
    }

    private func detach(_ slot: Slot, keeping kept: UUID) {
        for index in jobs.indices.reversed() {
            let stale = jobs[index].waiters.filter { $0.key != kept && $0.value.slot?.id == slot.id }
            guard !stale.isEmpty else { continue }
            for key in stale.keys {
                jobs[index].waiters[key] = nil
            }
            dropIfAbandoned(index)
            for waiter in stale.values {
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func dropIfAbandoned(_ index: Int) {
        guard jobs[index].waiters.isEmpty else { return }
        jobs.remove(at: index).task?.cancel()
    }

    private func complete(_ id: UUID, result: Result<CGImage, any Error>) {
        if running == id { running = nil }
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            let job = jobs.remove(at: index)
            if case let .success(image) = result { insert(image, for: job.request) }
            for waiter in job.waiters.values {
                waiter.continuation.resume(with: result)
            }
        }
        admit()
    }

    func insert(_ image: CGImage, for request: ShellSettingsPreview.Request) {
        if let index = entries.firstIndex(where: { $0.0 == request }) {
            let removed = entries.remove(at: index).1
            retainedBytes -= removed.bytesPerRow * removed.height
        }
        entries.append((request, image))
        retainedBytes += image.bytesPerRow * image.height
        while entries.count > 12 || retainedBytes > Self.maximumBytes {
            let removed = entries.removeFirst().1
            retainedBytes -= removed.bytesPerRow * removed.height
        }
    }
}
