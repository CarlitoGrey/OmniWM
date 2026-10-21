// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Darwin
import Foundation
import SQLite3

enum ShellNotificationStore {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")

    private enum Failure: Error {
        case query
        case malformed
    }

    private struct Budget {
        var rows = 20_000
        var bytes = 4 << 20
        var encoded = 3 << 20
        var complete = true
        var malformed = false

        mutating func include(_ value: ShellServiceValue) -> Bool {
            let count = ShellNotificationMetadata.encodedSize(value)
            guard count <= encoded else { complete = false
                return false
            }
            encoded -= count
            return true
        }
    }

    private enum Column {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)

        var value: ShellServiceValue {
            switch self {
            case .null: .null
            case let .integer(value): ShellNotificationMetadata.integer(value)
            case let .real(value): .number(value)
            case let .text(value): .text(value)
            case let .blob(value): ShellNotificationMetadata.opaque(value)
            }
        }

        var integer: Int64? {
            if case let .integer(value) = self { value } else { nil }
        }

        var text: String? {
            if case let .text(value) = self { value } else { nil }
        }

        var blob: Data? {
            if case let .blob(value) = self { value } else { nil }
        }
    }

    private struct RecordContext {
        let appID: Int64
        let bundle: String
        let retained: Set<String>
        let categories: ShellServiceValue
    }

    private struct Tables {
        let apps: [[String: Column]]
        let categories: [[String: Column]]
        let lists: [String: [[String: Column]]]
        let memberships: [Int64: Set<String>]
        let records: [[String: Column]]
    }

    private struct Collected {
        var apps: [ShellServiceValue] = []
        var items: [ShellServiceValue] = []
        var found: [Int64: Set<String>] = [:]
    }

    static func read(at url: URL = defaultURL) -> ShellNotificationsData {
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        defer { if let database { sqlite3_close(database) } }
        guard opened == SQLITE_OK, let database else {
            let denied = opened == SQLITE_AUTH || opened == SQLITE_PERM ||
                (database.map { [EACCES, EPERM].contains(sqlite3_system_errno($0)) } ?? false)
            return ShellNotificationsData(
                state: denied ? "accessDenied" : "unavailable",
                complete: false,
                error: denied ? "Notification storage access denied" : "Notification storage unavailable"
            )
        }
        do {
            guard sqlite3_db_readonly(database, "main") == 1 else { throw Failure.query }
            try execute("PRAGMA query_only=ON", database)
            try execute("BEGIN", database)
            let result = try snapshot(database)
            try execute("COMMIT", database)
            return result
        } catch Failure.malformed {
            return ShellNotificationsData(
                state: "malformed",
                complete: false,
                error: "Notification storage contains malformed data"
            )
        } catch {
            return ShellNotificationsData(
                state: "queryError",
                complete: false,
                error: "Unable to read notification storage"
            )
        }
    }

    private static func snapshot(_ database: OpaquePointer) throws -> ShellNotificationsData {
        var budget = Budget()
        let source = try tables(database, budget: &budget)
        var result = Collected()
        for app in source
            .apps { try collectApp(app, from: source, database: database, budget: &budget, result: &result) }
        return finish(result, memberships: source.memberships, budget: &budget)
    }

    private static func tables(_ database: OpaquePointer, budget: inout Budget) throws -> Tables {
        let apps = try rows("SELECT * FROM app ORDER BY app_id", database, &budget)
        let categories = try rows("SELECT * FROM categories", database, &budget)
        var lists: [String: [[String: Column]]] = [:]
        for table in ["delivered", "displayed", "requests"] { lists[table] = try rows(
            "SELECT * FROM \(table)",
            database,
            &budget
        ) }
        var memberships: [Int64: Set<String>] = [:]
        for row in lists["delivered"] ?? [] {
            guard let app = row["app_id"]?.integer else { throw Failure.malformed }
            do { memberships[app] = try membership(row["list"]) } catch { budget.complete = false
                budget.malformed = true
            }
        }
        let activeApps = memberships.filter { !$0.value.isEmpty }.keys.sorted().map(String.init).joined(separator: ",")
        let records = activeApps.isEmpty ? [] : try rows(
            "SELECT * FROM record WHERE app_id IN (\(activeApps))",
            database,
            &budget,
            retained: memberships
        )
        return Tables(apps: apps, categories: categories, lists: lists, memberships: memberships, records: records)
    }

    private static func collectApp(
        _ app: [String: Column],
        from tables: Tables,
        database: OpaquePointer,
        budget: inout Budget,
        result: inout Collected
    ) throws {
        guard let appID = app["app_id"]?.integer, let bundle = app["identifier"]?.text else { throw Failure.malformed }
        let decoded = category(tables.categories.first { $0["app_id"]?.integer == appID }, budget: &budget)
        result.apps.append(appMetadata(app, bundle: bundle, categories: decoded, lists: tables.lists, budget: &budget))
        guard let retained = tables.memberships[appID], !retained.isEmpty else { return }
        let context = RecordContext(appID: appID, bundle: bundle, retained: retained, categories: decoded.categories)
        collect(
            tables.records.filter { $0["app_id"]?.integer == appID },
            context: context,
            budget: &budget,
            result: &result
        )
        guard !(result.found[appID] ?? []).isSuperset(of: retained) else { return }
        let fallback = try rows("SELECT * FROM record WHERE app_id=\(appID)", database, &budget)
        let candidates = fallback.filter { row in
            guard let bytes = row["uuid"]?.blob, let id = ShellNotificationMetadata.guid(bytes) else { return false }
            return !retained.contains(id)
        }
        collect(candidates, context: context, budget: &budget, result: &result, tolerateNonmemberFailure: true)
    }

    private static func finish(
        _ collected: Collected,
        memberships: [Int64: Set<String>],
        budget: inout Budget
    ) -> ShellNotificationsData {
        for (app, retained) in memberships
            where !(collected.found[app] ?? []).isSuperset(of: retained) { budget.complete = false }
        var items = collected.items.sorted {
            let lhs = $0.fields?["date"]?.number ?? 0
            let rhs = $1.fields?["date"]?.number ?? 0
            return lhs == rhs ? ($0.fields?["id"]?.string ?? "") < ($1.fields?["id"]?.string ?? "") : lhs > rhs
        }
        if items.count > 256 { items = Array(items.prefix(256))
            budget.complete = false
        }
        items = items.filter { budget.include($0) }
        let apps = collected.apps.filter { budget.include($0) }
        let state = budget
            .complete ? (items.isEmpty ? "empty" : "ready") : (budget.malformed ? "malformed" : "incomplete")
        return ShellNotificationsData(
            state: state,
            items: items,
            apps: apps,
            complete: budget.complete,
            error: budget.complete ? nil : "Notification snapshot incomplete"
        )
    }

    private static func collect(
        _ records: [[String: Column]],
        context: RecordContext,
        budget: inout Budget,
        result: inout Collected,
        tolerateNonmemberFailure: Bool = false
    ) {
        for row in records {
            do {
                guard let item = try record(
                    row,
                    bundle: context.bundle,
                    retained: context.retained,
                    categories: context.categories,
                    budget: &budget
                ), let id = item.fields?["id"]?.string else { continue }
                if result.found[context.appID, default: []].insert(id).inserted { result.items.append(item) }
                else { budget.complete = false
                    budget.malformed = true
                }
            } catch {
                if tolerateNonmemberFailure { continue }
                budget.complete = false
                if (error as? ShellNotificationMetadata.Failure) != .limit { budget.malformed = true }
            }
        }
    }
}

