// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

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
