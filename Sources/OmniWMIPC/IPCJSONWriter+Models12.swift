// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension IPCJSONWriter {
    mutating func value(_ value: borrowing IPCRequest) throws {
        begin(123)
        var first = true
        if let fieldValue = value.authorizationToken {
            self.key("authorizationToken", &first)
            try self.value(fieldValue)
        }
        self.key("id", &first)
        try self.value(value.id)
        self.key("kind", &first)
        try self.value(value.kind)
        self.key("payload", &first)
        try self.value(value.payload)
        self.key("version", &first)
        try self.value(value.version)
        end(125)
    }
}
