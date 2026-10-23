-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local function line(vertical, props)
    return vertical and ui.column(props) or ui.row(props)
end

local function spacer(vertical, length)
    return vertical and ui.box{ w = 1, h = length } or ui.box{ w = length, h = 1 }
end

local function supported(m)
    return m.indicator == "pills" or m.indicator == "underline"
end

local function filled(style, m, focused)
    return focused and style.accents and style.backgrounds and m.indicator ~= "underline"
end

local function labelColor(style, m, workspace)
    if style.textColor ~= nil then
        return "foreground"
    end
    if filled(style, m, workspace.focused) then
        return "accentForeground"
    end
    if workspace.focused then
        return style.accents and "accent" or "foreground"
    end
    return style.accents and "accent" or (#workspace.windows > 0 and "secondaryForeground" or "mutedForeground")
end

local function statsArc(value)
    local radius = 24.5
    local top = "M27 2.5"
    if value >= 0.999 then
        return top .. " A24.5 24.5 0 1 1 27 51.5 A24.5 24.5 0 1 1 27 2.5"
    end
    if value <= 0.005 then
        return nil
    end
    local angle = value * 2 * math.pi
    return string.format("%s A24.5 24.5 0 %d 1 %.2f %.2f", top, angle > math.pi and 1 or 0,
        27 + radius * math.sin(angle), 27 - radius * math.cos(angle))
end

local function statsGauge(metric, hue, width)
    local dial = { w = 54, h = 54, help = metric.detail,
        ui.path{ w = 54, h = 54, viewBox = { 0, 0, 54, 54 }, d = statsArc(1),
            border = "foreground/0.08", borderWidth = 5 } }
    local sweep = metric.value and statsArc(metric.value)
    if sweep then
        dial[#dial + 1] = ui.path{ w = 54, h = 54, viewBox = { 0, 0, 54, 54 }, d = sweep,
            border = metric.warn and "red" or (metric.hot and "warning" or hue), borderWidth = 5 }
    end
    dial[#dial + 1] = ui.text{ text = metric.percent, style = "rounded", size = 14, weight = "bold",
        color = "foreground" }
    local props = { w = width, gap = 6, center = true, ui.stack(dial),
        ui.text{ text = metric.title, size = 12, weight = "bold", color = "mutedForeground", maxWidth = width - 4 } }
    if metric.temperatureText then
        props[#props + 1] = ui.text{ text = metric.temperatureText, style = "mono", size = 10,
            color = metric.hot and "warning" or "secondaryForeground" }
    end
    return ui.column(props)
end

local function statsTile(symbol, hue)
    return ui.stack{ w = 24, h = 24, radius = 6, fill = hue .. "/0.16",
        ui.symbol{ name = symbol, size = 11, weight = "semibold", color = hue } }
end

local function statsDetail(symbol, hue, title, value, width, lines)
    local row = { w = width, gap = 10, statsTile(symbol, hue) }
    if title then
        row[#row + 1] = ui.text{ text = title, size = 13, weight = "semibold", color = "foreground" }
        row[#row + 1] = ui.box{ grow = 1, h = 1 }
        row[#row + 1] = ui.text{ text = value, size = 12, weight = "medium", color = "secondaryForeground",
            maxWidth = width - 125, lines = lines or 1 }
    else
        row[#row + 1] = ui.text{ text = value, size = 12, weight = "medium", color = "secondaryForeground",
            maxWidth = width - 34, lines = lines or 1 }
    end
    return ui.row(row)
end

local function statsCard(width, children)
    children.w, children.pad, children.gap = width, 10, 10
    children.radius, children.fill, children.center = 9, "elevatedSurface", false
    return ui.column(children)
end

return require("./skin")({
    base = 40,
    hover = "foreground/0.07",
    hiddenBarHover = "accent/0.15",
    width = 320,
    widths = { workspaces = 296, ["system-stats"] = 348 },
    size = { text = 14, icon = 24, slot = 28 },
    omniwmButton = function(ctx, glyph, locked)
        local size = 32 * ctx.data.bar.style.height / 40
        glyph.size = math.floor(size * 0.6)
        return { w = size, h = size, radius = math.floor(size * 0.24),
            fill = locked and "warning/0.25" or "accent/0.18", hoverOpacity = 0.85 }, size
    end,
    systemStatsButton = function(ctx, glyph)
        local style = ctx.data.bar.style
        local size = 32 * style.height / 40
        glyph.size, glyph.weight = math.floor(size * 0.52), "semibold"
        glyph.color = style.textColor ~= nil and "foreground" or "secondaryForeground"
        return { w = size, h = size, radius = math.floor(size * 0.24),
            fill = style.backgrounds and "elevatedSurface" or nil, hover = "foreground/0.08" }
    end,
    systemStatsSection = function(_, kind, m, width)
        local inner = width - 20
        if kind == "header" then
            local host = m.host
            local row = { w = width, h = 52, gap = 10,
                ui.stack{ w = 30, h = 30, radius = 8, fill = "accent",
                    ui.symbol{ name = "applelogo", size = 16, weight = "semibold", color = "accentForeground" } },
                ui.column{ gap = 1, center = false, grow = 1,
                    ui.text{ text = host and host.name or omniwm.l10n("System"), size = 14, weight = "bold",
                        color = "foreground", maxWidth = 170 },
                    ui.text{ text = host and host.chip or omniwm.l10n("Loading…"), size = 12, weight = "medium",
                        color = "mutedForeground", maxWidth = 170 } } }
            if host then
                row[#row + 1] = ui.row{ h = 22, radius = 6, fill = "foreground/0.06", gap = 4,
                    ui.box{ w = 4, h = 1 },
                    ui.symbol{ name = "power", size = 9, weight = "bold", color = "green" },
                    ui.text{ text = host.uptime, style = "mono", size = 12, weight = "semibold",
                        color = "secondaryForeground" }, ui.box{ w = 5, h = 1 } }
            end
            return ui.row(row)
        elseif kind == "metrics" then
            local hues = { "blue", "purple", "green", "yellow" }
            local row = { w = width, gap = 0, pad = 4, radius = 9, fill = "elevatedSurface", center = false }
            for index, metric in ipairs(m.metrics) do
                row[#row + 1] = statsGauge(metric, hues[index], (width - 8) / 4)
            end
            return ui.row(row)
        elseif kind == "network" then
            local graph = { w = inner, h = 44 }
            if m.network.graph then
                local down, up = m.network.graph(inner, 44)
                for index, path in ipairs({ up, down }) do
                    if path then
                        graph[#graph + 1] = ui.path{ w = inner, h = 44, d = path,
                            border = index == 1 and "purple" or "blue", borderWidth = 1.5 }
                    end
                end
            else
                graph[#graph + 1] = ui.text{ text = omniwm.l10n("Collecting data…"), size = 11,
                    color = "mutedForeground" }
            end
            return statsCard(width, {
                ui.row{ w = inner, gap = 10, statsTile("network", "blue"),
                    ui.text{ text = omniwm.l10n("Network"), size = 13, weight = "semibold", color = "foreground" } },
                ui.stack(graph),
                statsDetail("arrow.down", "blue", omniwm.l10n("Download"), m.network.down, inner),
                statsDetail("arrow.up", "purple", omniwm.l10n("Upload"), m.network.up, inner),
                statsDetail("arrow.up.arrow.down", "accent", omniwm.l10n("Total"), m.network.total, inner) })
        elseif kind == "battery" then
            local battery = m.battery
            return statsCard(width, {
                statsDetail(battery.symbol, "green",
                    omniwm.l10n("Battery"), battery.percent, inner),
                ui.progress{ w = inner, h = 5, radius = 2.5, value = battery.level, fill = "foreground/0.08",
                    color = battery.low and "warning" or "green" },
                ui.text{ text = battery.status, size = 12, color = "secondaryForeground", maxWidth = inner } })
        elseif kind == "details" then
            local rows = {
                statsDetail("cpu", m.cpu.hot and "warning" or "blue", m.cpu.title, m.cpu.detail, inner, 2),
                statsDetail("cube", m.gpu.hot and "warning" or "purple", m.gpu.title, m.gpu.detail, inner, 2),
                statsDetail("memorychip", m.memory.pressure == "critical" and "red" or "green",
                    m.memory.title, m.memory.detail, inner, 2),
                statsDetail("internaldrive", "yellow", m.disk.title, m.disk.detail, inner, 2) }
            if m.host then
                rows[#rows + 1] = statsDetail("display", "blue", nil, table.concat(m.displays, "\n"), inner,
                    math.max(1, #m.displays))
                rows[#rows + 1] = statsDetail("laptopcomputer", "accent", m.host.model, m.host.os, inner, 2)
            end
            for index = #rows, 2, -1 do
                table.insert(rows, index, ui.box{ w = inner, h = 1, fill = "foreground/0.07" })
            end
            return statsCard(width, rows)
        end
        return nil
    end,
    systemStatsPanel = function(_, props)
        local header = table.remove(props, 1)
        local width = props.w
        props.center = false
        return ui.column{ w = width, gap = 0, material = "clear", radius = 12, fill = "surface",
            border = "border", borderWidth = 1, center = false,
            ui.stack{ w = width, h = 52,
                ui.box{ w = width, h = 52, radius = 12, fill = "elevatedSurface" },
                ui.box{ align = "bottom", w = width, h = 12, fill = "elevatedSurface" }, header },
            ui.box{ w = width, h = 1, fill = "border" },
            ui.column(props) }
    end,
    workspaceMetrics = function(_, style, m)
        return { item = 32 * m.scale, focusCue = supported(m) and not m.compact and style.backgrounds }
    end,
    workspaceMarker = function(_, workspace, style, m, occupied)
        if not supported(m) or (m.compact and not style.labels) then
            return nil
        end
        local radius = math.floor(m.item * 0.24)
        local fill = style.backgrounds and (filled(style, m, workspace.focused) and "accent"
            or (style.accents and "accent/0.24" or "foreground/0.07")) or nil
        local block = { w = m.vertical and m.item or (utf8.len(workspace.name) <= 2 and 28 * m.scale or nil),
            h = m.item, radius = radius, fill = fill }
        if occupied and not m.compact then
            block[#block + 1] = ui.box{ align = m.vertical and "bottom" or "trailing",
                w = m.vertical and m.item or radius, h = m.vertical and radius or m.item,
                fill = style.backgrounds and "elevatedSurface" or nil,
                ui.box{ w = m.vertical and m.item or radius, h = m.vertical and radius or m.item, fill = fill } }
        end
        block[#block + 1] = ui.row{
            ui.box{ w = 4 * m.scale, h = 1 },
            ui.text{ text = workspace.name, size = 14 * m.scale, weight = "bold",
                color = labelColor(style, m, workspace), maxWidth = m.vertical and m.item - 8 * m.scale or nil },
            ui.box{ w = 4 * m.scale, h = 1 } }
        return ui.stack(block)
    end,
    workspacePill = function(pill, workspace, style, m, occupied)
        if not supported(m) then
            return
        end
        pill.gap = 4 * m.scale
        pill.radius = math.floor(m.item * 0.24)
        if not (m.occupiedBackground and occupied and not workspace.focused) then
            pill.fill = style.backgrounds and "elevatedSurface" or nil
        end
        pill.hover = not workspace.focused and "accent/0.15" or nil
        if workspace.focused and not style.labels then
            pill.border = style.accents and m.indicator ~= "underline" and "accent"
                or (style.backgrounds and not style.accents and "secondaryForeground/0.5" or nil)
            pill.borderWidth = 1.5
        end
    end,
    windowIcon = function(icon)
        icon.radius = 5
    end,
    countBadge = function(text)
        return ui.row{ align = "bottomTrailing", dx = 1, dy = 1, h = 11, radius = 5.5,
            fill = "surface", border = "border", borderWidth = 1,
            ui.box{ w = 2.5, h = 1 },
            ui.text{ text = text, style = "mono", size = 8, weight = "bold", color = "foreground" },
            ui.box{ w = 2.5, h = 1 } }
    end,
    notificationBadge = function(item, mode, m)
        if mode == "dot" then
            return ui.box{ align = "topTrailing", w = 7, h = 7, radius = 3.5, fill = "badge",
                border = "elevatedSurface", borderWidth = 1 }
        end
        return ui.row{ align = "topTrailing", dx = 1, dy = -1, h = 11, radius = 5.5, fill = "badge",
            ui.box{ w = 2.5, h = 1 },
            ui.text{ text = item.badge, style = "mono", size = 8, weight = "bold", color = "background", maxWidth = m.slot },
            ui.box{ w = 2.5, h = 1 } }
    end,
    hiddenIndicator = function(item)
        local full = item.count > 0 and item.hidden == item.count
        return ui.stack{ align = "bottomLeading", dx = -1, dy = 1, w = 10, h = 10, radius = 5,
            fill = full and "badge" or "surface", border = full and nil or "badge", borderWidth = 1,
            ui.symbol{ name = full and "eye.slash.fill" or "eye.slash", size = 6, weight = "bold",
                color = full and "background" or "badge" } }
    end,
    floatingGroup = function(icons, style, m)
        local symbol = 12 * m.scale
        local group = { gap = m.scale, radius = 5 * m.scale,
            w = m.vertical and m.slot or nil, h = not m.vertical and m.slot or nil,
            fill = style.backgrounds and "foreground/0.06" or nil,
            spacer(m.vertical, 3 * m.scale),
            ui.symbol{ name = "rectangle.on.rectangle", size = symbol, w = symbol, h = symbol, weight = "semibold",
                color = style.textColor ~= nil and "foreground" or "mutedForeground" },
            spacer(m.vertical, m.scale) }
        for _, icon in ipairs(icons) do
            group[#group + 1] = icon
        end
        group[#group + 1] = spacer(m.vertical, m.scale)
        return line(m.vertical, group), 5 * m.scale + symbol + #icons * m.slot + (#icons + 3) * m.scale
    end,
    workspaceGroup = function(_, pills, _, _, m)
        if not supported(m) then
            return nil
        end
        pills.gap = 6 * m.scale
        return line(m.vertical, pills)
    end,
    scratchpadMetrics = function(_, _, m)
        return { item = 30 * m.scale, icon = 24 * m.scale, slot = 24 * m.scale,
            gap = 2, compactGap = 2, edge = 4, compactEdge = 4, spacing = 2 }
    end,
    scratchpadLabel = function(scratchpad, style, m, text, width)
        local active = (scratchpad.revealed or scratchpad.focused) and style.accents
        local hue = style.accentColor ~= nil and "accent" or "purple"
        local color = style.textColor ~= nil and "foreground" or active and hue
            or (scratchpad.visible and "foreground" or "secondaryForeground")
        local name = ui.text{ text = text, size = if width then math.min(14 * m.scale, width / 2) else 14 * m.scale,
            weight = "bold", color = color, maxWidth = width }
        if scratchpad.visible or active then
            return name
        end
        return line(m.vertical, { gap = 2, name,
            ui.symbol{ name = "eye.slash", size = 8, weight = "bold", color = "mutedForeground" } })
    end,
    scratchpadCount = function(text)
        return ui.row{ h = 14, radius = 7, fill = "foreground/0.08",
            ui.box{ w = 4, h = 1 },
            ui.text{ text = text, style = "mono", size = 9, weight = "bold", color = "secondaryForeground" },
            ui.box{ w = 4, h = 1 } }
    end,
    scratchpadIcon = function(_, glyph, member, scratchpad, style)
        glyph.opacity = member.focused and 1 or (style.inactive >= 0 and style.inactive
            or (scratchpad.visible and 0.9 or 0.6))
    end,
    scratchpadPill = function(node, scratchpad, style, m)
        local active = (scratchpad.revealed or scratchpad.focused) and style.accents
        local hue = style.accentColor ~= nil and "accent" or "purple"
        node.radius = math.floor(32 * m.scale * 0.24) - 1
        node.fill = (active and style.backgrounds) and (hue .. "/0.22") or nil
        node.hover = not active and (hue .. "/0.15") or nil
        node.border = scratchpad.focused and not style.accents and "foreground/0.4" or nil
        node.borderWidth = 1
        if not scratchpad.compact then
            table.insert(node, 3, spacer(m.vertical, 0))
        end
    end,
    scratchpadGroup = function(_, items, style, m)
        if #items == 0 then
            return ui.row{}
        end
        local size = 32 * m.scale
        local radius = math.floor(size * 0.24)
        local block = ui.stack{ w = size, h = size,
            ui.box{ w = size, h = size, radius = radius, fill = "purple" },
            ui.box{ align = m.vertical and "bottom" or "trailing", w = m.vertical and size or radius,
                h = m.vertical and radius or size, fill = "purple" },
            ui.symbol{ name = "tray.fill", size = math.floor(size * 0.5), weight = "semibold", color = "accentForeground" } }
        items.gap = 2
        items.radius = radius
        items.fill = style.backgrounds and "elevatedSurface" or nil
        items.w = m.vertical and size or nil
        items.h = not m.vertical and size or nil
        table.insert(items, 1, spacer(m.vertical, 0))
        table.insert(items, 1, block)
        items[#items + 1] = spacer(m.vertical, 0)
        return line(m.vertical, items)
    end,
    pickerHeader = function(header, item)
        header[1].size = 13
        header[1].weight = "bold"
        header[1].maxWidth = 180
        table.insert(header, 1, ui.icon{ app = item.bundle, w = 18, h = 18, placeholder = "app.dashed" })
    end,
    pickerRow = function(row, window)
        row.pad = 10
        row.gap = 8
        row.radius = 9
        row[1].size = 14
        row[1].weight = window.focused and "semibold" or "medium"
        row[1].maxWidth -= 24
        table.insert(row, 1, ui.box{ w = 3, h = 16, radius = 1.5,
            fill = window.focused and "accent" or "foreground/0.12" })
    end,
    list = function(props)
        props.gap = 0
        props.pad = 0
        props.radius = 9
        props.fill = "elevatedSurface"
        props.center = true
        local count = #props
        for index = count, 2, -1 do
            table.insert(props, index, ui.box{ w = 276, h = 1, fill = "foreground/0.07" })
        end
        return ui.column(props)
    end,
    hiddenMenuRow = function(row, item, kind)
        if kind == "separator" then
            row[1].fill = "foreground/0.08"
        elseif kind == "item" then
            row[1].size, row[1].weight, row[1].color = 12, "bold", "accent"
            row[2].size, row[2].weight = 12, "medium"
            row[2].color = item.enabled and "foreground" or "mutedForeground"
            row[3].style, row[3].size, row[3].weight, row[3].color = "mono", 11, "medium", "mutedForeground"
            if item.submenu then
                row[4].weight, row[4].color = "bold", "mutedForeground"
            end
        elseif kind == "back" then
            row[1].weight, row[1].color = "bold", "accent"
            row[2].size, row[2].weight, row[2].color = 12, "semibold", "accent"
        elseif kind == "title" then
            local label = row[1]
            if not string.find(label.text, "[\128-\255]") then
                label.text = string.upper(label.text)
            end
            label.size, label.weight, label.color = 10, "bold", "mutedForeground"
        elseif kind == "empty" then
            row[1].size, row[1].color = 12, "mutedForeground"
        elseif kind == "unavailable" then
            row.size, row.color = 12, "mutedForeground"
        end
    end,
    hiddenMenuPanel = function(_, rows)
        rows.radius, rows.material, rows.fill = 12, "clear", "surface"
        rows.border, rows.borderWidth, rows.center = "border", 1, false
        return ui.column(rows)
    end,
    panel = function(_, props)
        local header = props[1]
        header.h = 44
        local body = { w = 320, pad = 12, center = false }
        for index = 2, #props do
            body[#body + 1] = props[index]
        end
        return ui.column{ w = 320, gap = 0, material = "clear", radius = 12, fill = "surface", border = "border",
            borderWidth = 1, center = false,
            ui.stack{ w = 320, h = 44,
                ui.box{ w = 320, h = 44, radius = 12, fill = "elevatedSurface" },
                ui.box{ align = "bottom", w = 320, h = 12, fill = "elevatedSurface" },
                header },
            ui.box{ w = 320, h = 1, fill = "border" },
            ui.column(body) }
    end,
})
