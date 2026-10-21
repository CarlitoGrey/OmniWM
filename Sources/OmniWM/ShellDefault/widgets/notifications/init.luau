-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local presentation = require("../lib/notification-style")

local WIDTH = 392
local PAGE = 8
local DETAILS = 24
local TEXT_PAGE = 8
local button = presentation.button

local function replyAction(item)
    local reply = nil
    for _, action in item.actions or {} do
        if type(action) == "table" and type(action.title) == "string" and action.title ~= ""
            and type(action.textInputButtonTitle) == "string" and action.textInputButtonTitle ~= "" then
            if reply then return nil end
            reply = action
        end
    end
    if reply then
        local count = 0
        for _, action in item.actions or {} do
            if type(action) == "table" and action.title == reply.title then count += 1 end
        end
        if count ~= 1 then return nil end
    end
    return reply
end

local function actionMessage(action)
    if not action then return nil end
    if action.state == "pending" then
        return if action.kind == "reply" then omniwm.l10n("Submitting reply…") else omniwm.l10n("Dismissing notification…")
    elseif action.state == "dispatched" then
        return if action.kind == "reply" then omniwm.l10n("Reply submitted to Notification Center.") else omniwm.l10n("Dismiss requested in Notification Center.")
    elseif action.state == "dispatchedPanelOpen" then
        return omniwm.l10n("Action submitted. Close Notification Center to continue.")
    elseif action.state == "failedPanelOpen" then
        return omniwm.l10n("The action failed. Close Notification Center and try again.")
    elseif action.state == "notFound" then
        return omniwm.l10n("This notification is no longer available in Notification Center.")
    elseif action.state == "denied" then
        return omniwm.l10n("Accessibility access is required for notification actions.")
    elseif action.state == "unavailable" then
        return omniwm.l10n("Notification Center is unavailable.")
    elseif action.state == "ambiguous" then
        return omniwm.l10n("The native notification action could not be matched uniquely.")
    elseif action.state == "unsupported" then
        return omniwm.l10n("This native notification action is unavailable.")
    elseif action.state == "failed" then
        return omniwm.l10n("The native notification action failed.")
    elseif action.state == "cancelled" then
        return omniwm.l10n("Notification action cancelled.")
    elseif action.state == "timeout" then
        return omniwm.l10n("Notification Center did not complete the action.")
    end
    return nil
end

local function emptyReply(value)
    for _, scalar in utf8.codes(value) do
        if not ((scalar >= 9 and scalar <= 13) or scalar == 32 or scalar == 133 or scalar == 160
            or scalar == 5760 or (scalar >= 8192 and scalar <= 8203) or scalar == 8232 or scalar == 8233
            or scalar == 8239 or scalar == 8287 or scalar == 12288) then
            return false
        end
    end
    return true
end

local function syncReplies(ctx, value)
    ctx.state.drafts = ctx.state.drafts or {}
    local action = if value then value.action else nil
    local key = if action then action.bundle .. ":" .. action.id .. ":" .. action.kind .. ":" .. action.state else nil
    if key ~= ctx.state.lastAction then
        ctx.state.lastAction = key
        local matching = false
        for _, item in (if value then value.items or {} else {}) do
            if string.lower(item.id) == (if action then action.id else nil) and item.bundle == action.bundle then
                matching = true
                break
            end
        end
        if action and matching and (action.state == "dispatched" or action.state == "dispatchedPanelOpen") and action.kind == "reply" then
            ctx.state.drafts[action.id] = nil
            if ctx.state.reply == action.id then
                ctx.state.reply = nil
                ctx.state.replyError = nil
            end
        end
    end
    if value and value.complete == true and (value.state == "ready" or value.state == "empty") then
        local retained = {}
        for _, item in value.items or {} do retained[string.lower(item.id)] = true end
        for id in ctx.state.drafts do
            if not retained[id] then ctx.state.drafts[id] = nil end
        end
        if ctx.state.reply and not retained[ctx.state.reply] then
            ctx.state.reply = nil
            ctx.state.replyError = nil
        end
    end
end

local function composer(ctx, item, action, width, busy)
    local id = string.lower(item.id)
    local draft = ctx.state.drafts[id] or ""
    local function send(next, event)
        if busy then return end
        local value = if event and event.text then event.text else next.state.drafts[id] or ""
        next.state.drafts[id] = value
        if string.find(value, "\0", 1, true) then
            next.state.replyError = omniwm.l10n("Reply contains unsupported characters.")
            return
        end
        if emptyReply(value) then
            next.state.replyError = omniwm.l10n("Reply cannot be empty.")
            return
        end
        if #value > 4096 then
            next.state.replyError = omniwm.l10n("Reply exceeds the 4096-byte limit.")
            return
        end
        local encoded = table.create(#value)
        for index = 1, #value do encoded[index] = string.format("%02x", string.byte(value, index)) end
        next.state.replyError = nil
        omniwm.run("notifications reply " .. item.bundle .. " " .. id .. " " .. table.concat(encoded))
    end
    local function cancel(next)
        next.state.reply = nil
        next.state.replyError = nil
    end
    local rows = { w = width, pad = 6, gap = 6, center = false,
        ui.input{ key = "notification-reply-" .. id, w = width - 12, h = 72, multiline = true, maxLength = 1024,
            text = draft, placeholder = if type(action.textInputPlaceholder) == "string" then action.textInputPlaceholder else nil,
            focus = true, color = "foreground",
            onChange = function(next, event)
                next.state.drafts[id] = event.text or ""
                next.state.replyError = nil
            end,
            onCommit = send, onCancel = cancel },
        ui.row{ gap = 6,
            button(omniwm.l10n("Send"), if busy or draft == "" then nil else send),
            button(omniwm.l10n("Cancel"), cancel) } }
    if ctx.state.replyError then
        rows[#rows + 1] = presentation.text{ text = ctx.state.replyError, style = "small", color = "secondaryForeground",
            maxWidth = width - 12, lines = 4 }
    end
    return presentation.group(rows, true)
end

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
    local value = ctx.data.notifications
    local action = value.action
    local id = string.lower(item.id)
    local busy = action and action.state == "pending"
    if value.complete == true then
        local reply = replyAction(item)
        local actions = { gap = 6,
            button(omniwm.l10n("Dismiss"), if busy then nil else "notifications dismiss " .. item.bundle .. " " .. id) }
        if reply then
            actions[#actions + 1] = button(omniwm.l10n("Reply"), function(next)
                next.state.reply = if next.state.reply == id then nil else id
                next.state.replyError = nil
            end)
        end
        rows[#rows + 1] = ui.row(actions)
        if reply and ctx.state.reply == id then
            rows[#rows + 1] = composer(ctx, item, reply, content, busy)
        end
    end
    if action and action.id == id and action.bundle == item.bundle then
        text(rows, actionMessage(action), content, "small", "secondaryForeground")
    end
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
    syncReplies(ctx, value)
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
