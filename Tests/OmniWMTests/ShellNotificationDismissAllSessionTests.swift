// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ShellNotificationDismissAllSessionTests: XCTestCase {
    private func requests() -> [ShellNotificationActionRequest] {
        let first = UUID()
        let sibling = UUID()
        let other = UUID()
        return [
            .init(bundle: "com.example.First", id: first, peers: [first, sibling], operation: .dismiss),
            .init(bundle: "com.example.Second", id: other, peers: [other], operation: .dismiss),
            .init(bundle: "com.example.First", id: sibling, peers: [first, sibling], operation: .dismiss)
        ]
    }

    func testPartialFailuresContinueInOrderWithinOneHistoryLifetime() {
        let requests = requests()
        var events: [String] = []
        var dismissed: [ShellNotificationActionRequest] = []
        let outcome = ShellNotificationDismissAll.perform(
            requests,
            begin: {
                events.append("begin")
                return nil
            },
            dismiss: { request in
                dismissed.append(request)
                events.append("dismiss:\(request.id)")
                return dismissed.count == 2 ? .notFound : .dispatched
            },
            finish: { outcome in
                events.append("finish:\(outcome.rawValue)")
                return outcome
            },
            progress: { events.append("progress:\($0.rawValue)") }
        )
        XCTAssertEqual(outcome, .dispatched)
        XCTAssertEqual(dismissed, requests)
        XCTAssertEqual(events, [
            "begin", "dismiss:\(requests[0].id)", "progress:dispatched",
            "dismiss:\(requests[1].id)", "progress:notFound",
            "dismiss:\(requests[2].id)", "progress:dispatched", "finish:dispatched"
        ])
    }

    func testBeginFailureStillFinishesWithoutDismissingAnyItem() {
        var events: [String] = []
        let outcome = ShellNotificationDismissAll.perform(
            requests(),
            begin: {
                events.append("begin")
                return .denied
            },
            dismiss: { _ in
                events.append("dismiss")
                return .dispatched
            },
            finish: { outcome in
                events.append("finish:\(outcome.rawValue)")
                return outcome
            },
            progress: { events.append("progress:\($0.rawValue)") }
        )
        XCTAssertEqual(outcome, .denied)
        XCTAssertEqual(events, ["begin", "finish:denied"])
    }

    func testCancellationAfterProgressStopsBeforeNextItemAndFinishesHistory() async {
        let requests = requests()
        let task = Task { @MainActor in
            var events: [String] = []
            let outcome = ShellNotificationDismissAll.perform(
                requests,
                begin: {
                    events.append("begin")
                    return nil
                },
                dismiss: { request in
                    events.append("dismiss:\(request.id)")
                    return .dispatched
                },
                finish: { outcome in
                    events.append("finish:\(outcome.rawValue)")
                    return outcome
                },
                progress: { outcome in
                    events.append("progress:\(outcome.rawValue)")
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            )
            return (outcome, events)
        }
        let (outcome, events) = await task.value
        XCTAssertTrue(task.isCancelled)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(events, [
            "begin", "dismiss:\(requests[0].id)", "progress:dispatched", "finish:cancelled"
        ])
    }

    func testAlreadyCancelledTaskPerformsNoNativeSessionWork() async {
        let requests = requests()
        let task = Task { @MainActor in
            var events: [String] = []
            let outcome = ShellNotificationDismissAll.perform(
                requests,
                begin: {
                    events.append("begin")
                    return nil
                },
                dismiss: { _ in
                    events.append("dismiss")
                    return .dispatched
                },
                finish: { outcome in
                    events.append("finish:\(outcome.rawValue)")
                    return outcome
                },
                progress: { events.append("progress:\($0.rawValue)") }
            )
            return (outcome, events)
        }
        task.cancel()
        let (outcome, events) = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(events.isEmpty)
    }

    func testHistoryCleanupOutcomeCannotBeReplacedWithAllClearSuccess() {
        var progress: [ShellNotificationActionOutcome] = []
        var finishes: [ShellNotificationActionOutcome] = []
        let requests = requests()
        let outcome = ShellNotificationDismissAll.perform(
            requests,
            begin: { nil },
            dismiss: { _ in .dispatched },
            finish: { outcome in
                finishes.append(outcome)
                return .dispatchedPanelOpen
            },
            progress: { progress.append($0) }
        )
        XCTAssertEqual(progress, Array(repeating: .dispatched, count: requests.count))
        XCTAssertEqual(finishes, [.dispatched])
        XCTAssertEqual(outcome, .dispatchedPanelOpen)
    }
}
