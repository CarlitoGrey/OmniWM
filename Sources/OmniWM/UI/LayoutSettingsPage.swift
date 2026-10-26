// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct LayoutSettingsPage: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @Environment(SettingsNavigationModel.self) private var navigation

    private var selection: Binding<String> {
        Binding(get: { navigation.route.tab ?? "spacing" }, set: { navigation.selectTab($0) })
    }

    var body: some View {
        SettingsTabs(selection: selection, tabs: [
            ("Spacing", "spacing"), ("Niri", "niri"), ("Dwindle", "dwindle")
        ]) { tab in
            switch tab {
            case "niri": NiriSettingsTab(settings: settings, controller: controller)
            case "dwindle": DwindleSettingsTab(settings: settings, controller: controller)
            default: SpacingSettingsPage(settings: settings, controller: controller)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
