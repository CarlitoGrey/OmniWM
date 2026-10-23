// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import CoreText
import ImageIO
@testable import OmniWM
import OmniWMScriptHost
import OmniWMShellCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ShellStyleLayoutTests: XCTestCase {
    private let applications = ["com.apple.Safari", "com.apple.Terminal", "com.apple.finder", "com.apple.Notes"]
    private let profiles = ["default", "wayline", "nocturne", "celestial", "lake", "system", "sakura"]

    func testManagedProfileEjectCreatesPersistentUserOverrides() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        XCTAssertTrue(try ShellProfiles.select("celestial", in: shell))
        let celestial = ShellConfig.resolve(shellDirectory: shell)
        XCTAssertEqual(
            try ShellProfiles.eject("workspaces", config: celestial, shellDirectory: shell),
            shell.appendingPathComponent("widgets/workspaces", isDirectory: true)
        )
        XCTAssertNil(try ShellProfiles.eject("workspaces", config: celestial, shellDirectory: shell))
        XCTAssertNotNil(celestial.file("lib/shapes.luau"))
        let copied = try XCTUnwrap(ShellProfiles.eject("privacy", config: celestial, shellDirectory: shell))
        XCTAssertEqual(copied, shell.appendingPathComponent("widgets/privacy", isDirectory: true))
        XCTAssertTrue(try ShellProfiles.create("custom", in: shell))
        XCTAssertNotNil(ShellConfig.resolve(shellDirectory: shell).widget("custom"))
        XCTAssertTrue(try ShellProfiles.select("default", in: shell))
        let original = ShellConfig.resolve(shellDirectory: shell)
        XCTAssertEqual(
            original.widget("workspaces"),
            shell.appendingPathComponent("widgets/workspaces/init.luau")
        )
        XCTAssertEqual(original.widget("privacy"), shell.appendingPathComponent("widgets/privacy/init.luau"))
        XCTAssertNil(original.widget("custom"))
        XCTAssertNil(original.file("lib/shapes.luau"))
    }

    func testStylesFitTheirThicknessAtBothBackingScalesAndOrientations() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let appearances = ProcessInfo.processInfo.environment["OMNIWM_SHELL_SNAPSHOTS"] != nil ? [false, true] : [false]
        for profile in profiles {
            _ = try ShellProfiles.select(profile, in: shell)
            let config = ShellConfig.resolve(shellDirectory: shell)
            let base = config.barOverride?.settings.height ?? 24
            for height in [base, base * 1.5] {
                for vertical in [false, true] {
                    for scale in [CGFloat(1), 2] {
                        for dark in appearances {
                            try render(
                                config,
                                shell: shell,
                                height: height,
                                vertical: vertical,
                                scale: scale,
                                dark: dark
                            )
                        }
                    }
                }
            }
        }
    }

    func testExportWidgetRendersForEveryProfile() throws {
        guard let directory = ProcessInfo.processInfo.environment["OMNIWM_STEP_RENDERS"] else {
            throw XCTSkip("Set OMNIWM_STEP_RENDERS to export per-profile widget renders")
        }
        let name = ProcessInfo.processInfo.environment["OMNIWM_STEP_WIDGET"] ?? "workspaces"
        let shared = ProcessInfo.processInfo.environment["OMNIWM_STEP_SHARED"] == "1"
        let tab = ProcessInfo.processInfo.environment["OMNIWM_STEP_TAB"] ?? "audio"
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        let environment = ProcessInfo.processInfo.environment
        XCTAssertEqual(ShellDefaults.sync(
            into: shell,
            from: environment["OMNIWM_STEP_FROM"].map { URL(fileURLWithPath: $0) } ?? ShellDefaults.bundled,
            styles: environment["OMNIWM_STEP_STYLES"].map { URL(fileURLWithPath: $0) } ?? ShellDefaults.bundledStyles
        ), [])
        if !shared, let baseline = ProcessInfo.processInfo.environment["OMNIWM_STEP_BASE_SOURCE"] {
            try Data(contentsOf: URL(fileURLWithPath: baseline))
                .write(to: shell.appendingPathComponent("default/widgets/\(name)/init.luau"))
        }
        try useSharedLibraries(ProcessInfo.processInfo.environment["OMNIWM_STEP_SHARED_LIBS"] ?? "", in: shell)
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let height = config.barOverride?.settings.height ?? 32
            for dark in [false, true] {
                for vertical in [false, true] {
                    let resources = ShellResources(
                        motion: MotionPolicy(animationsEnabled: false),
                        windowIcon: { [applications] id in
                            guard let index = Int(id), applications.indices.contains(index),
                                  let url = NSWorkspace.shared
                                      .urlForApplication(withBundleIdentifier: applications[index])
                            else { return nil }
                            return NSWorkspace.shared.icon(forFile: url.path)
                        }
                    )
                    resources.palette.refresh(
                        theme: config.theme,
                        appearance: try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
                    )
                    let widget = try makeWidget(
                        name, config: config, shell: shell, resources: resources,
                        source: shared ? shell.appendingPathComponent("default/widgets/\(name)/init.luau") : nil
                    )
                    if ["volume", "control-center"].contains(name) {
                        audioFixture(widget, access: .granted)
                    }
                    if name == "media" || (name == "control-center" && tab == "media") {
                        mediaFixture(widget)
                    }
                    if ["clock", "calendar"].contains(name) || (name == "control-center" && tab == "calendar") {
                        calendarFixture(widget)
                    }
                    if name == "weather" || (name == "control-center" && tab == "weather") {
                        weatherFixture(widget)
                    }
                    if ["battery", "battery-details"].contains(name) {
                        batteryFixture(widget)
                    }
                    if name == "active-window" {
                        widget.set("app") { $0.string("Safari") }
                        widget.set("bundle") { $0.string("com.apple.Safari") }
                        widget.set("title") { $0.string("A quiet afternoon") }
                    }
                    var bar = name == "scratchpads"
                        ? scratchpadFixture(config, height: height, vertical: vertical)
                        : fixture(config, height: height, vertical: vertical)
                    if environment["OMNIWM_STEP_CAPSULE"] == "1" {
                        bar.style.transparent = true
                        bar.style.backgrounds = true
                    }
                    widget.render(bar)
                    if ["hidden-bar", "hidden-bar-menu"].contains(name) {
                        let hidden = hiddenBarFixture(vertical: vertical, menu: name == "hidden-bar-menu")
                        widget.set("hiddenBar") { hidden.write(into: &$0) }
                        widget.layoutPopout()
                    }
                    let background = resources.palette.color(.clear, default: .background)
                    try ShellBundledWidgetTests.writeSnapshot(
                        widget.surface,
                        name: "\(name)-\(profile)-\(vertical ? "vertical" : "horizontal")-\(dark ? "dark" : "light")",
                        dark: dark, directory: directory, background: background
                    )
                    if name == "battery-details" {
                        for mode in ["inside", "off"] {
                            widget.set("settings") {
                                ShellServiceValue.object(["percent": .text(mode)]).write(to: &$0)
                            }
                            widget.render(bar)
                            try ShellBundledWidgetTests.writeSnapshot(
                                widget.surface,
                                name: "\(name)-\(profile)-\(vertical ? "vertical" : "horizontal")-\(mode)\(dark ? "-dark" : "")",
                                dark: dark, directory: directory, background: background
                            )
                        }
                        widget.set("settings") { ShellServiceValue.object([:]).write(to: &$0) }
                        widget.render(bar)
                    }
                    if ["volume", "control-center"].contains(name), !vertical {
                        audioFixture(widget, access: .granted)
                        if name == "control-center" {
                            widget.set("settings") { ShellServiceValue.object(["tab": .text(tab)]).write(to: &$0) }
                        }
                        widget.layoutPopout()
                        try ShellBundledWidgetTests.writeSnapshot(
                            widget.surface,
                            name: "\(name)-\(profile)-popout-\(dark ? "dark" : "light")",
                            dark: dark, directory: directory, background: background
                        )
                        if !dark {
                            audioFixture(widget, access: .denied)
                            widget.layoutPopout()
                            try ShellBundledWidgetTests.writeSnapshot(
                                widget.surface, name: "\(name)-\(profile)-popout-denied",
                                dark: false, directory: directory, background: background
                            )
                            if name == "volume" {
                                audioFixture(widget, access: .granted)
                                for state in ["muted", "zero", "unavailable"] {
                                    widget.set("muted") { $0.bool(state == "muted") }
                                    widget.set("volume") {
                                        if state == "unavailable" { $0.null() }
                                        else { $0.number(state == "zero" ? 0 : 62) }
                                    }
                                    if state == "unavailable" {
                                        widget.set("outputs") { $0.null() }
                                        widget.set("audioApps") { $0.null() }
                                    }
                                    widget.layoutPopout()
                                    try ShellBundledWidgetTests.writeSnapshot(
                                        widget.surface, name: "volume-\(profile)-popout-\(state)",
                                        dark: false, directory: directory, background: background
                                    )
                                }
                            }
                        }
                    }
                    if name == "calendar" || (name == "clock" && shared)
                        || (name == "control-center" && tab == "calendar"), !vertical
                    {
                        widget.layoutPopout()
                        try ShellBundledWidgetTests.writeSnapshot(
                            widget.surface,
                            name: "\(name)-\(profile)-popout-\(dark ? "dark" : "light")",
                            dark: dark, directory: directory, background: background
                        )
                        if !dark {
                            for state in ["notDetermined", "denied", "nomonth", "loading"] {
                                if state == "loading" {
                                    widget.set("calendar") { $0.null() }
                                } else {
                                    calendarFixture(
                                        widget,
                                        access: state == "nomonth" ? "full" : state,
                                        month: state != "nomonth"
                                    )
                                }
                                widget.layoutPopout()
                                try ShellBundledWidgetTests.writeSnapshot(
                                    widget.surface, name: "\(name)-\(profile)-popout-\(state)",
                                    dark: false, directory: directory, background: background
                                )
                            }
                            calendarFixture(widget)
                        }
                    }
                    if name == "battery-details", !vertical {
                        widget.layoutPopout()
                        try ShellBundledWidgetTests.writeSnapshot(
                            widget.surface,
                            name: "\(name)-\(profile)-popout-\(dark ? "dark" : "light")",
                            dark: dark, directory: directory, background: background
                        )
                        if !dark {
                            for state in ["charging", "low", "charged", "ac", "nopower", "unavailable"] {
                                switch state {
                                case "ac": batteryFixture(widget, level: 80, power: ShellPower(source: "ac"))
                                case "nopower":
                                    batteryFixture(widget)
                                    widget.set("power") { $0.null() }
                                case "charging": batteryFixture(
                                        widget,
                                        charging: true,
                                        power: ShellPower(source: "ac", full: 40)
                                    )
                                case "low":
                                    batteryFixture(
                                        widget,
                                        level: 12,
                                        power: ShellPower(source: "battery", remaining: 25, lowPower: true)
                                    )
                                case "unavailable": widget.set("battery") { $0.null() }
                                default: batteryFixture(
                                        widget,
                                        level: 100,
                                        power: ShellPower(source: "ac", charged: true)
                                    )
                                }
                                widget.layoutPopout()
                                try ShellBundledWidgetTests.writeSnapshot(
                                    widget.surface, name: "\(name)-\(profile)-popout-\(state)",
                                    dark: false, directory: directory, background: background
                                )
                            }
                            batteryFixture(widget)
                        }
                    }
                    if name == "weather" || (name == "control-center" && tab == "weather"), !vertical {
                        func writeScrolledWeatherSnapshot(_ suffix: String) throws {
                            guard name == "weather", shared, profile == "celestial" else { return }
                            let scroll = try XCTUnwrap(widget.surface.layout.core.elements { $0.scrolls }.first)
                            let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: scroll))
                            let point = CGPoint(x: frame.midX, y: frame.midY)
                            XCTAssertTrue(widget.surface.scroll(
                                at: point,
                                event: ShellEvent(button: .none),
                                content: CGPoint(x: 0, y: 10_000)
                            ))
                            try ShellBundledWidgetTests.writeSnapshot(
                                widget.surface,
                                name: "weather-celestial-popout-scrolled-\(suffix)",
                                dark: dark, directory: directory, background: background
                            )
                            XCTAssertTrue(widget.surface.scroll(
                                at: point,
                                event: ShellEvent(button: .none),
                                content: CGPoint(x: 0, y: -10_000)
                            ))
                        }
                        if name == "weather" {
                            widget.layoutPopout()
                            try ShellBundledWidgetTests.writeSnapshot(
                                widget.surface,
                                name: "\(name)-\(profile)-popout-\(dark ? "dark" : "light")",
                                dark: dark, directory: directory, background: background
                            )
                            try writeScrolledWeatherSnapshot(dark ? "dark" : "light")
                        }
                        if !dark {
                            for state in ["stale", "unavailable"] {
                                if state == "stale" {
                                    weatherFixture(widget, stale: true)
                                } else {
                                    widget.set("weather") { $0.null() }
                                }
                                widget.layoutPopout()
                                try ShellBundledWidgetTests.writeSnapshot(
                                    widget.surface, name: "\(name)-\(profile)-popout-\(state)",
                                    dark: false, directory: directory, background: background
                                )
                                if state == "stale" {
                                    try writeScrolledWeatherSnapshot(state)
                                }
                            }
                            weatherFixture(widget)
                        }
                    }
                    if name == "media", !vertical {
                        widget.layoutPopout()
                        try ShellBundledWidgetTests.writeSnapshot(
                            widget.surface,
                            name: "\(name)-\(profile)-popout-\(dark ? "dark" : "light")",
                            dark: dark, directory: directory, background: background
                        )
                        if !dark {
                            for state in ["paused", "loading", "nolyrics", "nothing"] {
                                switch state {
                                case "paused": mediaFixture(widget, playing: false)
                                case "loading": mediaFixture(widget, lyrics: .loading)
                                case "nolyrics": mediaFixture(widget, lyrics: .missing)
                                default:
                                    widget.set("media") { $0.null() }
                                    widget.set("lyrics") { $0.null() }
                                }
                                widget.layoutPopout()
                                try ShellBundledWidgetTests.writeSnapshot(
                                    widget.surface, name: "media-\(profile)-popout-\(state)",
                                    dark: false, directory: directory, background: background
                                )
                            }
                        }
                    }
                    if name == "system-stats", !vertical {
                        systemStatsFixture(widget)
                        widget.layoutPopout()
                        try ShellBundledWidgetTests.writeSnapshot(
                            widget.surface,
                            name: "\(name)-\(profile)-popout-\(dark ? "dark" : "light")",
                            dark: dark, directory: directory, background: background
                        )
                    }
                    if name == "workspaces", ProcessInfo.processInfo.environment["OMNIWM_STEP_POPOUT"] == "1" {
                        let group = try XCTUnwrap(widget.tree()
                            .first { widget.text.string($0.content.target) == "window 1" })
                        widget.invoke(group.content.action)
                        widget.layoutPopout()
                        try ShellBundledWidgetTests.writeSnapshot(
                            widget.surface,
                            name: "\(name)-\(profile)-picker-\(vertical ? "vertical" : "horizontal")-\(dark ? "dark" : "light")",
                            dark: dark, directory: directory, background: background
                        )
                    }
                }
            }
        }
    }

    func testSharedBatteryModelKeepsThresholdsPercentModesAndPowerStates() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let folder = shell.appendingPathComponent("default/widgets/battery-model-probe")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        local battery = require("../lib/battery")
        function render(ctx)
            local m = battery.model(ctx)
            if not m then return ui.text{ text = "nil" } end
            local rows = {}
            for _, key in {"level", "charging", "low", "tint", "symbol", "text", "percent", "reserve", "mode", "status", "settings"} do
                rows[#rows + 1] = ui.text{ text = key .. "=" .. tostring(m[key]) }
            end
            for _, detail in m.details do
                rows[#rows + 1] = ui.text{ text = detail.label .. "=" .. detail.value }
            end
            return ui.column(rows)
        end
        """.write(to: folder.appendingPathComponent("init.luau"), atomically: true, encoding: .utf8)
        let config = ShellConfig.resolve(shellDirectory: shell)
        let widget = try makeWidget("battery-model-probe", config: config, shell: shell)
        let bar = fixture(config, height: 32, vertical: false)
        let thresholds = [
            (0, "0", "error"),
            (10, "0", "error"),
            (11, "25", "warning"),
            (20, "25", "warning"),
            (21, "25", "foreground"),
            (35, "25", "foreground"),
            (36, "50", "foreground"),
            (60, "50", "foreground"),
            (61, "75", "foreground"),
            (85, "75", "foreground"),
            (86, "100", "foreground"),
            (100, "100", "foreground")
        ]
        for (level, symbol, tint) in thresholds {
            for charging in [false, true] {
                batteryFixture(widget, level: Double(level), charging: charging)
                widget.render(bar)
                let strings = widget.strings()
                XCTAssertTrue(strings.contains("level=\(level)"))
                XCTAssertTrue(strings.contains("text=\(level)"))
                XCTAssertTrue(strings.contains("charging=\(charging)"))
                XCTAssertTrue(strings.contains("low=\(level <= 20 && !charging)"))
                XCTAssertTrue(strings.contains("tint=\(charging ? "success" : tint)"))
                XCTAssertTrue(strings
                    .contains("symbol=\(charging ? "battery.100percent.bolt" : "battery.\(symbol)percent")"))
                XCTAssertTrue(strings.contains("percent=" + percent(Double(level) / 100)))
                XCTAssertTrue(strings.contains("reserve=" + percent(1)))
            }
        }
        for mode in ["beside", "inside", "off"] {
            widget.set("settings") { ShellServiceValue.object(["percent": .text(mode)]).write(to: &$0) }
            widget.render(bar)
            XCTAssertTrue(widget.strings().contains("mode=" + mode))
        }
        let states: [(ShellPower, Bool, String, String?, Double?)] = [
            (ShellPower(source: "battery", remaining: 254), false, "On battery", "Time Remaining", 254),
            (ShellPower(source: "ac"), false, "Not charging", nil, nil),
            (ShellPower(source: "ac", full: 40), true, "Charging", "Time to Full", 40),
            (ShellPower(source: "ac", charged: true), false, "Fully charged", nil, nil),
            (ShellPower(source: "battery", remaining: 0, lowPower: true), false, "On battery", "Time Remaining", 0)
        ]
        for (power, charging, status, timeKey, minutes) in states {
            batteryFixture(widget, charging: charging, power: power)
            widget.render(bar)
            let strings = widget.strings()
            XCTAssertTrue(strings.contains("status=" + ShellLocalizer.string(status, [])))
            XCTAssertTrue(strings.contains(ShellLocalizer.string("Power Source", []) + "=" + ShellLocalizer.string(
                power.source == "ac" ? "Power Adapter" : "Battery",
                []
            )))
            XCTAssertTrue(strings.contains(ShellLocalizer.string("Low Power Mode", []) + "=" + ShellLocalizer.string(
                power.lowPower ? "On" : "Off",
                []
            )))
            XCTAssertTrue(strings.contains("settings=battery settings"))
            if let timeKey, let minutes {
                let duration = ShellLocalizer.string(
                    "%lldh %lldm",
                    [.number(floor(minutes / 60)), .number(minutes.truncatingRemainder(dividingBy: 60))]
                )
                XCTAssertTrue(strings.contains(ShellLocalizer.string(timeKey, []) + "=" + duration))
            } else {
                XCTAssertFalse(strings
                    .contains {
                        $0.hasPrefix(ShellLocalizer.string("Time Remaining", []) + "=") || $0
                            .hasPrefix(ShellLocalizer.string(
                                "Time to Full",
                                []
                            ) + "=")
                    })
            }
        }
        widget.set("power") { $0.null() }
        widget.render(bar)
        XCTAssertTrue(widget.strings().contains("status=" + ShellLocalizer.string("On battery", [])))
        XCTAssertFalse(widget.strings().contains { $0.hasPrefix(ShellLocalizer.string("Low Power Mode", []) + "=") })
        widget.set("battery") { $0.null() }
        widget.render(bar)
        XCTAssertEqual(widget.strings(), ["nil"])
    }

    func testSharedBatteryBarsKeepModesScaledSkinsClicksAndDataDemand() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let hooked = ["wayline", "nocturne", "celestial"]
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let base = config.barOverride?.settings.height ?? 32
            for name in ["battery", "battery-details"] {
                let widget = try makeWidget(
                    name,
                    config: config,
                    shell: shell,
                    source: shell.appendingPathComponent("default/widgets/\(name)/init.luau")
                )
                for height in Set([base, 32]).sorted() {
                    for vertical in [false, true] {
                        for mode in [nil, "beside", "inside", "off"] as [String?] {
                            let context = "\(profile)/\(name) h=\(height) vertical=\(vertical) \(mode ?? "default")"
                            widget.set("settings") {
                                ShellServiceValue.object(mode.map { ["percent": .text($0)] } ?? [:]).write(to: &$0)
                            }
                            batteryFixture(widget)
                            widget.render(fixture(config, height: height, vertical: vertical))
                            let tree = widget.tree()
                            let labels = tree.filter {
                                $0.kind == .label && ShellFontFamily(style: $0.content.style) != .symbols
                            }.map { widget.text.string($0.content.text) }
                            let effectiveMode = mode ?? "beside"
                            let showsText = name == "battery" || effectiveMode != "off" ||
                                (vertical && !hooked.contains(profile))
                            let expected = vertical || (name == "battery-details" && effectiveMode == "inside")
                                ? "76" : percent(0.76)
                            XCTAssertEqual(labels, showsText ? [expected] : [], context)
                            if profile == "nocturne", name == "battery-details", vertical, effectiveMode != "beside" {
                                let root = try XCTUnwrap(tree.first, context)
                                XCTAssertEqual(
                                    widget.surface.size.width,
                                    widget.surface.size.height,
                                    accuracy: 0.01,
                                    context
                                )
                                XCTAssertLessThanOrEqual(
                                    CGFloat(root.paint.cornerRadius),
                                    widget.surface.size.height / 2,
                                    context
                                )
                            }
                            if profile == "wayline", name == "battery-details", effectiveMode == "inside" {
                                let label = try XCTUnwrap(tree.first { $0.kind == .label }, context)
                                XCTAssertEqual(
                                    label.content.color.role & 0xFF,
                                    UInt16(ShellRole.accentForeground.rawValue + 1),
                                    context
                                )
                            }
                            XCTAssertGreaterThan(widget.surface.size.width, 0, context)
                            XCTAssertGreaterThan(widget.surface.size.height, 0, context)
                            XCTAssertLessThanOrEqual(
                                vertical ? widget.surface.size.width : widget.surface.size.height,
                                height,
                                context
                            )
                            if name == "battery-details" {
                                let button = try XCTUnwrap(
                                    widget.surface.layout.core.elements { $0.action == OMNI_ACTION_POPOUT }.first,
                                    context
                                )
                                let content = widget.surface.layout.core.content(of: button)
                                XCTAssertEqual(
                                    widget.text.string(content.help),
                                    percent(0.76),
                                    context
                                )
                                let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                                let point = CGPoint(x: frame.midX, y: frame.midY)
                                let count = widget.actions.count
                                widget.surface.press(at: point)
                                widget.surface.release(at: point)
                                XCTAssertEqual(widget.actions.count, count + 1, context)
                                XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT, context)
                            } else {
                                XCTAssertTrue(tree.allSatisfy { $0.content.action == 0 }, context)
                            }
                            var stats = omni_render_stats()
                            var error = [CChar](repeating: 0, count: 256)
                            XCTAssertEqual(
                                omni_instance_render(
                                    widget.instance,
                                    OMNI_VIEW_BAR,
                                    100_000_000,
                                    &stats,
                                    &error,
                                    error.count
                                ),
                                OMNI_OK,
                                context
                            )
                            XCTAssertNotEqual(stats.deps & ShellDataKey.battery.bit, 0, context)
                            XCTAssertEqual(stats.deps & ShellDataKey.power.bit, 0, context)
                            XCTAssertEqual(stats.deps & ShellDataKey.seconds.bit, 0, context)
                            if hooked.contains(profile), !vertical {
                                let design: Double = profile == "celestial" ? 60 : 40
                                let expected = (profile == "celestial" ? 40 : 32) * height / design
                                XCTAssertEqual(widget.surface.size.height, expected, accuracy: 0.01, context)
                            }
                        }
                    }
                }
                widget.set("battery") { $0.null() }
                widget.render(fixture(config, height: base, vertical: false))
                XCTAssertEqual(widget.surface.size, .zero, profile + name)
                batteryFixture(widget)
                XCTAssertTrue(
                    omni_instance_needs_render(widget.instance, OMNI_VIEW_BAR, ShellDataKey.battery.bit),
                    profile + name
                )
            }
        }
    }

    func testSharedBatteryPanelsKeepPowerFeedbackSettingsAndMissingData() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let duration = ShellLocalizer.string("%lldh %lldm", [.number(4), .number(14)])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget(
                "battery-details",
                config: config,
                shell: shell,
                source: shell
                    .appendingPathComponent("default/widgets/battery-details/init.luau")
            )
            batteryFixture(widget)
            widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
            widget.layoutPopout()
            let strings = widget.strings(OMNI_VIEW_POPOUT)
            for text in [
                percent(0.76),
                ShellLocalizer.string("Battery", []),
                ShellLocalizer.string("On battery", []),
                ShellLocalizer.string("Power Source", []),
                ShellLocalizer.string("Time Remaining", []),
                duration,
                ShellLocalizer.string("Low Power Mode", []),
                ShellLocalizer.string("Off", [])
            ] {
                XCTAssertTrue(strings.contains(text), profile + " " + text)
            }
            if profile == "wayline" {
                XCTAssertEqual(widget.renderPopout().filter {
                    $0.paint.cornerRadius == 9 && $0.paint.fill
                        .role & 0xFF == UInt16(ShellRole.elevatedSurface.rawValue + 1)
                }.count, 2)
            }
            try clickCommand("battery settings", widget: widget, context: profile)
            batteryFixture(widget, level: 80, power: ShellPower(source: "ac"))
            widget.layoutPopout()
            let ac = widget.strings(OMNI_VIEW_POPOUT)
            XCTAssertTrue(ac.contains(percent(0.8)), profile)
            XCTAssertTrue(ac.contains(ShellLocalizer.string("Not charging", [])), profile)
            XCTAssertTrue(ac.contains(ShellLocalizer.string("Power Adapter", [])), profile)
            XCTAssertEqual(
                ac.filter { $0 == ShellLocalizer.string("Battery", []) }.count,
                profile == "celestial" ? 0 : 1,
                profile
            )
            if profile == "celestial" {
                let source = try XCTUnwrap(widget.surface.layout.core.elements {
                    widget.text.string($0.text) == ShellLocalizer.string("Power Source", [])
                }.first)
                let adapter = try XCTUnwrap(widget.surface.layout.core.elements {
                    widget.text.string($0.text) == ShellLocalizer.string("Power Adapter", [])
                }.first)
                let sourceFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: source))
                let adapterFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: adapter))
                XCTAssertLessThanOrEqual(sourceFrame.maxX + 8, adapterFrame.minX)
                let bounds = CGRect(origin: .zero, size: widget.surface.size)
                XCTAssertTrue(bounds.contains(sourceFrame))
                XCTAssertTrue(bounds.contains(adapterFrame))
            }
            widget.set("battery") { $0.null() }
            widget.layoutPopout()
            XCTAssertGreaterThan(widget.surface.size.width, 0, profile)
            XCTAssertGreaterThan(widget.surface.size.height, 0, profile)
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Unavailable", [])), profile)
            batteryFixture(widget, charging: true, power: ShellPower(source: "ac", full: 40, lowPower: true))
            widget.layoutPopout()
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Charging", [])), profile)
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Time to Full", [])), profile)
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("On", [])), profile)
            widget.set("power") { $0.null() }
            widget.layoutPopout()
            if profile == "wayline" {
                XCTAssertEqual(widget.renderPopout().filter {
                    $0.paint.cornerRadius == 9 && $0.paint.fill
                        .role & 0xFF == UInt16(ShellRole.elevatedSurface.rawValue + 1)
                }.count, 1)
            }
        }
    }

    func testCelestialStatusBatteryUsesTheSharedPowerModel() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        XCTAssertTrue(try ShellProfiles.select("celestial", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        let widget = try makeWidget("status", config: config, shell: shell)
        widget.set("settings") {
            ShellServiceValue.object(["battery": .bool(true), "network": .bool(false), "bluetooth": .bool(false)])
                .write(to: &$0)
        }
        batteryFixture(widget, level: 80, power: ShellPower(source: "ac"))
        widget.render(fixture(config, height: 60, vertical: false))
        let entry = try XCTUnwrap(widget.surface.layout.core.elements {
            widget.text.string($0.help) == ShellLocalizer.string("Battery", []) && $0.action != 0
        }.first)
        let content = widget.surface.layout.core.content(of: entry)
        let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: entry))
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let count = widget.actions.count
        widget.surface.press(at: point)
        widget.surface.release(at: point)
        XCTAssertEqual(widget.actions.count, count + 1)
        XCTAssertEqual(widget.actions.last, content.action)
        XCTAssertEqual(widget.invoke(content.action), [])
        widget.layoutPopout()
        let strings = widget.strings(OMNI_VIEW_POPOUT)
        XCTAssertTrue(strings.contains(percent(0.8)))
        for key in ["Not charging", "Power Adapter", "Low Power Mode", "Off"] {
            XCTAssertTrue(strings.contains(ShellLocalizer.string(key, [])), key)
        }
        try clickCommand("battery settings", widget: widget, context: "celestial/status")
        widget.set("battery") { $0.null() }
        widget.layoutPopout()
        XCTAssertGreaterThan(widget.surface.size.width, 0)
        XCTAssertGreaterThan(widget.surface.size.height, 0)
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Unavailable", [])))
    }

    func testSharedPanelsKeepDefaultCapsulesAndSystemGlassInEveryBackgroundSetting() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in ["default", "system"] {
            _ = try ShellProfiles.select(profile, in: shell)
            let config = ShellConfig.resolve(shellDirectory: shell)
            XCTAssertEqual(config.profile, profile)
            let folder = shell.appendingPathComponent("\(profile)/widgets/panel-probe")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            func drawing(_ module: String, _ bar: ShellBarData) throws -> [TreeNode] {
                try """
                local look = require("../lib/\(module)")
                function render(ctx) return ui.box{ w = 1, h = 1 } end
                function popout(ctx)
                    local props = { w = 220, ui.text{ text = "Probe" } }
                    return \(module == "look" ? "look.panel(ctx, props)" : "look.panel(props)")
                end
                """.write(to: folder.appendingPathComponent("init.luau"), atomically: true, encoding: .utf8)
                let widget = try makeWidget("panel-probe", config: config, shell: shell)
                widget.render(bar)
                return widget.renderPopout()
            }
            for transparent in [false, true] {
                for backgrounds in [false, true] {
                    var bar = fixture(config, height: 32, vertical: false)
                    bar.style.transparent = transparent
                    bar.style.backgrounds = backgrounds
                    let tree = try drawing("look", bar)
                    let root = try XCTUnwrap(tree.first)
                    let capsule = profile == "default" && transparent && backgrounds
                    XCTAssertEqual(root.paint.material, UInt8(capsule ? OMNI_MATERIAL_CLEAR : OMNI_MATERIAL_GLASS))
                    XCTAssertEqual(root.paint.cornerRadius, capsule ? 14 : 20)
                    if capsule {
                        XCTAssertEqual(root.paint.fill.role & 0xFF, UInt16(ShellRole.background.rawValue + 1))
                        XCTAssertEqual(root.paint.stroke.role & 0xFF, UInt16(ShellRole.border.rawValue + 1))
                        XCTAssertEqual(root.paint.strokeWidth, 1)
                    }
                    if profile == "system" {
                        let legacy = try drawing("style", bar)
                        XCTAssertEqual(
                            tree.map { "\($0.layout) \($0.paint)" },
                            legacy.map { "\($0.layout) \($0.paint)" }
                        )
                    }
                }
            }
        }
    }

    func testSharedActiveWindowHonoursDisplayModesPresetsAndDeliveredClicks() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let height = config.barOverride?.settings.height ?? 32
            let presetWidth: Float = ["matrix": 160, "sakura": 160, "celestial": 320][profile] ?? 260
            let widget = try makeWidget(
                "active-window", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/active-window/init.luau")
            )
            widget.set("app") { $0.string("Safari") }
            widget.set("bundle") { $0.string("com.apple.Safari") }
            for mode in ["preset", "icon_and_text", "icon_only", "text_only"] {
                if mode != "preset" {
                    widget.set("settings") {
                        ShellServiceValue.object(["display": .text(mode), "maxWidth": .number(72)]).write(to: &$0)
                    }
                }
                let display = mode == "preset"
                    ? (["matrix", "sakura"].contains(profile) ? "text_only" : "icon_and_text") : mode
                let maximum = mode == "preset" ? presetWidth : 72
                for vertical in [false, true] {
                    for backgrounds in [false, true] {
                        let context = "\(profile) \(mode) vertical=\(vertical) backgrounds=\(backgrounds)"
                        var bar = fixture(config, height: height, vertical: vertical)
                        bar.style.backgrounds = backgrounds
                        widget.set("title") { $0.string("A quiet afternoon") }
                        widget.render(bar)
                        let tree = widget.tree()
                        let showsText = display != "icon_only" && (!vertical || profile == "celestial")
                        let showsIcon = display != "text_only" || (vertical && profile != "celestial")
                        let icons = tree
                            .filter { $0.kind == .image && widget.text.string($0.content.text) == "com.apple.Safari" }
                        let labels = tree.filter { $0.kind == .label }
                        XCTAssertEqual(icons.count, showsIcon ? 1 : 0, context)
                        XCTAssertEqual(labels.count, showsText ? 1 : 0, context)
                        if let label = labels.first {
                            XCTAssertEqual(
                                widget.text.string(label.content.text),
                                profile == "matrix" ? "~/Safari" : "A quiet afternoon", context
                            )
                            XCTAssertEqual(label.content.maxWidth, maximum, context)
                            XCTAssertEqual(label.paint.rotate, vertical ? 90 : 0, context)
                        }
                        XCTAssertLessThanOrEqual(
                            vertical ? widget.surface.size.width : widget.surface.size.height,
                            height,
                            context
                        )
                        let button = try XCTUnwrap(tree.first, context)
                        XCTAssertEqual(widget.text.string(button.content.help), "Safari — A quiet afternoon", context)
                        try clickCommand("open-command-palette windows", widget: widget, context: context)
                    }
                }
            }
            widget.set("settings") { ShellServiceValue.object(["display": .text("icon_and_text")]).write(to: &$0) }
            widget.set("title") { $0.string("") }
            widget.render(fixture(config, height: height, vertical: false))
            XCTAssertEqual(widget.text.string(try XCTUnwrap(widget.tree().first).content.help), "Safari", profile)
            XCTAssertTrue(widget.strings().contains(profile == "matrix" ? "~/Safari" : "Safari"), profile)
            widget.set("app") { $0.string("") }
            widget.render(fixture(config, height: height, vertical: false))
            XCTAssertEqual(widget.surface.size, .zero, profile)
            XCTAssertTrue(widget.tree().allSatisfy { $0.content.action == 0 }, profile)
        }
    }

    func testSharedActiveWindowKeepsEachCustomSkinAndTextOverride() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in ["matrix", "celestial", "wayline", "nocturne"] {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let base = config.barOverride?.settings.height ?? 32
            let widget = try makeWidget(
                "active-window", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/active-window/init.luau")
            )
            widget.set("app") { $0.string("Safari") }
            widget.set("bundle") { $0.string("com.apple.Safari") }
            widget.set("title") { $0.string("A quiet afternoon") }
            for height in [base, 32] {
                let scale = height / (profile == "celestial" ? 60 : 40)
                for vertical in [false, true] {
                    let context = "\(profile) height=\(height) vertical=\(vertical)"
                    var bar = fixture(config, height: height, vertical: vertical)
                    bar.style.backgrounds = true
                    widget.render(bar)
                    let root = try XCTUnwrap(widget.tree().first, context)
                    let labels = widget.tree().filter { $0.kind == .label }
                    let icons = widget.tree().filter { $0.kind == .image }
                    XCTAssertEqual(icons.count, profile == "matrix" && !vertical ? 0 : 1, context)
                    XCTAssertEqual(labels.count, !vertical || profile == "celestial" ? 1 : 0, context)
                    let cross = vertical ? widget.surface.size.width : widget.surface.size.height
                    XCTAssertLessThanOrEqual(cross, height, context)
                    for icon in icons {
                        let designSize: Double = profile == "matrix" ? 18 : profile == "nocturne" ? 20 : 24
                        XCTAssertEqual(Double(icon.layout.width), designSize * scale, accuracy: 0.01, context)
                        XCTAssertEqual(Double(icon.layout.height), designSize * scale, accuracy: 0.01, context)
                    }
                    for label in labels {
                        let role: ShellRole = profile == "matrix" ? .secondaryForeground : profile == "celestial" ?
                            .accent : .foreground
                        let designSize: Double = profile == "matrix" ? 11 : profile == "celestial" ? 16 : 14
                        XCTAssertEqual(label.content.color.role & 0xFF, UInt16(role.rawValue + 1), context)
                        XCTAssertEqual(
                            CTFontGetSize(ShellTextStyle.font(for: label.content.style)),
                            designSize * scale,
                            accuracy: 0.01,
                            context
                        )
                    }
                    if profile == "matrix" {
                        XCTAssertEqual(cross, height - 4, accuracy: 0.01, context)
                    } else if profile == "wayline" {
                        XCTAssertEqual(cross, 32 * scale, accuracy: 0.01, context)
                        XCTAssertEqual(root.paint.cornerRadius, Float(floor(32 * scale * 0.24)), context)
                        XCTAssertEqual(
                            root.paint.fill.role & 0xFF,
                            UInt16(ShellRole.elevatedSurface.rawValue + 1),
                            context
                        )
                        XCTAssertEqual(root.content.hoverOpacity, 0.9, context)
                        if !vertical {
                            let label = try XCTUnwrap(widget.surface.layout.core.elements {
                                widget.text.string($0.text) == "A quiet afternoon"
                            }.first, context)
                            let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: label))
                            XCTAssertEqual(widget.surface.size.width - frame.maxX, 9 * scale, accuracy: 0.01, context)
                        }
                    } else if profile == "nocturne" {
                        XCTAssertEqual(cross, 32 * scale, accuracy: 0.01, context)
                        XCTAssertEqual(Double(root.paint.cornerRadius), 16 * scale - 1, accuracy: 0.01, context)
                        XCTAssertEqual(root.paint.fill.role & 0xFF, UInt16(ShellRole.surface.rawValue + 1), context)
                        XCTAssertEqual(root.paint.strokeWidth, 1, context)
                        XCTAssertTrue(root.content.hover.isVisible, context)
                    } else {
                        XCTAssertEqual(cross, (vertical ? 40 : 32) * scale, accuracy: 0.01, context)
                        XCTAssertEqual(Double(root.paint.cornerRadius), 16 * scale, accuracy: 0.01, context)
                        bar.style.textColor = "#123456"
                        widget.render(bar)
                        let overridden = try XCTUnwrap(widget.tree().first { $0.kind == .label }, context)
                        XCTAssertEqual(
                            overridden.content.color.role & 0xFF,
                            UInt16(ShellRole.foreground.rawValue + 1),
                            context
                        )
                    }
                    try clickCommand("open-command-palette windows", widget: widget, context: context)
                    if ["wayline", "nocturne"].contains(profile) {
                        bar.style.backgrounds = false
                        widget.render(bar)
                        let unfilled = try XCTUnwrap(widget.tree().first, context)
                        XCTAssertFalse(unfilled.paint.fill.isVisible, context)
                        XCTAssertFalse(unfilled.paint.stroke.isVisible, context)
                    }
                }
            }
        }
    }

    func testSharedBarCapsulesKeepTheirPaintAndContentInsideTheButton() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in ["default", "lake"] {
            _ = try ShellProfiles.select(profile, in: shell)
            let config = ShellConfig.resolve(shellDirectory: shell)
            for name in [
                "active-window",
                "volume",
                "clock",
                "weather",
                "omniwm",
                "calendar",
                "system-stats",
                "battery",
                "battery-details"
            ] {
                let widget = try makeWidget(name, config: config, shell: shell)
                widget.set("app") { $0.string("Safari") }
                widget.set("bundle") { $0.string("com.apple.Safari") }
                widget.set("title") { $0.string("A quiet afternoon") }
                widget.set("volume") { $0.number(62) }
                widget.set("muted") { $0.bool(false) }
                calendarFixture(widget)
                weatherFixture(widget)
                batteryFixture(widget)
                for state in ["volume", "calendar"].contains(name) ? ["full", "empty"] : ["full"] {
                    if state == "empty" {
                        if name == "volume" { widget.set("volume") { $0.null() } }
                        else { widget.set("calendar") { ShellCalendar(access: "full", events: []).write(into: &$0) } }
                    }
                    for height in [24.0, 28, 32, 40] {
                        for vertical in [false, true] {
                            let context = "\(profile)/\(name) \(state) height=\(height) vertical=\(vertical)"
                            var bar = fixture(config, height: height, vertical: vertical)
                            bar.style.transparent = true
                            bar.style.backgrounds = true
                            widget.render(bar)
                            let root = try XCTUnwrap(widget.tree().first, context)
                            let cross = vertical ? widget.surface.size.width : widget.surface.size.height
                            let main = vertical ? widget.surface.size.height : widget.surface.size.width
                            XCTAssertGreaterThanOrEqual(main, cross, context)
                            if name == "omniwm" {
                                XCTAssertEqual(
                                    widget.surface.size.width,
                                    widget.surface.size.height,
                                    accuracy: 0.01,
                                    context
                                )
                            }
                            XCTAssertEqual(CGFloat(root.paint.cornerRadius), cross / 2, accuracy: 0.01, context)
                            XCTAssertEqual(root.paint.fill.role & 0xFF, UInt16(ShellRole.surface.rawValue + 1), context)
                            XCTAssertEqual(
                                root.paint.stroke.role & 0xFF,
                                UInt16(ShellRole.border.rawValue + 1),
                                context
                            )
                            XCTAssertEqual(root.paint.strokeWidth, 0.5, context)
                            let bounds = CGRect(origin: .zero, size: widget.surface.size).insetBy(dx: -0.01, dy: -0.01)
                            for element in widget.surface.layout.core.elements(matching: { _ in true }) {
                                let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: element))
                                XCTAssertTrue(bounds.contains(frame), context + " \(frame) outside \(bounds)")
                                if name == "omniwm",
                                   widget.text.string(widget.surface.layout.core.content(of: element).text) == "omniwm"
                                {
                                    XCTAssertEqual(frame.midX, bounds.midX, accuracy: 0.01, context)
                                    XCTAssertEqual(frame.midY, bounds.midY, accuracy: 0.01, context)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testSharedBarPreservesTheSystemDrawingForEveryBackgroundSetting() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        XCTAssertTrue(try ShellProfiles.select("system", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        let folder = shell.appendingPathComponent("system/widgets/bar-probe")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func drawing(module: String, bar: ShellBarData) throws -> [String] {
            try """
            local look = require("../lib/\(module)")
            function render(ctx)
                return look.bar(ctx, { onClick = "shell menu", ui.text{ text = "Probe" } })
            end
            """.write(to: folder.appendingPathComponent("init.luau"), atomically: true, encoding: .utf8)
            let widget = try makeWidget("bar-probe", config: config, shell: shell)
            widget.render(bar)
            return widget.tree().map { "\($0.layout) \($0.paint) \($0.content.hover)" }
        }
        for vertical in [false, true] {
            for transparent in [false, true] {
                for backgrounds in [false, true] {
                    var bar = fixture(config, height: 32, vertical: vertical)
                    bar.style.transparent = transparent
                    bar.style.backgrounds = backgrounds
                    XCTAssertEqual(try drawing(module: "look", bar: bar), try drawing(module: "style", bar: bar))
                }
            }
        }
    }

    func testSharedLibrarySelectionSkipsInvalidNamesAndRejectsUnknownLibraries() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in ["default", "first", "second"] {
            let library = shell.appendingPathComponent("\(profile)/lib")
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            try Data("return \"\(profile)\"".utf8).write(to: library.appendingPathComponent("audio.luau"))
        }
        let privateAudio = ["first", "second"].map { shell.appendingPathComponent("\($0)/lib/audio.luau") }
        let before = try privateAudio.map { try Data(contentsOf: $0) }
        try useSharedLibraries(
            ",.,../audio,audio/child,audio..,nested\\audio,", in: shell
        )
        XCTAssertEqual(try privateAudio.map { try Data(contentsOf: $0) }, before)
        XCTAssertThrowsError(try useSharedLibraries("audio-typo", in: shell)) { error in
            XCTAssertEqual((error as NSError).code, CocoaError.fileNoSuchFile.rawValue)
        }
        XCTAssertEqual(try privateAudio.map { try Data(contentsOf: $0) }, before)
        let shared = shell.appendingPathComponent("default/lib/audio.luau")
        let sharedBefore = try Data(contentsOf: shared)
        try useSharedLibraries("audio", in: shell)
        XCTAssertTrue(privateAudio.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(try Data(contentsOf: shared), sharedBefore)
    }

    func testSharedWeatherModelLimitsForecastsAndNormalizesRangesAndUnits() throws {
        let shell = try sharedLibraryShell("weather")
        defer { try? FileManager.default.removeItem(at: shell) }
        let folder = shell.appendingPathComponent("default/widgets/weather-model-probe")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        local weather = require("../lib/weather")
        function render(ctx)
            local m = weather.model(ctx, (ctx.data.settings or {}).compact)
            local rows = {
                ui.text{ text = "hours:" .. #m.hours },
                ui.text{ text = "days:" .. #m.days },
                ui.text{ text = "limit:" .. m.forecastHours },
                ui.text{ text = "wind:" .. m.windValue },
                ui.text{ text = "temperature:" .. m.temperature },
                ui.text{ text = "stale:" .. tostring(m.stale) },
                ui.text{ text = "condition:" .. m.condition } }
            for index, day in m.days do
                rows[#rows + 1] = ui.text{ text = string.format("range%d:%.4f:%.4f", index, day.from, day.to) }
            end
            return ui.column(rows)
        end
        """.write(to: folder.appendingPathComponent("init.luau"), atomically: true, encoding: .utf8)
        let config = ShellConfig.resolve(shellDirectory: shell)
        let widget = try makeWidget("weather-model-probe", config: config, shell: shell)
        weatherFixture(widget)
        let bar = fixture(config, height: 32, vertical: false)
        widget.set("settings") { ShellServiceValue.object([:]).write(to: &$0) }
        widget.render(bar)
        XCTAssertTrue(widget.strings().contains("hours:12"))
        XCTAssertTrue(widget.strings().contains("days:7"))
        XCTAssertTrue(widget.strings().contains("limit:12"))
        XCTAssertTrue(widget.strings().contains("stale:nil"))
        XCTAssertTrue(widget.strings().contains("range1:0.2500:0.8750"))
        XCTAssertTrue(widget.strings().contains("range3:0.3750:1.0000"))
        XCTAssertTrue(widget.strings().contains("range5:0.0000:0.5000"))
        XCTAssertTrue(widget.strings().contains("condition:" + ShellLocalizer.string("Partly cloudy", [])))
        for hours in 4 ... 12 {
            widget.set("settings") {
                ShellServiceValue.object(["forecastHours": .number(Double(hours))]).write(to: &$0)
            }
            widget.render(bar)
            XCTAssertTrue(widget.strings().contains("hours:\(hours)"))
            XCTAssertTrue(widget.strings().contains("limit:\(hours)"))
        }
        widget.set("settings") {
            ShellServiceValue.object(["compact": .bool(true), "forecastHours": .number(12)]).write(to: &$0)
        }
        widget.render(bar)
        XCTAssertTrue(widget.strings().contains("hours:8"))
        XCTAssertTrue(widget.strings().contains("days:5"))
        let number = { ShellFormatter.string(kind: OMNI_FORMAT_NUMBER, $0, digits: 0) }
        for (unit, windUnit) in [("°C", "km/h"), ("°F", "mph")] {
            weatherFixture(widget, stale: true, unit: unit, flatRange: true)
            widget.render(bar)
            XCTAssertTrue(widget.strings().contains("wind:\(number(14)) \(windUnit)"))
            XCTAssertTrue(widget.strings().contains("stale:" + ShellLocalizer.string("Last update failed", [])))
            XCTAssertEqual(widget.strings().filter { $0.hasPrefix("range") }, (1 ... 5).map {
                "range\($0):0.0000:0.0000"
            })
        }
        var weather = weatherFixture(widget)
        weather.temp = 12.5
        weather.wind = 12.5
        widget.set("weather") { weather.write(into: &$0) }
        widget.render(bar)
        XCTAssertTrue(widget.strings().contains("temperature:\(number(13))°C"))
        XCTAssertTrue(widget.strings().contains("wind:\(number(13)) km/h"))
        XCTAssertTrue(widget.strings().contains("stale:nil"))
    }

    func testSharedWeatherBarsKeepSelectionsAndFreshClicksThroughEverySkin() throws {
        let shell = try sharedLibraryShell("weather")
        defer { try? FileManager.default.removeItem(at: shell) }
        let base: [String: ShellServiceValue] = [
            "symbol": .text("cloud.sun"), "temp": .number(18.4), "condition": .text("Partly cloudy"),
            "code": .number(2), "day": .bool(true), "unit": .text("°C"), "place": .text("Toronto"),
            "hours": .array([]), "days": .array([]), "status": .text("ok")
        ]
        let ignored: [(String, ShellServiceValue)] = [
            ("hours", .array([.object(["label": .text("Later")])])),
            ("days", .array([.object(["label": .text("Tomorrow")])])),
            ("unit", .text("°F")), ("place", .text("Elsewhere")), ("status", .text("stale"))
        ]
        let selected: [(String, ShellServiceValue)] = [
            ("symbol", .text("moon.stars")), ("temp", .number(24)), ("condition", .text("Rain")),
            ("code", .number(61)), ("day", .bool(false))
        ]
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let height = config.barOverride?.settings.height ?? 32
            let widget = try makeWidget(
                "weather",
                config: config,
                shell: shell,
                source: shell.appendingPathComponent("default/widgets/weather/init.luau")
            )
            for vertical in [false, true] {
                for backgrounds in [false, true] {
                    let context = "\(profile) vertical=\(vertical) backgrounds=\(backgrounds)"
                    var bar = fixture(config, height: height, vertical: vertical)
                    bar.style.backgrounds = backgrounds
                    widget.set("weather") { ShellServiceValue.object(base).write(to: &$0) }
                    widget.render(bar)
                    var stats = omni_render_stats()
                    var error = [CChar](repeating: 0, count: 256)
                    XCTAssertEqual(omni_instance_render(
                        widget.instance,
                        OMNI_VIEW_BAR,
                        100_000_000,
                        &stats,
                        &error,
                        error.count
                    ), OMNI_OK, context)
                    XCTAssertNotEqual(stats.deps & ShellDataKey.weather.bit, 0, context)
                    XCTAssertEqual(stats.deps & ShellDataKey.seconds.bit, 0, context)
                    for (field, value) in ignored {
                        widget.set("weather") { ShellServiceValue.object(base).write(to: &$0) }
                        widget.render(bar)
                        var changed = base
                        changed[field] = value
                        widget.set("weather") { ShellServiceValue.object(changed).write(to: &$0) }
                        XCTAssertFalse(omni_instance_needs_render(
                            widget.instance,
                            OMNI_VIEW_BAR,
                            ShellDataKey.weather.bit
                        ), context + " " + field)
                    }
                    for (field, value) in selected {
                        widget.set("weather") { ShellServiceValue.object(base).write(to: &$0) }
                        widget.render(bar)
                        var changed = base
                        changed[field] = value
                        widget.set("weather") { ShellServiceValue.object(changed).write(to: &$0) }
                        XCTAssertTrue(omni_instance_needs_render(
                            widget.instance,
                            OMNI_VIEW_BAR,
                            ShellDataKey.weather.bit
                        ), context + " " + field)
                    }
                    widget.set("weather") { ShellServiceValue.object(base).write(to: &$0) }
                    widget.render(bar)
                    let button = try XCTUnwrap(widget.surface.layout.core.elements {
                        $0.action == OMNI_ACTION_POPOUT
                    }.first, context)
                    let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                    let point = CGPoint(x: frame.midX, y: frame.midY)
                    let before = widget.actions.count
                    widget.surface.press(at: point)
                    widget.surface.release(at: point)
                    XCTAssertEqual(widget.actions.count, before + 1, context)
                    XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT, context)
                }
            }
            widget.set("weather") { $0.null() }
            widget.render(fixture(config, height: height, vertical: false))
            XCTAssertEqual(widget.surface.size, .zero, profile)
            var stats = omni_render_stats()
            var error = [CChar](repeating: 0, count: 256)
            XCTAssertEqual(omni_instance_render(
                widget.instance,
                OMNI_VIEW_BAR,
                100_000_000,
                &stats,
                &error,
                error.count
            ), OMNI_OK, profile)
            XCTAssertNotEqual(stats.deps & ShellDataKey.weather.bit, 0, profile)
            weatherFixture(widget)
            XCTAssertTrue(omni_instance_needs_render(widget.instance, OMNI_VIEW_BAR, ShellDataKey.weather.bit), profile)
            widget.render(fixture(config, height: height, vertical: false))
            XCTAssertGreaterThan(widget.surface.size.width, 0, profile)
            XCTAssertGreaterThan(widget.surface.size.height, 0, profile)
        }
    }

    func testSharedWeatherPanelsKeepForecastLimitsStaleFeedbackAndCompactContent() throws {
        let shell = try sharedLibraryShell("weather")
        defer { try? FileManager.default.removeItem(at: shell) }
        let hourLabels = (0 ..< 14).map { "Forecast hour \($0)" }
        let dayLabels = ["Today", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu"]
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for name in ["weather", "control-center"] {
                let context = "\(profile)/\(name)"
                let widget = try makeWidget(
                    name,
                    config: config,
                    shell: shell,
                    source: name == "weather" ? shell
                        .appendingPathComponent("default/widgets/weather/init.luau") : nil
                )
                var weather = weatherFixture(widget)
                weather.hours = weather.hours.enumerated().map { index, hour in
                    ShellWeatherHour(
                        time: hour.time,
                        label: hourLabels[index],
                        temp: hour.temp,
                        code: hour.code,
                        day: hour.day,
                        rain: hour.rain
                    )
                }
                widget.set("weather") { weather.write(into: &$0) }
                widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
                for limit in [4, 12] {
                    widget.set("settings") {
                        ShellServiceValue.object(["tab": .text("weather"), "forecastHours": .number(Double(limit))])
                            .write(to: &$0)
                    }
                    _ = widget.renderPopout()
                    let strings = widget.strings(OMNI_VIEW_POPOUT)
                    XCTAssertTrue(strings.contains("Toronto"), context)
                    XCTAssertTrue(strings.contains(ShellLocalizer.string("Partly cloudy", [])), context)
                    XCTAssertEqual(strings.filter { hourLabels.contains($0) }, Array(hourLabels.prefix(
                        name == "control-center" ? 8 : limit
                    )), context)
                    XCTAssertEqual(strings.filter { dayLabels.contains($0) }, Array(dayLabels.prefix(
                        name == "control-center" ? 5 : 7
                    )), context)
                }
                if name == "weather" {
                    weather.stale = true
                    widget.set("weather") { weather.write(into: &$0) }
                    _ = widget.renderPopout()
                    let strings = widget.strings(OMNI_VIEW_POPOUT)
                    XCTAssertTrue(strings.contains(ShellLocalizer.string("Last update failed", [])), context)
                    XCTAssertTrue(
                        strings.contains(ShellLocalizer.string("Weather by %@", [.text("Open-Meteo.com")])),
                        context
                    )
                    let wind = ShellFormatter.string(kind: OMNI_FORMAT_NUMBER, 14, digits: 0) + " km/h"
                    XCTAssertTrue(strings.contains { $0.contains(wind) }, context)
                }
            }
        }
    }

    func testSharedWeatherPanelsRemainNonzeroAndDemandWeatherWithoutData() throws {
        let shell = try sharedLibraryShell("weather")
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for name in ["weather", "control-center"] {
                let context = "\(profile)/\(name)"
                let widget = try makeWidget(
                    name,
                    config: config,
                    shell: shell,
                    source: name == "weather" ? shell
                        .appendingPathComponent("default/widgets/weather/init.luau") : nil
                )
                widget.set("settings") { ShellServiceValue.object(["tab": .text("weather")]).write(to: &$0) }
                widget.set("weather") { $0.null() }
                widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
                widget.layoutPopout()
                XCTAssertGreaterThan(widget.surface.size.width, 0, context)
                XCTAssertGreaterThan(widget.surface.size.height, 0, context)
                XCTAssertTrue(
                    widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Unavailable", [])),
                    context
                )
                if ["nocturne", "wayline"].contains(profile), name == "weather" {
                    let elements = widget.surface.layout.core.elements { _ in true }
                    let body = try XCTUnwrap(elements.first {
                        let paint = widget.surface.layout.core.paint(of: $0)
                        return paint.cornerRadius == (profile == "nocturne" ? 18 : 12)
                    }, context)
                    let label = try XCTUnwrap(elements.first {
                        widget.text.string(widget.surface.layout.core.content(of: $0).text)
                            == ShellLocalizer.string("Unavailable", [])
                    }, context)
                    let card = widget.surface.layout.core.parent(of: label)
                    let bounds = CGRect(widget.surface.layout.core.absoluteFrame(of: body))
                    let content = CGRect(widget.surface.layout.core.absoluteFrame(of: card))
                    XCTAssertTrue(bounds.contains(content), context + ": \(content) outside \(bounds)")
                }
                if profile == "celestial", name == "weather" {
                    let scroll = try XCTUnwrap(widget.surface.layout.core.elements { $0.scrolls }.first, context)
                    let viewport = CGRect(widget.surface.layout.core.absoluteFrame(of: scroll))
                    XCTAssertEqual(viewport.size, CGSize(width: 840, height: 530), context)
                }
                var stats = omni_render_stats()
                var error = [CChar](repeating: 0, count: 256)
                XCTAssertEqual(omni_instance_render(
                    widget.instance,
                    OMNI_VIEW_POPOUT,
                    100_000_000,
                    &stats,
                    &error,
                    error.count
                ), OMNI_OK, context)
                XCTAssertNotEqual(stats.deps & ShellDataKey.weather.bit, 0, context)
                XCTAssertEqual(stats.deps & ShellDataKey.seconds.bit, 0, context)
                weatherFixture(widget)
                _ = widget.renderPopout()
                XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("Toronto"), context)
            }
        }
    }

    func testCelestialDashboardWeatherUsesTheSharedModelAndKeepsItsTabAndMissingState() throws {
        let shell = try sharedLibraryShell("weather")
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertTrue(try ShellProfiles.select("celestial", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        let widget = try makeWidget("dashboard", config: config, shell: shell)
        calendarFixture(widget)
        weatherFixture(widget)
        widget.set("media") { $0.null() }
        widget.render(fixture(config, height: config.barOverride?.settings.height ?? 60, vertical: false))
        _ = widget.renderPopout()
        let temperature = ShellFormatter.string(kind: OMNI_FORMAT_NUMBER, 18, digits: 0)
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(temperature + "°C"))
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Partly cloudy", [])))
        let weather = weatherFixture(widget, stale: true, unit: "°F")
        _ = widget.renderPopout()
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(temperature + "°F"))
        widget.layoutPopout()
        let label = try XCTUnwrap(widget.surface.layout.core.elements {
            widget.text.string($0.text) == ShellLocalizer.string("Weather", [])
        }.first)
        let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: label))
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let before = widget.actions.count
        widget.surface.press(at: point)
        widget.surface.release(at: point)
        XCTAssertEqual(widget.actions.count, before + 1)
        XCTAssertEqual(widget.invoke(try XCTUnwrap(widget.actions.last), view: OMNI_VIEW_POPOUT), [])
        _ = widget.renderPopout()
        let strings = widget.strings(OMNI_VIEW_POPOUT)
        XCTAssertTrue(strings.contains("Toronto"))
        XCTAssertTrue(strings.contains(temperature + "°F"))
        let wind = ShellFormatter.string(kind: OMNI_FORMAT_NUMBER, 14, digits: 0) + " mph"
        XCTAssertTrue(strings.contains { $0.contains(wind) })
        XCTAssertTrue(strings.contains(ShellLocalizer.string("7-day forecast", [])))
        try assertCelestialWeatherLayout(widget, weather: weather, context: "dashboard")
        widget.set("weather") { $0.null() }
        _ = widget.renderPopout()
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Unavailable", [])))
        widget.layoutPopout()
        let scroll = try XCTUnwrap(widget.surface.layout.core.elements { $0.scrolls }.first)
        XCTAssertEqual(
            CGRect(widget.surface.layout.core.absoluteFrame(of: scroll)).size,
            CGSize(width: 840, height: 530)
        )
    }

    func testCelestialWeatherPopoutKeepsExtrasReachableWithinItsViewport() throws {
        let shell = try sharedLibraryShell("weather")
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertTrue(try ShellProfiles.select("celestial", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        let widget = try makeWidget(
            "weather",
            config: config,
            shell: shell,
            source: shell.appendingPathComponent("default/widgets/weather/init.luau")
        )
        let weather = weatherFixture(widget, stale: true)
        widget.render(fixture(config, height: config.barOverride?.settings.height ?? 60, vertical: false))
        try assertCelestialWeatherLayout(widget, weather: weather, context: "weather")
    }

    func testSharedClockBarsKeepOptionsTimeAndGesturesWithoutCalendarDemand() throws {
        let shell = try sharedLibraryShell("calendar")
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let height = config.barOverride?.settings.height ?? 32
            let widget = try makeWidget(
                "clock", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/clock/init.luau")
            )
            calendarFixture(widget)
            for vertical in [false, true] {
                for date in [false, true] {
                    for icon in [false, true] {
                        let context = "\(profile) vertical=\(vertical) date=\(date) icon=\(icon)"
                        widget.set("settings") {
                            ShellServiceValue.object(["date": .bool(date), "icon": .bool(icon)]).write(to: &$0)
                        }
                        widget.render(fixture(config, height: height, vertical: vertical))
                        var stats = omni_render_stats()
                        var error = [CChar](repeating: 0, count: 256)
                        XCTAssertEqual(
                            omni_instance_render(
                                widget.instance,
                                OMNI_VIEW_BAR,
                                100_000_000,
                                &stats,
                                &error,
                                error.count
                            ),
                            OMNI_OK, context
                        )
                        XCTAssertEqual(stats.deps & (ShellDataKey.calendar.bit | ShellDataKey.seconds.bit), 0, context)
                        let strings = widget.strings()
                        XCTAssertEqual(
                            strings.contains("calendar") || strings.contains("calendar_month") || strings
                                .contains("clock.fill"),
                            icon, context
                        )
                        if vertical {
                            for value in ["09", "41", "am"] {
                                XCTAssertTrue(strings.contains(value), context + ": " + value)
                            }
                        } else {
                            XCTAssertTrue(strings.contains("9:41 AM"), context)
                            XCTAssertEqual(
                                strings.contains(profile == "matrix" ? "FRI OCT 23" : "Fri Oct 23"),
                                date,
                                context
                            )
                            if profile == "matrix" {
                                XCTAssertEqual(strings.contains("//"), date, context)
                            }
                        }
                        let element = try XCTUnwrap(widget.surface.layout.core.elements {
                            profile == "celestial"
                                ? widget.text.string($0.action) == "shell toggle dashboard"
                                : $0.action == OMNI_ACTION_POPOUT
                        }.first, context)
                        let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: element))
                        let point = CGPoint(x: frame.midX, y: frame.midY)
                        let before = widget.actions.count
                        widget.surface.press(at: point)
                        widget.surface.release(at: point)
                        XCTAssertEqual(widget.actions.count, before + 1, context)
                        if profile == "celestial" {
                            XCTAssertEqual(widget.clicks.last?.action, "shell toggle dashboard", context)
                            let beforeRight = widget.actions.count
                            widget.surface.press(at: point, button: .right)
                            widget.surface.release(at: point, event: ShellEvent(button: .right))
                            XCTAssertEqual(widget.actions.count, beforeRight + 1, context)
                            XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT, context)
                        } else {
                            XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT, context)
                        }
                    }
                }
            }
            widget.set("clock") { $0.string("19:04") }
            widget.render(fixture(config, height: height, vertical: true))
            XCTAssertTrue(widget.strings().contains("19"), profile)
            XCTAssertTrue(widget.strings().contains("04"), profile)
            XCTAssertFalse(widget.strings().contains("am"), profile)
            XCTAssertFalse(widget.strings().contains("pm"), profile)
        }
    }

    func testSharedVerticalClocksParseSupportedFormatsAndFallbackForRegionalFormats() throws {
        let shell = try sharedLibraryShell("calendar")
        defer { try? FileManager.default.removeItem(at: shell) }
        let parsed = [
            ("4:05\u{202F}PM", ["04", "05", "pm"]),
            ("4:05 pm", ["04", "05", "pm"]),
            ("16.05", ["16", "05"]),
            ("19:04", ["19", "04"])
        ]
        let fallback = ["오후 4:05", "下午4:05", "4:05\u{202F}μμ", "٤:٠٥ م"]
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let bar = fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: true)
            let widget = try makeWidget(
                "clock", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/clock/init.luau")
            )
            calendarFixture(widget)
            widget.set("settings") {
                ShellServiceValue.object(["date": .bool(false), "icon": .bool(false)]).write(to: &$0)
            }
            for (clock, expected) in parsed {
                widget.set("clock") { $0.string(clock) }
                widget.render(bar)
                XCTAssertEqual(widget.strings(), expected, "\(profile) \(clock)")
            }
            for clock in fallback {
                widget.set("clock") { $0.string(clock) }
                widget.render(bar)
                let strings = widget.strings()
                XCTAssertEqual(strings.count, 2, "\(profile) \(clock)")
                XCTAssertTrue(strings.allSatisfy {
                    $0.range(of: "^[0-9]{2}$", options: .regularExpression) != nil
                }, "\(profile) \(clock): \(strings)")
            }
        }
    }

    func testSharedClockAndControlCenterKeepLoadingCalendarPanelsOpenAndDemandCalendarData() throws {
        let shell = try sharedLibraryShell("calendar")
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for name in ["clock", "control-center"] {
                let context = "\(profile)/\(name)"
                let widget = try makeWidget(
                    name, config: config, shell: shell,
                    source: name == "clock" ? shell.appendingPathComponent("default/widgets/clock/init.luau") : nil
                )
                widget.set("settings") { ShellServiceValue.object(["tab": .text("calendar")]).write(to: &$0) }
                calendarFixture(widget)
                widget.set("calendar") { $0.null() }
                widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
                widget.layoutPopout()
                XCTAssertGreaterThan(widget.surface.size.width, 0, context)
                XCTAssertGreaterThan(widget.surface.size.height, 0, context)
                XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(
                    ShellLocalizer.string("Loading…", [])
                ), context)
                var stats = omni_render_stats()
                var error = [CChar](repeating: 0, count: 256)
                XCTAssertEqual(
                    omni_instance_render(widget.instance, OMNI_VIEW_POPOUT, 100_000_000, &stats, &error, error.count),
                    OMNI_OK, context
                )
                XCTAssertNotEqual(stats.deps & ShellDataKey.calendar.bit, 0, context)
                XCTAssertEqual(stats.deps & ShellDataKey.seconds.bit, 0, context)
                calendarFixture(widget)
                _ = widget.renderPopout()
                let strings = widget.strings(OMNI_VIEW_POPOUT)
                XCTAssertFalse(strings.contains(ShellLocalizer.string("Loading…", [])), context)
                XCTAssertTrue(strings.contains("October 2026"), context)
                XCTAssertTrue(strings.contains("Team standup"), context)
            }
        }
    }

    func testCelestialDashboardCalendarDoesNotDemandSecondsWithoutMedia() throws {
        let shell = try sharedLibraryShell("calendar")
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertTrue(try ShellProfiles.select("celestial", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        let widget = try makeWidget("dashboard", config: config, shell: shell)
        calendarFixture(widget)
        widget.set("media") { $0.null() }
        widget.render(fixture(config, height: config.barOverride?.settings.height ?? 60, vertical: false))
        _ = widget.renderPopout()
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("October 2026"))
        XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Nothing is playing", [])))
        var stats = omni_render_stats()
        var error = [CChar](repeating: 0, count: 256)
        XCTAssertEqual(
            omni_instance_render(widget.instance, OMNI_VIEW_POPOUT, 100_000_000, &stats, &error, error.count),
            OMNI_OK
        )
        XCTAssertNotEqual(stats.deps & ShellDataKey.calendar.bit, 0)
        XCTAssertEqual(stats.deps & ShellDataKey.seconds.bit, 0)
    }

    func testSharedCalendarPanelsDeliverNavigationAgendaAccessAndPreciseScroll() throws {
        let shell = try sharedLibraryShell("calendar")
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for name in ["clock", "calendar", "control-center"] {
                let context = "\(profile)/\(name)"
                let widget = try makeWidget(
                    name, config: config, shell: shell,
                    source: name == "control-center" ? nil : shell
                        .appendingPathComponent("default/widgets/\(name)/init.luau")
                )
                widget.set("settings") {
                    ShellServiceValue.object(["tab": .text("calendar"), "agendaEvents": .number(2)]).write(to: &$0)
                }
                calendarFixture(widget)
                widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
                _ = widget.renderPopout()
                for label in ["Team standup", "Design review", "Now"] {
                    XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string(label, [])), context)
                }
                XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(
                    ShellLocalizer.string("In %lld min", [.number(25)])
                ), context)
                XCTAssertFalse(widget.strings(OMNI_VIEW_POPOUT).contains("Team offsite"), context)
                for command in [
                    "calendar month previous", "calendar month today", "calendar month next",
                    "calendar open standup", "calendar open review", "calendar open"
                ] {
                    widget.layoutPopout()
                    try clickCommand(command, widget: widget, context: context)
                }
                widget.layoutPopout()
                let scrollElement = try XCTUnwrap(
                    widget.surface.layout.core.elements { $0.scrollAction != 0 }.first, context
                )
                let scrollAction = widget.surface.layout.core.content(of: scrollElement).scrollAction
                let scrollFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: scrollElement))
                var probe = ShellEvent(button: .none)
                probe.kind = .scroll
                let beforeScroll = widget.actions.count
                XCTAssertTrue(widget.surface.scroll(
                    at: CGPoint(x: scrollFrame.midX, y: scrollFrame.midY), event: probe
                ), context)
                XCTAssertEqual(widget.actions.count, beforeScroll + 1, context)
                XCTAssertEqual(widget.actions.last, scrollAction, context)
                let scroll = { (dy: Double, precise: Bool) in
                    var event = ShellEvent(button: .none)
                    event.kind = .scroll
                    event.dy = dy
                    event.precise = precise
                    return widget.invoke(scrollAction, view: OMNI_VIEW_POPOUT, event: event)
                }
                XCTAssertEqual(scroll(5, true), [], context)
                XCTAssertEqual(scroll(7, true), ["calendar month previous"], context)
                XCTAssertEqual(scroll(-6, true), [], context)
                XCTAssertEqual(scroll(-6, true), ["calendar month next"], context)
                XCTAssertEqual(scroll(0, false), [], context)
                XCTAssertEqual(scroll(-2, false), ["calendar month next", "calendar month next"], context)
                XCTAssertEqual(scroll(1, false), ["calendar month previous"], context)
                for (access, command) in [
                    ("notDetermined", "calendar authorize"), ("denied", "calendar settings"), ("full", "calendar open")
                ] {
                    calendarFixture(widget, access: access, month: false)
                    widget.layoutPopout()
                    try clickCommand(command, widget: widget, context: context + " " + access)
                    let nodes = widget.renderPopout()
                    let actions = nodes.map { widget.text.string($0.content.action) }
                    let celestialPanel = profile == "celestial" && name != "control-center"
                    XCTAssertEqual(actions.filter { $0 == command }.count, 1, context + " " + access)
                    XCTAssertEqual(
                        widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Open Calendar", [])),
                        !celestialPanel || access == "full", context
                    )
                    if access == "full" {
                        XCTAssertFalse(actions.contains("calendar authorize"), context)
                        XCTAssertEqual(actions.filter { $0.hasPrefix("calendar open ") }.count, 2, context)
                    } else if celestialPanel {
                        XCTAssertFalse(actions.contains("calendar open"), context + " " + access)
                    }
                }
            }
        }
    }

    func testSharedCalendarAgendaLimitAndBarCountdownFollowTheModel() throws {
        let shell = try sharedLibraryShell("calendar")
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget(
                "calendar", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/calendar/init.luau")
            )
            calendarFixture(widget)
            widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
            for (limit, expected) in [(1.0, 1), (2, 2), (2.7, 3), (12, 4)] {
                widget.set("settings") {
                    ShellServiceValue.object(["agendaEvents": .number(limit)]).write(to: &$0)
                }
                let events = widget.renderPopout()
                    .filter { widget.text.string($0.content.action).hasPrefix("calendar open ") }
                XCTAssertEqual(events.count, expected, "\(profile) agendaEvents=\(limit)")
            }
            widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
            XCTAssertTrue(widget.strings().contains("Team standup"), profile)
            XCTAssertTrue(widget.strings().contains(ShellLocalizer.string("Now", [])), profile)
            widget.set("seconds") { $0.number(1_000_901) }
            widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
            XCTAssertTrue(widget.strings().contains("Design review"), profile)
            XCTAssertTrue(widget.strings().contains(ShellLocalizer.string("In %lld min", [.number(10)])), profile)
        }
    }

    func testSharedMediaBarsKeepSelectionsAndInputThroughEverySkin() throws {
        let shell = try sharedLibraryShell("media")
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let height = config.barOverride?.settings.height ?? 32
            let widget = try makeWidget(
                "media", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/media/init.luau")
            )
            for vertical in [false, true] {
                for backgrounds in [false, true] {
                    mediaFixture(widget)
                    var bar = fixture(config, height: height, vertical: vertical)
                    bar.style.backgrounds = backgrounds
                    widget.render(bar)
                    let context = "\(profile) vertical=\(vertical) backgrounds=\(backgrounds)"
                    var stats = omni_render_stats()
                    var error = [CChar](repeating: 0, count: 256)
                    XCTAssertEqual(
                        omni_instance_render(widget.instance, OMNI_VIEW_BAR, 100_000_000, &stats, &error, error.count),
                        OMNI_OK, context
                    )
                    XCTAssertNotEqual(stats.deps & ShellDataKey.media.bit, 0, context)
                    XCTAssertEqual(stats.deps & (ShellDataKey.seconds.bit | ShellDataKey.lyrics.bit), 0, context)
                    mediaFixture(widget, elapsed: 120)
                    XCTAssertFalse(
                        omni_instance_needs_render(widget.instance, OMNI_VIEW_BAR, ShellDataKey.media.bit),
                        context
                    )
                    XCTAssertFalse(
                        omni_instance_needs_render(widget.instance, OMNI_VIEW_BAR, ShellDataKey.seconds.bit),
                        context
                    )
                    mediaFixture(widget, title: "Changed track")
                    XCTAssertTrue(
                        omni_instance_needs_render(widget.instance, OMNI_VIEW_BAR, ShellDataKey.media.bit),
                        context
                    )
                    mediaFixture(widget)
                    widget.render(bar)
                    XCTAssertLessThanOrEqual(
                        vertical ? widget.surface.size.width : widget.surface.size.height,
                        height,
                        context
                    )
                    let button = try XCTUnwrap(
                        widget.surface.layout.core.elements { $0.action == OMNI_ACTION_POPOUT }.first,
                        context
                    )
                    let content = widget.surface.layout.core.content(of: button)
                    XCTAssertEqual(widget.text.string(content.help), "Northern Lights — Sample Artist", context)
                    let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                    let point = CGPoint(x: frame.midX, y: frame.midY)
                    let beforePopout = widget.actions.count
                    widget.surface.press(at: point)
                    widget.surface.release(at: point)
                    XCTAssertEqual(widget.actions.count, beforePopout + 1, context)
                    XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT, context)
                    let before = widget.clicks.count
                    widget.surface.press(at: point, button: .right)
                    widget.surface.release(at: point, event: ShellEvent(button: .right))
                    XCTAssertEqual(widget.clicks.count, before + 1, context)
                    XCTAssertEqual(widget.clicks.last?.action, "media toggle", context)
                }
            }
            widget.set("media") { $0.null() }
            widget.render(fixture(config, height: height, vertical: false))
            XCTAssertEqual(widget.surface.size, .zero, profile)
        }
    }

    func testSharedMediaPanelsDeliverControlsSeekAndLyricsThroughEverySkin() throws {
        let shell = try sharedLibraryShell("media")
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for name in profile == "celestial" ? ["media", "control-center", "dashboard"] :
                ["media", "control-center"]
            {
                let context = "\(profile)/\(name)"
                let widget = try makeWidget(
                    name, config: config, shell: shell,
                    source: name == "media" ? shell.appendingPathComponent("default/widgets/media/init.luau") : nil
                )
                mediaFixture(widget)
                widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
                try selectMediaTab(widget, name: name)
                let nodes = widget.renderPopout()
                if name == "control-center", ["wayline", "nocturne", "celestial"].contains(profile) {
                    let index = try XCTUnwrap(
                        nodes.firstIndex { widget.text.string($0.content.action) == "media toggle" },
                        context
                    )
                    let play = nodes[index]
                    XCTAssertEqual(play.paint.fill.role & 0xFF, UInt16(ShellRole.accent.rawValue + 1), context)
                    XCTAssertEqual(play.paint.cornerRadius, 20, context)
                    let glyph = try XCTUnwrap(
                        nodes[(index + 1) ..< Int(play.subtreeEnd)].first { $0.kind == .symbol },
                        context
                    )
                    XCTAssertEqual(
                        glyph.content.color.role & 0xFF,
                        UInt16(ShellRole.accentForeground.rawValue + 1),
                        context
                    )
                    widget.layoutPopout()
                    let handle = try XCTUnwrap(
                        widget.surface.layout.core.elements { widget.text.string($0.action) == "media toggle" }.first,
                        context
                    )
                    let frame = widget.surface.layout.core.absoluteFrame(of: handle)
                    XCTAssertEqual(frame.width, 40, context)
                    XCTAssertEqual(frame.height, 40, context)
                }
                if profile == "wayline", name == "media" {
                    let current = try XCTUnwrap(
                        nodes.first { widget.text.string($0.content.text) == "Every window holds a song" },
                        context
                    )
                    XCTAssertEqual(current.content.color.role & 0xFF, UInt16(ShellRole.accent.rawValue + 1), context)
                }
                for command in [
                    "media previous",
                    "media toggle",
                    "media next",
                    "media open",
                    "media shuffle",
                    "media repeat"
                ] {
                    widget.layoutPopout()
                    try clickCommand(command, widget: widget, context: context)
                }
                let sliders = nodes.filter { $0.kind == .slider }
                let slider = try XCTUnwrap(sliders.first, context)
                XCTAssertEqual(sliders.count, 1, context)
                XCTAssertEqual(slider.content.value, 407, context)
                var event = ShellEvent(button: .left)
                event.kind = .slider
                event.value = 0.5
                event.phase = .changed
                XCTAssertEqual(widget.invoke(slider.content.action, view: OMNI_VIEW_POPOUT, event: event), [], context)
                event.phase = .ended
                XCTAssertEqual(
                    widget.invoke(slider.content.action, view: OMNI_VIEW_POPOUT, event: event),
                    ["media seek 121.5"],
                    context
                )
                widget.layoutPopout()
                try clickCommand("media seek 98.0", widget: widget, context: context)
                var stats = omni_render_stats()
                var error = [CChar](repeating: 0, count: 256)
                XCTAssertEqual(
                    omni_instance_render(widget.instance, OMNI_VIEW_POPOUT, 100_000_000, &stats, &error, error.count),
                    OMNI_OK, context
                )
                let timing = ShellDataKey.seconds.bit | ShellDataKey.lyrics.bit
                XCTAssertEqual(stats.deps & timing, timing, context)
                mediaFixture(widget, shuffle: nil, repeatMode: nil)
                let unsupported = widget.renderPopout()
                let actions = unsupported.map { widget.text.string($0.content.action) }
                XCTAssertFalse(actions.contains("media shuffle"), context)
                XCTAssertFalse(actions.contains("media repeat"), context)
                mediaFixture(widget, playing: false, shuffle: true, repeatMode: .one)
                let paused = widget.renderPopout()
                let symbols = paused.filter { $0.kind == .symbol || $0.kind == .label }
                    .map { widget.text.string($0.content.text) }
                XCTAssertTrue(
                    symbols.contains(profile == "celestial" && name != "control-center" ? "play_arrow" : "play.fill"),
                    context
                )
                XCTAssertTrue(
                    symbols.contains(profile == "celestial" && name != "control-center" ? "repeat_one" : "repeat.1"),
                    context
                )
                for (lyrics, expected) in [(ShellLyrics.loading, "Loading lyrics…"), (
                    .missing,
                    "No lyrics found"
                )] {
                    mediaFixture(widget, lyrics: lyrics)
                    let state = widget.renderPopout()
                    XCTAssertTrue(
                        widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string(expected, [])),
                        context
                    )
                    XCTAssertFalse(
                        state.contains { widget.text.string($0.content.action).hasPrefix("media seek ") },
                        context
                    )
                }
                widget.set("media") { $0.null() }
                widget.set("lyrics") { $0.null() }
                _ = widget.renderPopout()
                XCTAssertTrue(
                    widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Nothing is playing", [])),
                    context
                )
                if name == "media", profile == "nocturne" {
                    widget.layoutPopout()
                    let label = try XCTUnwrap(widget.surface.layout.core.elements {
                        widget.text.string($0.text) == ShellLocalizer.string("Nothing is playing", [])
                    }.first, context)
                    let frame = widget.surface.layout.core.absoluteFrame(of: label)
                    XCTAssertEqual(
                        CGFloat(frame.x + frame.width / 2),
                        widget.surface.size.width / 2,
                        accuracy: 0.5,
                        context
                    )
                }
                if name == "control-center", ["system", "matrix", "sakura"].contains(profile) {
                    mediaFixture(widget)
                    widget.set("settings") { ShellServiceValue.object(["tab": .text("overview")]).write(to: &$0) }
                    let overview = widget.renderPopout()
                    XCTAssertFalse(
                        overview.contains { widget.text.string($0.content.action).hasPrefix("media seek ") },
                        context
                    )
                    XCTAssertEqual(
                        omni_instance_render(
                            widget.instance,
                            OMNI_VIEW_POPOUT,
                            100_000_000,
                            &stats,
                            &error,
                            error.count
                        ),
                        OMNI_OK, context
                    )
                    XCTAssertEqual(stats.deps & timing, 0, context)
                }
            }
        }
    }

    func testSharedMediaModelsClampProgressAndFormatLongDurations() throws {
        let shell = try sharedLibraryShell("media")
        defer { try? FileManager.default.removeItem(at: shell) }
        let config = ShellConfig.resolve(shellDirectory: shell)
        let widget = try makeWidget("media", config: config, shell: shell)
        widget.render(fixture(config, height: 32, vertical: false))
        for (elapsed, playing, expected) in [(-50.0, false, 0), (5000.0, false, 1000), (20.0, false, 5)] {
            mediaFixture(widget, playing: playing, elapsed: elapsed, duration: 3661)
            let slider = try XCTUnwrap(widget.renderPopout().first { $0.kind == .slider })
            XCTAssertEqual(slider.content.value, UInt32(expected))
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("1:01:01"))
        }
        mediaFixture(widget, elapsed: nil)
        XCTAssertFalse(widget.renderPopout().contains { $0.kind == .slider })
        mediaFixture(widget, duration: nil)
        let unknownDuration = widget.renderPopout()
        XCTAssertFalse(unknownDuration.contains { $0.kind == .slider })
        XCTAssertEqual(
            unknownDuration.map { widget.text.string($0.content.action) }.filter { $0.hasPrefix("media seek ") },
            ["media seek 86.0", "media seek 92.0", "media seek 98.0", "media seek 104.0", "media seek 110.0"]
        )
    }

    func testSharedVolumeBarsKeepInputAndAvoidOutputAndAppDemand() throws {
        let shell = try sharedAudioShell()
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let height = config.barOverride?.settings.height ?? 32
            let widget = try makeWidget(
                "volume", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/volume/init.luau")
            )
            audioFixture(widget, access: .granted)
            for vertical in [false, true] {
                for backgrounds in [false, true] {
                    var bar = fixture(config, height: height, vertical: vertical)
                    bar.style.backgrounds = backgrounds
                    widget.render(bar)
                    let context = "\(profile) vertical=\(vertical) backgrounds=\(backgrounds)"
                    var stats = omni_render_stats()
                    var error = [CChar](repeating: 0, count: 256)
                    XCTAssertEqual(
                        omni_instance_render(widget.instance, OMNI_VIEW_BAR, 100_000_000, &stats, &error, error.count),
                        OMNI_OK, context
                    )
                    XCTAssertEqual(stats.deps & (ShellDataKey.outputs.bit | ShellDataKey.audioApps.bit), 0, context)
                    XCTAssertEqual(
                        stats.deps & (ShellDataKey.volume.bit | ShellDataKey.muted.bit),
                        ShellDataKey.volume.bit | ShellDataKey.muted.bit, context
                    )
                    XCTAssertLessThanOrEqual(
                        vertical ? widget.surface.size.width : widget.surface.size.height,
                        height,
                        profile
                    )
                    let button = try XCTUnwrap(
                        widget.surface.layout.core.elements { $0.action == OMNI_ACTION_POPOUT }.first,
                        profile
                    )
                    let content = widget.surface.layout.core.content(of: button)
                    XCTAssertEqual(widget.text.string(content.help), ShellLocalizer.string("Volume", []), profile)
                    XCTAssertNotEqual(content.scrollAction, 0, profile)
                    let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                    let point = CGPoint(x: frame.midX, y: frame.midY)
                    widget.surface.press(at: point)
                    widget.surface.release(at: point)
                    XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT, profile)
                }
            }
            let action = try XCTUnwrap(
                widget.tree().first { $0.content.scrollAction != 0 }?.content.scrollAction,
                profile
            )
            let scroll = { (dy: Double, precise: Bool) in
                var event = ShellEvent(button: .none)
                event.dy = dy
                event.precise = precise
                return widget.invoke(action, event: event)
            }
            let step = profile == "celestial" ? "5" : "6.25"
            XCTAssertEqual(scroll(5, true), [], profile)
            XCTAssertEqual(scroll(-14, true), ["volume down \(step)"], profile)
            XCTAssertEqual(scroll(8, true), [], profile)
            XCTAssertEqual(scroll(8, true), ["volume up \(step)"], profile)
            for volume in [0.0, 62.0] {
                widget.set("volume") { $0.number(volume) }
                widget.set("muted") { $0.bool(true) }
                widget.render(fixture(config, height: height, vertical: false))
                XCTAssertGreaterThan(widget.surface.size.width, 0, profile)
            }
            widget.set("volume") { $0.null() }
            widget.render(fixture(config, height: height, vertical: false))
            if profile == "celestial" {
                XCTAssertEqual(widget.surface.size, .zero, profile)
            } else {
                XCTAssertGreaterThan(widget.surface.size.width, 0, profile)
            }
        }
    }

    func testSharedAudioPanelsDeliverSlidersMutesOutputsAndPermissionThroughEverySkin() throws {
        let shell = try sharedAudioShell()
        defer { try? FileManager.default.removeItem(at: shell) }
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for name in profile == "celestial" ? ["volume", "control-center", "status"] : ["volume", "control-center"] {
                let context = "\(profile)/\(name)"
                let widget = try makeWidget(
                    name, config: config, shell: shell,
                    source: name == "volume" ? shell.appendingPathComponent("default/widgets/volume/init.luau") : nil
                )
                if name == "control-center" {
                    widget.set("settings") { ShellServiceValue.object(["tab": .text("audio")]).write(to: &$0) }
                }
                widget.render(fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false))
                audioFixture(widget, access: .granted)
                let sliders = widget.renderPopout().filter { $0.kind == .slider }
                XCTAssertEqual(sliders.map(\.content.value), [620, 800, 1000, 450], context)
                for (slider, command) in zip(sliders, [
                    "volume set 0",
                    "volume app com.apple.Music set 0",
                    "volume app com.apple.Safari set 0",
                    "volume app com.apple.Podcasts set 0"
                ]) {
                    var event = ShellEvent(button: .left)
                    event.kind = .slider
                    event.phase = .changed
                    event.value = 0
                    XCTAssertEqual(
                        widget.invoke(slider.content.action, view: OMNI_VIEW_POPOUT, event: event),
                        [command],
                        context
                    )
                    event.value = 0.754
                    XCTAssertEqual(
                        widget.invoke(slider.content.action, view: OMNI_VIEW_POPOUT, event: event),
                        [command.replacingOccurrences(of: "set 0", with: "set 75")],
                        context
                    )
                }
                widget.layoutPopout()
                for command in [
                    "volume mute",
                    "volume output 41",
                    "volume output 42",
                    "volume output 43",
                    "volume app com.apple.Music mute",
                    "volume app com.apple.Safari mute",
                    "volume app com.apple.Podcasts mute"
                ] {
                    try clickCommand(command, widget: widget, context: context)
                }
                var stats = omni_render_stats()
                var error = [CChar](repeating: 0, count: 256)
                XCTAssertEqual(
                    omni_instance_render(widget.instance, OMNI_VIEW_POPOUT, 100_000_000, &stats, &error, error.count),
                    OMNI_OK
                )
                let demand = ShellDataKey.outputs.bit | ShellDataKey.audioApps.bit
                XCTAssertEqual(stats.deps & demand, demand, context)
                audioFixture(widget, access: .denied)
                XCTAssertEqual(widget.renderPopout().filter { $0.kind == .slider }.count, 1, context)
                widget.layoutPopout()
                try clickCommand("volume permission", widget: widget, context: context)
                widget.set("volume") { $0.null() }
                widget.set("outputs") { $0.null() }
                widget.set("audioApps") { $0.null() }
                XCTAssertFalse(widget.renderPopout().contains { $0.kind == .slider }, context)
                let unavailable = widget.strings(OMNI_VIEW_POPOUT)
                if profile == "nocturne", name == "volume" {
                    XCTAssertTrue(unavailable.contains("—"), context)
                    XCTAssertTrue(unavailable.contains(ShellLocalizer.string("Volume", [])), context)
                } else {
                    XCTAssertTrue(unavailable.contains(ShellLocalizer.string("Unavailable", [])), context)
                }
            }
        }
    }

    func testCelestialAudioPermissionTextFitsInsideItsAction() throws {
        let shell = try sharedAudioShell()
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertTrue(try ShellProfiles.select("celestial", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        for name in ["volume", "status"] {
            let widget = try makeWidget(
                name, config: config, shell: shell,
                source: name == "volume" ? shell.appendingPathComponent("default/widgets/volume/init.luau") : nil
            )
            widget.render(fixture(config, height: 60, vertical: false))
            audioFixture(widget, access: .denied)
            widget.layoutPopout()
            let action = try XCTUnwrap(widget.surface.layout.core.elements {
                widget.text.string($0.action) == "volume permission"
            }.first, name)
            let label = try XCTUnwrap(widget.surface.layout.core.elements {
                widget.text.string($0.text) == ShellLocalizer.string(
                    "Allow System Audio Recording to set app volumes",
                    []
                )
            }.first, name)
            let actionFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: action))
            let labelFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: label))
            XCTAssertGreaterThanOrEqual(labelFrame.minX, actionFrame.minX, name)
            XCTAssertLessThanOrEqual(labelFrame.maxX, actionFrame.maxX, name)
            XCTAssertGreaterThanOrEqual(labelFrame.minY, actionFrame.minY, name)
            XCTAssertLessThanOrEqual(labelFrame.maxY, actionFrame.maxY, name)
            let content = widget.surface.layout.core.content(of: label)
            XCTAssertGreaterThanOrEqual(labelFrame.width, CGFloat(content.maxWidth), name)
            let font = ShellTextStyle.font(for: content.style)
            let text = NSAttributedString(
                string: widget.text.string(content.text),
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            let lines = ShellTextStyle.wrappedLines(
                text, width: min(labelFrame.width, CGFloat(content.maxWidth)), limit: Int.max
            )
            XCTAssertLessThanOrEqual(lines.count, Int(content.lines), name)
            XCTAssertLessThanOrEqual(ShellTextStyle.wrappedSize(of: lines, font: font).height, labelFrame.height, name)
            try clickCommand("volume permission", widget: widget, context: name)
        }
    }

    func testSharedSystemStatsKeepsApprovedDataAndPartialLoadingThroughEverySkin() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget(
                "system-stats", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/system-stats/init.luau")
            )
            widget.resources.palette.refresh(theme: config.theme, appearance: try XCTUnwrap(NSAppearance(named: .aqua)))
            var bar = fixture(config, height: 32, vertical: false)
            bar.style.statsButton = false
            widget.render(bar)
            XCTAssertFalse(widget.tree().contains { $0.content.action == OMNI_ACTION_POPOUT }, profile)
            bar.style.statsButton = true
            for vertical in [false, true] {
                bar.style.vertical = vertical
                widget.render(bar)
                let button = try XCTUnwrap(
                    widget.surface.layout.core.elements { $0.action == OMNI_ACTION_POPOUT }.first,
                    profile
                )
                let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                XCTAssertLessThanOrEqual(frame.height, 32, profile)
                var popoutAction: UInt32 = 0
                widget.surface.onAction = { popoutAction = $0.action }
                let point = CGPoint(x: frame.midX, y: frame.midY)
                widget.surface.press(at: point, event: ShellEvent(button: .left))
                widget.surface.release(at: point, event: ShellEvent(button: .left))
                XCTAssertEqual(popoutAction, OMNI_ACTION_POPOUT, profile)
            }
            bar.style.vertical = false
            widget.render(bar)
            systemStatsFixture(widget)
            let tree = widget.renderPopout()
            let labels = tree.filter { $0.kind == .label }.map { widget.text.string($0.content.text) }
            let memory = { ShellFormatter.string(kind: OMNI_FORMAT_MEMORY, $0, digits: 0) }
            let file = { ShellFormatter.string(kind: OMNI_FORMAT_FILE, $0, digits: 0) }
            for value in [
                "studio", "Apple M4 Max", "Apple M4 Max GPU", "Mac16,9", "Version 27.2",
                "61°C", "48°C", percent(0.37), percent(0.18), percent(0.76),
                memory(Double(21 << 30)), memory(Double(36 << 30)),
                file(612_000_000_000), file(994_000_000_000),
                file(1_840_000) + "/s", file(312_000) + "/s", file(18_400_000_000), file(2_100_000_000),
                ShellLocalizer.string("%lldh %lldm", [.number(4), .number(14)])
            ] {
                XCTAssertTrue(labels.contains { $0.contains(value) }, "\(profile): missing \(value): \(labels)")
            }
            let paths = Set(tree.filter { $0.kind == .path }.map { widget.text.string($0.content.text) })
            widget.set("networkHistory") { $0.null() }
            let withoutHistory = widget.renderPopout()
            let remainingPaths = Set(withoutHistory.filter { $0.kind == .path }.map {
                widget.text.string($0.content.text)
            })
            XCTAssertGreaterThanOrEqual(
                paths.subtracting(remainingPaths).count,
                2,
                "\(profile): no graph paths removed"
            )
            XCTAssertTrue(remainingPaths.isSubset(of: paths), "\(profile): unrelated graph paint changed")
            XCTAssertFalse(labels.contains(ShellLocalizer.string("Collecting data…", [])), profile)
            XCTAssertTrue(
                widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Collecting data…", [])),
                profile
            )
            systemStatsFixture(widget)
            widget.set("thermal") { ShellThermal(cpu: 90, gpu: 48, gpuName: "Apple M4 Max GPU").write(into: &$0) }
            let cool = try XCTUnwrap(widget.renderPopout().first {
                widget.text.string($0.content.text) == (profile == "celestial" ? "thermometer" : "90°C")
            }, profile)
            widget.set("thermal") { ShellThermal(cpu: 91, gpu: 48, gpuName: "Apple M4 Max GPU").write(into: &$0) }
            let hot = try XCTUnwrap(widget.renderPopout().first {
                widget.text.string($0.content.text) == (profile == "celestial" ? "thermometer_alert" : "91°C")
            }, profile)
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("91°C"), profile)
            XCTAssertNotEqual(cool.content.color, hot.content.color, profile)
            widget.set("battery") { $0.null() }
            widget.layoutPopout()
            let noBattery = widget.strings(OMNI_VIEW_POPOUT)
            XCTAssertFalse(noBattery.contains(ShellLocalizer.string("Battery", [])), profile)
            if profile == "celestial" {
                XCTAssertEqual(widget.surface.naturalSize.width, 860, profile)
            }
            try exportSystemStatsState(widget, profile: profile, state: "no-battery-hot")
            for key in ["system", "gpu", "memory", "disk", "thermal", "networkHistory"] {
                widget.set(key) { $0.null() }
            }
            widget.layoutPopout()
            let partial = widget.strings(OMNI_VIEW_POPOUT)
            XCTAssertTrue(partial.contains(percent(0.37)), profile)
            XCTAssertTrue(partial.contains(profile == "celestial" ? percent(0) : "—"), profile)
            XCTAssertTrue(partial.contains(ShellLocalizer.string("Loading…", [])), profile)
            XCTAssertTrue(partial.contains(ShellLocalizer.string("Collecting data…", [])), profile)
            try exportSystemStatsState(widget, profile: profile, state: "partial")
        }
    }

    func testSharedCelestialStatsButtonKeepsTheSurfacePillGeometry() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        XCTAssertTrue(try ShellProfiles.select("celestial", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        let probe = shell.appendingPathComponent("celestial/widgets/stats-pill-reference/init.luau")
        try FileManager.default.createDirectory(
            at: probe.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        local surface = require("../lib/surface")
        function render(ctx)
            local style = ctx.data.bar.style
            return surface.pill(style, { surface.icon("monitoring", { size = 24 * style.height / 60 }) })
        end
        """.write(to: probe, atomically: true, encoding: .utf8)
        let reference = try makeWidget("stats-pill-reference", config: config, shell: shell, source: probe)
        let widget = try makeWidget(
            "system-stats", config: config, shell: shell,
            source: shell.appendingPathComponent("default/widgets/system-stats/init.luau")
        )
        for height in [32.0, 60] {
            for vertical in [false, true] {
                let bar = fixture(config, height: height, vertical: vertical)
                widget.render(bar)
                reference.render(bar)
                XCTAssertEqual(widget.surface.size.width, reference.surface.size.width, accuracy: 0.001)
                XCTAssertEqual(widget.surface.size.height, reference.surface.size.height, accuracy: 0.001)
            }
        }
    }

    func testSharedStatsBatteryReflectsLevelAndChargingAndWaylineRingsAlign() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in ["default", "wayline", "nocturne"] {
            _ = try ShellProfiles.select(profile, in: shell)
            let config = ShellConfig.resolve(shellDirectory: shell)
            XCTAssertEqual(config.profile, profile)
            let widget = try makeWidget(
                "system-stats", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/system-stats/init.luau")
            )
            widget.render(fixture(config, height: 32, vertical: false))
            systemStatsFixture(widget)
            var lowColor: Color?
            for (level, charging, symbol) in [
                (10.0, false, "battery.0percent"),
                (76.0, false, "battery.75percent"),
                (10.0, true, "battery.100percent.bolt")
            ] {
                widget.set("battery") { $0.number(level) }
                widget.set("charging") { $0.bool(charging) }
                let tree = widget.renderPopout()
                XCTAssertTrue(
                    tree.contains { $0.kind == .symbol && widget.text.string($0.content.text) == symbol },
                    profile
                )
                let bar = try XCTUnwrap(tree.last { $0.kind == .progress }, profile)
                XCTAssertEqual(bar.content.value, UInt32(level * 10), profile)
                if level == 10, !charging {
                    lowColor = bar.content.color
                } else {
                    XCTAssertNotEqual(lowColor, bar.content.color, profile)
                }
            }
            if profile == "wayline" {
                widget.layoutPopout()
                let positions = try ["CPU", "GPU", "Memory", "Disk"].map { title in
                    let labels = widget.surface.layout.core.elements {
                        widget.text.string($0.text) == ShellLocalizer.string(title, [])
                    }
                    return try XCTUnwrap(labels.map { widget.surface.layout.core.absoluteFrame(of: $0).y }.min(), title)
                }
                for position in positions.dropFirst() {
                    XCTAssertEqual(position, positions[0], accuracy: 0.001)
                }
            }
        }
    }

    func testSharedNocturneStatsKeepsUniformFrameInsets() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        XCTAssertTrue(try ShellProfiles.select("nocturne", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        for position in ["top", "bottom", "left"] {
            let widget = try makeWidget(
                "system-stats", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/system-stats/init.luau")
            )
            var bar = fixture(config, height: 32, vertical: position == "left")
            bar.style.position = position
            widget.render(bar)
            systemStatsFixture(widget)
            widget.layoutPopout()
            let elements = widget.surface.layout.core.elements { _ in true }
            let body = try XCTUnwrap(elements.first {
                let paint = widget.surface.layout.core.paint(of: $0)
                return paint.cornerRadius == 18 && paint.strokeWidth == 1
            }, position)
            var bounds = CGRect(widget.surface.layout.core.absoluteFrame(of: body))
            if position == "top" {
                bounds.origin.y += 14
                bounds.size.height -= 14
            } else if position == "bottom" {
                bounds.size.height -= 14
            }
            let apple = try XCTUnwrap(elements
                .first { widget.text.string(widget.surface.layout.core.content(of: $0).text) == "applelogo" })
            let header = widget.surface.layout.core.parent(of: widget.surface.layout.core.parent(of: apple))
            let headerFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: header))
            XCTAssertEqual(headerFrame.minX - bounds.minX, 12, accuracy: 0.5, position)
            XCTAssertEqual(headerFrame.minY - bounds.minY, 12, accuracy: 0.5, position)
            var footer = try XCTUnwrap(elements.first {
                widget.text.string(widget.surface.layout.core.content(of: $0).text).hasPrefix("Mac16,9")
            })
            while footer.slot >= 0, widget.surface.layout.core.paint(of: footer).cornerRadius != 14 {
                footer = widget.surface.layout.core.parent(of: footer)
            }
            XCTAssertGreaterThanOrEqual(footer.slot, 0, position)
            let footerFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: footer))
            XCTAssertEqual(bounds.maxX - footerFrame.maxX, 12, accuracy: 0.5, position)
            XCTAssertEqual(bounds.maxY - footerFrame.maxY, 12, accuracy: 0.5, position)
        }
    }

    func testSharedSystemStatsKeepsItsFittedScrollingSurfaceThroughEverySkin() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for position in ["top", "bottom", "left"] {
                let context = "\(profile) \(position)"
                let widget = try makeWidget(
                    "system-stats", config: config, shell: shell,
                    source: shell.appendingPathComponent("default/widgets/system-stats/init.luau")
                )
                widget.resources.palette.refresh(
                    theme: config.theme,
                    appearance: try XCTUnwrap(NSAppearance(named: .aqua))
                )
                var bar = fixture(config, height: 32, vertical: position == "left")
                bar.style.position = position
                widget.render(bar)
                systemStatsFixture(widget)
                widget.layoutPopout()
                if profile == "nocturne", position != "top" {
                    try exportSystemStatsState(widget, profile: profile, state: position)
                }
                let natural = widget.surface.naturalSize
                let fitted = CGSize(width: natural.width, height: 180)
                XCTAssertGreaterThan(natural.height, fitted.height, context)
                widget.surface.setRootLimit(fitted)
                XCTAssertEqual(widget.surface.size, fitted, context)
                let scroll = try XCTUnwrap(widget.surface.layout.core.elements { $0.scrolls }.first, context)
                let viewport = CGRect(widget.surface.layout.core.absoluteFrame(of: scroll))
                XCTAssertTrue(CGRect(origin: .zero, size: fitted).contains(viewport), context)
                XCTAssertTrue(widget.surface.scroll(
                    at: CGPoint(x: viewport.midX, y: viewport.midY), event: ShellEvent(button: .none),
                    content: CGPoint(x: 0, y: 10_000)
                ), context)
                ShellLayerScene.engineQueue.sync {}
                let scrolled = try XCTUnwrap(widget.layers().first { $0.bounds.origin.y > 0 }, context)
                let bottom = try XCTUnwrap(scrolled.sublayers?.map(\.frame.maxY).max(), context)
                XCTAssertEqual(scrolled.bounds.height, viewport.height, accuracy: 0.5, context)
                XCTAssertEqual(scrolled.bounds.origin.y, bottom + 16 - viewport.height, accuracy: 0.5, context)
            }
        }
    }

    func testSkinDefaultsReproduceTheSystemStyleModule() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        XCTAssertTrue(try ShellProfiles.select("system", in: shell))
        let body = """
        function render(ctx)
            return ui.row{ gap = 4,
                module.bar(ctx, { onClick = "probe", ui.text{ text = "Bar" } }),
                module.button("xmark", "close"),
                module.heading("Heading", 120) }
        end
        function popout(ctx)
            return PANEL{ w = module.width + 28,
                module.group{ ui.text{ text = "Group" } },
                ui.text{ text = module.batterySymbol(50, false) } }
        end
        """
        func tree(module: String, panel: String) throws -> [String] {
            let folder = shell.appendingPathComponent("system/widgets/skin-\(module)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try ("local module = require(\"../lib/\(module)\")\nlocal PANEL = \(panel)\n" + body)
                .write(to: folder.appendingPathComponent("init.luau"), atomically: true, encoding: .utf8)
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget("skin-\(module)", config: config, shell: shell)
            widget.render(fixture(config, height: 32, vertical: false))
            return (widget.tree() + widget.renderPopout()).map { node in
                "\(node.kind) \(node.layout.width)x\(node.layout.height) radius=\(node.paint.cornerRadius)"
                    + " fill=\(node.paint.fill) hover=\(node.content.hover) material=\(node.paint.material)"
                    + " text=\(widget.text.string(node.content.text))"
            }
        }
        let skinned = try tree(module: "look", panel: "function(props) return module.panel(nil, props) end")
        XCTAssertGreaterThan(skinned.count, 8)
        XCTAssertTrue(skinned.contains { $0.contains("text=Group") }, "\(skinned)")
        XCTAssertEqual(skinned, try tree(module: "style", panel: "function(props) return module.panel(props) end"))
    }

    func testEveryBundledProfileKeepsNativeWorkspaceContractsThroughItsEffectiveConfiguration() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let installed = ShellProfiles.names(in: shell)
        XCTAssertTrue(Set(profiles + ["matrix"]).isSubset(of: Set(installed + ["default"])), "\(installed)")
        for profile in Set(installed + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let height = config.barOverride?.settings.height ?? 32
            for vertical in [false, true] {
                for labels in [false, true] {
                    let context = "\(profile) vertical=\(vertical) labels=\(labels)"
                    let widget = try makeWidget("workspaces", config: config, shell: shell)
                    var bar = fixture(config, height: height, vertical: vertical)
                    bar.style.labels = labels
                    widget.render(bar)
                    for item in bar.workspaces.flatMap(\.windows) {
                        let icon = try XCTUnwrap(widget.surface.layout.core.elements {
                            $0.iconSource == .window && widget.text.string($0.iconRef) == item.id
                        }.first, "\(context): no window icon for \(item.id)")
                        var target = icon
                        while target.slot >= 0 {
                            let content = widget.surface.layout.core.content(of: target)
                            if widget.text.string(content.target) == "window \(item.id)",
                               content.menu, content.drag, content.preview || content.opensPopout { break }
                            target = widget.surface.layout.core.parent(of: target)
                        }
                        XCTAssertGreaterThanOrEqual(
                            target.slot,
                            0,
                            "\(context): icon \(item.id) lost its native controls"
                        )
                    }
                    for workspace in bar.workspaces {
                        let pill = try XCTUnwrap(widget.surface.layout.core.elements {
                            $0.menu && $0.drop && widget.text.string($0.target) == "workspace \(workspace.id)"
                        }.first, "\(context): no pill for workspace \(workspace.id)")
                        XCTAssertEqual(
                            widget.text.string(widget.surface.layout.core.content(of: pill).action),
                            "switch-workspace \(workspace.id)",
                            context
                        )
                    }
                }
            }
        }
    }

    func testScratchpadIconCountMatchesTheResolvedConfiguration() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let cases = [("nan", 0), ("\"4\"", 3), ("inf", 6), ("2.7", 2), ("9", 6), ("-1", 0), ("5", 5)]
        for (value, expected) in cases {
            try Data("[profiles.default.widgets.scratchpads]\nshownWindows = \(value)\n".utf8)
                .write(to: shell.appendingPathComponent("shell.toml"))
            let config = ShellConfig.resolve(shellDirectory: shell)
            XCTAssertEqual(config.scratchpadIcons, expected, value)
            let widget = try makeWidget("scratchpads", config: config, shell: shell)
            var bar = fixture(config, height: 32, vertical: false)
            bar.scratchpads = [ShellBarScratchpad(
                id: 1, name: "Notes", focused: false, revealed: false, visible: true,
                windows: (0 ..< 7).map { index in
                    ShellBarItem(
                        id: "\(index)", bundle: "", name: "App \(index)", focused: false, count: 1, hidden: 0,
                        windows: [ShellBarWindow(id: "w\(index)", title: "Window", focused: false, hidden: false)]
                    )
                }
            )]
            widget.render(bar)
            let tree = widget.tree()
            XCTAssertEqual(
                tree.filter { $0.kind == .image && $0.content.iconSource == .window }.count,
                config.scratchpadIcons,
                value
            )
            XCTAssertTrue(
                tree.contains { widget.text.string($0.content.text) == "+\(7 - config.scratchpadIcons)" },
                value
            )
        }
    }

    func testOmniWMButtonUsesAValidConfiguredIconColor() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let terracotta: UInt32 = 0xB665_45FF
        let cases: [String: UInt32] = [
            "\"#1E90FF\"": 0x1E90_FFFF, "\"#1E90FF80\"": 0x1E90_FF80, "\"#1E90F\"": terracotta,
            "\"#1E90FX\"": terracotta, "\"#GG90FF\"": terracotta, "\"blue\"": terracotta, "3": terracotta
        ]
        for (value, expected) in cases {
            try Data("[profiles.default.widgets.omniwm]\niconColor = \(value)\n".utf8)
                .write(to: shell.appendingPathComponent("shell.toml"))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget("omniwm", config: config, shell: shell)
            widget.render(fixture(config, height: 32, vertical: false))
            let logo = try XCTUnwrap(widget.tree().first {
                $0.kind == .symbol && widget.text.string($0.content.text) == "omniwm"
            }, value)
            XCTAssertEqual(logo.content.color, Color(packed: expected), value)
        }
    }

    func testOccupiedHighlightReachesSkinnedWorkspacePills() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in ["wayline", "nocturne"] {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget(
                "workspaces", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/workspaces/init.luau")
            )
            var bar = fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: false)
            bar.style.backgrounds = true
            let fills = { (highlight: Bool) -> [String: Color] in
                widget.set("settings") {
                    $0.map(2)
                    $0.key("indicator")
                    $0.string("pills")
                    $0.key("occupiedBackground")
                    $0.bool(highlight)
                }
                widget.render(bar)
                return Dictionary(uniqueKeysWithValues: widget.tree().filter(\.content.drop).map {
                    (widget.text.string($0.content.target), $0.paint.fill)
                })
            }
            let off = fills(false)
            let on = fills(true)
            XCTAssertNotEqual(on["workspace 2"], off["workspace 2"], profile)
            XCTAssertEqual(on["workspace 1"], off["workspace 1"], profile)
            XCTAssertEqual(on["workspace 3"], off["workspace 3"], profile)
        }
    }

    func testSharedWorkspaceSkinsKeepInputFocusAndIndicatorContracts() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            for vertical in [false, true] {
                let widget = try makeWidget(
                    "workspaces", config: config, shell: shell,
                    source: shell.appendingPathComponent("default/widgets/workspaces/init.luau")
                )
                var bar = fixture(config, height: config.barOverride?.settings.height ?? 32, vertical: vertical)
                bar.style.accents = true
                for labels in [false, true] {
                    bar.style.labels = labels
                    for indicator in ["pills", "underline", "dots", "numbers", "minimal"] {
                        let context = "\(profile) vertical=\(vertical) labels=\(labels) indicator=\(indicator)"
                        widget.set("settings") {
                            $0.map(1)
                            $0.key("indicator")
                            $0.string(indicator)
                        }
                        widget.render(bar)
                        XCTAssertLessThanOrEqual(
                            vertical ? widget.surface.size.width : widget.surface.size.height,
                            bar.style.height,
                            context
                        )
                        let tree = widget.tree()
                        let focused = try XCTUnwrap(tree.first { widget.text.string($0.content.target) == "window 0" })
                        XCTAssertEqual(focused.paint.scale, 1.1, context)
                        let glyph = try XCTUnwrap(tree
                            .first { $0.content.iconSource == .window && widget.text.string($0.content.iconRef) == "0"
                            })
                        XCTAssertTrue(glyph.paint.shadow.isVisible, context)
                        for workspace in bar.workspaces {
                            let pill = try XCTUnwrap(tree
                                .first {
                                    $0.content.drop && widget.text.string($0.content.target) == "workspace \(workspace.id)"
                                })
                            XCTAssertTrue(pill.content.menu, context)
                            XCTAssertEqual(
                                widget.text.string(pill.content.action),
                                "switch-workspace \(workspace.id)",
                                context
                            )
                        }
                        let single = try XCTUnwrap(widget.surface.layout.core.elements {
                            $0.drag && widget.text.string($0.target) == "window 0"
                        }.first)
                        let singleFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: single))
                        let point = CGPoint(x: singleFrame.midX, y: singleFrame.midY)
                        widget.surface.press(at: point)
                        widget.surface.release(at: point)
                        XCTAssertEqual(widget.clicks.last?.action, "window focus 0", context)
                        let grouped = try XCTUnwrap(tree.first { widget.text.string($0.content.target) == "window 1" })
                        XCTAssertTrue(
                            grouped.content.menu && grouped.content.drag && grouped.content.preview && grouped.content
                                .opensPopout,
                            context
                        )
                        widget.invoke(grouped.content.action)
                        widget.layoutPopout()
                        let row = try XCTUnwrap(widget.surface.layout.core.elements {
                            widget.text.string($0.action) == "window focus 1_0"
                        }.first)
                        let rowFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: row))
                        let rowPoint = CGPoint(x: rowFrame.midX, y: rowFrame.midY)
                        widget.surface.press(at: rowPoint)
                        widget.surface.release(at: rowPoint)
                        XCTAssertEqual(widget.clicks.last?.action, "window focus 1_0", context)
                        let close = try XCTUnwrap(widget.surface.layout.core
                            .elements { $0.action == OMNI_ACTION_POPOUT }.first)
                        let closeFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: close))
                        let closePoint = CGPoint(x: closeFrame.midX, y: closeFrame.midY)
                        widget.surface.press(at: closePoint)
                        widget.surface.release(at: closePoint)
                        XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT, context)
                    }
                }
                widget.set("settings") {
                    $0.map(1)
                    $0.key("indicator")
                    $0.string("pills")
                }
                bar.style.backgrounds = false
                widget.render(bar)
                if profile == "wayline" {
                    XCTAssertTrue(try XCTUnwrap(widget.tree()
                            .first { $0.content.drop && widget.text.string($0.content.target) == "workspace 1" }).paint
                                                .stroke.isVisible)
                }
                bar.style.accents = false
                bar.drag = ShellBarDrag(sources: ["1"], workspaces: ["3"], icons: ["0"])
                widget.render(bar)
                let dragged = widget.tree()
                XCTAssertEqual(
                    try XCTUnwrap(dragged.first { widget.text.string($0.content.target) == "window 0" }).paint
                        .strokeWidth,
                    1.5
                )
                XCTAssertEqual(
                    try XCTUnwrap(dragged
                        .first { $0.content.drop && widget.text.string($0.content.target) == "workspace 3" }).paint
                                            .strokeWidth,
                    1.5
                )
                XCTAssertEqual(
                    try XCTUnwrap(dragged
                        .first { $0.content.iconSource == .window && widget.text.string($0.content.iconRef) == "1" })
                        .paint.opacity,
                    0.35
                )
                bar.drag = nil
                widget.set("settings") {
                    $0.map(1)
                    $0.key("compact")
                    $0.bool(true)
                }
                bar.style.labels = false
                widget.render(bar)
                XCTAssertFalse(widget.tree().contains { $0.content.iconSource == .window && $0.kind == .image })
                bar.island = .active
                widget.render(bar)
                XCTAssertEqual(
                    Set(widget.surface.targetFrames().map { widget.text.string($0.target) }),
                    ["workspace 1"]
                )
                bar.island = .secondary
                widget.render(bar)
                XCTAssertEqual(
                    Set(widget.surface.targetFrames().map { widget.text.string($0.target) }),
                    ["workspace 2", "workspace 3"]
                )
            }
        }
    }

    func testSharedScratchpadSkinsKeepToggleFocusLabelsAndBadges() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let base = config.barOverride?.settings.height ?? 32
            for vertical in [false, true] {
                let widget = try makeWidget(
                    "scratchpads", config: config, shell: shell,
                    source: shell.appendingPathComponent("default/widgets/scratchpads/init.luau")
                )
                var menuTargets: [String] = []
                let strings = widget.text
                widget.surface.onMenu = { menuTargets.append(strings.string($0.target)) }
                for height in [base, base * 1.5] {
                    for compact in [false, true] {
                        var bar = scratchpadFixture(config, height: height, vertical: vertical)
                        bar.style.inactive = 0.27
                        bar.scratchpads = bar.scratchpads.map {
                            ShellBarScratchpad(
                                id: $0.id,
                                name: $0.name,
                                focused: $0.focused,
                                revealed: $0.revealed,
                                visible: $0.visible,
                                windows: $0.windows,
                                compact: compact
                            )
                        }
                        var size: CGSize?
                        for mode in ["off", "dot", "text"] {
                            let context = "\(profile) vertical=\(vertical) compact=\(compact) height=\(height) badges=\(mode)"
                            bar.badges = mode
                            bar.style.accents = true
                            widget.render(bar)
                            let currentSize = widget.surface.size
                            XCTAssertGreaterThan(currentSize.width, 0, context)
                            XCTAssertGreaterThan(currentSize.height, 0, context)
                            XCTAssertLessThanOrEqual(vertical ? currentSize.width : currentSize.height, height, context)
                            if let size { XCTAssertEqual(currentSize, size, context) }
                            size = currentSize
                            let tree = widget.tree()
                            XCTAssertEqual(
                                Set(tree.filter { $0.content.menu }.map { widget.text.string($0.content.target) }),
                                ["scratchpad 1", "scratchpad 2", "scratchpad 3"],
                                context
                            )
                            for scratchpad in bar.scratchpads {
                                let button = try XCTUnwrap(widget.surface.layout.core.elements {
                                    widget.text.string($0.target) == "scratchpad \(scratchpad.id)"
                                }.first, context)
                                let content = widget.surface.layout.core.content(of: button)
                                XCTAssertTrue(content.menu, context)
                                XCTAssertFalse(widget.text.string(content.help).isEmpty, context)
                                XCTAssertEqual(
                                    widget.text.string(content.action),
                                    "scratchpad toggle \(scratchpad.id)",
                                    context
                                )
                                let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                                let point = CGPoint(x: frame.midX, y: frame.midY)
                                widget.surface.press(at: point)
                                widget.surface.release(at: point)
                                XCTAssertEqual(
                                    widget.clicks.last?.action,
                                    "scratchpad toggle \(scratchpad.id)",
                                    context
                                )
                                XCTAssertTrue(widget.surface.openContextMenu(at: point, option: false), context)
                                XCTAssertEqual(menuTargets.last, "scratchpad \(scratchpad.id)", context)
                            }
                            let focused = try XCTUnwrap(tree
                                .first { widget.text.string($0.content.target) == "scratchpad 1" })
                            XCTAssertEqual(focused.paint.scale, 1.04, context)
                            XCTAssertTrue(focused.paint.stroke.isVisible, context)
                            XCTAssertEqual(focused.paint.strokeWidth, 1.2, context)
                            let label = try XCTUnwrap(tree.first {
                                $0.kind == .label && widget.text
                                    .string($0.content.text) == (vertical ? "T" : "Terminal sessions")
                            }, context)
                            if compact, !vertical {
                                XCTAssertEqual(
                                    label.content.maxWidth,
                                    Float(WorkspaceBarScratchpadLayout.compactLabelMaximumWidth),
                                    context
                                )
                                let attributes: [NSAttributedString.Key: Any] = [
                                    NSAttributedString.Key(kCTFontAttributeName as String): ShellTextStyle
                                        .font(for: label.content.style)
                                ]
                                let line = CTLineCreateWithAttributedString(NSAttributedString(
                                    string: "Terminal sessions",
                                    attributes: attributes
                                ))
                                let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(
                                    string: "…",
                                    attributes: attributes
                                ))
                                let truncated = try XCTUnwrap(
                                    CTLineCreateTruncatedLine(line, Double(label.content.maxWidth), .end, ellipsis),
                                    context
                                )
                                XCTAssertGreaterThan(
                                    CTLineGetGlyphCount(truncated),
                                    CTLineGetGlyphCount(ellipsis),
                                    context
                                )
                            }
                            let shown = config.scratchpadIcons
                            let shownIcons = (0 ..< min(shown, 5)).map(String.init) + (shown > 0 ? ["3", "4"] : [])
                            let labels = tree.filter { $0.kind == .label }.map { widget.text.string($0.content.text) }
                            XCTAssertTrue(labels.contains(compact ? "6" : "+\(5 - shown)"), context)
                            XCTAssertEqual(labels.contains("999+"), !compact && mode == "text" && shown > 2, context)
                            let icons = tree.filter { $0.kind == .image && $0.content.iconSource == .window }
                            XCTAssertEqual(icons.count, compact ? 0 : shownIcons.count, context)
                            if !compact {
                                XCTAssertEqual(
                                    icons.map { widget.text.string($0.content.iconRef) },
                                    shownIcons,
                                    context
                                )
                                XCTAssertEqual(
                                    icons.map(\.paint.opacity),
                                    [1] + Array(repeating: 0.27, count: shownIcons.count - 1),
                                    context
                                )
                            }
                        }
                        bar.style.accents = false
                        widget.render(bar)
                    }
                }
                var bar = scratchpadFixture(config, height: base, vertical: vertical)
                bar.island = .active
                widget.render(bar)
                XCTAssertEqual(widget.surface.size, .zero, profile)
                bar.island = .secondary
                widget.render(bar)
                XCTAssertFalse(widget.surface.layout.core.elements { $0.menu && $0.target != 0 }.isEmpty, profile)
                bar.scratchpads = []
                widget.render(bar)
                XCTAssertEqual(widget.surface.size, .zero, profile)
            }
        }
    }

    func testSharedOmniWMButtonsKeepMenuSecureInputAndKeyboardModeContracts() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        let states: [(locked: Bool, backgrounds: Bool, mode: KeyboardModeKind)] = [
            (false, false, .normal), (true, false, .normal),
            (false, true, .normal), (true, true, .normal),
            (false, false, .prefix), (true, true, .paused), (false, true, .window)
        ]
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let base = config.barOverride?.settings.height ?? 32
            for vertical in [false, true] {
                let widget = try makeWidget(
                    "omniwm", config: config, shell: shell,
                    source: shell.appendingPathComponent("default/widgets/omniwm/init.luau")
                )
                for height in [base, base * 1.5] {
                    for state in states {
                        let context = "\(profile) vertical=\(vertical) height=\(height) locked=\(state.locked) backgrounds=\(state.backgrounds) mode=\(state.mode.rawValue)"
                        var bar = fixture(config, height: height, vertical: vertical)
                        bar.style.secureInput = state.locked
                        bar.style.backgrounds = state.backgrounds
                        bar.style.keyboardMode = state.mode.rawValue
                        widget.render(bar)
                        XCTAssertGreaterThan(widget.surface.size.width, 0, context)
                        XCTAssertGreaterThan(widget.surface.size.height, 0, context)
                        XCTAssertLessThanOrEqual(
                            vertical ? widget.surface.size.width : widget.surface.size.height,
                            height,
                            context
                        )
                        let buttons = widget.surface.layout.core.elements {
                            widget.text.string($0.action) == ShellRequest.statusMenuCommand
                        }
                        XCTAssertEqual(buttons.count, 1, context)
                        let button = try XCTUnwrap(buttons.first, context)
                        let content = widget.surface.layout.core.content(of: button)
                        XCTAssertEqual(
                            widget.text.string(content.secondaryAction),
                            ShellRequest.statusMenuCommand,
                            context
                        )
                        let help = ShellLocalizer.string(
                            state
                                .locked ? "Secure Input is on: Option shortcuts are paused" : "Window manager controls",
                            []
                        )
                        XCTAssertEqual(widget.text.string(content.help), help, context)
                        let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                        let point = CGPoint(x: frame.midX, y: frame.midY)
                        let firstClick = widget.clicks.count
                        for mouseButton in [ShellEvent.Button.left, .right] {
                            widget.surface.press(at: point, button: mouseButton)
                            widget.surface.release(at: point, event: ShellEvent(button: mouseButton))
                        }
                        let clicks = widget.clicks.dropFirst(firstClick)
                        XCTAssertEqual(
                            clicks.map(\.action),
                            [ShellRequest.statusMenuCommand, ShellRequest.statusMenuCommand],
                            context
                        )
                        XCTAssertEqual(clicks.map(\.button), [.left, .right], context)
                        let tree = widget.tree()
                        let symbols = tree.filter { $0.kind == .symbol }.map { widget.text.string($0.content.text) }
                        let labels = tree.filter { $0.kind == .label }.map { widget.text.string($0.content.text) }
                        let logos = tree.filter {
                            $0.kind == .symbol && ["omniwm", "omniwm.lock"]
                                .contains(widget.text.string($0.content.text))
                        }
                        XCTAssertEqual(
                            logos.map { widget.text.string($0.content.text) },
                            [state.locked ? "omniwm.lock" : "omniwm"],
                            context
                        )
                        XCTAssertEqual(logos.first?.content.color, Color(packed: 0xB665_45FF), context)
                        if ["default", "lake", "system", "matrix", "sakura"].contains(profile) {
                            XCTAssertEqual(frame.width, height - 4, accuracy: 0.001, context)
                            XCTAssertEqual(frame.height, height - 4, accuracy: 0.001, context)
                        } else if ["wayline", "nocturne"].contains(profile) {
                            XCTAssertEqual(frame.width, 32 * height / 40, accuracy: 0.001, context)
                            XCTAssertEqual(frame.height, 32 * height / 40, accuracy: 0.001, context)
                        }
                        if profile == "wayline" {
                            XCTAssertTrue(widget.surface.layout.core.paint(of: button).fill.isVisible, context)
                            XCTAssertEqual(content.hoverOpacity, 0.85, accuracy: 0.001, context)
                        } else if profile == "nocturne" {
                            XCTAssertEqual(
                                widget.surface.layout.core.paint(of: button).fill.isVisible,
                                state.backgrounds,
                                context
                            )
                            XCTAssertEqual(content.hoverScale, 1.06, accuracy: 0.001, context)
                        }
                        let modeLabel: String
                        let modeHelp: String
                        switch state.mode {
                        case .normal:
                            XCTAssertFalse(symbols.contains("keyboard") || symbols.contains("pause.fill"), context)
                            continue
                        case .paused:
                            modeLabel = "Paused"
                            modeHelp = "OmniWM shortcuts are paused."
                        case .prefix:
                            modeLabel = "Prefix"
                            modeHelp = "Prefix: the next key runs an OmniWM command. Escape cancels."
                        case .window:
                            modeLabel = "Window Mode"
                            modeHelp = "Window mode: keys run OmniWM commands until you press Escape."
                        }
                        XCTAssertTrue(symbols.contains(state.mode == .paused ? "pause.fill" : "keyboard"), context)
                        XCTAssertEqual(labels.contains(ShellLocalizer.string(modeLabel, [])), !vertical, context)
                        let chip = try XCTUnwrap(widget.surface.layout.core.elements {
                            widget.text.string($0.help) == ShellLocalizer.string(modeHelp, [])
                        }.first, context)
                        let chipFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: chip))
                        XCTAssertEqual(
                            vertical ? chipFrame.minY - frame.maxY : chipFrame.minX - frame.maxX,
                            4,
                            accuracy: 0.001,
                            context
                        )
                    }
                }
            }
        }
    }

    func testSharedHiddenBarsKeepNativeGeometryAndActivationAcrossSkins() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget(
                "hidden-bar", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/hidden-bar/init.luau")
            )
            for vertical in [false, true] {
                widget.render(fixture(config, height: 32, vertical: vertical))
                for cell in [20.0, 24.0] {
                    let context = "\(profile) vertical=\(vertical) cell=\(cell)"
                    var hidden = ShellHiddenBarData(cell: cell, vertical: vertical)
                    widget.set("hiddenBar") { hidden.write(into: &$0) }
                    widget.layoutPopout()
                    XCTAssertEqual(widget.surface.size, CGSize(width: 140, height: cell + 4), context)
                    XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string(
                        "No hidden items",
                        []
                    )))
                    hidden.items = (0 ..< 3).map { index in
                        ShellHiddenBarItem(
                            id: "app#\(index)", name: "Hidden App \(index)",
                            image: index == 0 ? "hidden-bar/fixture" : nil, width: 30, height: 16
                        )
                    }
                    for constrained in [false, true] {
                        hidden.maxWidth = constrained ? 70 : 600
                        hidden.maxHeight = constrained ? cell * 2 : 600
                        widget.set("hiddenBar") { hidden.write(into: &$0) }
                        widget.layoutPopout()
                        let expected = vertical
                            ? CGSize(width: constrained ? 66 : 34, height: constrained ? cell * 2 + 8 : cell * 3 + 8)
                            : CGSize(width: constrained ? 68 : 98, height: constrained ? cell * 2 + 6 : cell + 4)
                        XCTAssertEqual(widget.surface.size, expected, "\(context) constrained=\(constrained)")
                        let actions = widget.surface.layout.core.elements { $0.action != 0 }.sorted { left, right in
                            let a = widget.surface.layout.core.absoluteFrame(of: left)
                            let b = widget.surface.layout.core.absoluteFrame(of: right)
                            return vertical
                                ? (a.x == b.x ? a.y < b.y : a.x < b.x)
                                : (a.y == b.y ? a.x < b.x : a.y < b.y)
                        }
                        XCTAssertEqual(actions.count, 3, context)
                        let firstClick = widget.clicks.count
                        for (index, action) in actions.enumerated() {
                            let content = widget.surface.layout.core.content(of: action)
                            XCTAssertEqual(widget.text.string(content.help), "Hidden App \(index)", context)
                            let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: action))
                            let point = CGPoint(x: frame.midX, y: frame.midY)
                            widget.surface.press(at: point)
                            widget.surface.release(at: point)
                        }
                        XCTAssertEqual(
                            widget.clicks.dropFirst(firstClick).map(\.action),
                            (0 ..< 3).map { "hidden-bar activate app#\($0)" }, context
                        )
                        let tree = widget.renderPopout()
                        XCTAssertEqual(tree.filter { $0.kind == .bitmap }.count, 1, context)
                        XCTAssertEqual(tree.filter {
                            $0.kind == .symbol && widget.text.string($0.content.text) == "app.dashed"
                        }.count, 2, context)
                    }
                }
            }
        }
    }

    func testSharedHiddenMenusKeepContentDisabledRowsAndDeliveredActionsAcrossSkins() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget(
                "hidden-bar-menu", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/hidden-bar-menu/init.luau")
            )
            widget.render(fixture(config, height: 32, vertical: false))
            var hidden = hiddenBarFixture(vertical: false, menu: true)
            widget.set("hiddenBar") { hidden.write(into: &$0) }
            widget.layoutPopout()
            XCTAssertEqual(widget.surface.size, CGSize(width: 240, height: 165), profile)
            let tree = widget.renderPopout()
            let scroll = try XCTUnwrap(tree.first { $0.content.scrolls }, profile)
            XCTAssertEqual(scroll.layout.padding, 8, profile)
            XCTAssertEqual(scroll.layout.gap, 0, profile)
            let strings = widget.strings(OMNI_VIEW_POPOUT)
            for string in [
                "Checked item",
                "Disabled item",
                "More options",
                "✓",
                "⌘K",
                ShellLocalizer.string("Back", [])
            ] {
                XCTAssertTrue(strings.contains(string), "\(profile): \(string)")
            }
            XCTAssertTrue(strings.contains(profile == "wayline" ? "OPTIONS" : "Options"), profile)
            XCTAssertTrue(
                tree.contains { $0.kind == .symbol && widget.text.string($0.content.text) == "chevron.right" },
                profile
            )
            XCTAssertTrue(
                tree.contains { $0.kind == .symbol && widget.text.string($0.content.text) == "chevron.left" },
                profile
            )
            XCTAssertTrue(tree.contains { $0.layout.height == 9 }, profile)
            let actions = widget.surface.layout.core.elements { $0.action != 0 }.sorted {
                widget.surface.layout.core.absoluteFrame(of: $0).y < widget.surface.layout.core.absoluteFrame(of: $1).y
            }
            XCTAssertEqual(actions.map {
                widget.text.string(widget.surface.layout.core.content(of: $0).action)
            }, ["hidden-bar-menu back", "hidden-bar-menu checked", "hidden-bar-menu submenu"], profile)
            for action in actions {
                let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: action))
                let point = CGPoint(x: frame.midX, y: frame.midY)
                widget.surface.press(at: point)
                widget.surface.release(at: point)
            }
            XCTAssertEqual(
                widget.clicks.map(\.action),
                ["hidden-bar-menu back", "hidden-bar-menu checked", "hidden-bar-menu submenu"], profile
            )
            let disabled = try XCTUnwrap(widget.surface.layout.core.elements {
                widget.text.string($0.text) == "Disabled item"
            }.first, profile)
            let disabledRow = widget.surface.layout.core.parent(of: disabled)
            let disabledContent = widget.surface.layout.core.content(of: disabledRow)
            XCTAssertEqual(disabledContent.action, 0, profile)
            XCTAssertFalse(disabledContent.hasHoverEffect, profile)
            let disabledFrame = CGRect(widget.surface.layout.core.absoluteFrame(of: disabledRow))
            let disabledPoint = CGPoint(x: disabledFrame.midX, y: disabledFrame.midY)
            widget.surface.press(at: disabledPoint)
            widget.surface.release(at: disabledPoint)
            XCTAssertEqual(widget.clicks.count, 3, profile)
            if profile == "wayline" {
                let shortcut = try XCTUnwrap(tree.first { widget.text.string($0.content.text) == "⌘K" }, profile)
                XCTAssertEqual(shortcut.content.style & OMNI_STYLE_BASE_MASK, 2, profile)
                let mark = try XCTUnwrap(tree.first { widget.text.string($0.content.text) == "✓" }, profile)
                XCTAssertEqual(mark.content.color.role & 0xFF, UInt16(ShellRole.accent.rawValue + 1), profile)
            }
            hidden.menu = HiddenBarMenuPage(title: "Réglages", rows: [], backID: nil)
            widget.set("hiddenBar") { hidden.write(into: &$0) }
            widget.layoutPopout()
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains("Réglages"), profile)
            XCTAssertTrue(
                widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("No menu items available", [])),
                profile
            )
            XCTAssertTrue(widget.surface.layout.core.elements { $0.action != 0 }.isEmpty, profile)
            hidden.menu = nil
            widget.set("hiddenBar") { hidden.write(into: &$0) }
            widget.layoutPopout()
            XCTAssertTrue(widget.strings(OMNI_VIEW_POPOUT).contains(ShellLocalizer.string("Unavailable", [])), profile)
        }
    }

    func testSharedHiddenMenusScrollToTheLastActionWithinScreenBoundsAcrossSkins() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in Set(ShellProfiles.names(in: shell) + ["default"]).sorted() {
            XCTAssertTrue(try ShellProfiles.select(profile, in: shell))
            let config = ShellConfig.resolve(shellDirectory: shell)
            let widget = try makeWidget(
                "hidden-bar-menu", config: config, shell: shell,
                source: shell.appendingPathComponent("default/widgets/hidden-bar-menu/init.luau")
            )
            widget.render(fixture(config, height: 32, vertical: false))
            let hidden = ShellHiddenBarData(maxWidth: 240, maxHeight: 140, menu: HiddenBarMenuPage(
                title: nil,
                rows: (0 ..< 30).map {
                    hiddenMenuFixtureRow("item-\($0)", title: "Item \($0)")
                }, backID: nil
            ))
            widget.set("hiddenBar") { hidden.write(into: &$0) }
            widget.layoutPopout()
            XCTAssertEqual(widget.surface.size, CGSize(width: 240, height: 140), profile)
            let first = CGPoint(x: 60, y: 18)
            widget.surface.press(at: first)
            widget.surface.release(at: first)
            XCTAssertEqual(widget.clicks.last?.action, "hidden-bar-menu item-0", profile)
            XCTAssertTrue(widget.surface.scroll(
                at: first, event: ShellEvent(button: .none), content: CGPoint(x: 0, y: 10000)
            ), profile)
            let last = CGPoint(x: 60, y: 121)
            widget.surface.press(at: last)
            widget.surface.release(at: last)
            XCTAssertEqual(widget.clicks.last?.action, "hidden-bar-menu item-29", profile)
        }
    }

    func testSystemCompactWorkspacesKeepButtonsAndTargetsAcrossOrientations() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        XCTAssertTrue(try ShellProfiles.select("system", in: shell))
        let config = ShellConfig.resolve(shellDirectory: shell)
        XCTAssertNil(config.widgetSettings["workspaces"])
        for vertical in [false, true] {
            for labels in [false, true] {
                let widget = try makeWidget("workspaces", config: config, shell: shell)
                widget.set("settings") {
                    $0.map(1)
                    $0.key("compact")
                    $0.bool(true)
                }
                var bar = fixture(config, height: 32, vertical: vertical)
                bar.style.labels = labels
                widget.render(bar)
                let size = widget.surface.size
                XCTAssertTrue(size.width.isFinite && size.height.isFinite)
                XCTAssertGreaterThan(size.width, 0)
                XCTAssertGreaterThan(size.height, 0)
                XCTAssertLessThanOrEqual(vertical ? size.width : size.height, 32)
                let tree = widget.tree()
                XCTAssertFalse(tree.contains { $0.kind == .image && $0.content.iconSource == .window })
                XCTAssertEqual(Set(widget.surface.targetFrames().map { widget.text.string($0.target) }), [
                    "workspace 1", "workspace 2", "workspace 3"
                ])
                for workspace in bar.workspaces {
                    XCTAssertEqual(tree.contains {
                        $0.kind == .label && widget.text.string($0.content.text) == workspace.name
                    }, labels)
                    let button = try XCTUnwrap(widget.surface.layout.core.elements {
                        $0.menu && $0.drop && widget.text.string($0.target) == "workspace \(workspace.id)"
                    }.first)
                    let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: button))
                    XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite)
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                    let point = CGPoint(x: frame.midX, y: frame.midY)
                    widget.surface.press(at: point)
                    widget.surface.release(at: point)
                    XCTAssertEqual(widget.clicks.last?.action, "switch-workspace \(workspace.id)")
                }
            }
        }
    }

    func testWorkspaceGroupsKeepTheirTargetsAndPickerAcrossProfilesAndOrientations() throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in profiles {
            _ = try ShellProfiles.select(profile, in: shell)
            let config = ShellConfig.resolve(shellDirectory: shell)
            for vertical in [false, true] {
                for labels in [false, true] {
                    let widget = try makeWidget("workspaces", config: config, shell: shell)
                    if ["system", "sakura"].contains(profile) {
                        widget.set("settings") {
                            $0.map(1)
                            $0.key("compact")
                            $0.bool(false)
                        }
                    }
                    var bar = fixture(config, height: config.barOverride?.settings.height ?? 24, vertical: vertical)
                    bar.style.labels = labels
                    widget.render(bar)
                    let targets = widget.surface.targetFrames()
                    XCTAssertEqual(Set(targets.map { widget.text.string($0.target) }), [
                        "workspace 1", "workspace 2", "workspace 3", "window 0", "window 1", "window 2", "window 3"
                    ], "\(profile) vertical=\(vertical) labels=\(labels)")
                    let group = try XCTUnwrap(widget.tree()
                        .first { widget.text.string($0.content.target) == "window 1" })
                    XCTAssertTrue(group.content.menu && group.content.preview && group.content.drag && group.content
                        .opensPopout)
                    if profile == "wayline", labels {
                        let label = try XCTUnwrap(widget.surface.layout.core.elements {
                            widget.text.string($0.text) == "1"
                        }.first)
                        let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: label))
                        let window = try XCTUnwrap(widget.surface.layout.core.elements {
                            $0.drag && widget.text.string($0.target) == "window 0"
                        }.first)
                        let icon = CGRect(widget.surface.layout.core.absoluteFrame(of: window))
                        XCTAssertLessThanOrEqual(vertical ? frame.maxY : frame.maxX, vertical ? icon.minY : icon.minX)
                    }
                    widget.invoke(group.content.action)
                    widget.layoutPopout()
                    if profile == "system" {
                        XCTAssertEqual(widget.surface.chrome, ShellPopoutChrome(glass: true, radius: 20))
                        if ProcessInfo.processInfo.environment["OMNIWM_SHELL_SNAPSHOTS"] != nil {
                            try write(
                                [("workspaces", raster(widget.surface, scale: 2), widget.surface.size)],
                                name: "system-workspaces-picker-\(vertical ? "vertical" : "horizontal")-labels-\(labels)",
                                scale: 2, dark: false, solidBlack: false
                            )
                        }
                    }
                    for window in bar.workspaces[0].windows[1].windows {
                        let row = try XCTUnwrap(widget.surface.layout.core.elements {
                            widget.text.string($0.action) == "window focus \(window.id)"
                        }.first)
                        let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: row))
                        let point = CGPoint(x: frame.midX, y: frame.midY)
                        widget.surface.press(at: point)
                        widget.surface.release(at: point)
                        XCTAssertEqual(widget.clicks.last?.action, "window focus \(window.id)")
                    }
                    let close = try XCTUnwrap(widget.surface.layout.core.elements { $0.action == OMNI_ACTION_POPOUT }
                        .first)
                    let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: close))
                    let point = CGPoint(x: frame.midX, y: frame.midY)
                    widget.surface.press(at: point)
                    widget.surface.release(at: point)
                    XCTAssertEqual(widget.actions.last, OMNI_ACTION_POPOUT)
                    if profile == "wayline", !labels {
                        bar.style.accents = false
                        bar.style.backgrounds = true
                        widget.render(bar)
                        let selected = try XCTUnwrap(widget.tree()
                            .first { $0.content.drop && widget.text.string($0.content.target) == "workspace 1" })
                        let inactive = try XCTUnwrap(widget.tree()
                            .first { $0.content.drop && widget.text.string($0.content.target) == "workspace 2" })
                        XCTAssertTrue(selected.paint.stroke.isVisible)
                        XCTAssertNotEqual(selected.paint.stroke, inactive.paint.stroke)
                    }
                    bar.workspaces.removeFirst()
                    widget.render(bar)
                    XCTAssertFalse(widget.renderPopout().contains { $0.content.action != 0 })
                }
            }
        }
    }

    func testUnderlineSpansTheWorkspaceWithOrWithoutLabelsAndRespectsAccents() throws {
        let widget = try ShellRenderedWidget("workspaces")
        widget.set("settings") {
            $0.map(1)
            $0.key("indicator")
            $0.string("underline")
        }
        for vertical in [false, true] {
            for labels in [false, true] {
                for accents in [false, true] {
                    var bar = fixture(ShellConfig(), height: 32, vertical: vertical)
                    bar.style.labels = labels
                    bar.style.accents = accents
                    widget.render(bar)
                    let paths = widget.surface.layout.core.elements { _ in true }.filter {
                        widget.surface.layout.core.kind(of: $0) == .path
                    }
                    XCTAssertEqual(paths.count, accents ? 1 : 0)
                    guard let path = paths.first else { continue }
                    let line = CGRect(widget.surface.layout.core.absoluteFrame(of: path))
                    let workspace = try XCTUnwrap(widget.surface.targetFrames().first {
                        widget.text.string($0.target) == "workspace 1"
                    }).frame
                    XCTAssertEqual(
                        vertical ? line.height : line.width,
                        vertical ? workspace.height : workspace.width,
                        accuracy: 0.01
                    )
                }
            }
        }
    }

    func testSolidBlackWorkspaceLabelsStayReadableInLightAndDarkAppearances() throws {
        let widget = try ShellRenderedWidget("workspaces")
        let black = ShellRGBA(CGColor(gray: 0, alpha: 1))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            widget.resources.palette.refresh(theme: .native, appearance: try XCTUnwrap(NSAppearance(named: appearance)))
            for accents in [false, true] {
                var bar = fixture(ShellConfig(), height: 32, vertical: false)
                bar.style.solidBlack = true
                bar.style.accents = accents
                widget.render(bar)
                for name in accents ? ["2", "3"] : ["1", "2", "3"] {
                    let label = try XCTUnwrap(widget.tree().first {
                        widget.text.string($0.content.text) == name
                            && widget.text.string($0.content.target) == "workspace \(name)"
                            && $0.kind == .label
                    })
                    let color = try ShellRGBA(XCTUnwrap(widget.resources.palette.color(label.content.color)))
                    XCTAssertGreaterThanOrEqual(color.contrast(black), 4.5, "\(appearance.rawValue) workspace \(name)")
                }
            }
        }
    }

    private func render(
        _ config: ShellConfig,
        shell: URL,
        height: Double,
        vertical: Bool,
        scale: CGFloat,
        dark: Bool
    ) throws {
        let resources = ShellResources(
            motion: MotionPolicy(animationsEnabled: false),
            windowIcon: { [applications] id in
                guard let index = Int(id), applications.indices.contains(index),
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applications[index])
                else { return nil }
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        )
        var theme = config.theme
        for (role, color) in [
            (ShellRole.accent, config.barOverride?.accentColor),
            (.foreground, config.barOverride?.textColor)
        ] {
            guard let color else { continue }
            let value = NSColor(deviceRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            theme.light[role.rawValue] = value
            theme.dark[role.rawValue] = value
        }
        resources.palette.refresh(
            theme: theme,
            appearance: try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
        )
        let bar = fixture(config, height: height, vertical: vertical)
        var previews: [(String, CGImage, CGSize)] = []
        for name in ["workspaces", "scratchpads", "clock", "system-stats"] {
            let widget = try makeWidget(name, config: config, shell: shell, scale: scale, resources: resources)
            widget.set("clock") { $0.string("9:41 AM") }
            widget.set("date") { $0.string("Sat, Oct 10") }
            widget.set("cpu") { $0.number(42) }
            widget.set("memory") { $0.number(61) }
            widget.set("gpu") { $0.number(18) }
            widget.render(bar)
            let size = widget.surface.size
            XCTAssertGreaterThan(size.width, 0, "\(config.profile)/\(name)")
            XCTAssertGreaterThan(size.height, 0, "\(config.profile)/\(name)")
            XCTAssertLessThanOrEqual(
                vertical ? size.width : size.height,
                height,
                "\(config.profile)/\(name) \(height) vertical=\(vertical): \(size)"
            )
            if ProcessInfo.processInfo.environment["OMNIWM_SHELL_SNAPSHOTS"] != nil {
                previews.append((name, try raster(widget.surface, scale: scale), size))
            }
        }
        if !previews.isEmpty {
            let name = "\(config.profile)-\(Int(height))-\(vertical ? "vertical" : "horizontal")-\(dark ? "dark" : "light")-\(Int(scale))x"
            try write(previews, name: name, scale: scale, dark: dark, solidBlack: bar.style.solidBlack)
        }
    }

    private func exportSystemStatsState(_ widget: ShellRenderedWidget, profile: String, state: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["OMNIWM_STEP_RENDERS"] else { return }
        try ShellBundledWidgetTests.writeSnapshot(
            widget.surface, name: "system-stats-\(profile)-\(state)", dark: false,
            directory: URL(fileURLWithPath: directory).appendingPathComponent("states").path,
            background: widget.resources.palette.color(.clear, default: .background)
        )
    }

    private func useSharedLibraries(_ names: String, in shell: URL) throws {
        for library in names.split(separator: ",", omittingEmptySubsequences: false) {
            guard !library.isEmpty, library != ".", !library.contains("/"), !library.contains("\\"),
                  !library.contains("..") else { continue }
            var removed = false
            for profile in ShellProfiles.names(in: shell) where profile != "default" {
                let path = shell.appendingPathComponent("\(profile)/lib/\(library).luau")
                if FileManager.default.fileExists(atPath: path.path) {
                    try FileManager.default.removeItem(at: path)
                    removed = true
                }
            }
            guard removed else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "lib/\(library).luau"])
            }
        }
    }

    private func sharedAudioShell() throws -> URL {
        try sharedLibraryShell("audio")
    }

    private func sharedLibraryShell(_ library: String) throws -> URL {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        for profile in ShellProfiles.names(in: shell) where profile != "default" {
            let audio = shell.appendingPathComponent("\(profile)/lib/\(library).luau")
            if FileManager.default.fileExists(atPath: audio.path) {
                try FileManager.default.removeItem(at: audio)
            }
        }
        return shell
    }

    private func selectMediaTab(_ widget: ShellRenderedWidget, name: String) throws {
        if name == "control-center" {
            widget.set("settings") { ShellServiceValue.object(["tab": .text("media")]).write(to: &$0) }
        } else if name == "dashboard" {
            widget.set("clock") { $0.string("9:41 AM") }
            widget.layoutPopout()
            let label = try XCTUnwrap(widget.surface.layout.core.elements {
                widget.text.string($0.text) == ShellLocalizer.string("Media", [])
            }.first)
            let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: label))
            let point = CGPoint(x: frame.midX, y: frame.midY)
            let before = widget.actions.count
            widget.surface.press(at: point)
            widget.surface.release(at: point)
            XCTAssertEqual(widget.actions.count, before + 1)
            let action = try XCTUnwrap(widget.actions.last)
            XCTAssertEqual(widget.invoke(action, view: OMNI_VIEW_POPOUT), [])
        }
    }

    private func clickCommand(_ command: String, widget: ShellRenderedWidget, context: String) throws {
        let element = try XCTUnwrap(
            widget.surface.layout.core.elements { widget.text.string($0.action) == command }.first,
            context + ": " + command
        )
        let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: element))
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let before = widget.clicks.count
        widget.surface.press(at: point)
        widget.surface.release(at: point)
        XCTAssertEqual(widget.clicks.count, before + 1, context + ": " + command)
        XCTAssertEqual(widget.clicks.last?.action, command, context)
    }

    private func assertCelestialWeatherLayout(
        _ widget: ShellRenderedWidget,
        weather: ShellWeather,
        context: String
    ) throws {
        widget.layoutPopout()
        let scroll = try XCTUnwrap(widget.surface.layout.core.elements { $0.scrolls }.first, context)
        let viewport = CGRect(widget.surface.layout.core.absoluteFrame(of: scroll))
        XCTAssertEqual(viewport.height, 530, context)
        func frame(_ element: ElementHandle, relativeTo ancestor: ElementHandle) -> CGRect {
            var result = CGRect(widget.surface.layout.core.layoutFrame(of: element))
            var parent = widget.surface.layout.core.parent(of: element)
            while parent != .none, parent != ancestor {
                let position = widget.surface.layout.core.layoutFrame(of: parent)
                result.origin.x += CGFloat(position.x)
                result.origin.y += CGFloat(position.y)
                parent = widget.surface.layout.core.parent(of: parent)
            }
            XCTAssertEqual(parent, ancestor, context)
            return result
        }
        let elements = widget.surface.layout.core.elements { _ in true }
        for day in weather.days {
            let label = try XCTUnwrap(elements.first {
                widget.text.string(widget.surface.layout.core.content(of: $0).text) == day.label
            }, context + ": " + day.label)
            let card = widget.surface.layout.core.parent(of: label)
            let bounds = CGRect(widget.surface.layout.core.absoluteFrame(of: card))
            XCTAssertEqual(bounds.height, 162, context + ": " + day.label)
            let local = frame(card, relativeTo: scroll)
            XCTAssertTrue(
                CGRect(origin: .zero, size: viewport.size).contains(local),
                context + ": \(day.label) \(local) outside \(viewport.size)"
            )
            for child in elements {
                var parent = widget.surface.layout.core.parent(of: child)
                while parent != .none, parent != card {
                    parent = widget.surface.layout.core.parent(of: parent)
                }
                if parent == card {
                    let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: child))
                    XCTAssertTrue(bounds.contains(frame), context + ": \(day.label) child \(frame) outside \(bounds)")
                }
            }
        }
        if weather.stale {
            let stale = ShellLocalizer.string("Last update failed", [])
            let cue = try XCTUnwrap(elements.first {
                widget.text.string(widget.surface.layout.core.content(of: $0).help) == stale
            }, context)
            let frame = CGRect(widget.surface.layout.core.absoluteFrame(of: cue))
            XCTAssertGreaterThan(frame.width, 0, context)
            XCTAssertGreaterThan(frame.height, 0, context)
            XCTAssertTrue(viewport.contains(frame), context + ": stale cue \(frame) outside \(viewport)")
        }
        let attribution = try XCTUnwrap(widget.surface.layout.core.elements {
            widget.text.string($0.text) == ShellLocalizer.string("Weather by %@", [.text("Open-Meteo.com")])
        }.first, context)
        let before = CGRect(widget.surface.layout.core.absoluteFrame(of: attribution))
        XCTAssertGreaterThanOrEqual(before.minY, viewport.maxY, context)
        XCTAssertTrue(
            widget.surface.scroll(
                at: CGPoint(x: viewport.midX, y: viewport.midY),
                event: ShellEvent(button: .none),
                content: CGPoint(x: 0, y: 10_000)
            ),
            context
        )
        let after = CGRect(widget.surface.layout.core.absoluteFrame(of: attribution))
        XCTAssertTrue(viewport.contains(after), context + ": \(after) outside \(viewport)")
    }

    private func audioFixture(_ widget: ShellRenderedWidget, access: AppVolumeAccess) {
        widget.set("volume") { $0.number(62) }
        widget.set("muted") { $0.bool(false) }
        let outputs = [
            ShellAudioOutput(id: 41, name: "MacBook Pro Speakers", transport: "builtin", isDefault: true),
            ShellAudioOutput(id: 42, name: "AirPods Pro", transport: "bluetooth", isDefault: false),
            ShellAudioOutput(id: 43, name: "Studio Display Speakers", transport: "usb", isDefault: false)
        ]
        widget.set("outputs") { writer in
            writer.array(outputs.count)
            outputs.forEach { $0.write(into: &writer) }
        }
        let apps = access == .granted ? [
            ShellAudioApp(id: "com.apple.Music", name: "Music", playing: true, volume: 80, muted: false),
            ShellAudioApp(id: "com.apple.Safari", name: "Safari", playing: true, volume: 100, muted: false),
            ShellAudioApp(id: "com.apple.Podcasts", name: "Podcasts", playing: false, volume: 45, muted: true)
        ] : []
        widget.set("audioApps") { ShellAudioApps(access: access, apps: apps).write(into: &$0) }
    }

    private func calendarFixture(_ widget: ShellRenderedWidget, access: String = "full", month: Bool = true) {
        let now = 1_000_000.0
        let events = access == "full" ? [
            ShellCalendarEvent(
                id: "standup", title: "Team standup", calendar: "Work", color: "#0A84FF",
                start: now - 600, end: now + 900, allDay: false, location: nil, time: "9:30 AM", day: "Today"
            ),
            ShellCalendarEvent(
                id: "review", title: "Design review", calendar: "Work", color: "#FF9F0A",
                start: now + 1500, end: now + 4200, allDay: false, location: "Room 4", time: "10:05 AM", day: "Today"
            ),
            ShellCalendarEvent(
                id: "holiday", title: "Team offsite", calendar: "Home", color: "#30D158",
                start: now + 7200, end: now + 93600, allDay: true, location: nil, time: "", day: "Tomorrow"
            ),
            ShellCalendarEvent(
                id: "dinner", title: "Dinner with friends", calendar: "Home", color: "#BF5AF2",
                start: now + 90000, end: now + 97200, allDay: false, location: nil, time: "7:00 PM", day: "Tomorrow"
            )
        ] : []
        let calendar = ShellCalendar(access: access, events: events, month: month ? ShellCalendarMonth(
            title: "October 2026", year: 2026, month: 10, days: 31, offset: 4, today: 23,
            weekdays: ["S", "M", "T", "W", "T", "F", "S"], marked: [5, 12, 23, 24]
        ) : nil)
        widget.set("calendar") { calendar.write(into: &$0) }
        widget.set("seconds") { $0.number(now) }
        widget.set("clock") { $0.string("9:41 AM") }
        widget.set("date") { $0.string("Fri Oct 23") }
    }

    private func percent(_ value: Double) -> String {
        ShellFormatter.string(kind: OMNI_FORMAT_PERCENT, value, digits: 0)
    }

    private func batteryFixture(
        _ widget: ShellRenderedWidget,
        level: Double = 76,
        charging: Bool = false,
        power: ShellPower = ShellPower(source: "battery", remaining: 254)
    ) {
        widget.set("battery") { $0.number(level) }
        widget.set("charging") { $0.bool(charging) }
        widget.set("power") { power.write(into: &$0) }
    }

    @discardableResult
    private func weatherFixture(
        _ widget: ShellRenderedWidget,
        stale: Bool = false,
        unit: String = "°C",
        flatRange: Bool = false
    ) -> ShellWeather {
        let codes = [2, 1, 2, 3, 61, 63, 80, 95, 3, 2, 1, 0, 0, 1]
        let weather = ShellWeather(
            temp: 18.4, feels: 17, high: 21, low: 11, rain: 30, wind: 14, humidity: 64, sunrise: 999_000,
            sunset: 1_040_000, code: 2, day: true, unit: unit, place: "Toronto", stale: stale,
            hours: (0 ..< 14).map { index in ShellWeatherHour(
                time: 1_000_000 + Double(index) * 3600, label: index == 0 ? "Now" : "\((9 + index) % 24)",
                temp: 18 + sin(Double(index) / 3) * 3, code: codes[index], day: index < 10, rain: Double(index * 5)
            ) },
            days: ["Today", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu"].enumerated().map { index, label in
                ShellWeatherDay(
                    time: 1_000_000 + Double(index) * 86400, label: label,
                    high: flatRange ? 10 : [21, 19, 23, 17, 15, 18, 22][index],
                    low: flatRange ? 10 : [11, 10, 13, 9, 7, 8, 12][index],
                    code: [2, 61, 0, 63, 95, 3, 1][index], rain: [30, 80, 0, 60, 90, 20, 10][index]
                )
            }
        )
        widget.set("weather") { weather.write(into: &$0) }
        return weather
    }

    private func mediaFixture(
        _ widget: ShellRenderedWidget,
        playing: Bool = true,
        title: String = "Northern Lights",
        elapsed: Double? = 87,
        duration: Double? = 243,
        shuffle: Bool? = false,
        repeatMode: ShellMedia.Repeat? = .all,
        lyrics: ShellLyrics = ShellLyrics(status: .synced, lines: [
            .init(time: 80, text: "Lights across the harbour"),
            .init(time: 86, text: "Waiting for the morning train"),
            .init(time: 92, text: ""),
            .init(time: 98, text: "Every window holds a song"),
            .init(time: 104, text: "Carried on the evening rain"),
            .init(time: 110, text: "Until the city sings along")
        ])
    ) {
        var media = ShellMedia()
        media.title = title
        media.artist = "Sample Artist"
        media.album = "Sample Album"
        media.app = "Music"
        media.bundle = "com.apple.Music"
        media.playing = playing
        media.duration = duration
        media.elapsed = elapsed
        media.rate = playing ? 1 : 0
        media.sampledAt = 1000
        media.shuffle = shuffle
        media.repeatMode = repeatMode
        widget.set("media") { media.write(into: &$0) }
        widget.set("seconds") { $0.number(1012) }
        widget.set("lyrics") { lyrics.write(into: &$0) }
    }

    private func systemStatsFixture(_ widget: ShellRenderedWidget) {
        widget.set("system") { writer in
            ShellSystemData(
                memoryUsed: 21 << 30,
                memoryTotal: 36 << 30,
                pressure: .normal,
                diskUsed: 612_000_000_000,
                diskTotal: 994_000_000_000,
                uptime: 273_840,
                host: SystemStatsHostInfo(
                    chip: "Apple M4 Max",
                    modelIdentifier: "Mac16,9",
                    osVersion: "Version 27.2",
                    hostname: "studio"
                ),
                displays: [
                    ShellSystemDisplay(width: 5120, height: 2880, refresh: 120),
                    ShellSystemDisplay(width: 3024, height: 1964, refresh: 120)
                ]
            ).write(into: &writer)
        }
        widget.set("cpu") { $0.number(37) }
        widget.set("gpu") { $0.number(18) }
        widget.set("memory") { $0.number(58) }
        widget.set("disk") { $0.number(62) }
        widget.set("thermal") { ShellThermal(cpu: 61, gpu: 48, gpuName: "Apple M4 Max GPU").write(into: &$0) }
        widget.set("network") {
            ShellServiceValue.object(["down": .number(1_840_000), "up": .number(312_000)]).write(to: &$0)
        }
        var history = ShellNetworkHistory(received: 18_400_000_000, sent: 2_100_000_000)
        for index in 0 ..< ShellNetworkHistory.length {
            let phase = Double(index) / 4
            history.append(ShellNetworkRate(down: 900_000 + sin(phase) * 700_000, up: 200_000 + cos(phase) * 120_000))
        }
        widget.set("networkHistory") { history.write(into: &$0) }
        batteryFixture(widget)
    }

    private func hiddenBarFixture(vertical: Bool, menu: Bool) -> ShellHiddenBarData {
        ShellHiddenBarData(
            enabled: true, available: true,
            items: (0 ..< 5).map {
                ShellHiddenBarItem(id: "app#\($0)", name: "Hidden App \($0)", image: nil, width: 24, height: 16)
            },
            maxWidth: 240, maxHeight: menu ? 220 : 60, cell: 24, vertical: vertical,
            menu: menu ? HiddenBarMenuPage(title: "Options", rows: [
                hiddenMenuFixtureRow("checked", title: "Checked item", mark: "✓", shortcut: "⌘K"),
                hiddenMenuFixtureRow("disabled", title: "Disabled item", enabled: false),
                hiddenMenuFixtureRow("separator", title: "", enabled: false, separator: true),
                hiddenMenuFixtureRow("submenu", title: "More options", submenu: true)
            ], backID: "back") : nil
        )
    }

    private func hiddenMenuFixtureRow(
        _ id: String,
        title: String,
        enabled: Bool = true,
        mark: String? = nil,
        shortcut: String? = nil,
        submenu: Bool = false,
        separator: Bool = false
    ) -> HiddenBarMenuRow {
        HiddenBarMenuRow(
            id: id, title: title, enabled: enabled, mark: mark,
            shortcut: shortcut, submenu: submenu, separator: separator
        )
    }

    private func makeWidget(
        _ name: String,
        config: ShellConfig,
        shell: URL,
        scale: CGFloat = 2,
        resources: ShellResources? = nil,
        source override: URL? = nil
    ) throws -> ShellRenderedWidget {
        let source = try override ?? XCTUnwrap(config.widget(name))
        let chunk = String(source.path.dropFirst(shell.path.count + 1))
        let profile = chunk.split(separator: "/").first.map(String.init) ?? config.profile
        var modules: [ShellWidgetSource.Module] = []
        var seen: Set<String> = []
        for directory in config.directories {
            let library = directory.appendingPathComponent("lib")
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: library.path)) ?? []
                where entry.hasSuffix(".luau") && seen.insert(entry).inserted
            {
                modules.append(try ShellWidgetSource.Module(
                    path: "\(profile)/lib/\(entry)",
                    source: String(contentsOf: library.appendingPathComponent(entry), encoding: .utf8)
                ))
            }
        }
        let widget = try ShellRenderedWidget(
            name: name, source: String(contentsOf: source, encoding: .utf8), directories: config.directories,
            modules: modules, chunk: "@" + chunk, scale: scale, resources: resources
        )
        if let settings = config.widgetSettings[name] {
            XCTAssertEqual(settings.withUnsafeBufferPointer {
                omni_instance_set_value(widget.instance, "settings", $0.baseAddress, $0.count)
            }, OMNI_OK)
        }
        return widget
    }

    private func scratchpadFixture(_ config: ShellConfig, height: Double, vertical: Bool) -> ShellBarData {
        var bar = fixture(config, height: height, vertical: vertical)
        bar.style.accents = true
        let members = (0 ..< 5).map { index in
            ShellBarItem(
                id: "\(index)",
                bundle: applications[index % applications.count],
                name: "App \(index)",
                focused: index == 0,
                count: index == 1 ? 2 : 1,
                hidden: 0,
                badge: ["7", "42", "999+", "3", ""][index],
                windows: [
                    ShellBarWindow(
                        id: "scratch-\(index)",
                        title: "Window \(index)",
                        focused: index == 0,
                        hidden: false
                    )
                ]
            )
        }
        bar.scratchpads = [
            ShellBarScratchpad(
                id: 1,
                name: "Terminal sessions",
                focused: true,
                revealed: true,
                visible: true,
                windows: members
            ),
            ShellBarScratchpad(
                id: 2,
                name: "Chat",
                focused: false,
                revealed: false,
                visible: false,
                windows: [members[3]],
                compact: true
            ),
            ShellBarScratchpad(
                id: 3,
                name: "Music",
                focused: false,
                revealed: false,
                visible: true,
                windows: [members[4]]
            )
        ]
        return bar
    }

    private func fixture(_ config: ShellConfig, height: Double, vertical: Bool) -> ShellBarData {
        var bar = ShellBarData(badges: "text")
        let settings = config.barOverride?.settings
        bar.style.labels = settings?.showLabels ?? bar.style.labels
        bar.style.backgrounds = settings?.showItemBackgrounds ?? bar.style.backgrounds
        bar.style.accents = settings?.showAccentHighlights ?? bar.style.accents
        bar.style.transparent = settings?.transparentBackground ?? bar.style.transparent
        bar.style.solidBlack = settings?.solidBlackBackground ?? bar.style.solidBlack
        bar.style.height = height
        bar.style.vertical = vertical
        bar.style.statsButton = true
        bar.style.position = vertical ? "left" : "top"
        let items = applications.enumerated().map { index, bundle in
            ShellBarItem(
                id: "\(index)", bundle: bundle, name: ["Safari", "Terminal", "Finder", "Notes"][index],
                focused: index == 0, count: index == 1 ? 2 : 1, hidden: index == 1 || index == 2 ? 1 : 0,
                badge: index == 0 ? "3" : "", floating: index == 3,
                windows: (0 ..< (index == 1 ? 2 : 1)).map { window in
                    ShellBarWindow(
                        id: "\(index)_\(window)", title: "Window \(index)-\(window)",
                        focused: index == 0, hidden: index == 2 || index == 1 && window == 0
                    )
                }
            )
        }
        bar.workspaces = [
            ShellBarWorkspace(id: "1", name: "1", focused: true, windows: Array(items.prefix(2))),
            ShellBarWorkspace(id: "2", name: "2", focused: false, windows: Array(items.suffix(2))),
            ShellBarWorkspace(id: "3", name: "3", focused: false, windows: [])
        ]
        bar.scratchpads = [
            ShellBarScratchpad(id: 1, name: "Chat", focused: false, revealed: true, visible: true, windows: [items[3]])
        ]
        return bar
    }

    private func raster(_ surface: ShellWidgetSurface, scale: CGFloat) throws -> CGImage {
        ShellLayerScene.engineQueue.sync {}
        let size = surface.size
        let context = try XCTUnwrap(CGContext(
            data: nil, width: Int(ceil(size.width * scale)), height: Int(ceil(size.height * scale)),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: scale, y: -scale)
        try XCTUnwrap(surface.view.layer).render(in: context)
        return try XCTUnwrap(context.makeImage())
    }

    private func write(
        _ previews: [(String, CGImage, CGSize)],
        name: String,
        scale: CGFloat,
        dark: Bool,
        solidBlack: Bool
    ) throws {
        let spacing: CGFloat = 24
        let width = previews.reduce(spacing) { $0 + $1.2.width + spacing }
        let height = (previews.map { $0.2.height }.max() ?? 0) + spacing * 2
        let context = try XCTUnwrap(CGContext(
            data: nil, width: Int(ceil(width * scale)), height: Int(ceil(height * scale)),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: solidBlack ? 0 : dark ? 0.09 : 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var x = spacing
        for (_, image, size) in previews {
            context.draw(
                image,
                in: CGRect(x: x, y: height - spacing - size.height, width: size.width, height: size.height)
            )
            x += size.width + spacing
        }
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OMNIWM_SHELL_SNAPSHOTS"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            directory.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
