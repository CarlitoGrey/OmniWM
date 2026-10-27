// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct ShellLyricsTrack: Hashable, Sendable {
    var title: String
    var artist: String
    var album = ""
    var duration: Int?
}

extension ShellLyricsTrack {
    init?(_ media: ShellMedia) {
        let title = media.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        self.title = title
        artist = media.artist.trimmingCharacters(in: .whitespaces)
        album = media.album
        duration = media.duration.flatMap { $0 > 0 && $0 < Double(Int32.max) ? Int($0.rounded()) : nil }
    }
}

struct ShellLyrics: Equatable, Sendable, ShellValueWritable {
    enum Status: String, Sendable {
        case loading
        case synced
        case missing = "none"
    }

    struct Line: Equatable, Sendable {
        var time: Double
        var text: String
    }

    static let loading = ShellLyrics(status: .loading)
    static let missing = ShellLyrics(status: .missing)

    var status: Status
    var access = ShellServiceAccess.ok
    var lines: [Line] = []

    init(status: Status, lines: [Line] = [], access: ShellServiceAccess = .ok) {
        self.status = status
        self.lines = lines
        self.access = access
    }

    init(lrc: String) {
        lines = Self.lines(lrc)
        status = lines.isEmpty ? .missing : .synced
    }

    func write(into writer: inout ShellValueWriter) {
        writer.map(3)
        writer.key("access")
        writer.string(access.rawValue)
        writer.key("status")
        writer.string(status.rawValue)
        writer.key("lines")
        writer.array(lines.count)
        for line in lines {
            writer.map(2)
            writer.key("time")
            writer.number(line.time)
            writer.key("text")
            writer.string(line.text)
        }
    }

    static func lines(_ lrc: String) -> [Line] {
        var lines: [Line] = []
        for row in lrc.split(whereSeparator: \.isNewline) {
            var rest = row[...]
            var times: [Double] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]"),
                  let time = time(rest[rest.index(after: rest.startIndex) ..< close])
            {
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Line(time: $0, text: text) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.first?.isNumber == true }),
              let minutes = Int(parts[0]), let seconds = Double(parts[1]), seconds.isFinite
        else {
            return nil
        }
        return Double(minutes) * 60 + seconds
    }
}

enum ShellLyricsClient {
    static func request(for track: ShellLyricsTrack) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/get"
        var query = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        if !track.album.isEmpty {
            query.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if let duration = track.duration {
            query.append(URLQueryItem(name: "duration", value: String(duration)))
        }
        components.queryItems = query
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("OmniWM (https://github.com/OmniNull/OmniWM)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func lyrics(
        _ track: ShellLyricsTrack,
        permissions: ShellNetworkPermissions,
        protocolClasses: [AnyClass]? = nil
    ) async throws -> ShellLyrics {
        guard let request = request(for: track) else { throw URLError(.badURL) }
        let (data, response) = try await ShellBuiltInHTTPClient.load(
            request, service: .lyrics, permissions: permissions, protocolClasses: protocolClasses
        )
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try lyrics(from: data)
        case 404: return .missing
        default: throw URLError(.badServerResponse)
        }
    }

    static func lyrics(from data: Data) throws -> ShellLyrics {
        try ShellLyrics(lrc: JSONDecoder().decode(LyricsRecord.self, from: data).syncedLyrics ?? "")
    }
}

private struct LyricsRecord: Decodable {
    let syncedLyrics: String?
}

@MainActor
final class LyricsController {
    private static let cacheLimit = 64

    private let load: (@Sendable (ShellLyricsTrack) async throws -> ShellLyrics)?
    private var permissions: ShellNetworkPermissions
    private var cache: [ShellLyricsTrack: ShellLyrics] = [:]
    private var track: ShellLyricsTrack?
    private(set) var task: Task<Void, Never>?
    private(set) var lyrics: ShellLyrics?
    var onLoad: ((ShellLyrics) -> Void)?

    init(
        load: (@Sendable (ShellLyricsTrack) async throws -> ShellLyrics)? = nil,
        permissions: ShellNetworkPermissions = ShellNetworkPermissions()
    ) {
        self.load = load
        self.permissions = permissions
    }

    func setPermissions(_ permissions: ShellNetworkPermissions) {
        self.permissions = permissions
    }

    func invalidate() {
        task?.cancel()
        task = nil
        track = nil
        lyrics = nil
        cache.removeAll(keepingCapacity: true)
    }

    func show(_ next: ShellLyricsTrack?) {
        let access = permissions.access(.lyrics)
        guard access == .ok else {
            invalidate()
            lyrics = ShellLyrics(status: .missing, access: access)
            return
        }
        guard next != track else { return }
        task?.cancel()
        task = nil
        track = next
        guard let next else {
            lyrics = nil
            return
        }
        if let cached = cache[next] {
            lyrics = cached
            return
        }
        lyrics = .loading
        task = Task { [weak self, load, permissions] in
            let result: ShellLyrics?
            do {
                if let load { result = try await load(next) }
                else { result = try await ShellLyricsClient.lyrics(next, permissions: permissions) }
            } catch {
                if !Task.isCancelled {
                    Log.shell.error("Lyrics did not load: \(error.localizedDescription)")
                }
                result = nil
            }
            guard !Task.isCancelled, permissions.access(.lyrics) == .ok else { return }
            self?.finish(next, result)
        }
    }

    private func finish(_ loaded: ShellLyricsTrack, _ result: ShellLyrics?) {
        guard loaded == track else { return }
        task = nil
        if let result {
            if cache.count >= Self.cacheLimit {
                cache.removeAll(keepingCapacity: true)
            }
            cache[loaded] = result
        }
        let lyrics = result ?? .missing
        self.lyrics = lyrics
        onLoad?(lyrics)
    }
}
