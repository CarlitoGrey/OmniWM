// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDrawerEditorForm: View {
    let editor: ShellDesktopEditor
    @State private var adding = false

    var body: some View {
        Form {
            ShellDesktopEditorMessages(editor: editor)
            if editor.snapshot != nil {
                Section("Drawers") {
                    if editor.drawers.isEmpty {
                        Text("This style has no drawers.")
                        SettingsCaption(
                            localized: "Group widgets in a panel at a screen edge. Drawers can open on hover or with a shortcut."
                        )
                    } else {
                        ForEach(editor.drawers, id: \.id) { drawer in
                            drawerRow(drawer)
                        }
                    }
                    Button("Add Drawer…", systemImage: "plus") { adding = true }
                        .disabled(editor.drawerCandidates(nil).isEmpty)
                    if !editor.drawersLoad {
                        SettingsCaption(
                            localized: "Drawers load only while the Workspace Bar or Dynamic Island is on."
                        )
                    }
                }
                if let drawer = editor.drawer {
                    ShellDrawerInspector(editor: editor, drawer: drawer)
                }
            } else if editor.problem == nil {
                Section { ProgressView("Loading style…").frame(maxWidth: .infinity) }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $adding) { ShellAddDrawerSheet(editor: editor) }
    }

    private func drawerRow(_ drawer: ShellDrawerConfig) -> some View {
        Button { Task { await editor.selectDrawer(drawer.id) } } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                VStack(alignment: .leading, spacing: 3) {
                    Text(ShellBarLayout.title(of: drawer.id)).fontWeight(.medium)
                    let edge = ShellWidgetSettingsModel.title(drawer.edge.rawValue)
                    let count = editor.drawerMembers(drawer.id).count
                    Text(count == 1
                        ? String(localized: "\(edge) · 1 widget")
                        : String(localized: "\(edge) · \(count) widgets"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if editor.isStyleDrawer(drawer.id) {
                    Text("Style").font(.caption).foregroundStyle(.secondary)
                }
                if editor.selectedDrawer == drawer.id {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                editor.selectedDrawer == drawer.id ? Color.accentColor.opacity(0.14) : Color.clear,
                in: .rect(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
