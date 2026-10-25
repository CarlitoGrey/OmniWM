// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDrawerMemberList: View {
    let editor: ShellDesktopEditor
    let drawer: String
    @State private var adding = false
    @State private var insertion: Int?
    @State private var frames: [String: CGRect] = [:]
    @State private var panels = ShellDrawerPanels()

    private var members: [String] {
        editor.drawerMembers(drawer)
    }

    var body: some View {
        let members = self.members
        let request = editor.panelRequest(members.sorted())
        let values = panels.values(for: request)
        let load = ShellDrawerPanels.Load(request: request, attempt: panels.attempt)
        Section("Widgets") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(members, id: \.self) { widget in
                    row(widget, panel: values[widget])
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("drawer-members")) } action: {
                            frames[widget] = $0
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if let insertion, let y = marker(at: insertion) {
                    Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: y)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "drawer-members")
            .dropDestination(for: String.self) { items, session in
                guard session.localSession != nil, let payload = items.first else { return }
                _ = editor.dropDrawerWidget(payload, into: drawer, at: insertionIndex(at: session.location))
                insertion = nil
            }
            .dropConfiguration { .init(operation: $0.localSession == nil ? .forbidden : .move) }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering,
                     .active:
                    if session.localSession != nil { insertion = insertionIndex(at: session.location) }
                default:
                    insertion = nil
                }
            }
            ShellDrawerPanelStatus(panels: panels, request: request)
            Button("Add Widget…") { adding = true }
                .disabled(editor.drawerCandidates(drawer).isEmpty)
        }
        .task(id: load) {
            await panels.load(load)
        }
        .shellWidgetLibrary(editor: editor, target: .drawer(drawer), isPresented: $adding)
    }

    private func row(_ widget: String, panel: ShellSettingsPreview.Panel?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(ShellBarLayout.title(of: widget), systemImage: "puzzlepiece.extension")
            switch panel {
            case .missing:
                Text("This widget has no panel, so it can't show in a drawer.")
                    .font(.caption).foregroundStyle(.secondary)
            case let .failed(problem):
                Text(problem).font(.caption).foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
        .draggable(editor.drawerWidgetPayload(widget, in: drawer))
        .dragConfiguration(.init(
            operationsWithinApp: .init(allowCopy: false, allowMove: true),
            operationsOutsideApp: .init(allowCopy: false)
        ))
        .contextMenu {
            Button("Move Earlier") { editor.shiftDrawerWidget(widget, in: drawer, by: -1) }
                .disabled(members.first == widget)
            Button("Move Later") { editor.shiftDrawerWidget(widget, in: drawer, by: 1) }
                .disabled(members.last == widget)
            Button("Remove", role: .destructive) { editor.removeDrawerWidget(widget, from: drawer) }
                .disabled(members.count <= 1)
        }
    }

    private func insertionIndex(at point: CGPoint) -> Int {
        for (index, widget) in members.enumerated() {
            guard let frame = frames[widget] else { return members.count }
            if point.y < frame.midY { return index }
        }
        return members.count
    }

    private func marker(at index: Int) -> CGFloat? {
        if members.isEmpty { return 0 }
        if index < members.count { return frames[members[index]].map { $0.minY - 3 } }
        return members.last.flatMap { frames[$0] }.map { $0.maxY + 3 }
    }
}
