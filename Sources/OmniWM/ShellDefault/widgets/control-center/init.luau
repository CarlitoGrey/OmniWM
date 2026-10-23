-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local audio = require("../lib/audio")
local media = require("../lib/media")
local calendar = require("../lib/calendar")
local weather = require("../lib/weather")

local HOVER = "foreground/0.12"
local WIDTH = 340
local CONTENT = WIDTH - 24
local INNER = CONTENT - 20
local RING = "M12 2.5 A9.5 9.5 0 1 1 12 21.5 A9.5 9.5 0 1 1 12 2.5"
local TABS = {
    { id = "audio", symbol = "speaker.wave.2.fill", label = omniwm.l10n("Audio") },
    { id = "media", symbol = "music.note", label = omniwm.l10n("Media") },
    { id = "calendar", symbol = "calendar", label = omniwm.l10n("Calendar") },
    { id = "weather", symbol = "cloud.sun.fill", label = omniwm.l10n("Weather") },
    { id = "system", symbol = "gauge.with.needle", label = omniwm.l10n("System") },
}

local function card(props)
    props.w = CONTENT
    props.pad = 10
    props.radius = 12
    props.fill = "surface"
    props.gap = props.gap or 6
    props.center = false
    return ui.column(props)
end

local function calendarTab(ctx)
    return calendar.content(ctx, CONTENT)
end

local function weatherTab(ctx)
    return weather.content(ctx, true, CONTENT)
end

local function arc(fraction: number): string
    if fraction >= 0.999 then
        return RING
    end
    local angle = fraction * 2 * math.pi
    return string.format("M12 2.5 A9.5 9.5 0 %d 1 %.2f %.2f", if angle > math.pi then 1 else 0,
        12 + 9.5 * math.sin(angle), 12 - 9.5 * math.cos(angle))
end

local function gauge(ctx, label: string, value: number?, tint: string)
    local size = 54
    local ring = { w = size, h = size,
        ui.path{ w = size, h = size, viewBox = { 0, 0, 24, 24 }, d = RING, border = "foreground/0.14",
            borderWidth = 2.4 } }
    if value and value > 0.5 then
        ring[#ring + 1] = ui.path{ w = size, h = size, viewBox = { 0, 0, 24, 24 }, d = arc(value / 100),
            border = if value >= 90 then "warning" else tint, borderWidth = 2.4 }
    end
    ring[#ring + 1] = ui.text{ text = if value then ctx.format.percent(value / 100) else "—", style = "rounded",
        size = 12, weight = "semibold" }
    return ui.column{ w = INNER / 4, gap = 5,
        ui.stack(ring),
        ui.text{ text = label, size = 11, weight = "medium", color = "secondaryForeground" } }
end

local function systemTab(ctx)
    local data = ctx.data
    local rows = { gap = 8,
        card{ ui.row{ w = INNER, gap = 0,
            gauge(ctx, omniwm.l10n("CPU"), data.cpu, "accent"),
            gauge(ctx, omniwm.l10n("GPU"), data.gpu, "accent"),
            gauge(ctx, omniwm.l10n("Memory"), data.memory, "accent"),
            gauge(ctx, omniwm.l10n("Disk"), data.disk, "accent") } } }
    local facts = { gap = 6 }
    local system = data.system
    if system then
        facts[#facts + 1] = ui.row{ w = INNER, gap = 10,
            ui.symbol{ name = "applelogo", w = 18, h = 18 },
            ui.column{ gap = 1, center = false,
                ui.text{ text = system.host.name, weight = "semibold", maxWidth = INNER - 30 },
                ui.text{ text = system.host.chip .. " · " .. system.host.os, style = "small",
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

local function audioTab(ctx)
    return audio.content(ctx, CONTENT)
end

local function mediaTab(ctx)
    return media.content(ctx, false, CONTENT)
end

local SECTIONS = { audio = audioTab, media = mediaTab, calendar = calendarTab, weather = weatherTab, system = systemTab }

local function selected(ctx): string
    local tab = ctx.state.tab or (ctx.data.settings or {}).tab
    return if SECTIONS[tab] then tab else "audio"
end

function render(ctx: Context)
    local style = ctx.data.bar.style
    local size = math.max(16, style.height - 4)
    local capsule = style.transparent and style.backgrounds
    return ui.stack{ w = size, h = size, radius = if capsule then size / 2 else 4,
        fill = if capsule then "surface" else nil, border = if capsule then "border" else nil, borderWidth = 0.5,
        hover = HOVER, onClick = ui.popout, help = omniwm.l10n("Control Center"),
        ui.symbol{ name = "switch.2", size = math.max(11, size * 0.46), weight = "semibold",
            color = if capsule then "accent" else "foreground" } }
end

function popout(ctx: Context)
    local style = ctx.data.bar.style
    local current = selected(ctx)
    local tabs = { w = CONTENT, gap = 4 }
    for _, tab in TABS do
        local active = tab.id == current
        tabs[#tabs + 1] = ui.column{ w = (CONTENT - 16) / 5, h = 46, gap = 4, radius = 10,
            fill = if active then "accent/0.16" else nil, hover = HOVER,
            onClick = function(state)
                state.state.tab = tab.id
            end,
            ui.symbol{ name = tab.symbol, w = 16, h = 16, color = if active then "accent" else "secondaryForeground" },
            ui.text{ text = tab.label, size = 10, weight = if active then "semibold" else "medium",
                color = if active then "accent" else "secondaryForeground", maxWidth = (CONTENT - 20) / 5 } }
    end
    local root = { w = WIDTH, pad = 12, gap = 10, center = false,
        ui.row(tabs),
        SECTIONS[current](ctx) }
    if style.transparent and style.backgrounds then
        root.material = "clear"
        root.attach = true
        root.fill = "background"
        root.border = "border"
        root.borderWidth = 1
        root.radius = 16
    end
    return ui.column(root)
end
