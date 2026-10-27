// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

extension CommandPaletteLauncherResultsView {
    var toolbar: some View {
        HStack(spacing: 8) {
            if mode == .applications {
                Picker("Filter", selection: Binding(get: { filter }, set: onFilter)) {
                    ForEach(LauncherFilter.allCases, id: \.self) { filter in
                        Text(filter == .cli ? String(localized: "CLI Tools") : filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Button {
                                onChipSelect(chip)
                            } label: {
                                Text(chip.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(chipBackgroundColor(for: chip), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedChipID == chip.id ? .isSelected : [])
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            if mode == .applications {
                Menu {
                    Button("Add Application…") { onAdd(.application) }
                    Button("Add Command…") { onAdd(.command) }
                    Button("Add Script…") { onAdd(.script) }
                    Divider()
                    Button("Manage Launcher…", action: onManage)
                    Button("Refresh", action: onRefresh)
                } label: {
                    Label("Add…", systemImage: "plus")
                        .frame(height: 28)
                }
                .menuStyle(.borderlessButton)
            }
            if mode == .files || filter == .apps {
                Menu {
                    Button("Grid", systemImage: viewStyle == .grid ? "checkmark" : "square.grid.2x2") {
                        onViewStyleChange(.grid)
                    }
                    Button("List", systemImage: viewStyle == .list ? "checkmark" : "list.bullet") {
                        onViewStyleChange(.list)
                    }
                } label: {
                    Image(systemName: viewStyle == .grid ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("View content as")
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 20)
    }
}
