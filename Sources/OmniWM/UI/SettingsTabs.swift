// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

/// Segmented tabs for a settings page. SwiftUI's `TabView` is backed by `NSTabView`, which can size its tab
/// picker before the picker has a size when the page is inserted into a visible window, and only re-tiles it
/// on a later resize; the collapsed picker draws every label on top of the others.
///
/// Like `TabView`, a tab is built when first shown and then kept alive while hidden, so its view state
/// (scroll position, pickers, pending edits) survives switching tabs.
struct SettingsTabs<Value: Hashable, Content: View>: View {
    @Binding var selection: Value
    let tabs: [(title: LocalizedStringKey, value: Value)]
    @ViewBuilder let content: (Value) -> Content
    @State private var shown: Set<Value> = []

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
            ZStack {
                ForEach(tabs, id: \.value) { tab in
                    let selected = tab.value == selection
                    if selected || shown.contains(tab.value) {
                        content(tab.value)
                            .opacity(selected ? 1 : 0)
                            .allowsHitTesting(selected)
                            .disabled(!selected)
                            .accessibilityHidden(!selected)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: selection, initial: true) { _, value in shown.insert(value) }
    }
}
