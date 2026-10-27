// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import OmniWMScriptHost
import Synchronization
import XCTest

final class ShellRequireTests: XCTestCase {
    func testSelfAndRelativePathsFollowLuauRules() throws {
        let result = try Self.load("""
        local helpers = require("@self/helpers")
        local nested = require("@self/lib")
        local shared = require("./shared")
        local again = require("@self/helpers")
        assert(helpers.value == 1 and nested.value == 2 and shared.value == 3 and again == helpers)
        assert(leaked == nil)
        """, modules: [
            "widgets/clock/helpers.luau": "leaked = true return { value = 1 }",
            "widgets/clock/lib/init.luau": "return { value = require(\"./sibling\").value }",
            "widgets/clock/sibling.luau": "return { value = 2 }",
            "widgets/shared.luau": "return { value = 3 }"
        ])
        XCTAssertEqual(result.status, OMNI_OK, result.message)
    }

    func testMissingCyclicAndAbsoluteModulesFail() throws {
        let missing = try Self.load("require(\"@self/nope\")")
        XCTAssertEqual(missing.status, OMNI_ERR_RUNTIME)
        XCTAssertTrue(missing.message.contains("no module"), missing.message)

        let cycle = try Self.load("require(\"@self/a\")", modules: [
            "widgets/clock/a.luau": "return require(\"./b\")",
            "widgets/clock/b.luau": "return require(\"./a\")"
        ])
        XCTAssertEqual(cycle.status, OMNI_ERR_RUNTIME)
        XCTAssertTrue(cycle.message.contains("requires itself"), cycle.message)

        let absolute = try Self.load("require(\"helpers\")", modules: ["widgets/clock/helpers.luau": "return 1"])
        XCTAssertTrue(absolute.message.contains("must start with"), absolute.message)

        let escape = try Self.load("require(\"../../../etc\")")
        XCTAssertEqual(escape.status, OMNI_ERR_RUNTIME)
    }

    func testBytecodeCacheSharesRootsAndModulesAcrossVMs() throws {
        let id = UUID().uuidString
        let main = "cacheResult = require('@self/value').value -- \(id)"
        let modules = ["widgets/clock/value.luau": "return { value = 41 } -- \(id)"]
        let first = try Self.load(main, modules: modules)
        XCTAssertEqual(first.status, OMNI_OK, first.message)
        XCTAssertEqual(first.compiles, 2)
        XCTAssertEqual(first.value, 41)

        let prepared = try Self.load(main, modules: modules)
        XCTAssertEqual(prepared.status, OMNI_OK, prepared.message)
        XCTAssertEqual(prepared.value, 41)

        let shared = try Self.load(main, modules: modules)
        XCTAssertEqual(shared.status, OMNI_OK, shared.message)
        XCTAssertEqual(shared.compiles, 0)
        XCTAssertEqual(shared.value, 41)
    }

    func testBytecodeCacheCompilesAnEditedModule() throws {
        let id = UUID().uuidString
        let main = "cacheResult = require('@self/value').value -- \(id)"
        for _ in 0 ..< 2 {
            let prepared = try Self.load(main, modules: [
                "widgets/clock/value.luau": "return { value = 41 } -- \(id)"
            ])
            XCTAssertEqual(prepared.status, OMNI_OK, prepared.message)
            XCTAssertEqual(prepared.value, 41)
        }
        let edited = try Self.load(main, modules: [
            "widgets/clock/value.luau": "return { value = 73 } -- \(id)"
        ])
        XCTAssertEqual(edited.status, OMNI_OK, edited.message)
        XCTAssertEqual(edited.compiles, 1)
        XCTAssertEqual(edited.value, 73)
    }

    func testBytecodeCacheKeepsModuleStatePerVM() throws {
        let id = UUID().uuidString
        let main = """
        local value = require('@self/value')
        value.count += 1
        cacheResult = value.count
        -- \(id)
        """
        let modules = ["widgets/clock/value.luau": "return { count = 0 } -- \(id)"]
        for _ in 0 ..< 2 {
            let result = try Self.load(main, modules: modules)
            XCTAssertEqual(result.status, OMNI_OK, result.message)
            XCTAssertEqual(result.value, 1)
        }
    }

