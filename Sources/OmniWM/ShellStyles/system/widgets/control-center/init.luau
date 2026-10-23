-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local style = require("../lib/style")
local audio = require("../lib/audio")
local media = require("../lib/media")
local calendar = require("../lib/calendar")
local weather = require("../lib/weather")
local HOVER = style.hover
local CONTENT = style.width
local INNER = CONTENT - 24
local TABS = {
    { id = "overview", symbol = "square.grid.2x2", label = omniwm.l10n("Control Center") },
    { id = "audio", symbol = "speaker.wave.2.fill", label = omniwm.l10n("Audio") },
    { id = "media", symbol = "music.note", label = omniwm.l10n("Media") },
    { id = "calendar", symbol = "calendar", label = omniwm.l10n("Calendar") },
    { id = "weather", symbol = "cloud.sun.fill", label = omniwm.l10n("Weather") },
    { id = "system", symbol = "gauge.with.needle", label = omniwm.l10n("System") },
}

local function card(props)
    props.w = CONTENT
    return style.group(props)
end

local function calendarTab(ctx)
    return calendar.content(ctx, CONTENT)
end

local function weatherTab(ctx)
    return weather.content(ctx, true, CONTENT)
end

local function gauge(ctx, label: string, value: number?)
    local width = (INNER - 36) / 4
    return ui.column{ w = width, gap = 6,
        ui.text{ text = if value then ctx.format.percent(value / 100) else "—", size = 17, weight = "medium" },
        ui.progress{ value = (value or 0) / 100, w = width, h = 4, radius = 2, fill = "foreground/0.08",
            color = if value and value >= 90 then "warning" else "accent" },
        ui.text{ text = label, size = 11, color = "secondaryForeground" } }
end

