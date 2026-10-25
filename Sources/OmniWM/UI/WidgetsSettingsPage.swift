// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import SwiftUI

struct ShellWidgetLibraryEntry: Identifiable {
    let name: String
    var bar = false
    var island = false
    var id: String {
        name
    }
}

struct WidgetsSettingsPage: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @Environment(SettingsNavigationModel.self) private var navigation
    @State private var query = ""
    @State private var surface = "all"
    @State private var entries: [ShellWidgetLibraryEntry] = []
    @State private var editError: String?
    @State private var widgetStates: [String: String] = [:]
    @State private var widgetErrors: [String: String] = [:]
    @State private var monitors = Monitor.current()

    private var configuration: ShellConfigurationCoordinator {
        controller.workspaceBarManager.shellConfiguration
    }

    private var results: [ShellWidgetLibraryEntry] {
        entries.filter { entry in
            (surface == "all" || (surface == "bar" ? entry.bar : entry.island))
                && (query.isEmpty || ShellBarLayout.title(of: entry.name).localizedStandardContains(query)
                    || ShellWidgetSettingsModel.description(entry.name).localizedStandardContains(query))
        }
    }

    var body: some View {
        let vertical = ShellBarLayout.vertical(settings.workspaceBar, on: monitors)
        Form {
            Section {
                TextField("Search widgets", text: $query).textFieldStyle(.roundedBorder)
                Picker("Surface", selection: $surface) {
                    Text("All Widgets").tag("all")
                    Text("Bar").tag("bar")
                    Text("Island").tag("island")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let metadataError = configuration.metadataError {
                Section { Label(metadataError, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section("Widget Library") {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(results) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                ShellBarLayout.title(of: entry.name),
                                systemImage: configuration.catalog?.descriptors[entry.name]?.icon ?? "puzzlepiece.extension"
                            )
                            .fontWeight(.medium)
                            Spacer()
                            Text(applicability(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(ShellWidgetSettingsModel.description(entry.name)).font(.caption)
                            .foregroundStyle(.secondary)
                        if let state = widgetStates[entry.name] {
                            Label(
                                ShellWidgetSettingsModel.title(state),
                                systemImage: state == "failed" ? "exclamationmark.triangle" : "checkmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(state == "failed" ? Color.red : Color.secondary)
                        }
                        if let error = widgetErrors[entry.name] { Text(error).font(.caption).foregroundStyle(.red) }
                        HStack {
                            if entry.bar {
                                if let lane = configuration.config.barLane(of: entry.name) {
                                    Text(
                                        "On Bar · \(ShellBarLayout.side(lane, vertical: vertical))"
                                    )
                                    .font(.caption).foregroundStyle(.secondary)
                                    Button("Remove from Bar") {
                                        perform { try await configuration.editBar { $0.remove(entry.name) } }
                                    }
                                } else {
                                    Menu("Add to Bar") {
                                        ForEach(ShellLane.allCases, id: \.self) { lane in
                                            Button(ShellBarLayout.side(
                                                lane,
                                                vertical: vertical
                                            )) {
                                                perform {
                                                    try await configuration.editBar { $0.add(entry.name, to: lane) }
                                                }
                                            }
                                        }
                                    }
                                }
                                Button("Options…") {
                                    navigation.request(SettingsRoute(section: .styles, itemID: entry.name))
                                }
                            }
                            if entry.island {
                                Button("Add to Island") {
                                    perform {
                                        _ = try await configuration.island(.add(widget: entry.name, options: [:]))
                                    }
                                }
                                .disabled(configuration.config.island?.root == "focus-ribbon" || configuration.catalog?
                                    .settings == nil)
                            }
                        }
                        .controlSize(.small)
                        let instances = configuration.config.island?.components.filter { $0.widget == entry.name } ?? []
                        ForEach(instances, id: \.id) { component in
                            Button("Island Instance: \(component.id)") {
                                navigation.request(SettingsRoute(
                                    section: .island,
                                    tab: "widgets",
                                    itemID: component.id
                                ))
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            ShellDrawerSettingsSection(
                configuration: configuration,
                widgets: entries.filter(\.bar).map(\.name),
                settings: settings
            )
        }
        .formStyle(.grouped)
        .task {
            do { try await configuration.ensureLoaded() } catch { editError = error.localizedDescription }
            reload()
        }
        .onChange(of: configuration.config) { _, _ in reload() }
        .onChange(of: configuration.barLayout) { _, _ in reload() }
        .onChange(of: configuration.catalog) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .shellWidgetsDidChange)) { _ in reloadStatus() }
        .onReceive(NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification))
        { _ in
            monitors = Monitor.current()
        }
        .shellSettingsError($editError)
    }

    private func applicability(_ entry: ShellWidgetLibraryEntry) -> String {
        entry.bar && entry.island ? String(localized: "Bar and Island") : entry
            .bar ? String(localized: "Bar") : String(localized: "Island")
    }

    private func reload() {
        var available: [String: ShellWidgetLibraryEntry] = [:]
        for widget in configuration.availableWidgets where widget != configuration.config.island?.root {
            available[widget] = ShellWidgetLibraryEntry(name: widget, bar: true)
        }
        for entry in configuration.catalog?.entries ?? [] where entry.descriptor != nil {
            var value = available[entry.widget] ?? ShellWidgetLibraryEntry(name: entry.widget)
            value.island = true
            available[entry.widget] = value
        }
        entries = available.values.sorted {
            ShellBarLayout.title(of: $0.name)
                .localizedStandardCompare(ShellBarLayout.title(of: $1.name)) == .orderedAscending
        }
        reloadStatus()
    }

    private func reloadStatus() {
        let report = controller.workspaceBarManager.shellHost?.widgetReport
        widgetStates = Dictionary(uniqueKeysWithValues: (report?.widgets ?? []).map { ($0.name, $0.state) })
        widgetErrors = Dictionary(uniqueKeysWithValues: (report?.widgets ?? []).compactMap { widget in
            widget.error.map { (widget.name, $0) }
        })
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation() } catch { editError = error.localizedDescription } }
    }
}
