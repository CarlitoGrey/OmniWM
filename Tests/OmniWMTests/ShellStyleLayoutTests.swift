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
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        XCTAssertEqual(ShellDefaults.sync(into: shell), [])
        if !shared, let baseline = ProcessInfo.processInfo.environment["OMNIWM_STEP_BASE_SOURCE"] {
            try Data(contentsOf: URL(fileURLWithPath: baseline))
                .write(to: shell.appendingPathComponent("default/widgets/\(name)/init.luau"))
        }
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
                    widget.render(name == "scratchpads"
                        ? scratchpadFixture(config, height: height, vertical: vertical)
                        : fixture(config, height: height, vertical: vertical))
                    let background = resources.palette.color(.clear, default: .background)
                    try ShellBundledWidgetTests.writeSnapshot(
                        widget.surface,
                        name: "\(name)-\(profile)-\(vertical ? "vertical" : "horizontal")-\(dark ? "dark" : "light")",
                        dark: dark, directory: directory, background: background
                    )
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
