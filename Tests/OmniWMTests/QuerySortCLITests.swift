// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWMCtl
import OmniWMIPC
import XCTest

final class QuerySortCLITests: XCTestCase {
    func testWindowsQueryAcceptsSortMRUAlongsideSelectorsAndFields() throws {
        let request = try CLIQueryArguments.parse(
            arguments: ["windows", "--bundle-id", "com.apple.Safari", "--sort", "mru", "--fields", "id,focus-rank"]
        )
        XCTAssertEqual(request.sort, .mru)
        XCTAssertEqual(request.selectors.bundleId, "com.apple.Safari")
        XCTAssertEqual(request.fields, ["id", "focus-rank"])
        XCTAssertNil(try CLIQueryArguments.parse(arguments: ["windows"]).sort)
    }

    func testSortIsRejectedWhenUnknownRepeatedMissingOrOnOtherQueries() {
        let invalid = [
            ["windows", "--sort", "newest"],
            ["windows", "--sort", "mru", "--sort", "mru"],
            ["windows", "--sort"],
            ["workspaces", "--sort", "mru"]
        ]
        for arguments in invalid {
            XCTAssertThrowsError(try CLIQueryArguments.parse(arguments: arguments), arguments.joined(separator: " "))
        }
    }
}
