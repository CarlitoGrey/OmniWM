// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import SwiftUI
import XCTest

@MainActor
final class ShellWidgetSlotTests: XCTestCase {
    func testSlotHostsTheReplacementSurfaceView() {
        let widget = WorkspaceBarShellWidget(id: "clock", size: CGSize(width: 40, height: 20), lane: .trailing)
        let first = NSView()
        let replacement = NSView()
        let host = NSHostingView(rootView: ShellWidgetSlot(widget: widget, view: first))
        host.frame = CGRect(x: 0, y: 0, width: 80, height: 24)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(first.isDescendant(of: host))

        host.rootView = ShellWidgetSlot(widget: widget, view: replacement)
        host.layoutSubtreeIfNeeded()

        XCTAssertTrue(replacement.isDescendant(of: host))
        XCTAssertFalse(first.isDescendant(of: host))
    }
}
