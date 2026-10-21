// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import Synchronization
import XCTest

final class InputTapThreadProviderTests: XCTestCase {
    func testReadingTouchCountProviderDoesNotDeepenItsCallStack() {
        let thread = InputTapThread()
        let base = Mutex<UInt>(0)
        let depth = Mutex<UInt>(0)
        thread.touchCountProvider = {
            let here = stackAddress()
            depth.withLock { $0 = base.withLock { $0 } &- here }
            return 0
        }
        func callDepth() -> UInt {
            base.withLock { $0 = stackAddress() }
            _ = thread.touchCountProvider?()
            return depth.withLock { $0 }
        }
        let first = callDepth()
        for _ in 0 ..< 1000 {
            _ = thread.touchCountProvider
        }
        XCTAssertEqual(callDepth(), first)
    }
}

@inline(never) private func stackAddress() -> UInt {
    var marker = 0
    return withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
}
