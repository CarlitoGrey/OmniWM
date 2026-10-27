// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import SwiftUI

enum WelcomeReason {
    case firstRun
    case reopened

    var primaryActionTitle: String {
        switch self {
        case .firstRun: String(localized: "Get Started")
        case .reopened: String(localized: "Done")
        }
    }
}

struct WelcomeFeatureContent: Equatable {
    enum Shortcut: Equatable {
        case assigned(String)
        case unassigned(String)
    }

    let shortcut: Shortcut?
    let detail: String
}

enum WelcomeFeature: CaseIterable, Identifiable {
    case barMenus
    case commandPalette
    case quakeTerminal
    case widgetPermissions

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .barMenus: String(localized: "Bar Menus")
        case .commandPalette: String(localized: "Command Palette")
        case .quakeTerminal: String(localized: "Quake Terminal")
        case .widgetPermissions: String(localized: "Widget Permissions")
        }
    }

    var systemImage: String {
        switch self {
        case .barMenus: "menubar.rectangle"
        case .commandPalette: "magnifyingglass"
        case .quakeTerminal: "terminal"
        case .widgetPermissions: "network.badge.shield.half.filled"
        }
    }

    var actionTitle: String {
        switch self {
        case .barMenus: String(localized: "Learn More")
        case .commandPalette: String(localized: "Keyboard Shortcuts…")
        case .quakeTerminal: String(localized: "Quake Terminal Settings…")
        case .widgetPermissions: String(localized: "Network & Permissions…")
        }
    }

    var destination: SettingsSection? {
        switch self {
        case .barMenus: nil
        case .commandPalette: .hotkeys
        case .quakeTerminal: .quakeTerminal
        case .widgetPermissions: .network
        }
    }

    private var actionID: String? {
        switch self {
        case .barMenus: "openMenuAnywhere"
        case .commandPalette: "openCommandPalette"
        case .quakeTerminal: "toggleQuakeTerminal"
        case .widgetPermissions: nil
        }
    }

    func content(bindings: [HotkeyBinding], quakeEnabled: Bool) -> WelcomeFeatureContent {
        let trigger = actionID.map { id in bindings.first { $0.id == id }?.binding ?? .unassigned }
        let shortcut = trigger.map { trigger -> WelcomeFeatureContent.Shortcut in
            let text = HotkeySettingsDisplayModel.displayString(for: trigger)
            return trigger.isUnassigned ? .unassigned(text) : .assigned(text)
        }
        let tryIt: String? = if case let .assigned(text) = shortcut {
            String(localized: "Press \(text) to try it now.")
        } else {
            nil
        }
        let detail = switch self {
        case .barMenus where tryIt == nil:
            String(
                localized: "The Apple button on the bar opens the Apple menu, and the app name opens that app's menus. Menu Anywhere opens them at the pointer."
            )
        case .barMenus:
            String(
                localized: "The Apple button on the bar opens the Apple menu, and the app name opens that app's menus. Menu Anywhere opens them at the pointer; try it in another app."
            )
        case .commandPalette:
            sentences(
                String(localized: "Search windows, apps, files, the clipboard, app menus and OmniWM commands."),
                tryIt
            )
        case .quakeTerminal:
            sentences(
                String(
                    localized: "A terminal that drops down over any app, on any Space. Choose Ghostty, Kitty or foot."
                ),
                quakeEnabled ? tryIt : String(localized: "Turn it on in Quake Terminal Settings.")
            )
        case .widgetPermissions:
            String(
                localized: "Widgets ask the first time they contact a server, and programs ask before they run. Weather and Lyrics have their own switches."
            )
        }
        return WelcomeFeatureContent(shortcut: shortcut, detail: detail)
    }

    private func sentences(_ first: String, _ second: String?) -> String {
        second.map { "\(first) \($0)" } ?? first
    }
}

