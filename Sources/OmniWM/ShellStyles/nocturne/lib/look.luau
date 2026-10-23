-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local panel = require("./panel")

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

return require("./skin")({
    base = 40,
    hover = "focus/0.14",
    width = 300,
    widths = { workspaces = 274 },
    size = { text = 14, icon = 24, slot = 27 },
    omniwmButton = function(ctx, glyph)
        local style = ctx.data.bar.style
        local scale = style.height / 40
        local size = 32 * scale
        glyph.size = 24 * scale
        return { w = size, h = size, radius = size / 2,
            fill = style.backgrounds and "accent/0.18" or nil, hoverScale = 1.06 }, size
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
