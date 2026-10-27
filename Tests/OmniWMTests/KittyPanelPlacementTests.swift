// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

final class KittyPanelPlacementTests: XCTestCase {
    func testRequestEncodesScreenScaleAndBarSeparatelyFromPreferences() throws {
        let context = KittyQuakeControlContext(
            settings: KittyQuakeSettings(autoHide: true, opacity: 0.4),
            screen: .init(
                frame: CGRect(x: -1440, y: -120, width: 1440, height: 900),
                visibleFrame: CGRect(x: -1440, y: -100, width: 1440, height: 856),
                scale: 2
            ),
            barBottom: 746.5
        )
        let data = try JSONEncoder().encode(KittyQuakeControlRequest(operation: .toggle, context: context))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["operation"] as? String, "toggle")
        XCTAssertEqual(payload["settings"] as? NSDictionary, ["autoHide": true, "opacity": 0.4] as NSDictionary)
        XCTAssertEqual(payload["barBottom"] as? Double, 746.5)
        XCTAssertEqual(payload["screen"] as? NSDictionary, [
            "frame": ["x": -1440, "y": -120, "width": 1440, "height": 900],
            "visibleFrame": ["x": -1440, "y": -100, "width": 1440, "height": 856],
            "scale": 2
        ] as NSDictionary)
    }

    func testNativePreferencesAndAbsentBarDoNotBecomeExplicitOverrides() throws {
        let context = KittyQuakeControlContext(
            settings: KittyQuakeSettings(),
            screen: .init(
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 580),
                scale: 1
            ),
            barBottom: nil
        )
        let data = try JSONEncoder().encode(KittyQuakeControlRequest(operation: .apply, context: context))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["operation"] as? String, "apply")
        XCTAssertEqual(payload["settings"] as? NSDictionary, NSDictionary())
        XCTAssertNil(payload["barBottom"])
        XCTAssertNil(payload["placement"])
        XCTAssertNil(payload["opacity"])
    }
}
