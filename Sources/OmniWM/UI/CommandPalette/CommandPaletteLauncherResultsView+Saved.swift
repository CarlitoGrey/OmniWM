// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

extension CommandPaletteLauncherResultsView {
    @ViewBuilder
    var savedResults: some View {
        if !savedEntries.isEmpty {
            Text("Saved").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            ForEach(savedEntries) { entry in
                let selection = LauncherSelection(sectionID: .saved, itemID: entry.id.uuidString)
                launcherRow(
                    name: entry.name, subtitle: entry.kind == .command ? entry.command : entry.path,
                    badge: entry.kind == .application ? entry.kind.title : entry.terminal.title,
                    symbol: entry.symbol, selection: selection
                )
                .contextMenu {
                    Button("Run") { onActivate(selection) }
                    Button("Edit") { onContextAction(selection, .edit) }
                    Button("Remove", role: .destructive) { onContextAction(selection, .remove) }
                }
            }
        }
        if filter == .cli {
            if cliLoading { ProgressView(String(localized: "Loading CLI tools…")).padding() }
            ForEach(executables) { executable in
                let selection = LauncherSelection(sectionID: .executables, itemID: executable.path)
                launcherRow(
                    name: executable.name, subtitle: executable.path,
                    badge: String(localized: "CLI"), symbol: "terminal", selection: selection
                )
                .contextMenu {
                    Button("Run…") { onActivate(selection) }
                    Button("Show in Finder") { onContextAction(selection, .reveal) }
                    Button("Copy Path") { onContextAction(selection, .copyPath) }
                }
            }
        }
    }

    private func launcherRow(
        name: String, subtitle: String, badge: String, symbol: String, selection: LauncherSelection
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 23)).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(badge).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            selectedItem == selection ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture { onActivate(selection) }
        .onHover { if $0 { onSelect(selection) } }
        .padding(.horizontal, 12)
        .id(selection)
    }
}
