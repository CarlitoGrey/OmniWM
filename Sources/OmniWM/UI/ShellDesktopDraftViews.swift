// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDesktopTextDraft: View {
    let editor: ShellDesktopEditor
    let widget: String
    let option: String
    let title: String
    let multiline: Bool
    let maximum: Int

    private var key: ShellEditorDraft.Key {
        .init(widget: widget, option: option)
    }

    private var text: String {
        if let draft = editor.draft(key) {
            switch draft.value {
            case let .text(text): return text
            case let .lines(lines): return lines.joined(separator: "\n")
            default: break
            }
        }
        let value: ShellComponentValue?
        if let id = key.component {
            value = editor.component(id)?.options[option] ?? editor.componentDescriptor(id)?.options[option]?
                .defaultValue
        } else if key.islandRoot != nil {
            value = editor.islandRootValues[option] ?? editor.islandRootOptions[option]?.defaultValue
        } else {
            value = editor.values(for: widget)[option] ?? editor.schema(for: widget)?.options[option]?.defaultValue
        }
        switch value {
        case let .string(text)?: return text
        case let .strings(lines)?: return lines.joined(separator: "\n")
        default: return ""
        }
    }

    private var valid: Bool {
        multiline ? text.components(separatedBy: "\n").allSatisfy { $0.count <= maximum } : text.count <= maximum
    }

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 8) {
                TextField(title, text: Binding(get: { text }, set: update), axis: multiline ? .vertical : .horizontal)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .lineLimit(multiline ? 3 ... 8 : 1 ... 1)
                    .disabled(editor.draft(key)?.saving == true)
                    .onSubmit { Task { await editor.saveDraft(key) } }
                    .onExitCommand { editor.cancelDraft(key) }
                if !valid {
                    Text(multiline
                        ? String(localized: "Use at most \(maximum) characters per line.")
                        : String(localized: "Use at most \(maximum) characters."))
                        .font(.caption).foregroundStyle(.red)
                }
                ShellDesktopDraftActions(editor: editor, key: key, valid: valid)
            }
            .frame(minWidth: 140, maxWidth: 300)
        }
        .task(id: key) { begin() }
    }

    private func update(_ text: String) {
        begin()
        editor.updateDraft(key, multiline ? .lines(text.components(separatedBy: "\n")) : .text(text))
    }

    private func begin() {
        if let id = key.component { editor.beginComponentTextDraft(id, key: option) }
        else if key.islandRoot != nil { editor.beginIslandRootTextDraft(key: option) }
        else { editor.beginTextDraft(widget: widget, key: option) }
    }
}

struct ShellDesktopClocksDraft: View {
    let editor: ShellDesktopEditor
    private let key = ShellEditorDraft.Key(widget: "world-clock", option: "zones")

    private var clocks: [ShellWorldClockEntry] {
        if case let .clocks(clocks)? = editor.draft(key)?.value { clocks } else { [] }
    }

    var body: some View {
        Section("World Clock Locations") {
            if editor.draft(key) == nil {
                ProgressView().controlSize(.small)
                    .task(id: editor.snapshot?.config.profile) { editor.beginClocksDraft() }
            } else {
                clockRows
                HStack {
                    Button("Add Clock", systemImage: "plus") {
                        update(clocks + [ShellWorldClockEntry(label: "New York", zone: "America/New_York")])
                    }
                    .disabled(clocks.count >= 64 || editor.draft(key)?.saving == true)
                    Spacer()
                    ShellDesktopDraftActions(
                        editor: editor,
                        key: key,
                        valid: ShellWidgetSettingsModel.validClocks(clocks)
                    )
                }
                SettingsCaption(
                    localized: "The order here is the order in the bar and popup. Locations are saved for the selected style."
                )
            }
        }
        .onExitCommand { editor.cancelDraft(key) }
    }

