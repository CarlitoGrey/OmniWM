// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class ShellWidgetLibraryAvailabilityTests: XCTestCase {
    private var entry: ShellDesktopEditor.LibraryEntry {
        .init(name: "clock", title: "Clock", icon: "clock", summary: "Clock fixture")
    }

    func testDrawerAddRequiresAConfirmedAvailablePanel() {
        for panel in [nil, .missing, .failed("broken fixture")] as [ShellSettingsPreview.Panel?] {
            XCTAssertFalse(ShellWidgetLibrary.available(entry, panel: panel, target: .drawer("tools")))
        }
        XCTAssertTrue(ShellWidgetLibrary.available(entry, panel: .available, target: .drawer("tools")))
    }

    func testBarAndIslandAddIgnoreThePanelResult() {
        for target in [ShellDesktopEditor.LibraryTarget.bar, .island] {
            for panel in [nil, .available, .missing, .failed("broken fixture")] as [ShellSettingsPreview.Panel?] {
                XCTAssertTrue(ShellWidgetLibrary.available(entry, panel: panel, target: target))
            }
        }
    }

    func testAnUnavailableEntryCannotBeAddedToAnyTarget() {
        var unavailable = entry
        unavailable.available = false
        unavailable.problem = "Invalid descriptor fixture"
        for target in [ShellDesktopEditor.LibraryTarget.bar, .island, .drawer("tools")] {
            XCTAssertFalse(ShellWidgetLibrary.available(unavailable, panel: .available, target: target))
        }
    }
}
