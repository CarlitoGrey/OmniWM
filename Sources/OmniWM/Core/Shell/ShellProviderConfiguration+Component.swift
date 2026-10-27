// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension ShellComponentDescriptor {
    func authorizesProvider(_ instance: ShellComponentInstance) -> Bool {
        instance.enabled && providerCommand != nil && capabilities.provider
    }
}

extension ShellProviderConfiguration {
    private struct OptionValue: Encodable {
        let value: ShellComponentValue

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case let .bool(value): try container.encode(value)
            case let .number(value): try container.encode(value)
            case let .string(value): try container.encode(value)
            case let .strings(value): try container.encode(value)
            }
        }
    }

    private struct Options: Encodable {
        let values: [String: ShellComponentValue]

        func encode(to encoder: any Encoder) throws {
            try values.mapValues { OptionValue(value: $0) }.encode(to: encoder)
        }
    }

    init(
        instance: ShellComponentInstance, descriptor: ShellComponentDescriptor,
        permissions: ShellNetworkPermissions
    ) throws {
        guard descriptor.authorizesProvider(instance), let command = descriptor.providerCommand else {
            throw ShellProviderProtocol.Failure(message: "provider_denied")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.init(
            widget: instance.widget,
            instance: instance.id,
            folder: descriptor.folder,
            command: command,
            options: try encoder.encode(Options(values: instance.options)),
            sha256: permissions.approvedDigest(for: descriptor.principal, command: command),
            principal: descriptor.principal
        )
    }
}
