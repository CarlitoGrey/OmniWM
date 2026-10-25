// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct KittyQuakeSettingsSections: View {
    private enum AutoHideChoice: Hashable {
        case kittyConfig
        case on
        case off
    }

    let quake: QuakeTerminalSettings
    let controller: WMController

    private var autoHideChoice: Binding<AutoHideChoice> {
        Binding(
            get: { [quake] in
                switch quake.kitty.autoHide {
                case nil: .kittyConfig
                case true?: .on
                case false?: .off
                }
            },
            set: { [quake] choice in
                switch choice {
                case .kittyConfig: quake.kitty.autoHide = nil
                case .on: quake.kitty.autoHide = true
                case .off: quake.kitty.autoHide = false
                }
            }
        )
    }

    private var placementOverride: Binding<Bool> {
        Binding(
            get: { [quake] in quake.kitty.placement != nil },
            set: { [quake] enabled in
                quake.kitty.placement = enabled ? KittyQuakeSettings.Placement.defaultOverride : nil
            }
        )
    }

    private var opacityOverride: Binding<Bool> {
        Binding(
            get: { [quake] in quake.kitty.opacity != nil },
            set: { [quake] enabled in
                quake.kitty.opacity = enabled ? KittyQuakeSettings.defaultOpacityOverride : nil
            }
        )
    }

    var body: some View {
        Group {
            placementSection
            behaviorSection
            appearanceSection
        }
    }

    private var placementSection: some View {
        Section("Kitty Placement") {
            Toggle("Override Kitty Placement", isOn: placementOverride)
                .id("Override Kitty Placement")

            if let placement = quake.kitty.placement {
                Picker("Position", selection: Binding(
                    get: { [quake] in quake.kitty.placement?.position ?? placement.position },
                    set: { [quake] in quake.kitty.placement?.position = $0 }
                )) {
                    ForEach(QuakeTerminalPosition.allCases, id: \.self) { position in
                        Text(position.localizedDisplayName).tag(position)
                    }
                }
                .id("Kitty Position")

                SettingsSliderRow(
                    label: String(localized: "Width"),
                    value: Binding(
                        get: { [quake] in quake.kitty.placement?.widthPercent ?? placement.widthPercent },
                        set: { [quake] in quake.kitty.placement?.widthPercent = $0 }
                    ),
                    range: 10 ... 100,
                    step: 5,
                    valueText: "\(Int(placement.widthPercent))%"
                )
                .id("Kitty Width")

                SettingsSliderRow(
                    label: String(localized: "Height"),
                    value: Binding(
                        get: { [quake] in quake.kitty.placement?.heightPercent ?? placement.heightPercent },
                        set: { [quake] in quake.kitty.placement?.heightPercent = $0 }
                    ),
                    range: 10 ... 100,
                    step: 5,
                    valueText: "\(Int(placement.heightPercent))%"
                )
                .id("Kitty Height")
            }

            SettingsCaption(localized: "Placement changes apply the next time Kitty is shown.")

            SettingsCaption(
                localized: "Turning an override off returns that setting to Kitty's quick-access-terminal.conf the next time the Kitty panel starts."
            )
        }
        .id("Kitty Placement")
        .onChange(of: quake.kitty) { _, _ in
            controller.applyKittyQuakeSettings()
        }
    }

    private var behaviorSection: some View {
        Section("Kitty Behavior") {
            Picker("Auto-hide on Focus Loss", selection: autoHideChoice) {
                Text("Kitty Config").tag(AutoHideChoice.kittyConfig)
                Text("On").tag(AutoHideChoice.on)
                Text("Off").tag(AutoHideChoice.off)
            }
            .id("Kitty Auto-hide on Focus Loss")
        }
        .id("Kitty Behavior")
    }

    private var appearanceSection: some View {
        Section("Kitty Appearance") {
            Toggle("Override Kitty Opacity", isOn: opacityOverride)
                .id("Override Kitty Opacity")

            if let opacity = quake.kitty.opacity {
                SettingsSliderRow(
                    label: String(localized: "Quake Background Opacity"),
                    value: Binding(
                        get: { [quake] in quake.kitty.opacity ?? opacity },
                        set: { [quake] in quake.kitty.opacity = $0 }
                    ),
                    range: 0 ... 1.0,
                    step: 0.05,
                    valueText: "\(Int((opacity * 100).rounded()))%"
                )
                .id("Kitty Background Opacity")

                if controller.kittyQuickAccessTerminal.problem == .opacityNeedsRestart {
                    SettingsCaption(KittyQuickAccessTerminal.Problem.opacityNeedsRestart.message)
                }

                SettingsCaption(
                    localized: "Opacity changes apply live as you drag."
                )
            }
        }
        .id("Kitty Appearance")
    }
}
