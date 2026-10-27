// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

final class ExternalQuakeDisplayTests: XCTestCase {
    func testPanelAreaKeepsAppKitPointsAndStopsAtTheTopBar() {
        let retina = display(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), scale: 2, bar: 912)
        XCTAssertEqual(retina.panelArea, CGRect(x: 0, y: 0, width: 1512, height: 912))

        let left = display(visibleFrame: CGRect(x: -1440, y: -100, width: 1440, height: 856), bar: 700)
        XCTAssertEqual(left.panelArea, CGRect(x: -1440, y: -100, width: 1440, height: 800))
        XCTAssertEqual(
            FootQuakeControlContext(
                settings: FootQuakeSettings(),
                area: left.panelArea ?? .zero,
                animationDuration: 0.2
            ).overrides.last,
            "macos-quake-area=-1440.0,-100.0,1440.0,800.0"
        )
    }

    func testPanelAreaWithoutABarOrWithABarAboveItUsesTheVisibleFrame() {
        let visible = CGRect(x: 1512, y: 25, width: 2560, height: 1390)
        XCTAssertEqual(display(visibleFrame: visible, bar: nil).panelArea, visible)
        XCTAssertEqual(display(visibleFrame: visible, bar: 2000).panelArea, visible)
    }

    func testPanelAreaRejectsNonfiniteOrEmptyGeometry() {
        for (visibleFrame, bar) in [
            (CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600), nil),
            (CGRect(x: 0, y: 0, width: 800, height: CGFloat.infinity), nil),
            (CGRect(x: 0, y: 0, width: 0, height: 600), nil),
            (CGRect(x: 0, y: -100, width: 800, height: 600), CGFloat(-200)),
            (CGRect(x: 0, y: 0, width: 800, height: 600), CGFloat(0)),
            (CGRect.null, nil)
        ] as [(CGRect, CGFloat?)] {
            XCTAssertNil(
                display(visibleFrame: visibleFrame, bar: bar).panelArea,
                "\(visibleFrame) \(String(describing: bar))"
            )
        }
    }

    func testMonitorSelectionPrefersThePointerMonitorThenTheMainOne() {
        let main = monitor(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isMain: true)
        let left = monitor(id: 2, frame: CGRect(x: -1440, y: -100, width: 1440, height: 900), isMain: false)

        XCTAssertEqual(ExternalQuakeDisplay.monitor(at: CGPoint(x: -20, y: 10), in: [main, left])?.id, left.id)
        XCTAssertEqual(ExternalQuakeDisplay.monitor(at: CGPoint(x: 20, y: 10), in: [left, main])?.id, main.id)
        XCTAssertNil(ExternalQuakeDisplay.monitor(at: .zero, in: []))
    }

    func testKittyContextFromTheSharedDisplayEncodesTheSameRequest() throws {
        let shared = ExternalQuakeDisplay(
            frame: CGRect(x: -1440, y: -120, width: 1440, height: 900),
            visibleFrame: CGRect(x: -1440, y: -100, width: 1440, height: 856),
            scale: 2,
            topBarBottom: 746.5
        )
        let settings = KittyQuakeSettings(autoHide: true, opacity: 0.4)
        let direct = KittyQuakeControlContext(
            settings: settings,
            screen: .init(frame: shared.frame, visibleFrame: shared.visibleFrame, scale: 2),
            barBottom: 746.5
        )

        for context in [direct, KittyQuakeControlContext(settings: settings, display: shared)] {
            let data = try JSONEncoder().encode(KittyQuakeControlRequest(operation: .toggle, context: context))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
            XCTAssertEqual(payload, [
                "operation": "toggle",
                "settings": ["autoHide": true, "opacity": 0.4],
                "screen": [
                    "frame": ["x": -1440, "y": -120, "width": 1440, "height": 900],
                    "visibleFrame": ["x": -1440, "y": -100, "width": 1440, "height": 856],
                    "scale": 2
                ],
                "barBottom": 746.5
            ] as NSDictionary)
        }
        let barless = ExternalQuakeDisplay(
            frame: shared.frame,
            visibleFrame: shared.visibleFrame,
            scale: 1,
            topBarBottom: nil
        )
        XCTAssertNil(KittyQuakeControlContext(settings: settings, display: barless).barBottom)
    }

    private func display(visibleFrame: CGRect, scale: CGFloat = 1, bar: CGFloat?) -> ExternalQuakeDisplay {
        ExternalQuakeDisplay(frame: visibleFrame, visibleFrame: visibleFrame, scale: scale, topBarBottom: bar)
    }

    private func monitor(id: CGDirectDisplayID, frame: CGRect, isMain: Bool) -> Monitor {
        Monitor(
            id: Monitor.ID(displayId: id),
            displayId: id,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Display \(id)",
            isMain: isMain
        )
    }
}
