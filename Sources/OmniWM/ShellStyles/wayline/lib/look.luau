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

return require("./skin")({
    base = 40,
    hover = "foreground/0.07",
    width = 320,
    widths = { workspaces = 296 },
    size = { text = 14, icon = 24, slot = 28 },
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
