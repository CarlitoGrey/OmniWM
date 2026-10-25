// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellComponentGallery: View {
    let entries: [ShellComponentCatalog.Entry]
    var problem: String?
    let add: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Island Widget").font(.title2.bold())
            TextField("Search widgets", text: $query).textFieldStyle(.roundedBorder)
            List {
                ForEach(entries.filter {
                    query.isEmpty || ($0.descriptor?.title ?? $0.widget).localizedStandardContains(query)
                }, id: \.widget) { entry in
                    HStack {
                        Label(
                            entry.descriptor?.title ?? ShellBarLayout.title(of: entry.widget),
                            systemImage: entry.descriptor?.icon ?? "exclamationmark.triangle"
                        )
                        Spacer()
                        Button("Add") {
                            Task {
                                adding = true
                                if await add(entry.widget) { dismiss() }
                                adding = false
                            }
                        }
                        .disabled(entry.descriptor == nil || adding)
                    }
                    if let error = entry.error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .frame(minHeight: 240)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 400)
    }
}
