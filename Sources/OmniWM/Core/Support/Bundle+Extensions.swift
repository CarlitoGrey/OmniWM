// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension Bundle {
    var appVersion: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
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
