// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellAddDrawerSheet: View {
    let editor: ShellDesktopEditor
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var edge = ShellDrawerConfig.Edge.right
    @State private var firstWidget = ""
    @State private var adding = false
    @State private var panels = ShellDrawerPanels()

    init(
        editor: ShellDesktopEditor,
        initialName: String = "",
        initialEdge: ShellDrawerConfig.Edge = .right,
        initialWidget: String = ""
    ) {
        self.editor = editor
        _name = State(initialValue: initialName)
        _edge = State(initialValue: initialEdge)
        _firstWidget = State(initialValue: initialWidget)
    }

    var body: some View {
        let candidates = editor.drawerCandidates(nil)
        let request = editor.panelRequest(candidates)
        let values = panels.values(for: request)
        let available = candidates.filter { values[$0] == .available }
        let load = ShellDrawerPanels.Load(request: request, attempt: panels.attempt)
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Drawer").font(.title2.bold())
            TextField("Drawer name", text: $name).textFieldStyle(.roundedBorder).disabled(adding)
            Picker("Screen Edge", selection: $edge) {
                ForEach(ShellDrawerConfig.Edge.allCases, id: \.self) {
                    Text(ShellWidgetSettingsModel.title($0.rawValue)).tag($0)
                }
            }
            .disabled(adding)
            Picker("First Widget", selection: $firstWidget) {
                Text("Choose a widget").tag("")
                ForEach(available, id: \.self) { Text(ShellBarLayout.title(of: $0)).tag($0) }
            }
            .disabled(adding || panels.loading || available.isEmpty)
            if !panels.loading, available.isEmpty, !panels.hasFailure(for: request) {
                SettingsCaption(localized: "No widgets with panels are available in this style.")
            }
            failures(candidates: candidates, values: values)
            ShellDrawerPanelStatus(panels: panels, request: request, disabled: adding)
            if !adding, !name.isEmpty, let problem = editor.drawerNameProblem(name) {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let problem = editor.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            actions(available: available)
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480)
        .interactiveDismissDisabled(adding)
        .task(id: load) {
            await panels.load(load)
            guard !Task.isCancelled else { return }
            let values = panels.values(for: request)
            let available = candidates.filter { values[$0] == .available }
            if !available.contains(firstWidget) { firstWidget = available.first ?? "" }
        }
    }

    private func actions(available: [String]) -> some View {
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(adding)
            Spacer()
            if adding { ProgressView().controlSize(.small) }
            Button("Add") {
                let submittedEdge = edge
                let submittedName = name
                let submittedWidget = firstWidget
                adding = true
                Task {
                    if await editor.addDrawer(name: submittedName, edge: submittedEdge, widget: submittedWidget) {
                        dismiss()
                    } else {
                        adding = false
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(adding || editor.drawerNameProblem(name) != nil || !available.contains(firstWidget))
        }
    }

    @ViewBuilder
    private func failures(
        candidates: [String], values: [String: ShellSettingsPreview.Panel]
    ) -> some View {
        ForEach(candidates, id: \.self) { candidate in
            if case let .failed(problem) = values[candidate] {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ShellBarLayout.title(of: candidate)).fontWeight(.medium)
                    Text(problem).foregroundStyle(.red)
                }
                .font(.caption)
            }
        }
    }
}