    func testBytecodeCacheKeepsCompileErrorsPerChunk() throws {
        let source = "-- \(UUID().uuidString)\nlocal ="
        let firstChunk = "widgets/cache-first/init.luau"
        let secondChunk = "widgets/cache-second/init.luau"
        let first = try Self.load(source, chunk: "@\(firstChunk)")
        XCTAssertEqual(first.status, OMNI_ERR_COMPILE)
        XCTAssertEqual(first.compiles, 1)
        XCTAssertTrue(first.message.contains(firstChunk), first.message)
        XCTAssertFalse(first.message.contains(secondChunk), first.message)

        let second = try Self.load(source, chunk: "@\(secondChunk)")
        XCTAssertEqual(second.status, OMNI_ERR_COMPILE)
        XCTAssertEqual(second.compiles, 0)
        XCTAssertTrue(second.message.contains(secondChunk), second.message)
        XCTAssertFalse(second.message.contains(firstChunk), second.message)
    }

    func testBytecodeCacheCompilesConcurrentFirstLoadsOnce() throws {
        let source = "cacheResult = 73 -- \(UUID().uuidString)"
        let ready = DispatchGroup()
        let start = DispatchGroup()
        let finished = DispatchGroup()
        let results = Mutex<[Result<LoadResult, Error>]>([])
        start.enter()
        for _ in 0 ..< 4 {
            ready.enter()
            finished.enter()
            Thread.detachNewThread {
                defer { finished.leave() }
                var reachedLoad = false
                let result = Result {
                    try Self.load(source, beforeLoad: {
                        reachedLoad = true
                        ready.leave()
                        start.wait()
                    })
                }
                if !reachedLoad {
                    ready.leave()
                }
                results.withLock { $0.append(result) }
            }
        }
        ready.wait()
        start.leave()
        finished.wait()

        let loaded = try results.withLock { $0 }.map { try $0.get() }
        XCTAssertEqual(loaded.count, 4)
        XCTAssertEqual(loaded.reduce(0) { $0 + $1.compiles }, 1)
        for result in loaded {
            XCTAssertEqual(result.status, OMNI_OK, result.message)
            XCTAssertEqual(result.value, 73)
        }
    }

    func testBytecodeCacheEvictsAndReusesCanary() throws {
        let id = UUID().uuidString
        let canary = "cacheResult = 41 -- \(id)"
        let first = try Self.load(canary)
        XCTAssertEqual(first.status, OMNI_OK, first.message)
        XCTAssertEqual(first.compiles, 1)
        XCTAssertEqual(first.value, 41)

        let padding = String(repeating: "x", count: 256 << 10)
        var evicted = false
        for index in 0 ..< 64 {
            let filler = try Self.load("return '\(padding)' -- \(id)-\(index)")
            XCTAssertEqual(filler.status, OMNI_OK, filler.message)
            XCTAssertEqual(filler.compiles, 1)
            let probe = try Self.load(canary)
            XCTAssertEqual(probe.status, OMNI_OK, probe.message)
            XCTAssertLessThanOrEqual(probe.compiles, 1)
            XCTAssertEqual(probe.value, 41)
            if probe.compiles == 1 {
                evicted = true
                break
            }
        }
        XCTAssertTrue(evicted)

        let shared = try Self.load(canary)
        XCTAssertEqual(shared.status, OMNI_OK, shared.message)
        XCTAssertEqual(shared.compiles, 0)
        XCTAssertEqual(shared.value, 41)
    }

    private struct LoadResult: Sendable {
        let status: omni_status
        let message: String
        let compiles: UInt64
        let value: Double?
    }

    private static func load(
        _ main: String,
        modules: [String: String] = [:],
        chunk: String = "@widgets/clock/init.luau",
        beforeLoad: () -> Void = {}
    ) throws -> LoadResult {
        let vm = try XCTUnwrap(ShellVM.make(memoryLimit: 8 << 20))
        defer { _ = omni_vm_destroy(vm) }
        for (path, source) in modules {
            XCTAssertEqual(omni_vm_add_module(vm, path, path.utf8.count, source, source.utf8.count), OMNI_OK)
        }
        var capture = omni_capture_stats()
        XCTAssertTrue(omni_vm_capture_begin(vm, 1, &capture))
        var error = [CChar](repeating: 0, count: 512)
        beforeLoad()
        let status = omni_vm_load(
            vm,
            chunk,
            main,
            main.utf8.count,
            100_000_000,
            &error,
            error.count
        )
        XCTAssertTrue(omni_vm_capture_end(vm, 1, &capture))
        var value = 0.0
        let valueStatus = omni_vm_global_number(vm, "cacheResult", &value)
        return LoadResult(
            status: status,
            message: error.withUnsafeBufferPointer { String(cString: $0.baseAddress!) },
            compiles: capture.bytecode_compiles,
            value: valueStatus == OMNI_OK ? value : nil
        )
    }
}
