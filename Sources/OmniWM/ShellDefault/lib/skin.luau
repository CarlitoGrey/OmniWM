-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local SIZES = { text = 13, small = 11, symbol = 14, icon = 18, slot = 22, time = 13, glyph = 18 }

local function skin(look)
    look.base = look.base or 32
    look.hover = look.hover or "foreground/0.08"
    look.width = look.width or 320
    look.widths = look.widths or {}
    look.panelInset = look.panelInset or 0
    look.verticalText = look.verticalText or "hide"
    look.symbols = look.symbols or {}
    look.notification = look.notification or {}
    local sizes = table.clone(SIZES)
    for role, value in look.size or {} do
        sizes[role] = value
    end
    look.size = sizes

    look.scale = look.scale or function(ctx)
        return ctx.data.bar.style.height / look.base
    end
    look.px = look.px or function(ctx, role)
        return look.size[role] * look.scale(ctx)
    end
    look.radius = look.radius or function(value)
        return value
    end
    look.panelWidth = look.panelWidth or function(name)
        return look.widths[name] or look.width
    end
    look.text = look.text or function(props)
        if props.color == nil and props.role == "secondary" then
            props.color = "secondaryForeground"
        end
        props.role = nil
        return ui.text(props)
    end
    look.glyph = look.glyph or function(props)
        props.name = look.symbols[props.name] or props.name
        return ui.symbol(props)
    end
    look.hue = look.hue or function()
        return nil
    end
    look.batterySymbol = look.batterySymbol or function(level, charging)
        if charging then
            return "battery.100percent.bolt"
        end
        if level > 85 then
            return "battery.100percent"
        end
        if level > 60 then
            return "battery.75percent"
        end
        if level > 35 then
            return "battery.50percent"
        end
        if level > 10 then
            return "battery.25percent"
        end
        return "battery.0percent"
    end
    look.bar = look.bar or function(ctx, props)
        local bar = ctx.data.bar.style
        local scale = look.scale(ctx)
        props.gap = props.gap or 5 * scale
        props.pad = props.pad or 4 * scale
        props.radius = look.radius(6 * scale)
        if props.onClick or props.onRightClick then
            props.hover = props.hover or look.hover
        end
        if bar.backgrounds then
            props.fill = props.fill or "foreground/0.06"
        end
        if props.symbol then
            table.insert(props, 1, look.glyph{ name = props.symbol, size = look.px(ctx, "symbol"), color = props.tint })
        end
        props.symbol = nil
        props.tint = nil
        props.hue = nil
        props.joined = nil
        if bar.vertical then
            props.w = props.w or bar.height - 4
            return ui.column(props)
        end
        props.h = props.h or bar.height - 4
        return ui.row(props)
    end
    look.panel = look.panel or function(_, props)
        props.pad = props.pad or 14
        props.gap = props.gap or 12
        props.radius = look.radius(20)
        props.material = "glass"
        props.center = false
        return ui.column(props)
    end
    look.group = look.group or function(props)
        props.pad = props.pad or 12
        props.gap = props.gap or 8
        props.radius = look.radius(12)
        props.fill = props.fill or "surface"
        props.center = false
        return ui.column(props)
    end
    look.list = look.list or function(props)
        props.divided = nil
        props.gap = props.gap or 2
        return ui.column(props)
    end
    look.heading = look.heading or function(text, width)
        return ui.row{ w = width, look.text{ text = text, size = 14, weight = "semibold" } }
    end
    look.section = look.section or function(text, width)
        return look.heading(text, width)
    end
    look.button = look.button or function(name, action, props)
        props = props or {}
        local primary = props.primary
        local active = props.active
        local color = props.color or (if active then "accent" else nil)
        props.primary = nil
        props.active = nil
        props.color = nil
        props.w = props.w or (if primary then 36 else 28)
        props.h = props.h or (if primary then 36 else 28)
        props.radius = props.radius or look.radius(if primary then 18 else 7)
        props.fill = props.fill or (if primary then "foreground/0.06" else nil)
        props.hover = look.hover
        props.onClick = action
        props[#props + 1] = look.glyph{ name = name, size = 14, weight = "medium", color = color }
        return ui.stack(props)
    end
    return table.freeze(look)
end

return skin