local function systemTab(ctx)
    local data = ctx.data
    local rows = { gap = 8,
        card{ ui.row{ w = INNER, gap = 12,
            gauge(ctx, omniwm.l10n("CPU"), data.cpu),
            gauge(ctx, omniwm.l10n("GPU"), data.gpu),
            gauge(ctx, omniwm.l10n("Memory"), data.memory),
            gauge(ctx, omniwm.l10n("Disk"), data.disk) } } }
    local facts = { gap = 6 }
    local system = data.system
    if system then
        facts[#facts + 1] = ui.row{ w = INNER, gap = 10,
            ui.symbol{ name = "applelogo", w = 18, h = 18 },
            ui.column{ gap = 1, center = false,
                ui.text{ text = system.host.name, size = 13, weight = "semibold", maxWidth = INNER - 30 },
                ui.text{ text = system.host.chip .. " · " .. system.host.os, size = 11,
                    color = "secondaryForeground", maxWidth = INNER - 30 } } }
    end
    if data.network then
        facts[#facts + 1] = ui.row{ w = INNER, gap = 6,
            ui.symbol{ name = "arrow.down", w = 12, h = 12, color = "secondaryForeground" },
            ui.text{ text = ctx.format.bytes(data.network.down, "file") .. "/s", style = "mono", size = 11,
                reserve = "000.0 MB/s" },
            ui.box{ grow = 1 },
            ui.symbol{ name = "arrow.up", w = 12, h = 12, color = "secondaryForeground" },
            ui.text{ text = ctx.format.bytes(data.network.up, "file") .. "/s", style = "mono", size = 11,
                reserve = "000.0 MB/s" } }
    end
    if #facts > 0 then
        rows[#rows + 1] = card(facts)
    end
    return ui.column(rows)
end

local function connection(name: string, text: string, glyph, command: string)
    return style.group{ w = (CONTENT - 12) / 2, gap = 6, hover = HOVER, onClick = command,
        ui.row{ gap = 6,
            glyph,
            ui.text{ text = name, size = 13, weight = "semibold" } },
        ui.text{ text = text, size = 11, color = "secondaryForeground", maxWidth = (CONTENT - 12) / 2 - 24 } }
end

local function overview(ctx)
    local wifi = ctx.data.wifi
    local bluetooth = ctx.data.bluetooth
    local wireless = if not wifi then omniwm.l10n("Unavailable") elseif not wifi.power then omniwm.l10n("Off")
        elseif wifi.ssid then wifi.ssid elseif wifi.connected then omniwm.l10n("Connected")
        else omniwm.l10n("Not Connected")
    local connected = 0
    for _, device in if bluetooth then bluetooth.devices or {} else {} do
        if device.connected then
            connected += 1
        end
    end
    local bluetoothState = if not bluetooth then omniwm.l10n("Unavailable")
        elseif bluetooth.access ~= "granted" then omniwm.l10n("Allow Access")
        elseif not bluetooth.power then omniwm.l10n("Off")
        elseif connected > 0 then tostring(connected) .. " · " .. omniwm.l10n("Connected") else omniwm.l10n("On")
    local rows = { w = CONTENT, gap = 12, center = false,
        ui.row{ gap = 12,
            connection(omniwm.l10n("Wi-Fi"), wireless,
                ui.symbol{ name = if wifi and wifi.power then "wifi" else "wifi.slash", w = 16, h = 16,
                    color = if wifi and wifi.connected then "accent" else "secondaryForeground" }, "wifi settings"),
            connection(omniwm.l10n("Bluetooth"), bluetoothState,
                ui.path{ w = 16, h = 16, viewBox = { 0, 0, 24, 24 },
                    d = "M7 7.5 L17 16.5 L12 21 L12 3 L17 7.5 L7 16.5", borderWidth = 2.2,
                    border = if bluetooth and bluetooth.power then "accent" else "secondaryForeground" },
                if bluetooth and bluetooth.access ~= "granted" then "bluetooth authorize" else "bluetooth settings") },
        audio.level(ctx),
        media.content(ctx, true) }
    local level = ctx.data.battery
    if level then
        local power = ctx.data.power or {}
        rows[#rows + 1] = card{ hover = HOVER, onClick = "battery settings",
            ui.row{ w = INNER, gap = 8,
                ui.symbol{ name = style.batterySymbol(level, ctx.data.charging),
                    w = 22, h = 16 },
                ui.text{ text = omniwm.l10n("Battery"), size = 13, grow = 1 },
                ui.text{ text = ctx.format.percent(level / 100), size = 13 },
                ui.symbol{ name = "chevron.right", w = 10, h = 10, color = "secondaryForeground" } },
            ui.text{ text = if power.charged then omniwm.l10n("Fully charged")
                elseif ctx.data.charging then omniwm.l10n("Charging")
                elseif power.source == "ac" then omniwm.l10n("Power Adapter") else omniwm.l10n("On battery"),
                size = 11, color = "secondaryForeground" } }
    end
    return ui.column(rows)
end

local SECTIONS = {
    overview = overview, audio = audio.content, media = media.content, calendar = calendarTab,
    weather = weatherTab, system = systemTab,
}

local function selected(ctx): string
    local tab = ctx.state.tab or (ctx.data.settings or {}).tab
    return if SECTIONS[tab] then tab else "overview"
end

function render(ctx: Context)
    return style.bar(ctx, { onClick = ui.popout, help = omniwm.l10n("Control Center"),
        ui.symbol{ name = "switch.2", size = 14 * style.scale(ctx) } })
end

function popout(ctx: Context)
    local current = selected(ctx)
    local tabs = { w = CONTENT, gap = 4 }
    local title = omniwm.l10n("Control Center")
    for _, tab in TABS do
        local active = tab.id == current
        if active then
            title = tab.label
        end
        tabs[#tabs + 1] = style.button(tab.symbol, function(state)
            state.state.tab = tab.id
        end, { w = (CONTENT - 20) / 6, h = 30, help = tab.label,
            fill = if active then "foreground/0.10" else nil })
    end
    return style.panel{ w = CONTENT + 28,
        style.heading(title),
        ui.row(tabs),
        SECTIONS[current](ctx) }
end