extension ShellNotificationStore {
    private static func category(
        _ row: [String: Column]?,
        budget: inout Budget
    ) -> (categories: ShellServiceValue, metadata: ShellServiceValue) {
        guard let bytes = row?["categories"]?.blob else { return (.array([]), row.map(columns) ?? .null) }
        do {
            let decoded = try ShellNotificationMetadata.decode(bytes)
            budget.complete = budget.complete && decoded.complete
            return (
                decoded.resolved,
                .object([
                    "raw": ShellNotificationMetadata.opaque(bytes),
                    "payload": decoded.value,
                    "resolved": decoded.resolved,
                    "columns": row.map(columns) ?? .null
                ])
            )
        } catch {
            budget.complete = false
            if (error as? ShellNotificationMetadata.Failure) != .limit { budget.malformed = true }
            return (
                .array([]),
                .object([
                    "raw": ShellNotificationMetadata.opaque(bytes),
                    "decodeState": .text("incomplete"),
                    "columns": row.map(columns) ?? .null
                ])
            )
        }
    }

    private static func appMetadata(
        _ app: [String: Column],
        bundle: String,
        categories: (categories: ShellServiceValue, metadata: ShellServiceValue),
        lists: [String: [[String: Column]]],
        budget: inout Budget
    ) -> ShellServiceValue {
        var fields: [String: ShellServiceValue] = [
            "bundle": .text(bundle),
            "columns": columns(app),
            "categories": categories.categories,
            "categoryMetadata": categories.metadata
        ]
        for table in ["delivered", "displayed", "requests"] {
            guard let row = lists[table]?.first(where: { $0["app_id"]?.integer == app["app_id"]?.integer })
            else { fields[table] = .null
                continue
            }
            do { fields[table] = .object([
                "columns": columns(row),
                "ids": .array(try membership(row["list"]).sorted().map(ShellServiceValue.text))
            ]) } catch {
                fields[table] = .object(["columns": columns(row), "ids": .null])
                budget.complete = false
                budget.malformed = true
            }
        }
        return .object(fields)
    }

