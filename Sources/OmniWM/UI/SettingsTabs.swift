// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

/// Segmented tabs for a settings page. SwiftUI's `TabView` is backed by `NSTabView`, which can size its tab
/// picker before the picker has a size when the page is inserted into a visible window, and only re-tiles it
/// on a later resize; the collapsed picker draws every label on top of the others.
struct SettingsTabs<Value: Hashable, Content: View>: View {
    @Binding var selection: Value
    let tabs: [(title: LocalizedStringKey, value: Value)]
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        VStack(spacing: 12) {
            Picker(selection: $selection) {
                ForEach(tabs, id: \.value) { tab in
                    Text(tab.title).tag(tab.value)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            content(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
