// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDesktopLanes: View {
    let editor: ShellDesktopEditor
    @State private var adding = false
    @State private var expanded = true
    @State private var confirmingReset = false

    var body: some View {
        Section {
            DisclosureGroup("Widget Lanes", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ShellLane.allCases, id: \.self) { lane in
                        ShellDesktopLaneWell(editor: editor, lane: lane)
                    }
                }
            }
            HStack {
                Button("Add Widget…") { adding = true }
                    .disabled(editor.layout?.addable.isEmpty != false)
                Button("Use Style Layout…") { confirmingReset = true }
                    .disabled(editor.layout?.customized != true)
                Spacer(minLength: 0)
            }
        } header: {
            Text("Bar Widgets")
        } footer: {
            Text("Shared by all displays in this style.")
        }
        .sheet(isPresented: $adding) {
            ShellDesktopAddWidgetSheet(editor: editor) { adding = false }
        }
        .confirmationDialog("Use this style’s widget layout?", isPresented: $confirmingReset) {
            Button("Use Style Layout", role: .destructive) { editor.resetLayout() }
        } message: { Text("Your widget options are kept.") }
    }
}

struct ShellDesktopAddWidgetSheet: View {
    let editor: ShellDesktopEditor
    let dismiss: () -> Void
    @State private var query: String

    init(editor: ShellDesktopEditor, query: String = "", dismiss: @escaping () -> Void) {
        self.editor = editor
        self.dismiss = dismiss
        _query = State(initialValue: query)
    }

    private var widgets: [ShellBarLayout.Widget] {
        (editor.layout?.addable ?? []).filter {
            query.isEmpty || ShellBarLayout.title(of: $0.name).localizedCaseInsensitiveContains(query)
                || ShellWidgetSettingsModel.description($0.name).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Widget").font(.title2.bold())
            TextField("Search widgets", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(widgets) { widget in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ShellBarLayout.title(of: widget.name))
                                Text(ShellWidgetSettingsModel.description(widget.name))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu("Add to") {
                                ForEach(ShellLane.allCases, id: \.self) { lane in
                                    Button(ShellBarLayout.side(lane, vertical: orientation)) {
                                        editor.add(widget.name, to: lane)
                                        dismiss()
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
            }
            HStack { Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 380, height: 400)
    }

    private var orientation: Bool? {
        ShellBarLayout.vertical(editor.barSettings, on: editor.monitors)
    }
}

private struct ShellDesktopLaneWell: View {
    let editor: ShellDesktopEditor
    let lane: ShellLane
    @State private var insertion: Int?
    @State private var frames: [String: CGRect] = [:]

    private var names: [String] {
        editor.layout?.names(in: lane) ?? []
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(ShellBarLayout.side(lane, vertical: ShellBarLayout.vertical(editor.barSettings, on: editor.monitors)))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 58, height: 30, alignment: .leading)
            if names.isEmpty {
                Text("Drop widget here").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else {
                ShellDesktopLaneLayout {
                    ForEach(names, id: \.self) { name in
                        chip(name)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(lane)) } action: {
                                frames[name] = $0
                            }
                    }
                }
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            if let insertion, let marker = marker(at: insertion) {
                Rectangle().fill(Color.accentColor).frame(width: 3, height: 30)
                    .offset(x: marker.x, y: marker.y)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: lane)
        .dropDestination(for: String.self) { items, session in
            guard session.localSession != nil, let item = items.first else { return }
            _ = editor.drop(item, into: lane, at: insertionIndex(at: session.location))
            insertion = nil
        }
        .dropConfiguration { .init(operation: $0.localSession == nil ? .forbidden : .move) }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering,
                 .active:
                if session.localSession != nil { insertion = insertionIndex(at: session.location) }
            default: insertion = nil
            }
        }
    }

    private func insertionIndex(at point: CGPoint) -> Int {
        let ordered = names.compactMap { frames[$0] }
        guard ordered.count == names.count else { return names.count }
        return ShellDesktopLaneLayout.insertion(at: point, frames: ordered)
    }

    private func marker(at index: Int) -> CGPoint? {
        if names.isEmpty { return CGPoint(x: 71, y: 8) }
        let ordered = names.compactMap { frames[$0] }
        guard ordered.count == names.count else { return nil }
        if index < ordered.count { return CGPoint(x: ordered[index].minX - 3, y: ordered[index].minY) }
        return ordered.last.map { CGPoint(x: $0.maxX + 2, y: $0.minY) }
    }

    private func chip(_ name: String) -> some View {
        Button { Task { await editor.selectWidget(name) } } label: {
            HStack(spacing: 4) {
                if editor.snapshot?.config.widget(name) == nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Text(ShellBarLayout.title(of: name)).lineLimit(1).truncationMode(.tail)
            }
            .font(.caption).padding(.horizontal, 8).frame(height: 30)
            .background(
                editor.selectedWidget == name ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                in: .rect(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .help(ShellBarLayout.title(of: name))
        .draggable(editor.dragPayload(for: name))
        .dragConfiguration(.init(
            operationsWithinApp: .init(allowCopy: false, allowMove: true),
            operationsOutsideApp: .init(allowCopy: false)
        ))
        .contextMenu {
            Button("Move Earlier") { editor.shift(name, by: -1) }
                .disabled(names.first == name)
            Button("Move Later") { editor.shift(name, by: 1) }.disabled(names.last == name)
            Menu("Move to") {
                ForEach(ShellLane.allCases.filter { $0 != lane }, id: \.self) { target in
                    Button(ShellBarLayout.side(target, vertical: ShellBarLayout.vertical(
                        editor.barSettings,
                        on: editor.monitors
                    ))) {
                        editor.move(name, to: target)
                    }
                }
            }
            Button("Remove", role: .destructive) { editor.remove(name) }
        }
    }
}
