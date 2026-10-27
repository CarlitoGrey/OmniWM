// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension Bundle {
    var appVersion: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var appDisplayVersion: String? {
        guard let version = appVersion else { return nil }
        guard let tag = canaryReleaseTag else { return version }
        let date = tag.split(separator: "-")[1]
        return "\(version)-canary-\(date)"
    }

    var canaryReleaseTag: String? {
        guard let tag = infoDictionary?["OMNIWMCanaryTag"] as? String,
              GitHubRelease.isCanaryTag(tag)
        else { return nil }
        return tag
    }

    var releaseVersion: ReleaseVersion? {
        appVersion.flatMap(ReleaseVersion.init)
    }
}
