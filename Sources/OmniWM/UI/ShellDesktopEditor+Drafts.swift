// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension ShellDesktopEditor {
    func draft(_ key: ShellEditorDraft.Key) -> ShellEditorDraft? {
        drafts[key]
    }

    func beginClocksDraft() {
        let key = ShellEditorDraft.Key(widget: "world-clock", option: "zones")
        guard drafts[key] == nil, let snapshot else { return }
        let clocks = ShellEditorDraft.Value.clocks(ShellWidgetSettingsModel.clocks(config: snapshot.config))
        setDraft(ShellEditorDraft(key: key, profile: selectedStyle, original: clocks, value: clocks))
    }

    func beginTextDraft(widget: String, key option: String) {
        let key = ShellEditorDraft.Key(widget: widget, option: option)
        guard drafts[key] == nil, let value = textValue(widget: widget, option: option) else { return }
        setDraft(ShellEditorDraft(key: key, profile: selectedStyle, original: value, value: value))
    }

    private func textValue(widget: String, option: String) -> ShellEditorDraft.Value? {
        guard let setting = schema(for: widget)?.options[option] else { return nil }
        return switch values(for: widget)[option] ?? setting.defaultValue {
        case let .strings(lines)?: .lines(lines)
        case let .string(text)?: .text(text)
        case _ where setting.kind == .strings: .lines([])
        default: .text("")
        }
    }

    func beginWeatherDraft() async {
        guard drafts[.weather] == nil else { return }
        do {
            let weather = ShellEditorDraft.Value.weather(.init(try await configuration.sharedWeather()))
            guard drafts[.weather] == nil else { return }
            setDraft(ShellEditorDraft(key: .weather, profile: selectedStyle, original: weather, value: weather))
        } catch { problem = error.localizedDescription }
    }

    func refreshCleanDrafts() async {
        for (key, draft) in drafts where !draft.dirty && !draft.saving {
            let fresh: ShellEditorDraft.Value? = switch draft.value {
            case .clocks: snapshot.map { .clocks(ShellWidgetSettingsModel.clocks(config: $0.config)) }
            case .weather: await (try? configuration.sharedWeather()).map { .weather(.init($0)) }
            case .text,
                 .lines: textValue(widget: key.widget, option: key.option)
            }
            guard let fresh, !fresh.matches(draft.original), let current = drafts[key], current.id == draft.id,
                  !current.dirty, !current.saving
            else { continue }
            var updated = current
            updated.original = fresh
            updated.value = fresh
            setDraft(updated)
        }
    }

    func updateDraft(_ key: ShellEditorDraft.Key, _ value: ShellEditorDraft.Value) {
        guard var draft = drafts[key], !draft.saving else { return }
        draft.value = value
        draft.error = nil
        setDraft(draft)
    }

    func cancelDraft(_ key: ShellEditorDraft.Key) {
        guard drafts[key]?.saving == false else { return }
        clearDraft(key)
    }

    @discardableResult
    func saveDraft(_ key: ShellEditorDraft.Key) async -> Bool {
        guard var draft = drafts[key], !draft.saving else { return false }
        guard draft.dirty else {
            clearDraft(key)
            return true
        }
        guard draft.value.valid, fits(draft) else {
            draft.error = String(localized: "Check the highlighted values before saving.")
            setDraft(draft)
            return false
        }
        draft.saving = true
        draft.error = nil
        setDraft(draft)
        do {
            guard await writes.drain() else {
                draft.saving = false
                draft.error = String(localized: "A change could not be saved. Retry or discard it first.")
                setDraft(draft)
                return false
            }
            try await persist(draft)
            await reload()
            if drafts[key]?.id == draft.id { clearDraft(key) }
            return true
        } catch {
            if drafts[key]?.id == draft.id {
                draft.saving = false
                draft.error = error.localizedDescription
                setDraft(draft)
            }
            return false
        }
    }

    func saveDrafts() async -> Bool {
        for key in drafts.keys.sorted(by: { ($0.widget, $0.option) < ($1.widget, $1.option) }) {
            guard await saveDraft(key) else { return false }
        }
        return true
    }

    private func persist(_ draft: ShellEditorDraft) async throws {
        let widget = draft.key.widget
        let option = draft.key.option
        switch draft.value {
        case let .clocks(clocks):
            try await configuration.setWidgetOptions(clocks, widget: widget, key: option, profile: draft.profile)
        case let .weather(weather):
            try await configuration.setWeather(weather.stored)
        case let .text(text):
            try await configuration.setWidgetValue(.string(text), widget: widget, key: option, profile: draft.profile)
        case let .lines(lines):
            try await configuration.setWidgetValue(
                .strings(lines.filter { !$0.isEmpty }), widget: widget, key: option, profile: draft.profile
            )
        }
    }

    private func fits(_ draft: ShellEditorDraft) -> Bool {
        guard let limit = schema(for: draft.key.widget)?.options[draft.key.option]?.maxLength else { return true }
        return switch draft.value {
        case let .text(text): text.count <= limit
        case let .lines(lines): lines.allSatisfy { $0.count <= limit }
        case .clocks,
             .weather: true
        }
    }
}
