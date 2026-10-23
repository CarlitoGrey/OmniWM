// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import SwiftUI
import XCTest

@MainActor
final class ShellSettingsOptionRowTests: XCTestCase {
    func testBundledOptionTitleRendersInChinese() async throws {
        let schema = try XCTUnwrap(ShellRootSettings.load(
            "workspaces", directories: [try XCTUnwrap(ShellDefaults.bundled)]
        ))
        let option = try XCTUnwrap(schema.options["indicator"])
        var expected = option
        expected.title = "工作空间指示器"
        let actualPixels = try await snapshot(option, name: "workspace-actual")
        let expectedPixels = try await snapshot(expected, name: "workspace-expected")
        XCTAssertEqual(actualPixels, expectedPixels, "The native picker must display the Chinese option title")
    }

    func testEveryOptionControlTranslatesTitlesInBothAppearances() async throws {
        let cases: [(ShellComponentOption, String)] = [
            (.init(kind: .boolean, title: "Show date"), "显示日期"),
            (.init(kind: .choice, title: "Workspace indicator", choices: [""]), "工作空间指示器"),
            (
                .init(kind: .number, title: "Low battery threshold (%)", minimum: 1, maximum: 100),
                "低电量阈值 (%)"
            ),
            (.init(kind: .number, title: "Hover delay"), "悬停延迟"),
            (.init(kind: .string, title: "Initial label"), "初始标签"),
            (.init(kind: .string, title: "Selected tab color"), "选中选项卡颜色"),
            (.init(kind: .strings, title: "Component regions"), "组件区域")
        ]
        for (option, title) in cases {
            let key = option.title
            for dark in [false, true] {
                var expected = option
                expected.title = title
                let actualPixels = try await snapshot(option, key: key, dark: dark, name: "\(key)-\(dark)-actual")
                let expectedPixels = try await snapshot(expected, key: key, dark: dark, name: "\(key)-\(dark)-expected")
                XCTAssertEqual(actualPixels, expectedPixels, "\(key), dark: \(dark)")
            }
        }
    }

    private func snapshot(
        _ option: ShellComponentOption, key: String = "indicator", dark: Bool = false, name: String
    ) async throws -> Data {
        _ = NSApplication.shared
        let policy = NSApp.activationPolicy()
        _ = NSApp.setActivationPolicy(.accessory)
        defer { _ = NSApp.setActivationPolicy(policy) }
        let host = NSHostingView(rootView: Form {
            ShellSettingsOptionRow(key: key, option: option, value: nil) { _ in }
        }
        .formStyle(.grouped)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.colorScheme, dark ? .dark : .light)
        .transaction { $0.animation = nil })
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 180),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderBack(nil)
        defer { window.contentView = nil
            window.close()
        }
        await withCheckedContinuation { continuation in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { continuation.resume() }
            NSApp.updateWindows()
            host.layoutSubtreeIfNeeded()
            window.display()
            CATransaction.commit()
            CATransaction.flush()
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        let count = bitmap.bytesPerRow * bitmap.pixelsHigh
        bytes.initialize(repeating: 0, count: count)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let path = ProcessInfo.processInfo.environment["OMNIWM_SHELL_SNAPSHOTS"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent(name + ".png"))
        }
        let pixels = Data(bytes: bytes, count: count)
        XCTAssertGreaterThan(Set(pixels).count, 8, "\(name): native content must render before comparison")
        return pixels
    }
}
