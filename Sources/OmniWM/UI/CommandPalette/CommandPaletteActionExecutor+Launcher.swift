// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

@MainActor
extension CommandPaletteActionExecutor {
    func performLauncherAction(_ action: Action) {
        switch action {
        case let .openApplication(wmController, item, query):
            if let pid = environment.runningApplicationForResult(item),
               let handle = environment.mostRecentWindowForPID(wmController, pid),
               environment.navigateToApplicationWindow(wmController, handle)
            {
                environment.recordLauncherLaunch(wmController, item.id, query, item.displayName)
                return
            }
            environment.openApplication(item.bundleURL) { [weak self] failure in
                self?.completeLauncherOpen(failure, wmController, item.id, query, item.displayName)
            }
        case let .launchEntry(controller, entry, query):
            if entry.kind == .application {
                guard let url = ApplicationCatalogFilter.resolvedBundleURL(LauncherPaths.expanded(entry.path)) else {
                    environment.presentCommandFailure(String(localized: "The saved application is unavailable."))
                    return
                }
                perform(.openApplication(controller, LauncherApplicationResult(
                    bundleURL: url, bundleIdentifier: Bundle(url: url)?.bundleIdentifier, displayName: entry.name
                ), query))
            } else {
                LauncherExecution.shared.run(entry, controller: controller, query: query)
            }
        case let .openFile(wmController, item, query):
            environment.openFile(item.fileURL) { [weak self] failure in
                self?.completeLauncherOpen(failure, wmController, item.id, query, item.displayName)
            }
        case let .revealApplication(url),
             let .revealFile(url):
            environment.revealInFinder(url)
        default:
            break
        }
    }

    private func completeLauncherOpen(
        _ failure: String?,
        _ wmController: WMController,
        _ targetID: String,
        _ query: String,
        _ displayName: String
    ) {
        if let failure {
            environment.presentCommandFailure(failure)
        } else {
            environment.recordLauncherLaunch(wmController, targetID, query, displayName)
        }
    }
}
