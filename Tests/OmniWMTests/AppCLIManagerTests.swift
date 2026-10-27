// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

final class AppCLIManagerTests: XCTestCase {
    func testInstallCLIIgnoresPathsThatOnlyShareHomePrefix() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OmniWMCLIInstall-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        let siblingBinDirectory = root.appendingPathComponent("home-other/bin", isDirectory: true)
        let userBinDirectory = homeDirectory.appendingPathComponent("bin", isDirectory: true)
        let bundleURL = root.appendingPathComponent("OmniWM.app", isDirectory: true)
        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/omniwmctl")
        for directory in [
            homeDirectory,
            siblingBinDirectory,
            userBinDirectory,
            executableURL.deletingLastPathComponent()
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)

        let fallbackDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        for (pathDirectories, expectedDirectory, directoryOnPath) in [
            ([siblingBinDirectory], fallbackDirectory, false),
            ([siblingBinDirectory, userBinDirectory], userBinDirectory, true)
        ] {
            let manager = AppCLIManager(
                environmentProvider: {
                    ["PATH": pathDirectories.map { $0.standardizedFileURL.path }.joined(separator: ":")]
                },
                bundleURLProvider: { bundleURL },
                homeDirectoryURLProvider: { homeDirectory.standardizedFileURL },
                homebrewLinkURLsProvider: { [] }
            )
            let expectedLinkURL = expectedDirectory.standardizedFileURL.appendingPathComponent("omniwmctl")

            XCTAssertEqual(
                try manager.installCLIToPATH(),
                .installed(linkURL: expectedLinkURL, directoryOnPath: directoryOnPath)
            )
            XCTAssertFalse(fileManager.fileExists(atPath: siblingBinDirectory.appendingPathComponent("omniwmctl").path))
        }
    }

    func testDanglingNonManagedCLILinksAreConflicts() throws {
        for relative in [false, true] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let destination = relative
                ? "../../missing/omniwmctl"
                : fixture.root.appendingPathComponent("missing/omniwmctl").path
            try FileManager.default.createSymbolicLink(
                atPath: fixture.linkURL.path,
                withDestinationPath: destination
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.linkURL.path))
            XCTAssertEqual(fixture.manager.exposureStatus(), .conflict(existingURL: fixture.linkURL))
            XCTAssertThrowsError(try fixture.manager.installCLIToPATH()) {
                XCTAssertEqual($0 as? AppCLIInstallError, .conflictingInstall(fixture.linkURL))
            }
            XCTAssertThrowsError(try fixture.manager.removeInstalledCLI()) {
                XCTAssertEqual($0 as? AppCLIInstallError, .cannotRemoveNonManagedInstall(fixture.linkURL))
            }
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: fixture.linkURL.path),
                destination
            )
        }
    }

    func testDanglingAppManagedCLILinksCanBeRemoved() throws {
        for relative in [false, true] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let destination = relative
                ? "../../OmniWM.app/Contents/MacOS/omniwmctl"
                : fixture.executableURL.path
            try FileManager.default.createSymbolicLink(
                atPath: fixture.linkURL.path,
                withDestinationPath: destination
            )
            try FileManager.default.removeItem(at: fixture.executableURL)

            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.linkURL.path))
            XCTAssertEqual(
                fixture.manager.exposureStatus(),
                .appManaged(linkURL: fixture.linkURL, directoryOnPath: true)
            )
            XCTAssertThrowsError(try fixture.manager.installCLIToPATH()) {
                XCTAssertEqual($0 as? AppCLIInstallError, .bundledCLIMissing(fixture.executableURL))
            }
            XCTAssertEqual(try fixture.manager.removeInstalledCLI(), .removed(linkURL: fixture.linkURL))
            XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: fixture.linkURL.path))
            XCTAssertEqual(
                fixture.manager.exposureStatus(),
                .notInstalled(linkURL: fixture.linkURL, directoryOnPath: true)
            )
        }
    }

    func testAppManagedCLIInstallAndRemoval() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertEqual(
            fixture.manager.exposureStatus(),
            .notInstalled(linkURL: fixture.linkURL, directoryOnPath: true)
        )
        XCTAssertEqual(
            try fixture.manager.installCLIToPATH(),
            .installed(linkURL: fixture.linkURL, directoryOnPath: true)
        )
        XCTAssertEqual(
            fixture.manager.exposureStatus(),
            .appManaged(linkURL: fixture.linkURL, directoryOnPath: true)
        )
        XCTAssertEqual(
            try fixture.manager.installCLIToPATH(),
            .alreadyInstalled(linkURL: fixture.linkURL, directoryOnPath: true)
        )
        XCTAssertEqual(try fixture.manager.removeInstalledCLI(), .removed(linkURL: fixture.linkURL))
        XCTAssertEqual(
            fixture.manager.exposureStatus(),
            .notInstalled(linkURL: fixture.linkURL, directoryOnPath: true)
        )
    }

    private struct Fixture {
        let root: URL
        let manager: AppCLIManager
        let executableURL: URL
        let linkURL: URL
    }

    private func makeFixture() throws -> Fixture {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OmniWMCLIInstall-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        let binDirectory = homeDirectory.appendingPathComponent("bin", isDirectory: true)
        let bundleURL = root.appendingPathComponent("OmniWM.app", isDirectory: true)
        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/omniwmctl")
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        let manager = AppCLIManager(
            environmentProvider: { ["PATH": binDirectory.path] },
            bundleURLProvider: { bundleURL },
            homeDirectoryURLProvider: { homeDirectory },
            homebrewLinkURLsProvider: { [] }
        )
        return Fixture(
            root: root,
            manager: manager,
            executableURL: executableURL,
            linkURL: binDirectory.appendingPathComponent("omniwmctl")
        )
    }
}
