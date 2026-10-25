// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellIslandComponentList: View {
    let editor: ShellDesktopEditor
    @State private var adding = false
    @State private var insertion: Int?
    @State private var frames: [String: CGRect] = [:]

    private var components: [ShellComponentInstance] {
        editor.islandComponents
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(components, id: \.id) { component in
                    row(component)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("island-components")) } action: {
                            frames[component.id] = $0
                        }
                }
                if components.isEmpty {
                    Text("No widgets added.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if let insertion, let y = marker(at: insertion) {
                    Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: y)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "island-components")
            .dropDestination(for: String.self) { items, session in
                guard session.localSession != nil, let item = items.first else { return }
                _ = editor.dropComponent(item, at: insertionIndex(at: session.location))
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
            Button("Add Widget…") { adding = true }
        } header: {
            Text("Island Widgets")
        } footer: {
            Text("Order, placement and options are saved for this style.")
        }
        .shellWidgetLibrary(editor: editor, target: .island, isPresented: $adding)
    }

    private func insertionIndex(at point: CGPoint) -> Int {
        for (index, component) in components.enumerated() {
            guard let frame = frames[component.id] else { return components.count }
            if point.y < frame.midY { return index }
        }
        return components.count
    }

    private func marker(at index: Int) -> CGFloat? {
        if components.isEmpty { return 0 }
        if index < components.count { return frames[components[index].id].map { $0.minY - 3 } }
        return components.last.flatMap { frames[$0.id] }.map { $0.maxY + 3 }
    }

    private func row(_ component: ShellComponentInstance) -> some View {
        HStack(spacing: 8) {
            Button { Task { await editor.selectComponent(component.id) } } label: {
                Label(
                    editor.componentTitle(component.id),
                    systemImage: editor.componentDescriptor(component.id)?.icon ?? "puzzlepiece.extension"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("Enabled", isOn: Binding(
                get: { component.enabled },
                set: { editor.setComponentEnabled(component.id, $0) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(8)
        .background(
            editor.selectedComponent == component.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
            in: .rect(cornerRadius: 6)
        )
        .draggable(editor.componentDragPayload(for: component.id))
        .dragConfiguration(.init(
            operationsWithinApp: .init(allowCopy: false, allowMove: true),
            operationsOutsideApp: .init(allowCopy: false)
        ))
        .contextMenu {
            Button("Move Earlier") { editor.shiftComponent(component.id, by: -1) }
                .disabled(components.first?.id == component.id)
            Button("Move Later") { editor.shiftComponent(component.id, by: 1) }
                .disabled(components.last?.id == component.id)
            Button("Remove", role: .destructive) { editor.removeComponent(component.id) }
        }
    }
}
