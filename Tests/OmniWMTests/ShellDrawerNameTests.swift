// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

final class ShellDrawerNameTests: XCTestCase {
    func testNamesRejectEveryUnreachableOrAmbiguousClass() {
        for name in [
            "",
            " ",
            ".",
            ".tools",
            "tools.",
            "a.b",
            "two words",
            "a\tb",
            "a\nb",
            "a/b",
            "a\\b",
            "a:b",
            "a\0b"
        ] {
            XCTAssertNotNil(ShellDrawerName.problem(name, drawers: [], widgets: []), name.debugDescription)
        }
        XCTAssertNotNil(ShellDrawerName.problem(String(repeating: "a", count: 65), drawers: [], widgets: []))
        XCTAssertNotNil(ShellDrawerName.problem(String(repeating: "é", count: 33), drawers: [], widgets: []))
        XCTAssertNotNil(ShellDrawerName.problem("tools", drawers: ["tools"], widgets: []))
        XCTAssertNotNil(ShellDrawerName.problem("clock", drawers: [], widgets: ["clock"]))
    }

    func testTrimmingAndUtf8BoundariesAcceptReachableNames() {
        XCTAssertEqual(ShellDrawerName.normalized(" \n tools \t"), "tools")
        for name in [
            "tools",
            "my-tools_2",
            " Tools ",
            String(repeating: "a", count: 64),
            String(repeating: "é", count: 32)
        ] {
            XCTAssertNil(ShellDrawerName.problem(name, drawers: [], widgets: []), name)
        }
        XCTAssertFalse(ShellDrawerName.editable("a.b"))
        XCTAssertTrue(ShellDrawerName.editable("tools"))
    }
}
