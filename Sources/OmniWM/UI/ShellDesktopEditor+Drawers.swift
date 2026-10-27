// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension ShellDesktopEditor {
    enum DrawerShortcut: Equatable {
        case available
        case previewing
        case spaces
        case needsHost
    }

    var drawers: [ShellDrawerConfig] {
        snapshot?.config.drawers ?? []
    }

    var drawer: ShellDrawerConfig? {
        selectedDrawer.flatMap(drawer)
    }

    var drawersLoad: Bool {
        barEnabled || islandEnabled
    }

    var drawerPreviewConfig: ShellConfig? {
        guard var config = snapshot?.config else { return nil }
        config.drawers = config.drawers.map {
            var drawer = ShellDrawerConfig(id: $0.id, edge: .right, widgets: $0.widgets, hover: false)
            drawer.chrome = $0.chrome
            return drawer
        }
        return config
    }

    func drawer(_ id: String) -> ShellDrawerConfig? {
        drawers.first { $0.id == id }
    }

    func isStyleDrawer(_ id: String) -> Bool {
        snapshot?.config.styleDrawers.contains(id) == true
    }

    func drawerEditable(_ id: String) -> Bool {
        ShellDrawerName.editable(id)
    }

    func drawerMembers(_ id: String) -> [String] {
        Self.unique(drawer(id)?.widgets ?? [])
    }

    func drawerCandidates(_ id: String?) -> [String] {
        let members = id.map(drawerMembers) ?? []
        return (layout?.widgets.map(\.name) ?? []).filter { !members.contains($0) }
    }

    func drawerNameProblem(_ name: String) -> String? {
        ShellDrawerName.problem(
            name, drawers: drawers.map(\.id) + (snapshot?.config.styleDrawers ?? []),
            widgets: snapshot.map { ShellDrawerName.widgets($0.layout, config: $0.config) } ?? []
        )
    }

    func drawerShortcut(_ id: String) -> DrawerShortcut {
        if id.contains(where: \.isWhitespace) { return .spaces }
        let action = ActionCatalog.shellTogglePrefix + id
        if settings.hotkeyBindings.contains(where: { $0.id == action }) { return .available }
        return scope == .active ? .needsHost : .previewing
    }

    func drawerTarget(_ id: String, key: String) -> ShellSettingsWriteQueue.Target {
        barTarget(key, table: "drawer." + id)
    }

    func panelRequest(_ names: [String]) -> ShellSettingsPreview.PanelRequest? {
        snapshot.map {
            .init(names: names, config: $0.config, sourceGeneration: configuration.sourceGeneration)
        }
    }

    @discardableResult
    func addDrawer(name: String, edge: ShellDrawerConfig.Edge, widget: String) async -> Bool {
        let profile = selectedStyle
        let id = ShellDrawerName.normalized(name)
        guard drawerNameProblem(id) == nil else { return false }
        guard await run({ [configuration] in
            try await configuration.addDrawer(id, edge: edge, widget: widget, profile: profile)
        }) else { return false }
        focusDrawer(id)
        return true
    }

    @discardableResult
    func deleteDrawer(_ id: String) async -> Bool {
        let profile = selectedStyle
        let deleted = await run { [configuration] in try await configuration.deleteDrawer(id, profile: profile) }
        if deleted { syncRoute() }
        return deleted
    }

    func resetDrawer(_ id: String) {
        guard drawerEditable(id), isStyleDrawer(id) else { return }
        reset(table: "drawer." + id)
    }

    func setDrawer(_ id: String, key: String, value: (some Encodable & Sendable)?, continuous: Bool = false) {
        guard drawerEditable(id) else { return }
        set(value, key: key, table: "drawer." + id, continuous: continuous)
    }

    @discardableResult
    func addDrawerWidget(_ widget: String, to id: String) async -> Bool {
        await editMembers(of: id, profile: selectedStyle) { if !$0.contains(widget) { $0.append(widget) } }
    }

    func removeDrawerWidget(_ widget: String, from id: String) {
        let profile = selectedStyle
        Task { await editMembers(of: id, profile: profile) { $0.removeAll { $0 == widget } } }
    }

    func moveDrawerWidget(_ widget: String, in id: String, to index: Int) {
        let profile = selectedStyle
        Task {
            await editMembers(of: id, profile: profile) { members in
                members = Self.unique(members)
                guard let position = members.firstIndex(of: widget) else { return }
                members.remove(at: position)
                members.insert(widget, at: min(max(0, index), members.count))
            }
        }
    }

    func shiftDrawerWidget(_ widget: String, in id: String, by delta: Int) {
        let members = drawerMembers(id)
        guard let index = members.firstIndex(of: widget), members.indices.contains(index + delta) else { return }
        moveDrawerWidget(widget, in: id, to: index + delta)
    }

    func drawerWidgetPayload(_ widget: String, in id: String) -> String {
        ["omniwm-drawer", dragToken, selectedStyle, id, widget].joined(separator: "\n")
    }

    @discardableResult
    func dropDrawerWidget(_ payload: String, into drawer: String, at index: Int) -> Bool {
        let parts = payload.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, parts[0] == "omniwm-drawer", parts[1] == dragToken, parts[2] == selectedStyle,
              parts[3] == drawer, drawerEditable(drawer), let position = drawerMembers(drawer).firstIndex(of: parts[4])
        else { return false }
        let count = drawerMembers(drawer).count
        let target = min(max(0, position < index ? index - 1 : index), count - 1)
        guard target != position else { return false }
        moveDrawerWidget(parts[4], in: drawer, to: target)
        return true
    }

    private func editMembers(
        of id: String, profile: String, _ change: @escaping @Sendable (inout [String]) -> Void
    ) async -> Bool {
        guard drawerEditable(id) else { return false }
        return await run { [configuration] in try await configuration.editDrawerWidgets(id, profile: profile, change) }
    }

    private nonisolated static func unique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }
}
