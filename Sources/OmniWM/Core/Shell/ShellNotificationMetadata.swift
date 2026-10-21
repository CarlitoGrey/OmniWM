// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreFoundation
import Foundation

enum ShellNotificationMetadata {
    struct Decoded {
        let value: ShellServiceValue
        let resolved: ShellServiceValue
        let complete: Bool
    }

    enum Failure: Error, Equatable {
        case malformed
        case limit
    }

    static func integer(_ value: Int64) -> ShellServiceValue {
        abs(Double(value)) <= 9_007_199_254_740_991 ? .number(Double(value)) : .object([
            "type": .text("integer"),
            "value": .text(String(value))
        ])
    }

    static func decode(_ data: Data) throws -> Decoded {
        var decoder = Decoder()
        return try decoder.decode(data, depth: 0)
    }

    static func opaque(_ data: Data) -> ShellServiceValue {
        .object(["type": .text("data"), "bytes": .bytes(Array(data)), "byteLength": .number(Double(data.count))])
    }

    static func encodedSize(_ value: ShellServiceValue) -> Int {
        switch value {
        case .null,
             .bool: 1
        case .number: 9
        case let .bytes(value): 5 + value.count
        case let .array(values): 5 + values.reduce(0) { $0 + encodedSize($1) }
        case let .object(values): 5 + values.reduce(0) { $0 + 4 + $1.key.utf8.count + encodedSize($1.value) }
        }
    }

    static func guid(_ data: Data) -> String? {
        guard data.count == 16 else { return nil }
        let bytes = Array(data)
        let text = bytes.map { String(format: "%02X", $0) }.joined()
        let cuts = [8, 12, 16, 20]
        return text.enumerated().map { (cuts.contains($0.offset) ? "-" : "") + String($0.element) }.joined()
    }

    static func data(_ value: ShellServiceValue?) -> Data? {
        guard let fields = value?.fields, isOpaque(fields), case let .bytes(raw)? = fields["bytes"] else { return nil }
        return Data(raw)
    }

    private static func isOpaque(_ fields: [String: ShellServiceValue]) -> Bool {
        guard fields["type"]?.string == "data", case let .bytes(bytes)? = fields["bytes"] else { return false }
        return fields["byteLength"]?.number == Double(bytes.count)
    }

    static func unwrapped(_ value: ShellServiceValue?) -> ShellServiceValue {
        value?.fields?["resolved"] ?? value?.fields?["decoded"] ?? value ?? .null
    }
}

extension ShellNotificationMetadata {
    private struct Decoder {
        var remaining = 131_072
        var remainingBytes = 16 << 20
        var remainingXML = 32 << 20
        var complete = true

        mutating func enter(_ depth: Int) throws {
            guard depth < 40, remaining > 0 else { throw Failure.limit }
            remaining -= 1
        }

        mutating func decode(_ data: Data, depth: Int) throws -> Decoded {
            try enter(depth)
            guard data.count <= 2 << 20, data.count <= remainingBytes else { throw Failure.limit }
            remainingBytes -= data.count
            let property: Any
            let xml: Data
            do {
                property = try PropertyListSerialization.propertyList(from: data, format: nil)
                xml = try PropertyListSerialization.data(fromPropertyList: property, format: .xml, options: 0)
            } catch { throw Failure.malformed }
            guard xml.count <= remainingXML else { throw Failure.limit }
            remainingXML -= xml.count
            let original = String(decoding: xml, as: UTF8.self)
            var sentinel = "OmniWMNotificationUID"
            while original.contains(sentinel) { sentinel += "_" }
            let escaped = sentinel + "DictionaryKey"
            let protected = try protect(property, escaped: escaped, depth: depth + 1)
            let protectedXML: Data
            do {
                protectedXML = try PropertyListSerialization
                    .data(fromPropertyList: protected, format: .xml, options: 0)
            } catch { throw Failure.malformed }
            guard protectedXML.count <= remainingXML else { throw Failure.limit }
            remainingXML -= protectedXML.count
            let normalized = String(decoding: protectedXML, as: UTF8.self).replacingOccurrences(
                of: "<key>CF$UID</key>",
                with: "<key>\(sentinel)</key>"
            )
            let root: Any
            do { root = try PropertyListSerialization.propertyList(from: Data(normalized.utf8), format: nil) } catch {
                throw Failure.malformed
            }
            let value = try convert(root, uidKey: sentinel, escaped: escaped, depth: depth + 1)
            let resolved = try archive(value, depth: depth + 1)
            return Decoded(value: value, resolved: resolved, complete: complete)
        }

        mutating func protect(_ value: Any, escaped: String, depth: Int) throws -> Any {
            try enter(depth)
            if let values = value as? [String: Any] {
                var result: [String: Any] = [:]
                for (key, value) in values { result[key == "CF$UID" ? escaped : key] = try protect(
                    value,
                    escaped: escaped,
                    depth: depth + 1
                ) }
                return result
            }
            if let values = value as? [Any] {
                return try values.map { try protect($0, escaped: escaped, depth: depth + 1) }
            }
            return value
        }

        mutating func convert(_ value: Any, uidKey: String, escaped: String, depth: Int) throws -> ShellServiceValue {
            try enter(depth)
            if let value = value as? String { return .text(value) }
            if let value = value as? NSNumber { return try number(value) }
            if let value = value as? Date {
                return .object([
                    "type": .text("date"),
                    "unixSeconds": .number(value.timeIntervalSince1970),
                    "referenceSeconds": .number(value.timeIntervalSinceReferenceDate)
                ])
            }
            if let value = value as? Data { return binary(value, depth: depth) }
            if let values = value as? [Any] { return try .array(values.map { try convert(
                $0,
                uidKey: uidKey,
                escaped: escaped,
                depth: depth + 1
            ) }) }
            guard let fields = value as? [String: Any] else { throw Failure.malformed }
            return try dictionary(fields, uidKey: uidKey, escaped: escaped, depth: depth)
        }

