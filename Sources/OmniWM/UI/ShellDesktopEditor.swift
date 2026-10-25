// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import Observation

@MainActor
@Observable
final class ShellDesktopEditor {
    struct StyleCard: Identifiable, Equatable {
        let name: String
        let title: String
        let summary: String
        let active: Bool

        var id: String {
            name
        }
    }

    enum Scope: Equatable {
        case active
        case previewing(active: String)
    }

    enum Transition: Equatable {
        case style(String)
        case widget(String?)
        case useStyle
        case leave(SettingsRoute?)
    }

    enum Resolution {
        case save
        case discard
        case cancel
    }

    let configuration: ShellConfigurationCoordinator
    let settings: SettingsStore
    let writes = ShellSettingsWriteQueue()
    @ObservationIgnored let controller: WMController
    @ObservationIgnored let dragToken = UUID().uuidString
    @ObservationIgnored private weak var navigation: SettingsNavigationModel?

    private(set) var selectedStyle: String
    private(set) var snapshot: ShellEditorSnapshot?
    private(set) var barSettings = WorkspaceBarSettings()
    private(set) var monitors: [Monitor] = Monitor.current()
    private(set) var selectedMonitor: Monitor.ID?
    private(set) var selectedWidget: String?
    private(set) var drafts: [ShellEditorDraft.Key: ShellEditorDraft] = [:]
    private(set) var pendingTransition: Transition?
    var problem: String?

    init(configuration: ShellConfigurationCoordinator, settings: SettingsStore, controller: WMController) {
        self.configuration = configuration
        self.settings = settings
        self.controller = controller
        selectedStyle = configuration.config.profile
    }

    var activeStyle: String {
        configuration.config.profile
    }

    var scope: Scope {
        selectedStyle == activeStyle ? .active : .previewing(active: activeStyle)
    }

    var cards: [StyleCard] {
        configuration.profiles.map {
            StyleCard(
                name: $0, title: ShellStyleText.title($0), summary: ShellStyleText.summary($0),
                active: $0 == activeStyle
            )
        }
    }

    var monitor: Monitor? {
        monitors.first { $0.id == selectedMonitor }
    }

    var hasUnsavedChanges: Bool {
        drafts.values.contains(where: \.dirty) || !writes.failures.isEmpty
    }

    func reload() async {
        let style = selectedStyle
        do {
            try await configuration.ensureLoaded()
            let next = try await configuration.editorSnapshot(profile: style)
            guard style == selectedStyle else { return }
            snapshot = next
            barSettings = settings.workspaceBar.isolated(profileOverride: next.config.barOverride)
            if let widget = selectedWidget, next.layout.source(of: widget) == nil, next.layout.lane(of: widget) == nil {
                selectedWidget = nil
            }
            await refreshCleanDrafts()
        } catch is CancellationError {
        } catch {
            guard style == selectedStyle else { return }
            problem = error.localizedDescription
        }
    }

    func refreshMonitors() {
        monitors = Monitor.current()
        if !monitors.contains(where: { $0.id == selectedMonitor }) { selectedMonitor = nil }
    }

    func selectMonitor(_ id: Monitor.ID?) {
        selectedMonitor = monitors.contains { $0.id == id } ? id : nil
    }

    @discardableResult
    func selectStyle(_ name: String) async -> Bool {
        guard name != selectedStyle else { return true }
        return await request(.style(name))
    }

    @discardableResult
    func selectWidget(_ name: String?) async -> Bool {
        guard name != selectedWidget else { return true }
        return await request(.widget(name))
    }

    func open(_ route: SettingsRoute) async {
        guard route.section == .styles else { return }
        if let widget = route.itemID { await selectWidget(widget) } else if route.tab != nil { await selectWidget(nil) }
    }

    @discardableResult
    func useStyle() async -> Bool {
        await request(.useStyle)
    }

    func request(_ transition: Transition) async -> Bool {
        guard !hasUnsavedChanges else {
            pendingTransition = transition
            if !writes.failures.isEmpty {
                problem = String(localized: "A change could not be saved. Retry or discard it first.")
            }
            return false
        }
        return await complete(transition)
    }

    func resolve(_ resolution: Resolution) async {
        guard let transition = pendingTransition else { return }
        switch resolution {
        case .cancel:
            if case .leave = transition { navigation?.cancelNavigation() }
            pendingTransition = nil
            if case .widget = transition { syncRoute() }
        case .discard:
            drafts.removeAll()
            for target in writes.failures.keys {
                writes.discard(target)
            }
            pendingTransition = nil
            _ = await complete(transition)
        case .save:
            pendingTransition = nil
            for target in writes.failures.keys {
                writes.retry(target)
            }
            guard await saveDrafts(), await writes.drain() else {
                problem = String(localized: "A change could not be saved. Retry or discard it first.")
                return
            }
            _ = await complete(transition)
        }
    }

    func setDraft(_ draft: ShellEditorDraft) {
        drafts[draft.key] = draft
    }

    func clearDraft(_ key: ShellEditorDraft.Key) {
        drafts[key] = nil
    }

    func focus(_ widget: String) {
        guard drafts.values.allSatisfy({ !$0.dirty || $0.key.widget == widget }) else { return }
        selectedWidget = widget
        syncRoute()
    }

    private func syncRoute() {
        guard navigation?.section == .styles else { return }
        navigation?.reflect(SettingsRoute(section: .styles, itemID: selectedWidget))
    }

    func attach(_ navigation: SettingsNavigationModel) {
        self.navigation = navigation
        navigation.leaveGuard = { [weak self] route in
            guard let self else { return false }
            if hasUnsavedChanges {
                pendingTransition = .leave(route)
            } else {
                Task { _ = await complete(.leave(route)) }
            }
            return true
        }
    }

    func detach() {
        if navigation?.leaveGuard != nil { navigation?.leaveGuard = nil }
    }

    private func complete(_ transition: Transition) async -> Bool {
        if case .widget = transition {} else {
            guard await writes.drain() else {
                problem = String(localized: "A change could not be saved. Retry or discard it first.")
                return false
            }
        }
        switch transition {
        case let .widget(name):
            drafts.removeAll()
            selectedWidget = name
            syncRoute()
        case let .style(name):
            drafts.removeAll()
            selectedWidget = nil
            selectedStyle = name
            snapshot = nil
            await reload()
        case .useStyle:
            do { _ = try await configuration.selectProfile(selectedStyle) } catch {
                problem = error.localizedDescription
                return false
            }
        case let .leave(route):
            drafts.removeAll()
            navigation?.proceed(to: route)
        }
        return true
    }
}
