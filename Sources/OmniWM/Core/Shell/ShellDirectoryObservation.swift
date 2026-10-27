// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreServices
import Darwin
import Foundation

@MainActor
final class ShellDirectoryObservation {
    private static let maximumDescriptorCost = 32
    private static let reservedDescriptorCount = 64

    private final class Callback: Sendable {
        let onEvents: @Sendable ([String], [FSEventStreamEventFlags]) -> Void

        init(_ onEvents: @escaping @Sendable ([String], [FSEventStreamEventFlags]) -> Void) {
            self.onEvents = onEvents
        }
    }

    private let onChange: @MainActor () -> Void
    private let createStream: @MainActor (FSEventStreamContext, [String]) -> FSEventStreamRef?
    private let startStream: (FSEventStreamRef) -> Bool
    private let eventQueue = DispatchQueue(label: "com.omniwm.shell-directory-observation")
    private var stream: FSEventStreamRef?
    private var generation: UInt64 = 0
    private var retryTimer: DispatchSourceTimer?
    private var paths: [URL] = []
    private var watchedPaths: Set<String> = []
    private var roots: [String] = []

    init(
        createStream: @escaping @MainActor (FSEventStreamContext, [String])
            -> FSEventStreamRef? = ShellDirectoryObservation.makeStream,
        startStream: @escaping (FSEventStreamRef) -> Bool = FSEventStreamStart,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.createStream = createStream
        self.startStream = startStream
        self.onChange = onChange
    }

    isolated deinit {
        cancel()
    }

    func sync(paths: [URL]) {
        guard !paths.isEmpty else {
            cancel()
            return
        }
        self.paths = paths
        watchedPaths = Set(paths.map(Self.canonicalPath))
        let next = Self.directoryRoots(for: paths)
        guard next != roots || stream == nil else { return }
        stopStream()
        roots = next
        start()
    }

    func cancel() {
        retryTimer?.cancel()
        retryTimer = nil
        stopStream()
        paths = []
        watchedPaths = []
        roots = []
    }

    private func stopStream() {
        generation &+= 1
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventQueue.sync {}
    }

    private func start() {
        guard Self.hasDescriptorBudget(for: roots) else {
            retry()
            return
        }
        let generation = generation
        let callback = Callback { [weak self] paths, flags in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                receive(paths: paths, flags: flags)
            }
        }
        let context = Self.makeContext(callback)
        guard let candidate = withExtendedLifetime(callback, { createStream(context, roots) }) else {
            retry()
            return
        }
        FSEventStreamSetDispatchQueue(candidate, eventQueue)
        guard startStream(candidate) else {
            FSEventStreamInvalidate(candidate)
            FSEventStreamRelease(candidate)
            eventQueue.sync {}
            retry()
            return
        }
        stream = candidate
        retryTimer?.cancel()
        retryTimer = nil
    }

    private func retry() {
        guard retryTimer == nil else { return }
        Log.shell.error("Failed to start shell directory observation; retrying with periodic refreshes")
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            sync(paths: paths)
            onChange()
        }
        retryTimer = timer
        timer.resume()
    }

    private func receive(paths: [String], flags: [FSEventStreamEventFlags]) {
        let rescan = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        guard flags.contains(where: { $0 & rescan != 0 }) || paths.contains(where: {
            let path = $0.hasSuffix("/") && $0 != "/" ? String($0.dropLast()) : $0
            return watchedPaths.contains(path) || watchedPaths.contains((path as NSString).deletingLastPathComponent)
        }) else { return }
        sync(paths: self.paths)
        onChange()
    }

    private static func hasDescriptorBudget(for roots: [String]) -> Bool {
        let estimate = roots.reduce(4) { $0 + URL(fileURLWithPath: $1).pathComponents.count }
        guard estimate <= maximumDescriptorCost else { return false }
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return false }
        var available = 0
        for descriptor in 0 ..< Int32(min(limit.rlim_cur, 1024)) where fcntl(descriptor, F_GETFD) < 0 {
            available += 1
            if available >= estimate + reservedDescriptorCount { return true }
        }
        return false
    }

    private static func directoryRoots(for paths: [URL]) -> [String] {
        let directories = Set(paths.map { url -> String in
            var directory = URL(fileURLWithPath: canonicalPath(url))
            while true {
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
                if exists, isDirectory.boolValue { break }
                let parent = directory.deletingLastPathComponent()
                if parent == directory { break }
                directory = parent
            }
            return canonicalPath(directory)
        })
        var roots: [String] = []
        let sorted = directories.sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        for directory in sorted
            where !roots.contains(where: { directory == $0 || directory.hasPrefix($0 == "/" ? "/" : $0 + "/") })
        {
            roots.append(directory)
        }
        return roots
    }

    private static func canonicalPath(_ url: URL) -> String {
        var ancestor = url
        var missing: [String] = []
        while true {
            if let resolved = try? SettingsFileAccess.canonicalURL(for: ancestor) {
                return missing.reversed().reduce(resolved) { $0.appendingPathComponent($1) }.path
            }
            let parent = ancestor.deletingLastPathComponent()
            if parent == ancestor { return url.path }
            missing.append(ancestor.lastPathComponent)
            ancestor = parent
        }
    }

    private nonisolated static func makeContext(_ callback: Callback) -> FSEventStreamContext {
        FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { UnsafeRawPointer(Unmanaged<Callback>.fromOpaque($0!).retain().toOpaque()) },
            release: { Unmanaged<Callback>.fromOpaque($0!).release() },
            copyDescription: nil
        )
    }

    private nonisolated static func makeStream(context: FSEventStreamContext, paths: [String]) -> FSEventStreamRef? {
        var context = context
        return FSEventStreamCreate(
            nil,
            { _, info, count, eventPaths, eventFlags, _ in
                guard let info else { return }
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
                Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue().onEvents(paths, flags)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagWatchRoot)
        )
    }
}
