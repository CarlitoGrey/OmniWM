// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

final class HiddenBarMenuGuardTests: XCTestCase {
    private let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

    func testPopUpWindowOwnedByMenuOwnerDetected() {
        XCTAssertTrue(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [.init(layer: popUpLevel, ownerPID: 500, title: nil)],
                menuOwnerPIDs: [500]
            )
        )
    }

    func testOwnPopUpWindowsIgnored() {
        XCTAssertFalse(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [
                    .init(layer: popUpLevel, ownerPID: 42, title: nil),
                    .init(layer: popUpLevel, ownerPID: 42, title: nil)
                ],
                menuOwnerPIDs: [500]
            )
        )
    }

    func testStatusAndNormalLayersIgnored() {
        XCTAssertFalse(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [
                    .init(layer: 25, ownerPID: 500, title: nil),
                    .init(layer: 0, ownerPID: 500, title: nil)
                ],
                menuOwnerPIDs: [500]
            )
        )
    }

    func testLevelBelowPopUpDetected() {
        XCTAssertTrue(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [.init(layer: popUpLevel - 1, ownerPID: 500, title: nil)],
                menuOwnerPIDs: [500]
            )
        )
    }

    func testTitledPopUpWindowIgnored() {
        XCTAssertFalse(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [.init(layer: popUpLevel, ownerPID: 500, title: "Item-0")],
                menuOwnerPIDs: [500]
            )
        )
    }

    func testEmptyTitleCountsAsCandidate() {
        XCTAssertTrue(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [.init(layer: popUpLevel, ownerPID: 500, title: "")],
                menuOwnerPIDs: [500]
            )
        )
    }

    func testNativePanelDefersRehideUntilOnlyItsStatusItemRemains() {
        let menuBar = CGRect(x: 0, y: 0, width: 2560, height: 24)
        let item = HiddenBarMenuGuard.WindowInfo(
            layer: Int(CGWindowLevelForKey(.statusWindow)), ownerPID: 500, title: nil,
            bounds: CGRect(x: 2400, y: 0, width: 28, height: 24)
        )
        for title in [nil, "Native panel"] {
            let panel = HiddenBarMenuGuard.WindowInfo(
                layer: item.layer, ownerPID: item.ownerPID, title: title,
                bounds: CGRect(x: 2150, y: 24, width: 280, height: 180)
            )
            XCTAssertTrue(HiddenBarMenuGuard.isMenuOpen(
                windows: [item, panel], menuOwnerPIDs: [500], menuBarFrames: [menuBar]
            ))
        }
        XCTAssertFalse(HiddenBarMenuGuard.isMenuOpen(
            windows: [item], menuOwnerPIDs: [500], menuBarFrames: [menuBar]
        ))
    }

    func testNativePanelGuardKeepsOwnerAndLayerChecks() {
        let bounds = CGRect(x: 2150, y: 24, width: 280, height: 180)
        let menuBar = CGRect(x: 0, y: 0, width: 2560, height: 24)
        for window in [
            HiddenBarMenuGuard.WindowInfo(
                layer: Int(CGWindowLevelForKey(.statusWindow)), ownerPID: 42, title: nil, bounds: bounds
            ),
            HiddenBarMenuGuard.WindowInfo(layer: 0, ownerPID: 500, title: nil, bounds: bounds)
        ] {
            XCTAssertFalse(HiddenBarMenuGuard.isMenuOpen(
                windows: [window], menuOwnerPIDs: [500], menuBarFrames: [menuBar]
            ))
        }
    }

    @MainActor
    func testMenuBarFrameUsesThicknessNotchAndVisibleFrameGap() {
        let frame = CGRect(x: -1680, y: 1000, width: 1680, height: 1050)
        let reservations: [(gap: CGFloat, safeAreaTop: CGFloat, height: CGFloat)] = [
            (0, 0, 24), (0, 38, 38), (40, 38, 40)
        ]
        for (gap, safeAreaTop, height) in reservations {
            let visibleFrame = CGRect(
                x: frame.minX, y: frame.minY + 50, width: frame.width, height: frame.height - 50 - gap
            )
            let expected = CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
            XCTAssertEqual(
                MenuBarItemService.menuBarFrame(
                    frame: frame, visibleFrame: visibleFrame, safeAreaTop: safeAreaTop, thickness: 24
                ),
                ScreenCoordinateSpace.toWindowServer(rect: expected),
                "gap=\(gap), safeAreaTop=\(safeAreaTop)"
            )
        }
    }

    func testStatusItemsOnNotchedAndOffsetDisplaysDoNotDeferRehide() {
        let menuBars = [
            CGRect(x: 0, y: 0, width: 2560, height: 24),
            CGRect(x: 2560, y: -1050, width: 1680, height: 38)
        ]
        let items = menuBars.map { bar in
            HiddenBarMenuGuard.WindowInfo(
                layer: Int(CGWindowLevelForKey(.statusWindow)), ownerPID: 500, title: nil,
                bounds: CGRect(x: bar.maxX - 50, y: bar.minY, width: 28, height: bar.height)
            )
        }
        XCTAssertFalse(HiddenBarMenuGuard.isMenuOpen(
            windows: items, menuOwnerPIDs: [500], menuBarFrames: menuBars
        ))
        let panel = HiddenBarMenuGuard.WindowInfo(
            layer: items[1].layer, ownerPID: 500, title: nil,
            bounds: CGRect(x: 3900, y: -1012, width: 280, height: 180)
        )
        XCTAssertTrue(HiddenBarMenuGuard.isMenuOpen(
            windows: items + [panel], menuOwnerPIDs: [500], menuBarFrames: menuBars
        ))
    }

    func testEmptyOwnerSetShortCircuits() {
        XCTAssertFalse(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [.init(layer: popUpLevel, ownerPID: 500, title: nil)],
                menuOwnerPIDs: []
            )
        )
    }

    func testMixedWindowsAnyMatchWins() {
        XCTAssertTrue(
            HiddenBarMenuGuard.isMenuOpen(
                windows: [
                    .init(layer: popUpLevel, ownerPID: 42, title: nil),
                    .init(layer: popUpLevel, ownerPID: 500, title: nil)
                ],
                menuOwnerPIDs: [500]
            )
        )
    }
}
