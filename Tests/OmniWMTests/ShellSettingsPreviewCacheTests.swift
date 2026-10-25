// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class ShellSettingsPreviewCacheTests: XCTestCase {
    func testEqualConcurrentRequestsShareRenderingAndCompletedImage() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let request = request()
        let image = try image()
        let first = await submit(cache, request)
        await renderer.waitForCalls(1)
        let second = await submit(cache, request)
        renderer.finish(0, result: .success(image))
        let firstImage = try await first.value
        let secondImage = try await second.value
        XCTAssertTrue(firstImage === image)
        XCTAssertTrue(secondImage === image)
        let cachedImage = try await cache.image(for: request)
        XCTAssertTrue(cachedImage === image)
        XCTAssertEqual(renderer.count, 1)
        XCTAssertEqual(cache.count, 1)
    }

    func testCancelledWaiterReturnsBeforeRenderingFinishesAndPreservesOtherConsumer() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let request = request()
        let first = await submit(cache, request)
        await renderer.waitForCalls(1)
        let second = await submit(cache, request)
        first.cancel()
        await assertCancelled(first)
        XCTAssertEqual(renderer.count, 1)
        XCTAssertEqual(renderer.cancellations, 0)
        let image = try image()
        renderer.finish(0, result: .success(image))
        let secondImage = try await second.value
        XCTAssertTrue(secondImage === image)
        XCTAssertEqual(cache.count, 1)
    }

    func testLastConsumerCancellationHoldsAdmissionUntilTheAbandonedRenderReturns() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let request = request()
        let first = await submit(cache, request)
        await renderer.waitForCalls(1)
        first.cancel()
        await assertCancelled(first)
        await renderer.waitForCancellations(1)
        XCTAssertEqual(cache.count, 0)
        let second = await submit(cache, request)
        XCTAssertEqual(renderer.count, 1)
        let old = try image(4)
        let replacement = try image(8)
        renderer.finish(0, result: .success(old))
        await renderer.waitForCalls(2)
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(renderer.maximumActive, 1)
        renderer.finish(1, result: .success(replacement))
        let secondImage = try await second.value
        let cachedImage = try await cache.image(for: request)
        XCTAssertTrue(secondImage === replacement)
        XCTAssertTrue(cachedImage === replacement)
        XCTAssertEqual(renderer.count, 2)
        XCTAssertEqual(cache.count, 1)
    }

    func testSharedFailureClearsPendingRenderAndAllowsRetry() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let request = request()
        let first = await submit(cache, request)
        await renderer.waitForCalls(1)
        let second = await submit(cache, request)
        let queuedRequest = self.request(1)
        let queued = await submit(cache, queuedRequest)
        XCTAssertEqual(renderer.count, 1)
        renderer.finish(0, result: .failure(Failure.render))
        for result in [await first.result, await second.result] {
            guard case let .failure(error) = result, error is Failure else {
                XCTFail("Consumers did not share the render failure")
                continue
            }
        }
        await renderer.waitForCalls(2)
        XCTAssertEqual(renderer.requests, [request, queuedRequest])
        XCTAssertEqual(cache.count, 0)
        let image = try image()
        renderer.finish(1, result: .success(image))
        _ = try await queued.value
        let retry = await submit(cache, request)
        await renderer.waitForCalls(3)
        renderer.finish(2, result: .success(image))
        let retryImage = try await retry.value
        XCTAssertTrue(retryImage === image)
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(renderer.maximumActive, 1)
    }

    func testDifferentSourceGenerationsKeepContentAndImagesSeparateWithSequentialAdmission() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let firstRequest = request()
        let secondRequest = request(1)
        XCTAssertNotEqual(firstRequest, secondRequest)
        let first = await submit(cache, firstRequest)
        await renderer.waitForCalls(1)
        let second = await submit(cache, secondRequest)
        XCTAssertEqual(renderer.count, 1)
        let firstImage = try image(4)
        let secondImage = try image(8)
        renderer.finish(0, result: .success(firstImage))
        await renderer.waitForCalls(2)
        XCTAssertEqual(renderer.requests, [firstRequest, secondRequest])
        renderer.finish(1, result: .success(secondImage))
        let renderedFirst = try await first.value
        let renderedSecond = try await second.value
        XCTAssertTrue(renderedFirst === firstImage)
        XCTAssertTrue(renderedSecond === secondImage)
        let cachedFirst = try await cache.image(for: firstRequest)
        let cachedSecond = try await cache.image(for: secondRequest)
        XCTAssertTrue(cachedFirst === firstImage)
        XCTAssertTrue(cachedSecond === secondImage)
        XCTAssertEqual(renderer.maximumActive, 1)
        XCTAssertEqual(cache.count, 2)
    }

    func testBlockedSlotBurstStartsOnlyTheLatestRequestAndCancelsEverySupersededWaiter() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let blocker = await submit(cache, request())
        await renderer.waitForCalls(1)
        let slot = ShellSettingsPreviewCache.Slot(id: "main")
        let first = await submit(cache, request(1), slot: slot)
        let second = await submit(cache, request(2), slot: slot)
        let latest = await submit(cache, request(3), slot: slot)
        await assertCancelled(first)
        await assertCancelled(second)
        XCTAssertEqual(renderer.requests, [request()])
        let image = try image()
        renderer.finish(0, result: .success(image))
        _ = try await blocker.value
        await renderer.waitForCalls(2)
        XCTAssertEqual(renderer.requests, [request(), request(3)])
        renderer.finish(1, result: .success(image))
        let latestImage = try await latest.value
        XCTAssertTrue(latestImage === image)
        XCTAssertEqual(renderer.maximumActive, 1)
    }

    func testMainRequestsRunBeforeQueuedThumbnailsAndEqualPrioritiesRemainFIFO() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let blocker = await submit(cache, request())
        await renderer.waitForCalls(1)
        let firstThumbnail = await submit(cache, request(1), slot: .init(id: "first", priority: .thumbnail))
        let secondThumbnail = await submit(cache, request(2), slot: .init(id: "second", priority: .thumbnail))
        let main = await submit(cache, request(3), slot: .init(id: "main"))
        XCTAssertEqual(renderer.count, 1)
        let image = try image()
        renderer.finish(0, result: .success(image))
        _ = try await blocker.value
        await renderer.waitForCalls(2)
        XCTAssertEqual(renderer.requests.last, request(3))
        renderer.finish(1, result: .success(image))
        _ = try await main.value
        await renderer.waitForCalls(3)
        XCTAssertEqual(renderer.requests.last, request(1))
        renderer.finish(2, result: .success(image))
        _ = try await firstThumbnail.value
        await renderer.waitForCalls(4)
        XCTAssertEqual(renderer.requests.last, request(2))
        renderer.finish(3, result: .success(image))
        _ = try await secondThumbnail.value
        XCTAssertEqual(renderer.maximumActive, 1)
    }

    func testMainWaiterPromotesQueuedThumbnailAndSharesItsSingleRender() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let blocker = await submit(cache, request())
        await renderer.waitForCalls(1)
        let earlier = await submit(cache, request(1), slot: .init(id: "earlier", priority: .thumbnail))
        let thumbnail = await submit(cache, request(2), slot: .init(id: "shared", priority: .thumbnail))
        let main = await submit(cache, request(2), slot: .init(id: "main"))
        let image = try image()
        renderer.finish(0, result: .success(image))
        _ = try await blocker.value
        await renderer.waitForCalls(2)
        XCTAssertEqual(renderer.requests.last, request(2))
        renderer.finish(1, result: .success(image))
        let thumbnailImage = try await thumbnail.value
        let mainImage = try await main.value
        XCTAssertTrue(thumbnailImage === image)
        XCTAssertTrue(mainImage === image)
        await renderer.waitForCalls(3)
        XCTAssertEqual(renderer.requests.last, request(1))
        renderer.finish(2, result: .success(image))
        _ = try await earlier.value
        XCTAssertEqual(renderer.requests, [request(), request(2), request(1)])
    }

    func testReplacingOneOfTwoSlotsKeepsTheOtherWaiterAndSharedRender() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let blocker = await submit(cache, request())
        await renderer.waitForCalls(1)
        let firstSlot = ShellSettingsPreviewCache.Slot(id: "first")
        let first = await submit(cache, request(1), slot: firstSlot)
        let second = await submit(cache, request(1), slot: .init(id: "second"))
        let replacement = await submit(cache, request(2), slot: firstSlot)
        await assertCancelled(first)
        let image = try image()
        renderer.finish(0, result: .success(image))
        _ = try await blocker.value
        await renderer.waitForCalls(2)
        XCTAssertEqual(renderer.requests.last, request(1))
        renderer.finish(1, result: .success(image))
        let secondImage = try await second.value
        XCTAssertTrue(secondImage === image)
        await renderer.waitForCalls(3)
        XCTAssertEqual(renderer.requests.last, request(2))
        renderer.finish(2, result: .success(image))
        _ = try await replacement.value
        XCTAssertEqual(renderer.cancellations, 0)
    }

    func testSameSlotJoiningTheRunningRequestKeepsItsRenderAlive() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let slot = ShellSettingsPreviewCache.Slot(id: "main")
        let first = await submit(cache, request(), slot: slot)
        await renderer.waitForCalls(1)
        let replacement = await submit(cache, request(), slot: slot)
        await assertCancelled(first)
        XCTAssertEqual(renderer.cancellations, 0)
        let image = try image()
        renderer.finish(0, result: .success(image))
        let replacementImage = try await replacement.value
        XCTAssertTrue(replacementImage === image)
        XCTAssertEqual(renderer.count, 1)
    }

    func testCacheHitDetachesTheSlotsOlderQueuedWaiter() async throws {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let cachedRequest = request(9)
        let cached = try image(4)
        cache.insert(cached, for: cachedRequest)
        let blocker = await submit(cache, request())
        await renderer.waitForCalls(1)
        let slot = ShellSettingsPreviewCache.Slot(id: "main")
        let stale = await submit(cache, request(1), slot: slot)
        let hit = try await cache.image(for: cachedRequest, slot: slot)
        XCTAssertTrue(hit === cached)
        await assertCancelled(stale)
        let image = try image()
        renderer.finish(0, result: .success(image))
        _ = try await blocker.value
        XCTAssertEqual(renderer.requests, [request()])
        XCTAssertEqual(cache.count, 2)
    }

    func testCancellationBeforeRegistrationDoesNotStartRendering() async {
        let renderer = Renderer()
        let cache = ShellSettingsPreviewCache(render: renderer.render)
        let request = request()
        let task = Task { try await cache.image(for: request) }
        task.cancel()
        guard case .failure(is CancellationError) = await task.result else {
            XCTFail("Cancelled request succeeded")
            return
        }
        XCTAssertEqual(renderer.count, 0)
        XCTAssertEqual(cache.count, 0)
    }

    func testCompletedCacheRetainsTwelveImagesAndTouchesHitsBeforeEviction() async throws {
        var renders = 0
        let image = try image()
        let cache = ShellSettingsPreviewCache { _ in
            renders += 1
            return image
        }
        for generation: UInt64 in 0 ..< 12 { cache.insert(image, for: request(generation)) }
        _ = try await cache.image(for: request(0))
        cache.insert(image, for: request(12))
        XCTAssertEqual(cache.count, 12)
        XCTAssertEqual(cache.retainedBytes, image.bytesPerRow * image.height * 12)
        _ = try await cache.image(for: request(0))
        XCTAssertEqual(renders, 0)
        _ = try await cache.image(for: request(1))
        XCTAssertEqual(renders, 1)
        XCTAssertEqual(cache.count, 12)
    }

    func testCompletedCachePreservesByteLimitAndAccountsForReplacements() throws {
        let image = try image(2048)
        let cache = ShellSettingsPreviewCache()
        for generation: UInt64 in 0 ..< 3 { cache.insert(image, for: request(generation)) }
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.retainedBytes, ShellSettingsPreviewCache.maximumBytes)
        let replacement = try self.image()
        cache.insert(replacement, for: request(2))
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(
            cache.retainedBytes,
            image.bytesPerRow * image.height + replacement.bytesPerRow * replacement.height
        )
    }

    private func request(_ sourceGeneration: UInt64 = 0) -> ShellSettingsPreview.Request {
        .init(
            config: ShellConfig(), surface: .bar, style: .init(), scale: 1,
            dark: false, fullWidth: false, sourceGeneration: sourceGeneration
        )
    }

    private func image(_ side: Int = 8) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func submit(
        _ cache: ShellSettingsPreviewCache, _ request: ShellSettingsPreview.Request,
        slot: ShellSettingsPreviewCache.Slot? = nil
    ) async -> Task<CGImage, any Error> {
        let registered = Signal()
        let task = Task {
            Task { @MainActor in registered.signal() }
            return try await cache.image(for: request, slot: slot)
        }
        await registered.wait()
        return task
    }

    private func assertCancelled(
        _ task: Task<CGImage, any Error>, file: StaticString = #filePath, line: UInt = #line
    ) async {
        guard case .failure(is CancellationError) = await task.result else {
            XCTFail("Superseded consumer did not receive CancellationError", file: file, line: line)
            return
        }
    }

    private enum Failure: Error {
        case render
    }

    @MainActor
    private final class Renderer {
        private var calls: [CheckedContinuation<CGImage, any Error>?] = []
        private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var cancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var active = 0
        private(set) var cancellations = 0
        private(set) var maximumActive = 0
        private(set) var requests: [ShellSettingsPreview.Request] = []

        var count: Int {
            calls.count
        }

        func render(_ request: ShellSettingsPreview.Request) async throws -> CGImage {
            active += 1
            maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    requests.append(request)
                    calls.append(continuation)
                    let ready = callWaiters.filter { calls.count >= $0.0 }
                    callWaiters.removeAll { calls.count >= $0.0 }
                    for (_, waiter) in ready { waiter.resume() }
                }
            } onCancel: {
                Task { @MainActor in
                    self.cancellations += 1
                    let ready = self.cancellationWaiters.filter { self.cancellations >= $0.0 }
                    self.cancellationWaiters.removeAll { self.cancellations >= $0.0 }
                    for (_, waiter) in ready { waiter.resume() }
                }
            }
        }

        func waitForCalls(_ count: Int) async {
            if calls.count >= count { return }
            await withCheckedContinuation { callWaiters.append((count, $0)) }
        }

        func waitForCancellations(_ count: Int) async {
            if cancellations >= count { return }
            await withCheckedContinuation { cancellationWaiters.append((count, $0)) }
        }

        func finish(_ index: Int, result: Result<CGImage, any Error>) {
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
