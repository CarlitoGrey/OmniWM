// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct ShellEditorDraft: Equatable, Identifiable {
    struct Key: Hashable {
        let widget: String
        let option: String

        static let weather = Key(widget: "", option: "weather")

        static func component(_ id: String, option: String) -> Key {
            Key(widget: "island:" + id, option: option)
        }

        static func islandRoot(_ root: String, option: String) -> Key {
            Key(widget: "island-root:" + root, option: option)
        }

        var component: String? {
            widget.hasPrefix("island:") ? String(widget.dropFirst("island:".count)) : nil
        }

        var islandRoot: String? {
            widget.hasPrefix("island-root:") ? String(widget.dropFirst("island-root:".count)) : nil
        }
    }

    struct Weather: Equatable {
        var city = ""
        var coordinates = false
        var latitude = 0.0
        var longitude = 0.0
        var fahrenheit = false
        var refreshMinutes = 15.0

        init(_ location: ShellWeatherLocation?) {
            guard let location else { return }
            switch location.place {
            case let .city(name): city = name
            case let .coordinates(lat, lon):
                coordinates = true
                latitude = lat
                longitude = lon
            }
            fahrenheit = location.fahrenheit
            refreshMinutes = Double(location.refresh.components.seconds) / 60
        }

        var valid: Bool {
            coordinates
                ? latitude.isFinite && longitude.isFinite && (-90 ... 90).contains(latitude)
                && (-180 ... 180).contains(longitude)
                : !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var stored: StoredWeather {
            StoredWeather(
                city: coordinates ? nil : city.trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: coordinates ? latitude : nil,
                longitude: coordinates ? longitude : nil,
                units: fahrenheit ? "fahrenheit" : "celsius",
                refresh: refreshMinutes
            )
        }
    }

    struct StoredWeather: Encodable {
        let city: String?
        let latitude: Double?
        let longitude: Double?
        let units: String
        let refresh: Double
    }

    enum Value: Equatable {
        case clocks([ShellWorldClockEntry])
        case weather(Weather)
        case text(String)
        case lines([String])

        func matches(_ other: Value) -> Bool {
            switch (self, other) {
            case let (.clocks(lhs), .clocks(rhs)):
                lhs.map { [$0.label, $0.zone] } == rhs.map { [$0.label, $0.zone] }
            default: self == other
            }
        }

        var valid: Bool {
            switch self {
            case let .clocks(clocks): ShellWidgetSettingsModel.validClocks(clocks)
            case let .weather(weather): weather.valid
            case .text,
                 .lines: true
            }
        }
    }

    let id = UUID()
    let key: Key
    let profile: String
    var original: Value
    var value: Value
    var saving = false
    var error: String?

    var dirty: Bool {
        value != original
    }
}
