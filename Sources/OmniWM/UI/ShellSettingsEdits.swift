// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

@MainActor
enum ShellSettingsEdits {
    static func set<Value: Encodable>(
        _ value: Value?,
        key: String,
        table: String = "workspaceBar",
        settings: SettingsStore,
        controller: WMController
    ) async throws {
        try await controller.workspaceBarManager.shellConfiguration.set(value, key: key, table: table)
    }

    static func reset(
        table: String = "workspaceBar",
        settings: SettingsStore,
        controller: WMController
    ) async throws {
        try await controller.workspaceBarManager.shellConfiguration.reset(table: table)
    }
}

extension View {
    func shellSettingsError(
        _ error: Binding<String?>,
        title: LocalizedStringKey = "Unable to Save Shell Settings"
    ) -> some View {
        alert(title, isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}
