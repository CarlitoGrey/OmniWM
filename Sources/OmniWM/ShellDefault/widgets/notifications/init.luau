-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local presentation = require("../lib/notification-style")

local WIDTH = 392
local PAGE = 8
local DETAILS = 24
local TEXT_PAGE = 8
local button = presentation.button

local function text(rows, value, width, style, color, ctx, key)
    if type(value) ~= "string" or value == "" then
        return
    end
    if not utf8.len(value) then
        rows[#rows + 1] = presentation.text{ text = omniwm.l10n("Data (%lld bytes)", #value), style = "small", color = "secondaryForeground" }
        return
    end
    local starts = { 1 }
    local first = 1
    while first <= #value do
        local following = utf8.offset(value, 1025, first) or (#value + 1)
        local scan = first
        for line = 1, 128 do
            local newline = string.find(value, "\n", scan, true)
            if not newline or newline >= following then
                break
            end
            scan = newline + 1
            if line == 128 then
                following = scan
            end
        end
        starts[#starts + 1] = following
        first = following
    end
    local pages = math.max(1, math.ceil((#starts - 1) / TEXT_PAGE))
    local page = math.clamp(if ctx then (ctx.state.textPages or {})[key] or 1 else 1, 1, pages)
    for index = (page - 1) * TEXT_PAGE + 1, math.min(page * TEXT_PAGE, #starts - 1) do
        rows[#rows + 1] = presentation.text{ text = string.sub(value, starts[index], starts[index + 1] - 1),
            maxWidth = width, lines = 255, style = style, color = color }
    end
    if pages > 1 and ctx then
        local function select(state, selected)
            state.state.textPages = state.state.textPages or {}
            state.state.textPages[key] = selected
        end
        rows[#rows + 1] = ui.row{ gap = 5,
            button(omniwm.l10n("Previous Text"), function(state) select(state, math.max(1, page - 1)) end),
            presentation.text{ text = tostring(page) .. " / " .. tostring(pages), style = "small", color = "secondaryForeground" },
            button(omniwm.l10n("Next Text"), function(state) select(state, math.min(pages, page + 1)) end) }
    end
end

local function label(value)
    if type(value) == "string" then
        return value
    end
    if type(value) == "table" then
        return value.displayName or value.name or value.handle or value.identifier
    end
    return nil
end

local function detailLines(item, app)
    local lines = {}
    local function visit(value, path, depth)
        if type(value) ~= "table" then
            local shown = if type(value) == "string" and not utf8.len(value)
                then omniwm.l10n("Data (%lld bytes)", #value) else tostring(value)
            lines[#lines + 1] = { path = path, value = shown }
            return
        end
        if value.type == "data" and type(value.bytes) == "string" and type(value.byteLength) == "number" then
            local size = value.byteLength or (if type(value.bytes) == "string" then #value.bytes else 0)
            lines[#lines + 1] = { path = path, value = omniwm.l10n("Data (%lld bytes)", size) }
            if value.resolved then
                visit(value.resolved, path .. ".resolved", depth + 1)
            elseif value.decoded then
                visit(value.decoded, path .. ".decoded", depth + 1)
            end
            return
        end
        local keys = {}
        for key in value do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            return if type(a) == "number" and type(b) == "number" then a < b else tostring(a) < tostring(b)
        end)
        if #keys == 0 then
            lines[#lines + 1] = { path = path, value = "{}" }
        end
        for _, key in keys do
            local name = path .. "." .. tostring(key)
            if (key == "rawPayload" or key == "raw" or key == "bytes") and type(value[key]) == "string" then
                lines[#lines + 1] = { path = name, value = omniwm.l10n("Data (%lld bytes)", #value[key]) }
            elseif key == "base64" and type(value[key]) == "string" then
                lines[#lines + 1] = { path = name, value = omniwm.l10n("Encoded data (%lld characters)", #value[key]) }
            elseif depth < 64 then
                visit(value[key], name, depth + 1)
            else
                lines[#lines + 1] = { path = name, value = omniwm.l10n("Nested metadata") }
            end
        end
    end
    for _, key in { "id", "bundle", "requestId", "date", "thread", "category", "actions", "attachments", "userInfo", "communication", "metadata" } do
        if item[key] ~= nil then
            visit(item[key], key, 0)
        end
    end
    if app then
        visit(app, "app", 0)
    end
    return lines
end

local function inspector(ctx, item, width, app)
    local lines = detailLines(item, app)
    local pages = math.max(1, math.ceil(#lines / DETAILS))
    local page = math.clamp(ctx.state.detailsPage or 1, 1, pages)
    local rows = { w = width, gap = 3, center = false, pad = 6 }
    for index = (page - 1) * DETAILS + 1, math.min(page * DETAILS, #lines) do
        local line = lines[index]
        text(rows, line.path .. ": " .. line.value, width - 12, "small", "secondaryForeground", ctx, item.id .. ":detail:" .. tostring(index))
    end
    if pages > 1 then
        rows[#rows + 1] = ui.row{ gap = 5,
            button(omniwm.l10n("Previous"), function(state) state.state.detailsPage = math.max(1, page - 1) end),
            presentation.text{ text = tostring(page) .. " / " .. tostring(pages), style = "small" },
            button(omniwm.l10n("Next"), function(state) state.state.detailsPage = math.min(pages, page + 1) end) }
    end
    return presentation.group(rows, true)
end

local function notification(ctx, item)
    local width = WIDTH - 24
    local content = width - 16
    local rows = { key = item.id, w = width, gap = 5, pad = 8, center = false }
    local app = nil
    for _, value in ctx.data.notifications.apps or {} do
        if value.bundle == item.bundle then
            app = value
            break
        end
    end
    local name = if app then app.name or item.bundle else item.bundle
    local timestamp = if type(item.date) == "number" then ctx.format.date(item.date, "MMM d, HH:mm") else nil
    rows[#rows + 1] = ui.row{ w = content, gap = 6,
        ui.icon{ app = item.bundle, w = 18, h = 18, placeholder = "app" },
        presentation.text{ text = name, style = "small", grow = 1, maxWidth = content - 120 },
        presentation.text{ text = timestamp or "", style = "small", color = "secondaryForeground" } }
    local communication = item.communication
    if type(communication) == "table" then
        text(rows, label(communication.sender), content, "small", "secondaryForeground", ctx, item.id .. ":sender")
        text(rows, label(communication.conversation) or communication.displayName or communication.conversationIdentifier
            or communication.identifier, content, "small", "secondaryForeground", ctx, item.id .. ":conversation")
        local recipients = {}
        for _, recipient in communication.recipients or {} do
            local name = label(recipient)
            if type(name) == "string" and name ~= "" then
                recipients[#recipients + 1] = name
            end
        end
        text(rows, table.concat(recipients, ", "), content, "small", "secondaryForeground", ctx, item.id .. ":recipients")
    end
    text(rows, item.title, content, "bold", nil, ctx, item.id .. ":title")
    text(rows, item.subtitle, content, "body", "secondaryForeground", ctx, item.id .. ":subtitle")
    text(rows, item.body, content, "body", nil, ctx, item.id .. ":body")
    for _, attachment in item.attachments or {} do
        if type(attachment.image) == "string" and attachment.image ~= "" then
            rows[#rows + 1] = ui.image{ image = attachment.image, w = content, h = 144, radius = 6 }
        end
        text(rows, (attachment.type or omniwm.l10n("Attachment")) .. " · "
            .. (if attachment.available then omniwm.l10n("Available") else omniwm.l10n("Unavailable")), content, "small", "secondaryForeground")
        text(rows, attachment.path, content, "small", "secondaryForeground")
    end
    local expanded = ctx.state.details == item.id
    rows[#rows + 1] = ui.row{ gap = 6,
        button(if expanded then omniwm.l10n("Hide Details") else omniwm.l10n("Details"), function(state)
            state.state.details = if expanded then nil else item.id
            state.state.detailsPage = 1
        end),
        button(omniwm.l10n("Open App"), "notifications open " .. item.bundle) }
    if expanded then
        rows[#rows + 1] = inspector(ctx, item, content, app)
    end
    return presentation.group(rows)
end

local function status(value)
    if not value then
        return omniwm.l10n("Loading notifications…")
    end
    if value.state == "accessDenied" then
        return omniwm.l10n("Notification database access is denied. Check Full Disk Access in System Settings.")
    elseif value.state == "unavailable" then
        return omniwm.l10n("The notification database is unavailable.")
    elseif value.state == "queryError" then
        return omniwm.l10n("The notification database could not be read.")
    elseif value.state == "malformed" then
        return omniwm.l10n("The notification database contains unsupported or malformed data.")
    elseif value.state == "incomplete" or value.complete == false then
        return omniwm.l10n("Some notification data could not be read. The list is incomplete.")
    elseif value.state ~= "ready" and value.state ~= "empty" then
        return omniwm.l10n("Loading notifications…")
    end
    return nil
end

function render(ctx)
    local value = ctx.data.notifications
    local count = if value then #(value.items or {}) else 0
    local issue = status(value)
    local scale = presentation.scale(ctx)
    local rows = { gap = 4 * scale, onClick = ui.popout,
        help = issue or omniwm.l10n("Notifications"),
        presentation.icon(issue, 14 * scale) }
    if count > 0 then
        local size = if ctx.data.bar.style.vertical then math.min(12 * scale, (ctx.data.bar.style.height - 8) / 2)
            else 12 * scale
        rows[#rows + 1] = presentation.text{ text = tostring(count), style = "small", size = size }
    end
    return presentation.bar(ctx, rows)
end

function popout(ctx)
    local value = ctx.data.notifications
    local items = if value then value.items or {} else {}
    local pages = math.max(1, math.ceil(#items / PAGE))
    local page = math.clamp(ctx.state.page or 1, 1, pages)
    local rows = { w = WIDTH, h = 520, pad = 12, gap = 10, center = false, scroll = true,
        ui.row{ w = WIDTH - 24, gap = 5,
            presentation.text{ text = omniwm.l10n("Notifications"), style = "bold", grow = 1 },
            button(omniwm.l10n("Refresh"), "notifications refresh"),
            button(omniwm.l10n("Settings"), "notifications settings") } }
    local issue = status(value)
    if issue then
        text(rows, issue, WIDTH - 24, "body", "secondaryForeground")
    elseif #items == 0 then
        rows[#rows + 1] = presentation.text{ text = omniwm.l10n("No retained notifications"), color = "secondaryForeground" }
    end
    if value and value.error and value.error ~= "" then
        text(rows, value.error, WIDTH - 24, "small", "secondaryForeground")
    end
    for index = (page - 1) * PAGE + 1, math.min(page * PAGE, #items) do
        rows[#rows + 1] = notification(ctx, items[index])
    end
    if pages > 1 then
        rows[#rows + 1] = ui.row{ w = WIDTH - 24, gap = 8, center = true,
            button(omniwm.l10n("Previous"), function(state) state.state.page = math.max(1, page - 1) end),
            presentation.text{ text = tostring(page) .. " / " .. tostring(pages), style = "small", color = "secondaryForeground" },
            button(omniwm.l10n("Next"), function(state) state.state.page = math.min(pages, page + 1) end) }
    end
    return presentation.panel(ctx, rows)
end
