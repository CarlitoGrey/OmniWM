// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDesktopBarDisplayInspector: View {
    let editor: ShellDesktopEditor
    let monitor: Monitor

    private var settings: MonitorBarSettings {
        editor.monitorSettings(for: monitor)
    }

    private var inherited: ResolvedBarSettings {
        editor.inherited(for: monitor)
    }

    var body: some View {
        Section("Display Overrides") {
            LabeledContent("Overrides") {
                Text(settings.overriddenKeys.isEmpty ? String(localized: "Style default") : String(localized: "Custom"))
                    .foregroundStyle(.secondary)
            }
            Button("Reset Display Overrides") { editor.resetDisplay(monitor) }
                .disabled(settings.overriddenKeys.isEmpty)
        }
        Section("Position & Level") {
            picker(
                String(localized: "Position"),
                setting: ("position", \.position),
                fallback: inherited.position,
                options: WorkspaceBarPosition.allCases,
                title: { $0.displayName }
            )
            toggle(String(localized: "Full Width"), setting: ("fullWidth", \.fullWidth), fallback: inherited.fullWidth)
                .help("Span the whole edge of the screen, with each widget group pinned to its start, center, or end")
            picker(
                String(localized: "Window Level"),
                setting: ("windowLevel", \.windowLevel),
                fallback: inherited.windowLevel,
                options: WorkspaceBarWindowLevel.allCases,
                title: { $0.displayName }
            )
            DisclosureGroup("Advanced Positioning") {
                offset(String(localized: "X Offset"), setting: ("xOffset", \.xOffset), fallback: inherited.xOffset)
                    .help("Horizontal offset (negative = left, positive = right)")
                offset(String(localized: "Y Offset"), setting: ("yOffset", \.yOffset), fallback: inherited.yOffset)
                    .help("Vertical offset (negative = down, positive = up)")
            }
        }
        Section("Screen Placement") {
            toggle(
                String(localized: "Reserve Space for Workspace Bar"),
                setting: ("reserveLayoutSpace", \.reserveLayoutSpace),
                fallback: inherited.reserveLayoutSpace
            )
            .help(
                "Reserve tiled layout space at the selected edge. Overlapping bars reserve only the portion below the menu bar."
            )
            if settings.fullWidth ?? inherited.fullWidth {
                picker(
                    String(localized: "Notch Mode"),
                    setting: ("fullWidthNotchMode", \.fullWidthNotchMode),
                    fallback: inherited.fullWidthNotchMode,
                    options: WorkspaceBarFullWidthNotchMode.allCases,
                    title: { $0.displayName }
                )
            } else {
                picker(
                    String(localized: "Notch Mode"),
                    setting: ("notchMode", \.notchMode),
                    fallback: inherited.notchMode,
                    options: WorkspaceBarNotchMode.allCases,
                    title: { $0.displayName }
                )
                slider(
                    String(localized: "Active Zone Width"),
                    setting: ("notchActiveZoneWidth", \.notchActiveZoneWidth),
                    fallback: inherited.notchActiveZoneWidth,
                    range: 100 ... 400,
                    step: 10,
                    format: { String(localized: "\(Int($0)) px") }
                )
                .help("Width of the zone next to the notch that the focused workspace stays centered in")
            }
            SettingsCaption(localized: "Notch modes apply to the top edge only.")
        }
        Section("Appearance") {
            slider(
                String(localized: "Bar Thickness"),
                setting: ("height", \.height),
                fallback: inherited.height,
                range: 20 ... 200,
                step: 2,
                format: { String(localized: "\(Int($0)) pt") }
            )
            slider(
                String(localized: "Background Opacity"),
                setting: ("backgroundOpacity", \.backgroundOpacity),
                fallback: inherited.backgroundOpacity,
                range: 0 ... 1,
                step: 0.05,
                format: { "\(Int($0 * 100))%" }
            )
            slider(
                String(localized: "Inactive Icon Opacity"),
                setting: ("inactiveIconOpacity", \.inactiveIconOpacity),
                fallback: inherited.inactiveIconOpacity ?? 0.5,
                range: 0 ... 1,
                step: 0.05,
                format: { "\(Int($0 * 100))%" }
            )
            .help("Opacity of app icons that are not focused")
            toggle(
                String(localized: "Transparent Background"),
                setting: ("transparentBackground", \.transparentBackground),
                fallback: inherited.transparentBackground
            )
            .help("Hide the workspace bar material, tint, and border while keeping its contents interactive.")
            toggle(
                String(localized: "Solid Black Background"),
                setting: ("solidBlackBackground", \.solidBlackBackground),
                fallback: inherited.solidBlackBackground
            )
            .help("Fill the workspace bar with fully opaque black, overriding the tint, material, and border.")
            toggle(
                String(localized: "Show Item Backgrounds"),
                setting: ("showItemBackgrounds", \.showItemBackgrounds),
                fallback: inherited.showItemBackgrounds
            )
            .help("Show material backgrounds behind workspace groups, floating windows, scratchpad, and stats.")
            toggle(
                String(localized: "Show Accent Highlights"),
                setting: ("showAccentHighlights", \.showAccentHighlights),
                fallback: inherited.showAccentHighlights
            )
            .help("Show the focused-workspace outline and focused-icon accent glow.")
        }
        Section("Workspace Bar Behavior") {
            toggle(
                String(localized: "Enable Workspace Bar"),
                setting: ("enabled", \.enabled),
                fallback: inherited.enabled
            )
            if !editor.barEnabled {
                SettingsCaption(localized: "Display settings are saved while the global Workspace Bar is off.")
            }
            toggle(
                String(localized: "Show Workspace Labels"),
                setting: ("showLabels", \.showLabels),
                fallback: inherited.showLabels
            )
            toggle(
                String(localized: "Show Floating Windows"),
                setting: ("showFloatingWindows", \.showFloatingWindows),
                fallback: inherited.showFloatingWindows
            )
            toggle(
                String(localized: "Deduplicate App Icons"),
                setting: ("deduplicateAppIcons", \.deduplicateAppIcons),
                fallback: inherited.deduplicateAppIcons
            )
            .help("Group workspace windows by app with badge counts; scratchpad pills always group by app")
            toggle(
                String(localized: "Hide Empty Workspaces"),
                setting: ("hideEmptyWorkspaces", \.hideEmptyWorkspaces),
                fallback: inherited.hideEmptyWorkspaces
            )
            toggle(
                String(localized: "Automatically hide and show the workspace bar"),
                setting: ("autoHide", \.autoHide),
                fallback: inherited.autoHide
            )
            .help(
                "Show at the bar edge; hide when the pointer moves inward past the bar and interactions end. Never reserves layout space."
            )
        }
    }

    private func binding<Value: Sendable>(
        _ key: String, path: WritableKeyPath<MonitorBarSettings, Value?>, fallback: Value, continuous: Bool = false
    ) -> Binding<Value> {
        Binding(
            get: { editor.pending(editor.displayTarget(monitor, key: key)) ?? settings[keyPath: path] ?? fallback },
            set: { editor.setDisplay(monitor, key: key, value: $0, continuous: continuous) { $0[keyPath: path] = $1 } }
        )
    }

    private func reset<Value: Sendable>(_ key: String, path: WritableKeyPath<MonitorBarSettings, Value?>) {
        editor.setDisplay(monitor, key: key, value: Optional<Value>.none) { $0[keyPath: path] = $1 }
    }

    private func hasOverride<Value>(_ key: String, path: KeyPath<MonitorBarSettings, Value?>) -> Bool {
        settings[keyPath: path] != nil || editor.pending(editor.displayTarget(monitor, key: key), as: Value.self) != nil
    }

    @ViewBuilder
    private func status<Value: Sendable>(
        _ label: String,
        key: String,
        path: WritableKeyPath<MonitorBarSettings, Value?>
    ) -> some View {
        if hasOverride(key, path: path) {
            ResetIconButton(title: String(localized: "Reset \(label) to Style default")) { reset(key, path: path) }
        } else {
            Text("Style default")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func toggle(
        _ label: String,
        setting: (key: String, path: WritableKeyPath<MonitorBarSettings, Bool?>),
        fallback: Bool
    ) -> some View {
        let (key, path) = setting
        return HStack {
            Toggle(label, isOn: binding(key, path: path, fallback: fallback))
            status(label, key: key, path: path)
        }
    }

    private func picker<Value: Hashable & Sendable>(
        _ label: String, setting: (key: String, path: WritableKeyPath<MonitorBarSettings, Value?>), fallback: Value,
        options: [Value], title: @escaping (Value) -> String
    ) -> some View {
        let (key, path) = setting
        return HStack {
            Picker(label, selection: binding(key, path: path, fallback: fallback)) {
                ForEach(options, id: \.self) { Text(title($0)).tag($0) }
            }
            status(label, key: key, path: path)
        }
    }

    private func slider(
        _ label: String, setting: (key: String, path: WritableKeyPath<MonitorBarSettings, Double?>), fallback: Double,
        range: ClosedRange<Double>, step: Double = 1, format: @escaping (Double) -> String
    ) -> some View {
        let (key, path) = setting
        let value = binding(key, path: path, fallback: fallback, continuous: true)
        return HStack {
            SettingsSliderRow(
                label: label,
                value: value,
                range: range,
                step: step,
                valueText: format(value.wrappedValue)
            )
            status(label, key: key, path: path)
        }
    }

    private func offset(
        _ label: String,
        setting: (key: String, path: WritableKeyPath<MonitorBarSettings, Double?>),
        fallback: Double
    ) -> some View {
        let (key, path) = setting
        let value = binding(key, path: path, fallback: fallback)
        return HStack {
            SettingsNumberStepperRow(
                label: label,
                value: value,
                step: 10,
                valueText: String(localized: "\(Int(value.wrappedValue)) px")
            )
            status(label, key: key, path: path)
        }
    }
}
