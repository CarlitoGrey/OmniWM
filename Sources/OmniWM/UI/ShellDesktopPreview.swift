// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDesktopPreview: View {
    let config: ShellConfig
    let style: ShellBarStyle
    let display: ShellSettingsPreview.Display?
    let sourceGeneration: UInt64
    let fullWidth: Bool
    var surface: ShellSettingsPreview.Surface = .bar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var context: Context?
    @State private var current: ShellSettingsPreview.Request?
    @State private var updating = false
    @State private var failure: String?

    struct Context: Equatable {
        let profile: String
        let monitor: Monitor.ID?
        let surface: RetainedSurface
    }

    enum RetainedSurface: Equatable {
        case bar, island, drawer(String)
    }

    static func context(for request: ShellSettingsPreview.Request) -> Context {
        let surface: RetainedSurface = switch request.surface {
        case .bar: .bar
        case .island: .island
        case let .drawer(id): .drawer(id)
        }
        return Context(profile: request.config.profile, monitor: request.display?.monitor.id, surface: surface)
    }

    private var request: ShellSettingsPreview.Request {
        .init(
            config: config, surface: surface, style: style, scale: displayScale, dark: colorScheme == .dark,
            fullWidth: fullWidth, sourceGeneration: sourceGeneration,
            display: display
        )
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale).resizable().scaledToFit().padding(8)
            } else if let failure {
                Text(failure).font(.caption).foregroundStyle(.secondary).padding(8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if updating, image != nil {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Updating").font(.caption)
                }
                .padding(5).background(.regularMaterial, in: .capsule).padding(4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let failure, image != nil {
                Label("Preview could not update: \(failure)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).lineLimit(2)
                    .padding(6).background(.regularMaterial, in: .rect(cornerRadius: 6)).padding(4)
            }
        }
        .task(id: request) {
            let value = request
            let next = Self.context(for: value)
            if next != context { image = nil }
            context = next
            current = value
            updating = true
            failure = nil
            do {
                let slot = switch value.surface {
                case .bar: "editor-bar"
                case .island: "editor-island"
                case .drawer: "editor-drawer"
                }
                let rendered = try await ShellSettingsPreview.cachedImage(for: value, slot: .init(id: slot))
                try Task.checkCancellation()
                guard current == value else { return }
                image = rendered
                updating = false
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, current == value else { return }
                failure = (error as? ShellScriptFailure)?.message ?? error.localizedDescription
                updating = false
            }
        }
    }
}
