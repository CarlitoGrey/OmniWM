-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local panel = require("./panel")
local panelFrame = require("./panel-frame")

local function line(vertical, props)
    return vertical and ui.column(props) or ui.row(props)
end

local function spacer(vertical, length)
    return vertical and ui.box{ w = 1, h = length } or ui.box{ w = length, h = 1 }
end

local function badge(text, size, fill, color, align, dx, dy)
    return ui.row{ align = align, dx = dx, dy = dy, h = size, radius = size / 2, fill = fill,
        border = "surface", borderWidth = 1,
        ui.box{ w = 2.5, h = 1 },
        ui.text{ text = text, style = "mono", size = size - 3, weight = "bold", color = color },
        ui.box{ w = 2.5, h = 1 } }
end

local function statsPanel(ctx, props)
    local style = ctx.data.bar.style
    local attached = not style.vertical
    local width = props.w
    props.center = true
    for _, index in { 1, #props } do
        local section = props[index]
        section.dy = (section.dy or 0) + (index == 1 and -4 or 4)
        props[index] = ui.stack{ section }
    end
    local body = { w = width - (attached and panelFrame.shoulder * 2 or 8), gap = 0,
        radius = panelFrame.corner, fill = "background", border = "border", borderWidth = 1, ui.column(props) }
    local edge
    if attached then
        local flip = style.position == "bottom"
        local band = ui.box{ w = body.w, h = panelFrame.shoulder }
        if flip then
            body[#body + 1] = band
        else
            table.insert(body, 1, band)
        end
        edge = panelFrame.edge(body.w, flip, true)
        edge.align = flip and "bottom" or "top"
    end
    return ui.stack{ w = width, material = "clear", attach = attached or nil, ui.column(body), edge }
end

local function statsCircle(size, stroke)
    local c = size / 2
    local r = c - stroke / 2
    return string.format("M%g %g A%g %g 0 1 1 %g %g A%g %g 0 1 1 %g %g", c, c - r, r, r, c, c + r, r, r, c, c - r)
end

local function statsArc(size, stroke, value)
    if not value or value <= 0.001 then
        return nil
    end
    if value >= 0.999 then
        return statsCircle(size, stroke)
    end
    local c = size / 2
    local r = c - stroke / 2
    local angle = (value * 2 - 0.5) * math.pi
    return string.format("M%g %g A%g %g 0 %d 1 %.2f %.2f", c, c - r, r, r, value > 0.5 and 1 or 0,
        c + r * math.cos(angle), c + r * math.sin(angle))
end

local function statsCard(props)
    props.radius, props.fill, props.border, props.borderWidth = 14, "surface", "border", 1
    if props.center == nil then
        props.center = false
    end
    return ui.column(props)
end

local function statsGauge(metric, width, tint)
    local size, stroke = 64, 6
    local path = statsArc(size, stroke, metric.value)
    local color = if metric.warn or metric.hot then "warning" else tint
    local contents = { w = width, pad = 12, gap = 8,
        ui.stack{ w = size, h = size,
            ui.path{ w = size, h = size, d = statsCircle(size, stroke), border = tint .. "/0.16", borderWidth = stroke },
            ui.text{ text = metric.percent, size = 14, weight = "bold" },
            if path then ui.path{ w = size, h = size, d = path, border = color, borderWidth = stroke } else nil },
        ui.row{ gap = 5,
            ui.symbol{ name = metric.symbol, size = 10, weight = "semibold", color = tint },
            ui.text{ text = metric.title, size = 14, weight = "bold" } } }
    if metric.temperatureText then
        contents[#contents + 1] = ui.text{ text = metric.temperatureText, style = "mono", size = 12,
            color = if metric.hot then "warning" else "secondaryForeground" }
    end
    contents[#contents + 1] = ui.text{ text = metric.detail, size = 12, color = "secondaryForeground",
        maxWidth = width - 24, lines = 2 }
    contents.center = true
    return statsCard(contents)
end

local function statsBar(metric, width, tint)
    return ui.column{ w = width, gap = 5, center = false,
        ui.row{ w = width, gap = 8,
            ui.stack{ w = 24, h = 24, radius = 12, fill = tint .. "/0.18",
                ui.symbol{ name = metric.symbol, size = 11, weight = "semibold", color = tint } },
            ui.column{ gap = 1, center = false, grow = 1,
                ui.text{ text = metric.title, size = 14, weight = "bold" },
                ui.text{ text = metric.detail, size = 12, color = "secondaryForeground", maxWidth = width - 90, lines = 2 } },
            ui.text{ text = metric.percent, size = 14, weight = "bold" } },
        ui.progress{ value = metric.value or 0, w = width, h = 6, radius = 3, fill = tint .. "/0.16",
            color = if metric.warn then "warning" else tint, animate = "ease" } }
end

local function statsHeader(m, width)
    local host = m.host
    return ui.row{ w = width, gap = 10,
        ui.stack{ w = 34, h = 34, radius = 17, fill = "accent",
            ui.symbol{ name = "applelogo", size = 16, weight = "semibold", color = "accentForeground" } },
        ui.column{ gap = 1, center = false, grow = 1,
            ui.text{ text = host and host.name or omniwm.l10n("System"), size = 14, weight = "bold", maxWidth = width - 170 },
            ui.text{ text = host and host.chip or omniwm.l10n("Loading…"), size = 12, color = "secondaryForeground",
                maxWidth = width - 170 } },
        ui.row{ h = 22, gap = 4, radius = 11, fill = "blue/0.2",
            ui.box{ w = 4, h = 1 },
            ui.symbol{ name = "clock.arrow.circlepath", size = 10, weight = "semibold", color = "blue" },
            ui.text{ text = host and host.uptime or "—", style = "mono", size = 12, weight = "semibold", color = "blue" },
            ui.box{ w = 5, h = 1 } } }
end

local function statsLine(symbol, label, value, width, tint)
    return ui.row{ w = width, gap = 8,
        ui.stack{ w = 24, h = 24, radius = 12, fill = tint .. "/0.18",
            ui.symbol{ name = symbol, size = 11, weight = "semibold", color = tint } },
        ui.text{ text = label, size = 12, color = "secondaryForeground", grow = 1 },
        ui.text{ text = value, style = "mono", size = 12, weight = "semibold", maxWidth = width - 105 } }
end

local function statsNetwork(m, width)
    local inner, height = width - 20, 48
    local graph = { w = inner, h = height }
    if m.network.graph then
        local down, up = m.network.graph(inner, height)
        graph[#graph + 1] = ui.path{ w = inner, h = height, d = down, border = "cyan", borderWidth = 2 }
        graph[#graph + 1] = ui.path{ w = inner, h = height, d = up, border = "purple", borderWidth = 2 }
    else
        graph[#graph + 1] = ui.text{ text = omniwm.l10n("Collecting data…"), size = 12, color = "secondaryForeground" }
    end
    return statsCard{ w = width, pad = 10, gap = 8,
        ui.row{ gap = 5,
            ui.symbol{ name = "network", size = 11, weight = "semibold", color = "cyan" },
            ui.text{ text = omniwm.l10n("Network"), size = 14, weight = "bold" } },
        ui.stack(graph),
        statsLine("arrow.down", omniwm.l10n("Download"), m.network.down, inner, "cyan"),
        statsLine("arrow.up", omniwm.l10n("Upload"), m.network.up, inner, "purple"),
        statsLine("arrow.up.arrow.down", omniwm.l10n("Total"), m.network.total, inner, "blue") }
end

local function statsBattery(m, width)
    local battery = m.battery
    local tint = if battery.low then "warning" else "green"
    return statsCard{ w = width, pad = 10, gap = 6,
        statsLine(battery.symbol, omniwm.l10n("Battery"), battery.percent, width - 20, tint),
        ui.progress{ value = battery.level, w = width - 20, h = 6, radius = 3, fill = tint .. "/0.16", color = tint },
        ui.text{ text = battery.status, size = 12, color = "secondaryForeground", maxWidth = width - 20 } }
end

local function statsDetails(m, width)
    if not m.host then
        return statsCard{ w = width, pad = 10,
            ui.text{ text = omniwm.l10n("Loading…"), size = 12, color = "secondaryForeground" } }
    end
    return statsCard{ w = width, pad = 10, gap = 6,
        ui.row{ gap = 8,
            ui.symbol{ name = "laptopcomputer", w = 16, h = 14, size = 12, color = "secondaryForeground" },
            ui.text{ text = m.host.model .. " · " .. m.host.os, size = 12, weight = "medium", maxWidth = width - 44, lines = 2 } },
        ui.row{ gap = 8,
            ui.symbol{ name = "display.2", w = 16, h = 14, size = 12, color = "secondaryForeground" },
            ui.text{ text = table.concat(m.displays, "  ·  "), size = 12, color = "secondaryForeground",
                maxWidth = width - 44, lines = 2 } } }
end

return require("./skin")({
    base = 40,
    hover = "focus/0.14",
    width = 300,
    widths = { workspaces = 274, ["system-stats"] = 380 },
    size = { text = 14, icon = 24, slot = 27 },
    omniwmButton = function(ctx, glyph)
        local style = ctx.data.bar.style
        local scale = style.height / 40
        local size = 32 * scale
        glyph.size = 24 * scale
        return { w = size, h = size, radius = size / 2,
            fill = style.backgrounds and "accent/0.18" or nil, hoverScale = 1.06 }, size
    end,
    systemStatsButton = function(ctx, glyph)
        local style = ctx.data.bar.style
        local size = 32 * style.height / 40
        glyph.size, glyph.weight, glyph.color = math.max(11, size * 0.5), "semibold", "foreground"
        return { w = size, h = size, radius = size / 2 - 1,
            fill = style.backgrounds and "surface" or nil, border = style.backgrounds and "border/0.6" or nil,
            borderWidth = 1, hover = "focus/0.14" }
    end,
    systemStatsSection = function(ctx, kind, m, width)
        if not ctx.data.bar.style.vertical then
            width -= 20
        end
        if kind == "header" then
            return statsHeader(m, width)
        elseif kind == "metrics" then
            local half = (width - 10) / 2
            return ui.column{ w = width, gap = 10, center = false,
                ui.row{ w = width, gap = 10, statsGauge(m.cpu, half, "cyan"), statsGauge(m.gpu, half, "purple") },
                statsCard{ w = width, pad = 10, gap = 12,
                    statsBar(m.memory, width - 20, "green"), statsBar(m.disk, width - 20, "orange") } }
        elseif kind == "network" then
            return statsNetwork(m, width)
        elseif kind == "battery" then
            return statsBattery(m, width)
        elseif kind == "details" then
            return statsDetails(m, width)
        end
        return nil
    end,
    systemStatsPanel = statsPanel,
    hiddenMenuPanel = function(_, rows)
        rows.radius, rows.material, rows.fill = 18, "clear", "background"
        rows.border, rows.borderWidth, rows.center = "border", 1, false
        return ui.column(rows)
    end,
    panel = function(ctx, props)
        local width = props.w or 300
        props.w = width - 2
        props.pad = props.pad or 12
        props.gap = props.gap or 10
        props.center = false
        return panel(ctx.data.bar.style, width, ui.column(props))
    end,
    list = function(props)
        props.center = false
        props.gap = props.gap or 2
        props.divided = nil
        return ui.column(props)
    end,
    workspaceMetrics = function(_, style, m)
        return { item = if m.indicator == "pills" then 32 * m.scale else m.item, chip = 24 * m.scale }
    end,
    workspaceMarker = function(_, workspace, style, m)
        if m.indicator ~= "pills" or (m.compact and not style.labels) then
            return nil
        end
        local focused = workspace.focused
        local fill = if focused then (if style.accents then "accent" else "foreground") else "elevatedSurface"
        local color = if focused then (if style.accents then "accentForeground" else "background") else "secondaryForeground"
        if not style.backgrounds and not (focused and style.accents) then
            fill = nil
            color = if focused then "foreground" else color
        end
        local label = ui.text{ text = workspace.name, size = 14 * m.scale, weight = "bold",
            color = if style.textColor ~= nil then "foreground" else color,
            maxWidth = if m.vertical then m.chip - 4 else 96 }
        if utf8.len(workspace.name) <= 2 then
            local length = if focused then m.item else m.chip
            return ui.stack{ w = if m.vertical then m.chip else length,
                h = if m.vertical then length else m.chip, radius = m.chip / 2, fill = fill, label }
        end
        return line(m.vertical, { radius = m.chip / 2, fill = fill,
            w = if m.vertical then m.chip else nil, h = if m.vertical then nil else m.chip,
            spacer(m.vertical, 7), label, spacer(m.vertical, 7) })
    end,
    workspacePill = function(pill, workspace, style, m, occupied)
        if m.indicator ~= "pills" then
            return
        end
        pill.gap = 3
        pill.radius = m.item / 2 - 1
        if not (m.occupiedBackground and occupied and not workspace.focused) then
            pill.fill = if style.backgrounds then "surface" else nil
        end
        pill.hover = "focus/0.14"
        pill.border = if style.backgrounds then "border/0.6" else nil
        pill.borderWidth = 1
    end,
    windowIcon = function(icon, _, item, style, m)
        icon.radius = 6
        icon.hoverScale = 1.08
        if item.focused then
            icon[#icon + 1] = ui.box{ align = if m.vertical then "trailing" else "bottom",
                dx = if m.vertical then 3 else 0, dy = if m.vertical then 0 else 1.5,
                w = if m.vertical then 2 else 8, h = if m.vertical then 8 else 2, radius = 1,
                fill = if style.accents then "accent" else "foreground" }
        end
    end,
    countBadge = function(text, m)
        return badge(text, math.max(11, m.icon * 0.55), "elevatedSurface", "foreground", "bottomTrailing", 3, 1)
    end,
    notificationBadge = function(item, mode, m)
        if mode == "dot" then
            return ui.box{ align = "topTrailing", dx = 1, dy = -1, w = 7, h = 7, radius = 3.5,
                fill = "badge", border = "surface", borderWidth = 1 }
        end
        return badge(item.badge, math.max(11, m.icon * 0.55), "badge", "background", "topTrailing", 3, -2)
    end,
    hiddenIndicator = function(item, m)
        local full = item.count > 0 and item.hidden == item.count
        local size = math.max(10, m.icon * 0.52)
        return ui.stack{ align = "bottomLeading", dx = -1, dy = 1, w = size, h = size, radius = size / 2,
            fill = if full then "badge" else "elevatedSurface", border = "surface", borderWidth = 1,
            ui.symbol{ name = if full then "eye.slash.fill" else "eye.slash", size = size * 0.55,
                weight = "bold", color = if full then "background" else "badge" } }
    end,
    floatingGroup = function(icons, style, m)
        local symbol = math.max(9, m.icon * 0.5)
        local group = { gap = 2, radius = m.slot / 2,
            w = if m.vertical then m.slot else nil, h = if m.vertical then nil else m.slot,
            fill = if style.backgrounds then "elevatedSurface" else nil,
            spacer(m.vertical, 3),
            ui.symbol{ name = "rectangle.on.rectangle", size = symbol, w = symbol, h = symbol, weight = "semibold",
                color = if style.textColor ~= nil then "foreground" else "mutedForeground" } }
        for _, icon in ipairs(icons) do
            group[#group + 1] = icon
        end
        group[#group + 1] = spacer(m.vertical, 1)
        return line(m.vertical, group), 4 + symbol + #icons * m.slot + (#icons + 2) * 2
    end,
    pickerHeader = function(header, item)
        header[1].weight = "bold"
        header[1].maxWidth = 150
        table.insert(header, 1, ui.icon{ app = item.bundle, w = 22, h = 22, placeholder = "app.dashed" })
        table.insert(header, 3, ui.row{ h = 18, radius = 9, fill = "blue/0.2",
            ui.box{ w = 7, h = 1 },
            ui.text{ text = tostring(item.count), size = 11, weight = "bold", color = "blue" },
            ui.box{ w = 7, h = 1 } })
    end,
    pickerRow = function(row, window)
        row.gap = 8
        row.radius = 10
        row.fill = if window.focused then "surface" else nil
        row.border = if window.focused then "border" else nil
        row.borderWidth = 1
        row[1].size = 14
        row[1].weight = if window.focused then "semibold" else nil
        row[1].maxWidth -= 22
        table.insert(row, 1, ui.box{ w = 6, h = 6, radius = 3,
            fill = if window.focused then "accent" else "mutedForeground/0.5" })
    end,
    scratchpadMetrics = function(_, _, m)
        return { item = 32 * m.scale, icon = 24 * m.scale, slot = 27 * m.scale,
            gap = 3, compactGap = 3, edge = 1, compactEdge = 1, spacing = 6 }
    end,
    scratchpadLabel = function(scratchpad, style, m, text, width)
        local active = (scratchpad.revealed or scratchpad.focused) and style.accents
        local fill, color
        if active then
            fill, color = "accent", "accentForeground"
        elseif scratchpad.visible then
            fill, color = "blue/0.2", if style.textColor ~= nil then "foreground" else "blue"
        else
            fill, color = "foreground/0.07", if style.textColor ~= nil then "foreground" else "mutedForeground"
        end
        if not style.backgrounds and not active then
            fill = nil
        end
        local size = 24 * m.scale
        local label = ui.text{ text = text, size = if width then math.min(14 * m.scale, width / 2) else 14 * m.scale,
            weight = "bold",
            color = if style.textColor ~= nil then "foreground" else color, maxWidth = width }
        if scratchpad.compact or m.vertical then
            return ui.stack{ w = size, h = size, radius = size / 2, fill = fill, label }
        end
        return ui.row{ h = size, gap = 4, radius = size / 2, fill = fill,
            ui.box{ w = 5, h = 1 },
            ui.symbol{ name = "tray.fill", size = 9, weight = "bold", color = color },
            label,
            ui.box{ w = 6, h = 1 } }
    end,
    scratchpadCount = function(text, _, _, m)
        local size = m.item - 10
        return ui.row{ h = size, radius = size / 2, fill = "elevatedSurface",
            ui.box{ w = 4, h = 1 },
            ui.text{ text = text, style = "mono", size = size - 6, weight = "bold", color = "foreground" },
            ui.box{ w = 4, h = 1 } }
    end,
    scratchpadPill = function(node, scratchpad, style, m)
        node.radius = m.item / 2 - 1
        node.fill = if style.backgrounds then "surface" else nil
        node.hover = "focus/0.14"
        node.border = if style.backgrounds then "border/0.6" else nil
        node.borderWidth = 1
        node[#node] = spacer(m.vertical, if scratchpad.compact then 3 else 1)
    end,
})
