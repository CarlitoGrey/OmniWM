// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ShellDrawerPanels {
    struct Load: Equatable {
        let request: ShellSettingsPreview.PanelRequest?
        let attempt: Int
    }

    private(set) var loading = false
    private(set) var problem: String?
    private(set) var attempt = 0
    private var current: Load?
    private var loadToken = UUID()
    private var results: [String: ShellSettingsPreview.Panel] = [:]

    func retry() {
        attempt += 1
    }

    func values(for request: ShellSettingsPreview.PanelRequest?) -> [String: ShellSettingsPreview.Panel] {
        current?.request == request ? results : [:]
    }

    func hasFailure(for request: ShellSettingsPreview.PanelRequest?) -> Bool {
        guard current?.request == request else { return false }
        return problem != nil || values(for: request).values.contains {
            if case .failed = $0 { return true }
            return false
        }
    }

    func load(_ input: Load) async {
        let token = UUID()
        loadToken = token
        current = input
        results = [:]
        problem = nil
        guard let request = input.request else {
            loading = false
            return
        }
        loading = true
        do {
            let next = try await ShellSettingsPreview.panels(for: request)
            try Task.checkCancellation()
            guard loadToken == token else { return }
            results = next
        } catch is CancellationError {
        } catch {
            guard loadToken == token else { return }
            problem = error.localizedDescription
        }
        if loadToken == token { loading = false }
    }
}

struct ShellDrawerPanelStatus: View {
    let panels: ShellDrawerPanels
    let request: ShellSettingsPreview.PanelRequest?
    var disabled = false

    var body: some View {
        if panels.loading {
            ProgressView("Checking widget panels…").controlSize(.small)
        }
        if let problem = panels.problem {
            Text(problem).font(.caption).foregroundStyle(.red)
        }
        if panels.hasFailure(for: request) {
            Button("Retry") { panels.retry() }
                .disabled(disabled || panels.loading)
        }
    }
}
