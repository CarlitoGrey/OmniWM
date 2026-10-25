// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
extension ShellDesktopEditorTests {
    func testQueuedDrawerMemberActionsKeepTheirProfileWhenTheStyleChanges() async throws {
        for moving in [false, true] {
            let fixture = try await drawerFixture()
            for profile in ["celestial", "lake"] {
                try await fixture.configuration.addDrawer("tools", edge: .right, widget: "clock", profile: profile)
                try await fixture.configuration.editDrawerWidgets("tools", profile: profile) { $0.append("weather") }
            }
            await fixture.editor.reload()
            let count = fixture.saves.count + 1
            if moving { fixture.editor.moveDrawerWidget("weather", in: "tools", to: 0) }
            else { fixture.editor.removeDrawerWidget("weather", from: "tools") }
            let switched = await fixture.editor.selectStyle("lake")
            XCTAssertTrue(switched)
            await fixture.saves.wait(count)
            let original = try await fixture.configuration.previewConfig(profile: "celestial")
            let next = try await fixture.configuration.previewConfig(profile: "lake")
            XCTAssertEqual(
                original.drawers.first { $0.id == "tools" }?.widgets,
                moving ? ["weather", "clock"] : ["clock"]
            )
            XCTAssertEqual(next.drawers.first { $0.id == "tools" }?.widgets, ["clock", "weather"])
            XCTAssertEqual(fixture.configuration.config.profile, "default")
        }
    }
}
