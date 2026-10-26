// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Darwin
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class SettingsFileObservationTests: XCTestCase {
    func testRetargetedAncestorDirectoryLinkLoadsTheNewConfig() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeDirectory("first", in: root)
        let second = try makeDirectory("second", in: root)
        let firstConfig = try makeDirectory("omniwm", in: first)
        let secondConfig = try makeDirectory("omniwm", in: second)
        try writeSettings(17, in: firstConfig)
        try writeSettings(23, in: secondConfig)
        let base = root.appendingPathComponent("config-home", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: base.path, withDestinationPath: "first")
        let persistence = SettingsFilePersistence(directory: base.appendingPathComponent("omniwm"), deferSaves: false)
        XCTAssertEqual(persistence.load().gaps.size, 17)

        await expectReload(23, from: persistence) { try replaceLink(base, destination: "second") }
        await expectReload(29, from: persistence) { try writeSettings(29, in: secondConfig, atomic: true) }
    }

    func testRetargetedConfigDirectoryLoadsAndWatchesTheNewDirectory() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeDirectory("first", in: root)
        let second = try makeDirectory("second", in: root)
        try writeSettings(17, in: first)
        try writeSettings(23, in: second)
        let config = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: first)
        let persistence = SettingsFilePersistence(directory: config, deferSaves: false)
        XCTAssertEqual(persistence.load().gaps.size, 17)

        await expectReload(19, from: persistence) { try writeSettings(19, in: first) }
        await expectReload(23, from: persistence) { try replaceLink(config, destination: second.path) }
        await expectReload(29, from: persistence) { try writeSettings(29, in: second) }
        await expectReload(31, from: persistence) { try writeSettings(31, in: second, atomic: true) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: config.path), second.path)
    }

    func testDeletedExternalSettingsTargetIsWatchedAfterRecreation() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try makeDirectory("config", in: root)
        let external = try makeDirectory("external", in: root)
        try writeSettings(17, in: external)
        let target = external.appendingPathComponent(SettingsFilePersistence.fileName)
        let link = config.appendingPathComponent(SettingsFilePersistence.fileName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let persistence = SettingsFilePersistence(directory: config, deferSaves: false)
        XCTAssertEqual(persistence.load().gaps.size, 17)

        await expectReload(19, from: persistence) { try writeSettings(19, in: external) }
        try FileManager.default.removeItem(at: target)
        try await Task.sleep(for: .milliseconds(150))
        await expectReload(23, from: persistence) { try writeSettings(23, in: external) }
        await expectReload(29, from: persistence) { try writeSettings(29, in: external, atomic: true) }
        await expectReload(31, from: persistence) { try writeSettings(31, in: external) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
    }

    func testRemovedConfigDirectoryLinkCanBeRecreated() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeDirectory("first", in: root)
        let second = try makeDirectory("second", in: root)
        try writeSettings(17, in: first)
        try writeSettings(23, in: second)
        let config = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: first)
        let persistence = SettingsFilePersistence(directory: config, deferSaves: false)
        XCTAssertEqual(persistence.load().gaps.size, 17)

        try FileManager.default.removeItem(at: config)
        try await Task.sleep(for: .milliseconds(150))
        await expectReload(23, from: persistence) {
            try FileManager.default.createSymbolicLink(at: config, withDestinationURL: second)
        }
        await expectReload(29, from: persistence) { try writeSettings(29, in: second, atomic: true) }
    }

    func testRelativeSymlinkChainRetargetsAndRecoversItsExternalTarget() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try makeDirectory("config", in: root)
        let aliases = try makeDirectory("aliases", in: root)
        let first = try makeDirectory("first", in: root)
        let second = try makeDirectory("second", in: root)
        let nested = try makeDirectory("nested", in: second)
        try writeSettings(17, in: first)
        try writeSettings(23, in: second)
        let directoryLink = root.appendingPathComponent("directory-link")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: nested)
        let intermediate = aliases.appendingPathComponent("current.toml")
        try FileManager.default.createSymbolicLink(
            atPath: intermediate.path, withDestinationPath: "../first/settings.toml"
        )
        let settings = config.appendingPathComponent(SettingsFilePersistence.fileName)
        try FileManager.default.createSymbolicLink(
            atPath: settings.path, withDestinationPath: "../aliases/current.toml"
        )
        let persistence = SettingsFilePersistence(directory: config, deferSaves: false)
        XCTAssertEqual(persistence.load().gaps.size, 17)

        await expectReload(23, from: persistence) {
            try replaceLink(intermediate, destination: "../directory-link/../settings.toml")
        }
        try FileManager.default.removeItem(at: second.appendingPathComponent(SettingsFilePersistence.fileName))
        try await Task.sleep(for: .milliseconds(150))
        await expectReload(29, from: persistence) { try writeSettings(29, in: second, atomic: true) }
        await expectReload(31, from: persistence) { try writeSettings(31, in: second) }
    }

    func testDeletedTargetDirectoriesCanBeRecreatedInStages() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try makeDirectory("config", in: root)
        let external = try makeDirectory("external", in: root)
        let nested = try makeDirectory("nested", in: external)
        try writeSettings(17, in: nested)
        let settings = config.appendingPathComponent(SettingsFilePersistence.fileName)
        try FileManager.default.createSymbolicLink(
            at: settings, withDestinationURL: nested.appendingPathComponent(SettingsFilePersistence.fileName)
        )
        let persistence = SettingsFilePersistence(directory: config, deferSaves: false)
        XCTAssertEqual(persistence.load().gaps.size, 17)

        try FileManager.default.removeItem(at: external)
        try await Task.sleep(for: .milliseconds(150))
        _ = try makeDirectory("external", in: root)
        try await Task.sleep(for: .milliseconds(150))
        _ = try makeDirectory("nested", in: external)
        try await Task.sleep(for: .milliseconds(150))
        await expectReload(23, from: persistence) { try writeSettings(23, in: nested) }
        await expectReload(29, from: persistence) { try writeSettings(29, in: nested, atomic: true) }
    }

    func testInitiallyDanglingAndCyclicLinksRecoverAfterReplacement() async throws {
        for destination in ["../external/settings.toml", "settings.toml"] {
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let config = try makeDirectory("config", in: root)
            let external = try makeDirectory("external", in: root)
            let settings = config.appendingPathComponent(SettingsFilePersistence.fileName)
            try FileManager.default.createSymbolicLink(atPath: settings.path, withDestinationPath: destination)
            let persistence = SettingsFilePersistence(directory: config, deferSaves: false)
            XCTAssertNotNil(persistence.loadOutcome().notice)
            XCTAssertTrue(persistence.settingsWritesBlocked)

            await expectReload(23, from: persistence) {
                try writeSettings(23, in: external)
                try replaceLink(settings, destination: "../external/settings.toml")
            }
            XCTAssertFalse(persistence.settingsWritesBlocked)
            await expectReload(29, from: persistence) { try writeSettings(29, in: external, atomic: true) }
        }
    }

    func testUnrelatedDirectoryChangesAndOwnSavesDoNotReload() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try makeDirectory("config", in: root)
        try writeSettings(17, in: config)
        let persistence = SettingsFilePersistence(directory: config, deferSaves: false)
        var export = persistence.load()
        let reloaded = expectation(description: "Unchanged settings must not reload")
        reloaded.isInverted = true
        persistence.setExternalChangeHandler { _ in reloaded.fulfill() }

        try Data("unrelated".utf8).write(to: root.appendingPathComponent("sibling"))
        export.gaps.size = 23
        try persistence.saveImmediately(export)
        await fulfillment(of: [reloaded], timeout: 0.2)
        XCTAssertEqual(try SettingsTOMLCodec.decode(Data(contentsOf: persistence.fileURL)).gaps.size, 23)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMSettingsObservationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDirectory(_ name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeSettings(_ size: Double, in directory: URL, atomic: Bool = false) throws {
        var export = SettingsExport.defaults()
        export.gaps.size = size
        try SettingsTOMLCodec.encode(export).write(
            to: directory.appendingPathComponent(SettingsFilePersistence.fileName),
            options: atomic ? .atomic : []
        )
    }

    private func replaceLink(_ link: URL, destination: String) throws {
        let replacement = link.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(atPath: replacement.path, withDestinationPath: destination)
        guard Darwin.rename(replacement.path, link.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func expectReload(
        _ size: Double,
        from persistence: SettingsFilePersistence,
        file: StaticString = #filePath,
        line: UInt = #line,
        edit: () throws -> Void
    ) async {
        let changed = expectation(description: "Reload settings with gap size \(size)")
        changed.assertForOverFulfill = false
        persistence.setExternalChangeHandler { outcome in
            if outcome.export?.gaps.size == size { changed.fulfill() }
        }
        do {
            try edit()
        } catch {
            XCTFail("Failed to edit settings: \(error)", file: file, line: line)
            return
        }
        await fulfillment(of: [changed], timeout: 3)
    }
}
