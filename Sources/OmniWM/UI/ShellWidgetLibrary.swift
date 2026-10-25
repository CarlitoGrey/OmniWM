// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellWidgetLibrary: View {
    let editor: ShellDesktopEditor
    let target: ShellDesktopEditor.LibraryTarget
    let options: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var adding = false
    @State private var panels = ShellDrawerPanels()
    @State private var statuses: [String: (state: String, error: String?)] = [:]

    init(
        editor: ShellDesktopEditor, target: ShellDesktopEditor.LibraryTarget,
        query: String = "", options: @escaping (String) -> Void = { _ in }
    ) {
        self.editor = editor
        self.target = target
        self.options = options
        _query = State(initialValue: query)
    }

    private var entries: [ShellDesktopEditor.LibraryEntry] {
        editor.libraryEntries(target)
    }

    var body: some View {
        let entries = self.entries
        let request = panelRequest(entries)
        let values = panels.values(for: request)
        let load = ShellDrawerPanels.Load(request: request, attempt: panels.attempt)
        let matches = entries.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
        VStack(alignment: .leading, spacing: 12) {
            Text(target == .island ? String(localized: "Add Island Widget") : String(localized: "Add Widget"))
                .font(.title2.bold())
            TextField("Search widgets", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(matches) { entry in row(entry, panel: values[entry.name]) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ShellDrawerPanelStatus(panels: panels, request: request, disabled: adding)
            if let problem = editor.problem { message(problem) }
            if let problem = editor.metadataProblem { message(problem) }
            HStack {
                Spacer()
                if adding { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(adding)
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 480, minHeight: 400, idealHeight: 460)
        .interactiveDismissDisabled(adding)
        .task(id: load) {
            await panels.load(load)
        }
        .onChange(of: editor.selectedStyle, initial: true) { refreshStatuses() }
        .onReceive(NotificationCenter.default.publisher(for: .shellWidgetsDidChange)) { _ in
            refreshStatuses()
        }
    }

    private func row(_ entry: ShellDesktopEditor.LibraryEntry, panel: ShellSettingsPreview.Panel?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.icon).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).fontWeight(.medium)
                Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                if let reason = reason(entry, panel: panel) { message(reason) }
                if editor.scope == .active, let status = statuses[entry.name] {
                    Text(ShellWidgetSettingsModel.title(status.state)).font(.caption).foregroundStyle(.secondary)
                    if let error = status.error { message(error) }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                if target == .bar {
                    Menu("Add to") {
                        ForEach(ShellLane.allCases, id: \.self) { lane in
                            Button(ShellBarLayout.side(
                                lane, vertical: ShellBarLayout.vertical(editor.barSettings, on: editor.monitors)
                            )) { add(entry.name, lane: lane) }
                        }
                    }
                    .fixedSize().disabled(adding || !Self.available(entry, panel: panel, target: target))
                } else {
                    Button("Add") { add(entry.name) }
                        .disabled(adding || !Self.available(entry, panel: panel, target: target))
                }
                if target != .island {
                    Button("Options…") {
                        options(entry.name)
                        dismiss()
                    }
                    .disabled(adding)
                }
            }
        }
    }

    private func refreshStatuses() {
        statuses = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            editor.status(for: entry.name).map { (entry.name, $0) }
        })
    }

    private func panelRequest(_ entries: [ShellDesktopEditor.LibraryEntry]) -> ShellSettingsPreview.PanelRequest? {
        guard case .drawer = target else { return nil }
        return editor.panelRequest(entries.map(\.name))
    }

    private func reason(_ entry: ShellDesktopEditor.LibraryEntry, panel: ShellSettingsPreview.Panel?) -> String? {
        if let problem = entry.problem { return problem }
        guard case .drawer = target else { return nil }
        return switch panel {
        case .missing: String(localized: "No panel")
        case let .failed(problem): problem
        default: nil
        }
    }

    static func available(
        _ entry: ShellDesktopEditor.LibraryEntry, panel: ShellSettingsPreview.Panel?,
        target: ShellDesktopEditor.LibraryTarget
    ) -> Bool {
        guard entry.available else { return false }
        guard case .drawer = target else { return true }
        return panel == .available
    }

    private func add(_ name: String, lane: ShellLane = .trailing) {
        adding = true
        Task {
            if await editor.libraryAdd(name, to: target, lane: lane) { dismiss() }
            adding = false
        }
    }

    private func message(_ problem: String) -> some View {
        Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func shellWidgetLibrary(
        editor: ShellDesktopEditor, target: ShellDesktopEditor.LibraryTarget, isPresented: Binding<Bool>
    ) -> some View {
        modifier(ShellWidgetLibraryPresentation(editor: editor, target: target, presented: isPresented))
    }
}

private struct ShellWidgetLibraryPresentation: ViewModifier {
    let editor: ShellDesktopEditor
    let target: ShellDesktopEditor.LibraryTarget
    @Binding var presented: Bool
    @State private var pendingOptions: String?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $presented, onDismiss: {
            guard let widget = pendingOptions else { return }
            pendingOptions = nil
            Task { await editor.showOptions(widget) }
        }, content: {
            ShellWidgetLibrary(editor: editor, target: target) { pendingOptions = $0 }
        })
    }
}