    private var clockRows: some View {
        ForEach(clocks) { clock in
            VStack(alignment: .leading, spacing: 8) {
                TextField("Label", text: clockBinding(clock.id, \.label)).textFieldStyle(.roundedBorder)
                Picker("Time Zone", selection: clockBinding(clock.id, \.zone)) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { zone in
                        Text(zone.replacingOccurrences(of: "_", with: " ")).tag(zone)
                    }
                }
                Button("Remove Clock", role: .destructive) {
                    update(clocks.filter { $0.id != clock.id })
                }
                .disabled(clocks.count <= 1)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
            .disabled(editor.draft(key)?.saving == true)
        }
    }

    private func clockBinding(_ id: UUID, _ path: WritableKeyPath<ShellWorldClockEntry, String>) -> Binding<String> {
        Binding(
            get: { clocks.first { $0.id == id }?[keyPath: path] ?? "" },
            set: { value in
                var next = clocks
                guard let index = next.firstIndex(where: { $0.id == id }) else { return }
                next[index][keyPath: path] = value
                update(next)
            }
        )
    }

    private func update(_ clocks: [ShellWorldClockEntry]) {
        editor.beginClocksDraft()
        editor.updateDraft(key, .clocks(clocks))
    }
}

struct ShellDesktopWeatherDraft: View {
    let editor: ShellDesktopEditor

    private var weather: ShellEditorDraft.Weather? {
        guard case let .weather(weather)? = editor.draft(.weather)?.value else { return nil }
        return weather
    }

    var body: some View {
        Section("Weather Location") {
            SettingsCaption(localized: "Shared by all styles")
            if let weather {
                weatherFields(weather)
                    .disabled(editor.draft(.weather)?.saving == true)
                ShellDesktopDraftActions(editor: editor, key: .weather, valid: weather.valid)
            } else {
                ProgressView().controlSize(.small)
                    .task { await editor.beginWeatherDraft() }
            }
        }
        .onExitCommand { editor.cancelDraft(.weather) }
    }

    @ViewBuilder private func weatherFields(_ value: ShellEditorDraft.Weather) -> some View {
        Picker("Location", selection: binding(\.coordinates, fallback: value.coordinates)) {
            Text("City").tag(false)
            Text("Coordinates").tag(true)
        }
        if value.coordinates {
            TextField("Latitude", value: binding(\.latitude, fallback: value.latitude), format: .number)
            TextField("Longitude", value: binding(\.longitude, fallback: value.longitude), format: .number)
            SettingsCaption(localized: "Latitude −90 to 90; longitude −180 to 180.")
        } else {
            TextField("City", text: binding(\.city, fallback: value.city)).textFieldStyle(.roundedBorder)
        }
        Picker("Temperature", selection: binding(\.fahrenheit, fallback: value.fahrenheit)) {
            Text("Celsius").tag(false)
            Text("Fahrenheit").tag(true)
        }
        SettingsSliderRow(
            label: String(localized: "Refresh Interval"),
            value: binding(\.refreshMinutes, fallback: value.refreshMinutes),
            range: 5 ... 1440, step: 5,
            valueText: String(localized: "\(Int(value.refreshMinutes)) min")
        )
    }

    private func binding<Value>(
        _ path: WritableKeyPath<ShellEditorDraft.Weather, Value>, fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { weather?[keyPath: path] ?? fallback },
            set: { value in
                guard var next = weather else { return }
                next[keyPath: path] = value
                editor.updateDraft(.weather, .weather(next))
            }
        )
    }
}

private struct ShellDesktopDraftActions: View {
    let editor: ShellDesktopEditor
    let key: ShellEditorDraft.Key
    let valid: Bool

    var body: some View {
        if let draft = editor.draft(key), draft.dirty {
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Button("Cancel") { editor.cancelDraft(key) }
                    Button("Save") { Task { await editor.saveDraft(key) } }
                        .disabled(!valid)
                    if draft.saving { ProgressView().controlSize(.small) }
                }
                .disabled(draft.saving)
                if let error = draft.error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
    }
}
