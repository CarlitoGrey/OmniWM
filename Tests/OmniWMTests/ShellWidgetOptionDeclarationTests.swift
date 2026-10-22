// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ShellWidgetOptionDeclarationTests: XCTestCase {
    private static let undeclaredReads: Set<String> = ["world-clock:zones", "lake:render"]

    private func layers() throws -> [URL] {
        let styles = try XCTUnwrap(ShellDefaults.bundledStyles)
        return try [XCTUnwrap(ShellDefaults.bundled)] + FileManager.default
            .contentsOfDirectory(at: styles, includingPropertiesForKeys: nil)
            .filter(\.hasDirectoryPath)
    }

    private func declaredOptions(_ widget: String, in layer: URL) throws -> [String: ShellComponentOption] {
        var options = try ShellRootSettings.load(widget, directories: [layer])?.options ?? [:]
        let component = layer.appendingPathComponent("widgets/\(widget)/component.toml")
        if FileManager.default.fileExists(atPath: component.path) {
            options.merge(try ShellComponentCatalog.load(widget, directories: [layer]).options) { first, _ in first }
        }
        return options
    }

    private func optionReads(in folder: URL) throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"\b(?:settings|options)(?: or \{\}\))?\.([A-Za-z_]+)|select\("settings",\s*"([A-Za-z_]+)""#
        )
        var keys: Set<String> = []
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "luau" } ?? []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                for group in 1 ... 2 {
                    if let range = Range(match.range(at: group), in: source) { keys.insert(String(source[range])) }
                }
            }
        }
        return keys
    }

    func testBundledWidgetsDeclareEveryOptionTheyRead() throws {
        for layer in try layers() {
            let widgets = layer.appendingPathComponent("widgets")
            for name in try FileManager.default.contentsOfDirectory(atPath: widgets.path) {
                let declared = try declaredOptions(name, in: layer)
                for key in try optionReads(in: widgets.appendingPathComponent(name))
                    where declared[key] == nil && !Self.undeclaredReads.contains("\(name):\(key)")
                {
                    XCTFail("\(layer.lastPathComponent)/\(name) reads undeclared option \(key)")
                }
            }
        }
    }

    func testBundledColorOptionDefaultsAreHexColors() throws {
        for layer in try layers() {
            let widgets = layer.appendingPathComponent("widgets")
            for name in try FileManager.default.contentsOfDirectory(atPath: widgets.path) {
                for (key, option) in try declaredOptions(name, in: layer)
                    where option.kind == .string && key.lowercased().hasSuffix("color")
                {
                    guard case let .string(value)? = option.defaultValue else { continue }
                    XCTAssertNotNil(
                        ShellWidgetSettingsModel.rgba(value),
                        "\(layer.lastPathComponent)/\(name) \(key) default \(value) is not #rrggbb or #rrggbbaa"
                    )
                }
            }
        }
    }
}
