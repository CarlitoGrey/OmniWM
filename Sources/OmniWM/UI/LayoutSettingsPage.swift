// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct LayoutSettingsPage: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @Environment(SettingsNavigationModel.self) private var navigation
    // Owned here so each tab keeps its display scope while another tab is shown.
    @State private var spacingMonitor: Monitor.ID?
    @State private var niriMonitor: Monitor.ID?
    @State private var dwindleMonitor: Monitor.ID?

    private var selection: Binding<String> {
        Binding(get: { navigation.route.tab ?? "spacing" }, set: { navigation.selectTab($0) })
    }

    var body: some View {
        SettingsTabs(selection: selection, tabs: [
            ("Spacing", "spacing"), ("Niri", "niri"), ("Dwindle", "dwindle")
        ]) { tab in
            switch tab {
            case "niri":
                NiriSettingsTab(settings: settings, controller: controller, selectedMonitor: $niriMonitor)
            case "dwindle":
                DwindleSettingsTab(settings: settings, controller: controller, selectedMonitor: $dwindleMonitor)
            default:
                SpacingSettingsPage(settings: settings, controller: controller, selectedGapMonitor: $spacingMonitor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
