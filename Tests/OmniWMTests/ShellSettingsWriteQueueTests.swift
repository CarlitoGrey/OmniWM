// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class ShellSettingsWriteQueueTests: XCTestCase {
    func testBurstKeepsOneRunningWriteAndOnlyTheLatestPendingValue() async {
        let queue = ShellSettingsWriteQueue()
        let writer = Writer()
        let target = target()
        queue.submit(10, for: target, write: writer.write)
        await writer.waitForCalls(1)
        queue.submit(20, for: target, write: writer.write)
        queue.submit(30, for: target, write: writer.write)
        XCTAssertEqual(queue.value(for: target, as: Int.self), 30)
        XCTAssertEqual(writer.values, [10])
        writer.finish(0)
        await writer.waitForCalls(2)
        XCTAssertEqual(writer.values, [10, 30])
        writer.finish(1)
        let drained = await queue.drain()
        XCTAssertTrue(drained)
        XCTAssertEqual(writer.maximumActive, 1)
        XCTAssertNil(queue.value(for: target, as: Int.self))
        XCTAssertTrue(queue.failures.isEmpty)
    }

    func testTargetsDifferingOnlyByMonitorKeepIndependentPendingValues() async {
        let queue = ShellSettingsWriteQueue()
        let first = Writer()
        let second = Writer()
        let firstTarget = target(Monitor.ID(displayId: 94_611))
        let secondTarget = target(Monitor.ID(displayId: 94_612))
        queue.submit(10, for: firstTarget, write: first.write)
        queue.submit(20, for: secondTarget, write: second.write)
        await first.waitForCalls(1)
        await second.waitForCalls(1)
        queue.submit(11, for: firstTarget, write: first.write)
        queue.submit(21, for: secondTarget, write: second.write)
        first.finish(0)
        await first.waitForCalls(2)
        XCTAssertEqual(first.values, [10, 11])
        XCTAssertEqual(second.values, [20])
        second.finish(0)
        await second.waitForCalls(2)
        XCTAssertEqual(second.values, [20, 21])
        first.finish(1)
        second.finish(1)
        let drained = await queue.drain()
        XCTAssertTrue(drained)
        XCTAssertEqual(first.maximumActive, 1)
        XCTAssertEqual(second.maximumActive, 1)
    }

    func testDrainWaitsForBothRunningAndPendingWrites() async {
        let queue = ShellSettingsWriteQueue()
        let writer = Writer()
        let target = target()
        queue.submit(10, for: target, write: writer.write)
        await writer.waitForCalls(1)
        queue.submit(20, for: target, write: writer.write)
        let entered = Signal()
        var completed = false
        let drain = Task {
            entered.signal()
            let result = await queue.drain()
            completed = true
            return result
        }
        await entered.wait()
        XCTAssertFalse(completed)
        writer.finish(0)
        await writer.waitForCalls(2)
        XCTAssertFalse(completed)
        writer.finish(1)
        let drained = await drain.value
        XCTAssertTrue(drained)
        XCTAssertTrue(completed)
        XCTAssertEqual(writer.values, [10, 20])
    }

    func testFinalFailureRemainsUnsavedUntilRetrySucceeds() async {
        let queue = ShellSettingsWriteQueue()
        let writer = Writer()
        let target = target()
        queue.submit(30, for: target, write: writer.write)
        await writer.waitForCalls(1)
        writer.finish(0, result: .failure(Failure.write))
        let failed = await queue.drain()
        XCTAssertFalse(failed)
        XCTAssertEqual(queue.value(for: target, as: Int.self), 30)
        XCTAssertEqual(queue.failure(for: target), "Write failed")
        XCTAssertEqual(queue.failures, [target: "Write failed"])
        let stillFailed = await queue.drain()
        XCTAssertFalse(stillFailed)
        queue.retry(target)
        await writer.waitForCalls(2)
        XCTAssertNil(queue.failure(for: target))
        XCTAssertEqual(writer.values, [30, 30])
        writer.finish(1)
        let recovered = await queue.drain()
        XCTAssertTrue(recovered)
        XCTAssertNil(queue.value(for: target, as: Int.self))
        XCTAssertTrue(queue.failures.isEmpty)
    }

    func testDiscardClearsAFinalFailureWithoutWritingAgain() async {
        let queue = ShellSettingsWriteQueue()
        let writer = Writer()
        let target = target()
        queue.submit(30, for: target, write: writer.write)
        await writer.waitForCalls(1)
        queue.discard(target)
        XCTAssertEqual(queue.value(for: target, as: Int.self), 30)
        writer.finish(0, result: .failure(Failure.write))
        let failed = await queue.drain()
        XCTAssertFalse(failed)
        queue.discard(target)
        let drained = await queue.drain()
        XCTAssertTrue(drained)
        XCTAssertNil(queue.value(for: target, as: Int.self))
        XCTAssertTrue(queue.failures.isEmpty)
        XCTAssertEqual(writer.values, [30])
    }

    func testSupersededFailureIsNotReportedWhileTheLatestValueRuns() async {
        let queue = ShellSettingsWriteQueue()
        let writer = Writer()
        let target = target()
        queue.submit(10, for: target, write: writer.write)
        await writer.waitForCalls(1)
        queue.submit(20, for: target, write: writer.write)
        writer.finish(0, result: .failure(Failure.write))
        await writer.waitForCalls(2)
        XCTAssertNil(queue.failure(for: target))
        XCTAssertTrue(queue.failures.isEmpty)
        XCTAssertEqual(queue.value(for: target, as: Int.self), 20)
        writer.finish(1)
        let drained = await queue.drain()
        XCTAssertTrue(drained)
        XCTAssertEqual(writer.values, [10, 20])
    }

    private func target(_ monitor: Monitor.ID? = nil) -> ShellSettingsWriteQueue.Target {
        .init(profile: "lake", monitor: monitor, path: ["workspaceBar", "height"])
    }

    private enum Failure: LocalizedError {
        case write

        var errorDescription: String? {
            "Write failed"
        }
    }

    @MainActor
    private final class Writer {
        private var calls: [CheckedContinuation<Void, any Error>?] = []
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var active = 0
        private(set) var maximumActive = 0
        private(set) var values: [Int] = []

        func write(_ value: Int) async throws {
            active += 1
            maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            try await withCheckedThrowingContinuation { continuation in
                values.append(value)
                calls.append(continuation)
                let ready = waiters.filter { calls.count >= $0.0 }
                waiters.removeAll { calls.count >= $0.0 }
                for (_, waiter) in ready { waiter.resume() }
            }
        }

        func waitForCalls(_ count: Int) async {
            if calls.count >= count { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }

        func finish(_ index: Int, result: Result<Void, any Error> = .success(())) {
            let continuation = calls[index]
            calls[index] = nil
            continuation?.resume(with: result)
        }
    }

    @MainActor
    private final class Signal {
        private var signalled = false
        private var waiter: CheckedContinuation<Void, Never>?

        func signal() {
            signalled = true
            waiter?.resume()
            waiter = nil
        }

        func wait() async {
            if signalled { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }
}
