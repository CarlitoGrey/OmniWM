// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Darwin
import Foundation

enum SettingsFileObservationDirectories {
    static func paths(for fileURL: URL) -> Set<URL> {
        var directory = URL(fileURLWithPath: "/", isDirectory: true)
        var directories: Set<URL> = [directory]
        var components = fileURL.pathComponents.reversed().map { $0 }
        var followedLinks = 0

        while let component = components.popLast() {
            switch component {
            case "/",
                 ".":
                continue
            case "..":
                directory.deleteLastPathComponent()
                continue
            default:
                break
            }

            let entry = directory.appendingPathComponent(component)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: entry.path) else { break }
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink:
                guard followedLinks < MAXSYMLINKS,
                      let target = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path)
                else { return directories }
                followedLinks += 1
                if target.hasPrefix("/") {
                    directory = URL(fileURLWithPath: "/", isDirectory: true)
                }
                components.append(contentsOf: (target as NSString).pathComponents.reversed())
            case .typeDirectory:
                directory = entry
                directories.insert(directory)
            default:
                return directories
            }
        }

        return directories
    }
}