@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()

    private let presenter: HostedWindowPresenter
    private let showSettings: @MainActor (SettingsStore, WMController, SettingsSection) -> Void
    private var onDismiss: (@MainActor () -> Void)?

    init(
        presenter: HostedWindowPresenter = HostedWindowPresenter(),
        showSettings: @escaping @MainActor (SettingsStore, WMController, SettingsSection) -> Void = {
            SettingsWindowController.shared.show(settings: $0, controller: $1, section: $2)
        }
    ) {
        self.presenter = presenter
        self.showSettings = showSettings
    }

    var isVisible: Bool {
        presenter.window != nil
    }

    func show(
        settings: SettingsStore,
        controller: WMController,
        reason: WelcomeReason,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        if !isVisible {
            self.onDismiss = onDismiss
        }
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]
        presenter.present(
            title: String(localized: "Welcome to OmniWM"),
            styleMask: styleMask,
            contentSize: WelcomeView.minimumSize,
            minSize: NSWindow.frameRect(
                forContentRect: NSRect(origin: .zero, size: WelcomeView.minimumSize),
                styleMask: styleMask
            ).size,
            configure: { window in
                window.collectionBehavior = [.moveToActiveSpace]
                window.standardWindowButton(.closeButton)?.keyEquivalent = "\u{1b}"
            },
            onWillClose: { [weak self] in
                self?.dismiss()
            },
            content: {
                WelcomeView(
                    settings: settings,
                    reason: reason,
                    onOpenSettings: { [weak self, weak controller] section in
                        guard let self, let controller else { return }
                        showSettings(settings, controller, section)
                    },
                    onDone: { [weak self] in
                        self?.presenter.close()
                    }
                )
            }
        )
    }

    private func dismiss() {
        let onDismiss = onDismiss
        self.onDismiss = nil
        onDismiss?()
    }
}

struct WelcomeView: View {
    static let minimumSize = NSSize(width: 620, height: 721)
    private static let brandColor = Color(red: 182 / 255, green: 101 / 255, blue: 69 / 255)
    private static let quickStartURL = URL(string: "https://omniwm.app/guides/quick-start/")

    let settings: SettingsStore
    let reason: WelcomeReason
    let onOpenSettings: @MainActor (SettingsSection) -> Void
    let onDone: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: OmniWMBrandMark.statusItemImage(pointSize: 44))
                    .renderingMode(.template)
                    .foregroundStyle(Self.brandColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to OmniWM")
                        .font(.title2.bold())
                    Text(
                        "OmniWM arranges your windows. OmniShell draws the bar, its menus and widgets, and you can restyle all of it."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(WelcomeFeature.allCases) { feature in
                        WelcomeFeatureRow(
                            feature: feature,
                            content: feature.content(
                                bindings: settings.hotkeyBindings,
                                quakeEnabled: settings.quakeTerminal.enabled
                            ),
                            onOpenSettings: onOpenSettings
                        )
                    }
                    Text("Open this window again from the OmniWM menu: Help & Links > Welcome to OmniWM.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 12) {
                if let quickStartURL = Self.quickStartURL {
                    HelpLink(destination: quickStartURL)
                }
                Spacer()
                Button("Choose a Style…") { onOpenSettings(.styles) }
                    .buttonStyle(.bordered)
                Button(reason.primaryActionTitle, action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .background(.background)
    }
}

private struct WelcomeFeatureRow: View {
    private static let menusGuideURL = URL(string: "https://omniwm.app/omnishell/guides/menus/")

    let feature: WelcomeFeature
    let content: WelcomeFeatureContent
    let onOpenSettings: @MainActor (SettingsSection) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(feature.title).font(.headline)
                    Spacer(minLength: 0)
                    switch content.shortcut {
                    case let .assigned(shortcut):
                        Text(shortcut)
                            .font(.callout)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tertiary))
                    case let .unassigned(label):
                        Text(label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    case nil:
                        EmptyView()
                    }
                }
                Text(content.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if let destination = feature.destination {
                        Button(feature.actionTitle) { onOpenSettings(destination) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else if let menusGuideURL = Self.menusGuideURL {
                        Link(feature.actionTitle, destination: menusGuideURL)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
