// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

final class ShellDesktopLaneLayoutTests: XCTestCase {
    func testTitleSizedChipsWrapAndKeepTheirOrder() {
        let frames = ShellDesktopLaneLayout.frames(
            sizes: [CGSize(width: 90, height: 30), CGSize(width: 50, height: 30), CGSize(width: 80, height: 30)],
            width: 160
        )
        XCTAssertEqual(frames, [
            CGRect(x: 0, y: 0, width: 90, height: 30),
            CGRect(x: 96, y: 0, width: 50, height: 30),
            CGRect(x: 0, y: 36, width: 80, height: 30)
        ])
    }

    func testOversizedChipFitsTheLaneAndNextChipStartsAnotherRow() {
        let frames = ShellDesktopLaneLayout.frames(
            sizes: [CGSize(width: 400, height: 30), CGSize(width: 50, height: 30)],
            width: 160
        )
        XCTAssertEqual(frames, [
            CGRect(x: 0, y: 0, width: 160, height: 30),
            CGRect(x: 0, y: 36, width: 50, height: 30)
        ])
        XCTAssertTrue(ShellDesktopLaneLayout.frames(sizes: [], width: 160).isEmpty)
    }

    func testInsertionUsesBothCoordinatesAcrossWrappedRows() {
        let frames = [
            CGRect(x: 70, y: 8, width: 90, height: 30),
            CGRect(x: 166, y: 8, width: 50, height: 30),
            CGRect(x: 70, y: 44, width: 80, height: 30),
            CGRect(x: 156, y: 44, width: 60, height: 30)
        ]
        for (point, index) in [
            (CGPoint(x: 20, y: 0), 0),
            (CGPoint(x: 100, y: 20), 0),
            (CGPoint(x: 140, y: 20), 1),
            (CGPoint(x: 210, y: 20), 2),
            (CGPoint(x: 300, y: 20), 2),
            (CGPoint(x: 300, y: 40), 2),
            (CGPoint(x: 90, y: 55), 2),
            (CGPoint(x: 140, y: 55), 3),
            (CGPoint(x: 210, y: 55), 4),
            (CGPoint(x: 20, y: 90), 4)
        ] {
            XCTAssertEqual(ShellDesktopLaneLayout.insertion(at: point, frames: frames), index, "\(point)")
        }
        XCTAssertEqual(ShellDesktopLaneLayout.insertion(at: .zero, frames: []), 0)
    }
}