    private static func record(
        _ row: [String: Column],
        bundle: String,
        retained: Set<String>,
        categories: ShellServiceValue,
        budget: inout Budget
    ) throws -> ShellServiceValue? {
        guard let bytes = row["data"]?.blob else { throw Failure.malformed }
        let decoded = try ShellNotificationMetadata.decode(bytes)
        guard let root = decoded.value.fields, let guidBytes = ShellNotificationMetadata.data(root["uuid"]),
              let guid = ShellNotificationMetadata.guid(guidBytes) else { throw Failure.malformed }
        guard retained.contains(guid) else { return nil }
        if row["uuid"]?.blob != guidBytes { budget.complete = false }
        budget.complete = budget.complete && decoded.complete
        guard let request = root["req"]?.fields else { throw Failure.malformed }
        let category = request["cate"]?.string ?? ""
        let definition = categories.values?.first { $0.fields?["id"]?.string == category }
        let date = root["date"]?.number.map { $0 + Date.timeIntervalBetween1970AndReferenceDate }
        return .object([
            "id": .text(guid), "bundle": .text(bundle), "title": text(request["titl"], budget: &budget),
            "subtitle": text(request["subt"], budget: &budget), "body": text(request["body"], budget: &budget),
            "date": date.map(ShellServiceValue.number) ?? .null,
            "requestId": request["iden"] ?? .null, "thread": request["thre"] ?? .null, "category": .text(category),
            "attachments": .array(attachments(request)), "actions": .array(actions(definition)),
            "userInfo": ShellNotificationMetadata.unwrapped(request["usda"]),
            "communication": ShellNotificationMetadata.unwrapped(request["uncc"]),
            "metadata": .object([
                "rawPayload": ShellNotificationMetadata.opaque(bytes),
                "payload": decoded.value,
                "columns": columns(row)
            ])
        ])
    }

    private static func text(_ value: ShellServiceValue?, budget: inout Budget) -> ShellServiceValue {
        guard let value else { return .text("") }
        if value.string != nil { return value }
        budget.complete = false
        return .text("")
    }

    private static func attachments(_ request: [String: ShellServiceValue]) -> [ShellServiceValue] {
        request["atta"]?.values?.map { value in
            let fields = value.fields ?? [:]
            let path = fields["pat"]?.string ?? ""
            return .object([
                "id": fields["id"] ?? .null,
                "type": fields["uti"] ?? .null,
                "path": .text(path),
                "available": .bool(!path.isEmpty && FileManager.default.fileExists(atPath: path)),
                "metadata": value
            ])
        } ?? []
    }