        func number(_ value: NSNumber) throws -> ShellServiceValue {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            let type = String(cString: value.objCType)
            if type == "f" || type == "d" {
                guard value.doubleValue.isFinite else { throw Failure.malformed }
                return .number(value.doubleValue)
            }
            if let signed = Int64(value.stringValue) { return ShellNotificationMetadata.integer(signed) }
            return .object(["type": .text("integer"), "value": .text(value.stringValue)])
        }

        mutating func binary(_ value: Data, depth: Int) -> ShellServiceValue {
            var fields = ShellNotificationMetadata.opaque(value).fields ?? [:]
            guard value.starts(with: Data("bplist".utf8)) || value.starts(with: Data("<?xml".utf8))
            else { return .object(fields) }
            do {
                let nested = try decode(value, depth: depth + 1)
                fields["decoded"] = nested.value
                fields["resolved"] = nested.resolved
                complete = complete && nested.complete
            } catch {
                fields["decodeState"] = .text("incomplete")
                complete = false
            }
            return .object(fields)
        }

        mutating func dictionary(
            _ values: [String: Any],
            uidKey: String,
            escaped: String,
            depth: Int
        ) throws -> ShellServiceValue {
            if values.count == 1, let uid = values[uidKey] as? NSNumber {
                let number = Int64(uid.stringValue).map(ShellNotificationMetadata.integer) ?? .object([
                    "type": .text("integer"),
                    "value": .text(uid.stringValue)
                ])
                return .object(["type": .text("uid"), "value": number])
            }
            var fields: [String: ShellServiceValue] = [:]
            fields.reserveCapacity(values.count)
            for (key, value) in values { fields[key == escaped ? "CF$UID" : key] = try convert(
                value,
                uidKey: uidKey,
                escaped: escaped,
                depth: depth + 1
            ) }
            return .object(fields)
        }

        mutating func archive(_ value: ShellServiceValue, depth: Int) throws -> ShellServiceValue {
            guard let fields = value.fields, let objects = fields["$objects"]?.values,
                  let root = fields["$top"]?.fields?["root"] else { return value }
            return try resolve(root, objects: objects, path: [], depth: depth + 1)
        }

        mutating func resolve(
            _ value: ShellServiceValue,
            objects: [ShellServiceValue],
            path: Set<Int>,
            depth: Int
        ) throws -> ShellServiceValue {
            try enter(depth)
            if let fields = value.fields, fields["type"]?.string == "uid" {
                return try reference(fields, objects: objects, path: path, depth: depth)
            }
            if let values = value.values { return try .array(values.map { try resolve(
                $0,
                objects: objects,
                path: path,
                depth: depth + 1
            ) }) }
            guard let fields = value.fields else { return value }
            if ShellNotificationMetadata.isOpaque(fields) { return value }
            if let keys = fields["NS.keys"]?.values, let values = fields["NS.objects"]?.values,
               keys.count == values.count
            {
                return try entries(keys: keys, values: values, objects: objects, path: path, depth: depth)
            }
            if let values = fields["NS.objects"]?.values { return try .array(values.map { try resolve(
                $0,
                objects: objects,
                path: path,
                depth: depth + 1
            ) }) }
            return try object(fields, objects: objects, path: path, depth: depth)
        }

        mutating func reference(
            _ fields: [String: ShellServiceValue],
            objects: [ShellServiceValue],
            path: Set<Int>,
            depth: Int
        ) throws -> ShellServiceValue {
            guard let raw = fields["value"]?.number, raw >= 0, raw < Double(objects.count),
                  raw.rounded() == raw else { throw Failure.malformed }
            let index = Int(raw)
            if index == 0, objects[index].string == "$null" { return .null }
            if path.contains(index) { return .object(["type": .text("reference"), "value": .number(raw)]) }
            return try resolve(objects[index], objects: objects, path: path.union([index]), depth: depth + 1)
        }

        mutating func entries(
            keys: [ShellServiceValue],
            values: [ShellServiceValue],
            objects: [ShellServiceValue],
            path: Set<Int>,
            depth: Int
        ) throws -> ShellServiceValue {
            var result: [String: ShellServiceValue] = [:]
            for (key, item) in zip(keys, values) {
                guard let key = try resolve(key, objects: objects, path: path, depth: depth + 1).string,
                      result[key] == nil else { throw Failure.malformed }
                result[key] = try resolve(item, objects: objects, path: path, depth: depth + 1)
            }
            return .object(result)
        }

        mutating func object(
            _ fields: [String: ShellServiceValue],
            objects: [ShellServiceValue],
            path: Set<Int>,
            depth: Int
        ) throws -> ShellServiceValue {
            var result: [String: ShellServiceValue] = [:]
            for (key, item) in fields {
                if key == "$class", let index = item.fields?["value"]?.number, index >= 0,
                   index < Double(objects.count)
                {
                    result[key] = item
                    result["archivedClass"] = objects[Int(index)].fields?["$classname"] ?? .null
                } else { result[key] = try resolve(item, objects: objects, path: path, depth: depth + 1) }
            }
            return .object(result)
        }
    }
}
