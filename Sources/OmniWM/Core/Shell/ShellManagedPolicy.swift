// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreFoundation
import Foundation

protocol ShellManagedPreferenceReader {
    func forcedValue(_ key: String) -> CFPropertyList?
}

struct ShellAppManagedPreferences: ShellManagedPreferenceReader {
    let domain: String

    func forcedValue(_ key: String) -> CFPropertyList? {
        guard CFPreferencesAppValueIsForced(key as CFString, domain as CFString) else { return nil }
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }
}

enum ShellBuiltInService: String, CaseIterable, Sendable {
    case weather
    case lyrics
}

struct ShellManagedPolicy: Equatable, Sendable {
    enum Key: String, CaseIterable, Sendable {
        case allowedHosts = "ShellNetworkAllowedHosts"
        case blockedHosts = "ShellNetworkBlockedHosts"
        case onlyAllowedHosts = "ShellNetworkOnlyAllowedHosts"
        case providersAllowed = "ShellProvidersAllowed"
        case blockedServices = "ShellBlockedServices"
    }

    var allowedHosts: Set<String> = []
    var blockedHosts: Set<String> = []
    var blocksAllHosts = false
    var onlyAllowedHosts = false
    var providersAllowed = true
    var blockedServices: Set<ShellBuiltInService> = []
    var invalidKeys: [Key] = []

    init() {}

    init(reading reader: some ShellManagedPreferenceReader) {
        for key in Key.allCases {
            guard let value = reader.forcedValue(key.rawValue) else { continue }
            if !apply(value, to: key) { invalidKeys.append(key) }
        }
    }

    static func current() -> ShellManagedPolicy {
        guard let domain = Bundle.main.bundleIdentifier else { return ShellManagedPolicy() }
        CFPreferencesAppSynchronize(domain as CFString)
        return ShellManagedPolicy(reading: ShellAppManagedPreferences(domain: domain))
    }

    func blocks(_ host: String) -> Bool {
        blocksAllHosts || blockedHosts.contains(host) || onlyAllowedHosts && !allowedHosts.contains(host)
    }

    private mutating func apply(_ value: CFPropertyList, to key: Key) -> Bool {
        switch key {
        case .allowedHosts:
            let hosts = Self.hosts(value)
            allowedHosts = hosts ?? []
            return hosts != nil
        case .blockedHosts:
            let hosts = Self.hosts(value)
            blockedHosts = hosts ?? []
            blocksAllHosts = hosts == nil
            return hosts != nil
        case .onlyAllowedHosts:
            let flag = Self.flag(value)
            onlyAllowedHosts = flag ?? true
            return flag != nil
        case .providersAllowed:
            let flag = Self.flag(value)
            providersAllowed = flag ?? false
            return flag != nil
        case .blockedServices:
            let names = value as? [String]
            let services = names?.compactMap(ShellBuiltInService.init(rawValue:))
            let valid = services != nil && services?.count == names?.count
            blockedServices = valid ? Set(services ?? []) : Set(ShellBuiltInService.allCases)
            return valid
        }
    }

    private static let nameCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-._")

    private static func hosts(_ value: CFPropertyList) -> Set<String>? {
        guard let entries = value as? [String] else { return nil }
        let hosts = entries.map(ShellHTTPPolicy.canonicalHost)
        return hosts.allSatisfy(isHost) ? Set(hosts) : nil
    }

    private static func isHost(_ host: String) -> Bool {
        guard host.contains(":") else { return !host.isEmpty && host.allSatisfy(nameCharacters.contains) }
        var address = in6_addr()
        return inet_pton(AF_INET6, host, &address) == 1
    }

    private static func flag(_ value: CFPropertyList) -> Bool? {
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
