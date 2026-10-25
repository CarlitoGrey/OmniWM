// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class ShellSettingsPanelCacheTests: XCTestCase {
    func testEqualProbeRequestsJoinAndCacheTheCompletedResults() async throws {
        let worker = Worker()
        let cache = ShellSettingsPreviewCache(render: worker.render, probe: worker.probe)
        let first = await submit { try await cache.panels(for: self.request()) }
        await worker.waitForStarts(1)
        let second = await submit { try await cache.panels(for: self.request()) }
        worker.finishProbe(0, .success(["sample": .available]))
        let firstResult = try await first.value
        let secondResult = try await second.value
        let cached = try await cache.panels(for: request())
        XCTAssertEqual(firstResult, ["sample": .available])
        XCTAssertEqual(secondResult, firstResult)
        XCTAssertEqual(cached, firstResult)
        XCTAssertEqual(worker.starts, ["probe-0"])
    }

    func testFailedCandidateResultsAreRetriedInsteadOfBecomingPermanentCapabilities() async throws {
        var calls = 0
        let cache = ShellSettingsPreviewCache(probe: { _ in
            calls += 1
            return ["sample": calls == 1 ? .failed("temporary load error") : .available]
        })
        let first = try await cache.panels(for: request())
        let retry = try await cache.panels(for: request())
        XCTAssertEqual(first, ["sample": .failed("temporary load error")])
        XCTAssertEqual(retry, ["sample": .available])
        XCTAssertEqual(calls, 2)
    }

    func testLastCancelledProbeKeepsAdmissionUntilItDrainsAndNeverPublishesItsLateResult() async throws {
        let worker = Worker()
        let cache = ShellSettingsPreviewCache(render: worker.render, probe: worker.probe)
        let abandoned = await submit { try await cache.panels(for: self.request()) }
        await worker.waitForStarts(1)
        abandoned.cancel()
        await assertCancelled(abandoned)
        await worker.waitForCancellations(1)
        let image = await submit { try await cache.image(for: self.imageRequest(surface: .drawer("tools"))) }
        let retry = await submit { try await cache.panels(for: self.request()) }
        XCTAssertEqual(worker.starts, ["probe-0"])
        worker.finishProbe(0, .success(["sample": .missing]))
        await worker.waitForStarts(2)
        XCTAssertEqual(worker.starts, ["probe-0", "image"])
        worker.finishImage(1, try bitmap())
        _ = try await image.value
        await worker.waitForStarts(3)
        XCTAssertEqual(worker.starts, ["probe-0", "image", "probe-0"])
        worker.finishProbe(2, .success(["sample": .available]))
        let result = try await retry.value
        XCTAssertEqual(result, ["sample": .available])
        XCTAssertEqual(worker.maximumActive, 1)
    }

    func testCancellingOneSharedProbeConsumerPreservesTheOther() async throws {
        let worker = Worker()
        let cache = ShellSettingsPreviewCache(render: worker.render, probe: worker.probe)
        let first = await submit { try await cache.panels(for: self.request()) }
        await worker.waitForStarts(1)
        let second = await submit { try await cache.panels(for: self.request()) }
        first.cancel()
        await assertCancelled(first)
        XCTAssertEqual(worker.cancellations, 0)
        worker.finishProbe(0, .success(["sample": .missing]))
        let result = try await second.value
        XCTAssertEqual(result, ["sample": .missing])
        let cached = try await cache.panels(for: request())
        XCTAssertEqual(cached, result)
        XCTAssertEqual(worker.starts.count, 1)
    }

    func testQueuedMainAndThumbnailImagesBothRunBeforeQueuedProbes() async throws {
        let worker = Worker()
        let cache = ShellSettingsPreviewCache(render: worker.render, probe: worker.probe)
        let blocker = await submit { try await cache.panels(for: self.request()) }
        await worker.waitForStarts(1)
        let queued = await submit { try await cache.panels(for: self.request(1)) }
        let thumbnail = await submit {
            try await cache.image(for: self.imageRequest(), slot: .init(id: "thumbnail", priority: .thumbnail))
        }
        let main = await submit {
            try await cache.image(for: self.imageRequest(surface: .drawer("tools")), slot: .init(id: "main"))
        }
        worker.finishProbe(0, .success(["sample": .available]))
        _ = try await blocker.value
        await worker.waitForStarts(2)
        XCTAssertEqual(worker.imageRequests.last?.surface, .drawer("tools"))
        worker.finishImage(1, try bitmap())
        _ = try await main.value
        await worker.waitForStarts(3)
        XCTAssertEqual(worker.imageRequests.last?.surface, .bar)
        worker.finishImage(2, try bitmap())
        _ = try await thumbnail.value
        await worker.waitForStarts(4)
        XCTAssertEqual(worker.starts, ["probe-0", "image", "image", "probe-1"])
        worker.finishProbe(3, .success(["sample": .missing]))
        _ = try await queued.value
        XCTAssertEqual(worker.maximumActive, 1)
    }

    func testProbeFailureReleasesAdmissionAndAllowsTheSameRequestToRetry() async throws {
        let worker = Worker()
        let cache = ShellSettingsPreviewCache(render: worker.render, probe: worker.probe)
        let failed = await submit { try await cache.panels(for: self.request()) }
        await worker.waitForStarts(1)
        let queued = await submit { try await cache.image(for: self.imageRequest()) }
        worker.finishProbe(0, .failure(Failure.load))
        guard case .failure(is Failure) = await failed.result else {
            return XCTFail("Probe error was not delivered")
        }
        await worker.waitForStarts(2)
        worker.finishImage(1, try bitmap())
        _ = try await queued.value
        let retry = await submit { try await cache.panels(for: self.request()) }
        await worker.waitForStarts(3)
        worker.finishProbe(2, .success(["sample": .available]))
        let result = try await retry.value
        XCTAssertEqual(result, ["sample": .available])
        XCTAssertEqual(worker.maximumActive, 1)
    }

    func testCapabilityRecordsAreAnIndependentTwelveEntryLRUAndGenerationInvalidates() async throws {
        var generations: [UInt64] = []
        let cache = ShellSettingsPreviewCache(probe: { request in
            generations.append(request.sourceGeneration)
            return ["sample": .available]
        })
        for generation in 0 ..< 12 {
            _ = try await cache.panels(for: request(UInt64(generation)))
        }
        _ = try await cache.panels(for: request())
        _ = try await cache.panels(for: request(12))
        _ = try await cache.panels(for: request())
        XCTAssertEqual(generations, Array(0 ... 12).map(UInt64.init))
        _ = try await cache.panels(for: request(1))
        XCTAssertEqual(generations.last, 1)
        XCTAssertEqual(generations.count, 14)
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.retainedBytes, 0)
    }

    func testHoverAndWidgetSettingsReuseCapabilitiesWithoutAnotherProbe() async throws {
        var calls = 0
        let cache = ShellSettingsPreviewCache(probe: { _ in
            calls += 1
            return ["sample": .available]
        })
        var config = ShellConfig()
        config.drawers = [.init(id: "tools", edge: .left, widgets: ["sample"], hover: false)]
        let original = ShellSettingsPreview.PanelRequest(names: ["sample"], config: config, sourceGeneration: 4)
        _ = try await cache.panels(for: original)
        config.drawers = [.init(id: "tools", edge: .bottom, widgets: ["sample"], hover: true)]
        config.drawers[0].reach = 72
        config.drawers[0].width = 350
        config.widgetSettings["sample"] = [1, 2, 3]
        let edited = ShellSettingsPreview.PanelRequest(names: ["sample"], config: config, sourceGeneration: 4)
        XCTAssertEqual(original, edited)
        let result = try await cache.panels(for: edited)
        XCTAssertEqual(result, ["sample": .available])
        XCTAssertEqual(calls, 1)
    }

    func testDrawersToIslandCancellationDrainsTheDrawerAndPublishesOnlyTheIsland() async throws {
        let worker = Worker()
        let cache = ShellSettingsPreviewCache(render: worker.render, probe: worker.probe)
        let drawer = await submit {
            try await cache.image(for: self.imageRequest(surface: .drawer("tools")), slot: .init(id: "editor-drawer"))
        }
        await worker.waitForStarts(1)
        drawer.cancel()
        await assertCancelled(drawer)
        await worker.waitForCancellations(1)
        let islandRequest = imageRequest(surface: .island(expanded: true))
        let island = await submit { try await cache.image(for: islandRequest, slot: .init(id: "editor-island")) }
        XCTAssertEqual(worker.starts.count, 1)
        let stale = try bitmap(4)
        let selected = try bitmap(8)
        worker.finishImage(0, stale)
        await worker.waitForStarts(2)
        XCTAssertEqual(cache.count, 0)
        worker.finishImage(1, selected)
        let delivered = try await island.value
        let cached = try await cache.image(for: islandRequest)
        XCTAssertTrue(delivered === selected)
        XCTAssertTrue(cached === selected)
        XCTAssertFalse(delivered === stale)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(worker.maximumActive, 1)
    }

    private func request(_ generation: UInt64 = 0) -> ShellSettingsPreview.PanelRequest {
        .init(names: ["sample"], config: ShellConfig(), sourceGeneration: generation)
    }

    private func imageRequest(surface: ShellSettingsPreview.Surface = .bar) -> ShellSettingsPreview.Request {
        .init(
            config: ShellConfig(),
            surface: surface,
            style: .init(),
            scale: 1,
            dark: false,
            fullWidth: false,
            sourceGeneration: 0
        )
    }

    private func bitmap(_ side: Int = 8) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func submit<Value: Sendable>(
        _ action: @escaping @MainActor () async throws -> Value
    ) async -> Task<Value, any Error> {
        let registered = Signal()
        let task = Task {
            Task { @MainActor in registered.signal() }
            return try await action()
        }
        await registered.wait()
        return task
    }

    private func assertCancelled<Value: Sendable>(_ task: Task<Value, any Error>) async {
        guard case .failure(is CancellationError) = await task.result else {
            return XCTFail("Cancelled consumer did not receive CancellationError")
        }
    }

    private enum Failure: Error {
        case load
    }

    @MainActor
    private final class Worker {
        private var imageCalls: [Int: CheckedContinuation<CGImage, any Error>] = [:]
        private var probeCalls: [Int: CheckedContinuation<[String: ShellSettingsPreview.Panel], any Error>] = [:]
        private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var cancelWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var active = 0
        private(set) var starts: [String] = []
        private(set) var imageRequests: [ShellSettingsPreview.Request] = []
        private(set) var maximumActive = 0
        private(set) var cancellations = 0

        func render(_ request: ShellSettingsPreview.Request) async throws -> CGImage {
            active += 1
            maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    imageRequests.append(request)
                    imageCalls[starts.count] = continuation
                    started("image")
                }
            } onCancel: {
                Task { @MainActor in self.cancelled() }
            }
        }

        func probe(_ request: ShellSettingsPreview.PanelRequest) async throws -> [String: ShellSettingsPreview.Panel] {
            active += 1
            maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    probeCalls[starts.count] = continuation
                    started("probe-\(request.sourceGeneration)")
                }
            } onCancel: {
                Task { @MainActor in self.cancelled() }
            }
        }

        func waitForStarts(_ count: Int) async {
            if starts.count >= count { return }
            await withCheckedContinuation { startWaiters.append((count, $0)) }
        }

        func waitForCancellations(_ count: Int) async {
            if cancellations >= count { return }
            await withCheckedContinuation { cancelWaiters.append((count, $0)) }
        }

        func finishImage(_ index: Int, _ image: CGImage) {
            imageCalls.removeValue(forKey: index)?.resume(returning: image)
        }

        func finishProbe(_ index: Int, _ result: Result<[String: ShellSettingsPreview.Panel], any Error>) {
            probeCalls.removeValue(forKey: index)?.resume(with: result)
        }

        private func started(_ label: String) {
            starts.append(label)
            let ready = startWaiters.filter { starts.count >= $0.0 }
            startWaiters.removeAll { starts.count >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }

        private func cancelled() {
            cancellations += 1
            let ready = cancelWaiters.filter { cancellations >= $0.0 }
            cancelWaiters.removeAll { cancellations >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
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
