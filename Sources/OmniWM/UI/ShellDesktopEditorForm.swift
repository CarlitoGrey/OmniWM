// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDesktopEditorForm: View {
    let editor: ShellDesktopEditor

    var body: some View {
        Form {
            if let problem = editor.problem {
                Section {
                    HStack(alignment: .top) {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if editor.snapshot == nil {
                            Button("Retry") {
                                Task {
                                    editor.problem = nil
                                    await editor.reload()
                                }
                            }
                        } else {
                            Button("Dismiss") { editor.problem = nil }
                        }
                    }
                }
            }
            failedWrites
            if editor.snapshot != nil {
                ShellDesktopLanes(editor: editor)
                if let widget = editor.selectedWidget {
                    ShellDesktopWidgetInspector(editor: editor, widget: widget)
                } else {
                    ShellDesktopBarInspector(editor: editor)
                }
            } else if editor.problem == nil {
                Section {
                    ProgressView("Loading style…").frame(maxWidth: .infinity)
                }
            }
            ShellDesktopAllStyles(editor: editor)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var failedWrites: some View {
        if !editor.writes.failures.isEmpty {
            Section("Unsaved Changes") {
                ForEach(Array(editor.writes.failures.keys), id: \.self) { target in
                    VStack(alignment: .leading) {
                        Text(ShellDesktopWriteTitle.title(target, editor: editor)).fontWeight(.medium)
                        Text(editor.writes.failure(for: target) ?? "").foregroundStyle(.red)
                        HStack {
                            Button("Retry") { editor.writes.retry(target) }
                            Button("Discard") { editor.writes.discard(target) }
                        }
                    }
                }
            }
        }
    }
}
