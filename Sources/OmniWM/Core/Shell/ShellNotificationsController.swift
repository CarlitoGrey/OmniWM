// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum ShellNotificationsCommand: Equatable, Sendable {
    case refresh
    case open(bundle: String)

    init?(words: [String]) {
        if words == ["refresh"] {
            self = .refresh
        } else if words.count == 2, words[0] == "open", !words[1].isEmpty, words[1].utf8.count <= 255,
                  words[1].utf8.allSatisfy({
                      (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0)
                          || $0 == 45 || $0 == 46 || $0 == 95
                  })
        {
            self = .open(bundle: words[1])
        } else {
            return nil
        }
    }
}

private actor ShellNotificationsWorker {
    let queue = DispatchSerialQueue(label: "com.barut.OmniWM.shell.notifications", qos: .utility)

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    func read(at url: URL) -> ShellNotificationsData {
        ShellNotificationStore.read(at: url)
    }
}

@MainActor
final class ShellNotificationsController {
    typealias Loader = @Sendable (URL) async -> ShellNotificationsData

    private let url: URL
    private let load: Loader
    private var observation: ShellDirectoryObservation?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var pending = false
    private(set) var isListening = false
    private(set) var current = ShellNotificationsData(state: "loading")
    var onChange: (@MainActor (ShellNotificationsData) -> Void)?

    init(url: URL = ShellNotificationStore.defaultURL, load: Loader? = nil) {
        self.url = url
        let worker = ShellNotificationsWorker()
        self.load = load ?? { await worker.read(at: $0) }
    }

    isolated deinit {
        task?.cancel()
        observation?.cancel()
    }

    func setListening(_ listening: Bool) {
        guard listening != isListening else { return }
        isListening = listening
        generation &+= 1
        pending = false
        task?.cancel()
        task = nil
        if listening {
            observation = ShellDirectoryObservation { [weak self] in self?.refresh() }
            refresh()
        } else {
            observation?.cancel()
            observation = nil
            current = ShellNotificationsData(state: "loading")
        }
    }

    func refresh() {
        guard isListening else { return }
        let directory = url.deletingLastPathComponent()
        observation?.sync(paths: [
            directory.deletingLastPathComponent(),
            directory,
            url,
            URL(fileURLWithPath: url.path + "-wal")
        ])
        guard task == nil else {
            pending = true
            return
        }
        let generation = self.generation
        task = Task { [weak self, load, url] in
            let next = await load(url)
            guard !Task.isCancelled, let self, isListening, self.generation == generation else { return }
            task = nil
            if current != next {
                current = next
                onChange?(next)
            }
            if pending {
                pending = false
                refresh()
            }
        }
    }
}