    private static func actions(_ definition: ShellServiceValue?) -> [ShellServiceValue] {
        (definition?.fields?["acts"]?.values ?? []).map { value in
            let fields = value.fields ?? [:]
            var result: [String: ShellServiceValue] = [
                "id": fields["id"] ?? .null,
                "title": fields["ti"] ?? .null,
                "options": fields["op"] ?? .number(0),
                "metadata": value
            ]
            if let value = fields["tia"] { result["textInputButtonTitle"] = value }
            if let value = fields["tip"] { result["textInputPlaceholder"] = value }
            return .object(result)
        }
    }

    private static func columns(_ row: [String: Column]) -> ShellServiceValue {
        .object(row.mapValues(\.value))
    }

    private static func membership(_ column: Column?) throws -> Set<String> {
        guard let column else { throw Failure.malformed }
        if case .null = column { return [] }
        guard let bytes = column.blob, bytes.count.isMultiple(of: 16) else { throw Failure.malformed }
        var values = Set<String>()
        for offset in stride(from: 0, to: bytes.count, by: 16) {
            guard let guid = ShellNotificationMetadata.guid(bytes.subdata(in: offset ..< offset + 16))
            else { throw Failure.malformed }
            values.insert(guid)
        }
        return values
    }

    private static func execute(_ sql: String, _ database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw Failure.query }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.query }
    }
}

extension ShellNotificationStore {
    private static func rows(
        _ sql: String,
        _ database: OpaquePointer,
        _ budget: inout Budget,
        retained: [Int64: Set<String>]? = nil
    ) throws -> [[String: Column]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw Failure.query }
        defer { sqlite3_finalize(statement) }
        var result: [[String: Column]] = []
        let names = (0 ..< sqlite3_column_count(statement)).map { String(cString: sqlite3_column_name(statement, $0)) }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw Failure.query }
            guard budget.rows > 0 else { budget.complete = false
                return result
            }
            budget.rows -= 1
            if skip(statement, names: names, retained: retained) { continue }
            if let row = try row(statement, names: names, budget: &budget) { result.append(row) }
        }
    }

    private static func skip(_ statement: OpaquePointer, names: [String], retained: [Int64: Set<String>]?) -> Bool {
        guard let retained, let appIndex = names.firstIndex(of: "app_id"),
              let uuidIndex = names.firstIndex(of: "uuid") else { return false }
        let index = Int32(uuidIndex)
        guard sqlite3_column_type(statement, index) == SQLITE_BLOB, sqlite3_column_bytes(statement, index) == 16,
              let pointer = sqlite3_column_blob(
                  statement,
                  index
              ), let guid = ShellNotificationMetadata.guid(Data(bytes: pointer, count: 16)) else { return false }
        return !(retained[sqlite3_column_int64(statement, Int32(appIndex))] ?? []).contains(guid)
    }

    private static func row(
        _ statement: OpaquePointer,
        names: [String],
        budget: inout Budget
    ) throws -> [String: Column]? {
        var row: [String: Column] = [:]
        var accepted = true
        for (index, name) in names.enumerated() {
            if let value = try column(statement, index: Int32(index), budget: &budget) { row[name] = value }
            else { accepted = false }
        }
        return accepted ? row : nil
    }

    private static func column(_ statement: OpaquePointer, index: Int32, budget: inout Budget) throws -> Column? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL: return .null
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            let value = sqlite3_column_double(statement, index)
            guard value.isFinite else { throw Failure.malformed }
            return .real(value)
        default:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count <= 2 << 20, count <= budget.bytes else { budget.complete = false
                return nil
            }
            budget.bytes -= count
            if sqlite3_column_type(statement, index) == SQLITE_TEXT {
                guard let value = sqlite3_column_text(statement, index), let text = String(
                    data: Data(bytes: value, count: count),
                    encoding: .utf8
                ) else { throw Failure.malformed }
                return .text(text)
            }
            let pointer = sqlite3_column_blob(statement, index)
            guard count == 0 || pointer != nil else { throw Failure.malformed }
            return .blob(pointer.map { Data(bytes: $0, count: count) } ?? Data())
        }
    }
}
