-- Rendering only. Input targets are regenerated on each draw and consumed by input.lua.

local UI = {targets = {}}
local floor = math.floor

local function bounds()
    local width, height = 480, 800
    if punri.get_bounds then width, height = punri.get_bounds() end
    return width, height, (punri.get_metrics and punri.get_metrics() or {})
end

local function add_target(id, x, y, width, height)
    UI.targets[#UI.targets + 1] = {id = id, x = x, y = y, w = width, h = height}
end

function UI.hit(x, y)
    for i = #UI.targets, 1, -1 do
        local target = UI.targets[i]
        if punri.in_rect(x, y, target.x, target.y, target.w, target.h) then return target.id end
    end
    return nil
end

local function header(title, right)
    punri.clear()
    punri.header(title, right or "")
end

local function content_top(metrics, gap)
    return (metrics.top_padding or 0) + (metrics.header_height or 70) + (gap or 12)
end

local function selected_ink(selected)
    if selected then return false end
    return true
end

local function message(app, width, y, lines)
    if app.notice and app.notice ~= "" then
        local wrapped = punri.wrapped_text(app.notice, width - 36, "small", "regular", lines or 3)
        for i, line in ipairs(wrapped.lines) do punri.text(18, y + (i - 1) * punri.line_height("small"), line, "small") end
    end
end

-- Lua's sandbox does not expose utf8, so move only between UTF-8 codepoints.
-- text_width() follows the renderer's bidi/shaping path, which makes clipping
-- agree with the pixels that punri.text() will actually draw.
local function previous_codepoint(value, at)
    at = at - 1
    while at > 1 and value:byte(at) >= 128 and value:byte(at) < 192 do at = at - 1 end
    return at
end

local function clip(value, width, font, style)
    if punri.text_width(value, font, style) <= width then return value end
    local suffix, at = "...", #value + 1
    if punri.text_width(suffix, font, style) > width then return "" end
    repeat at = previous_codepoint(value, at)
    until at <= 1 or punri.text_width(value:sub(1, at - 1) .. suffix, font, style) <= width
    return value:sub(1, at - 1) .. suffix
end

local function line_y(y, height, font)
    return y + floor((height - punri.line_height(font)) / 2)
end

local function has_rtl(value)
    for i = 1, #value do
        local byte = value:byte(i)
        if byte == 0xD7 or byte == 0xD8 or byte == 0xD9 or byte == 0xDA or byte == 0xDB or byte == 0xEF then return true end
    end
    return false
end

local function value_text(x, y, width, height, value, font, style, ink)
    local align = has_rtl(value) and "right" or "left"
    local anchor = align == "right" and x + width or x
    punri.text(anchor, line_y(y, height, font), clip(value, width, font, style), font, style, align, ink)
end

local function wrapped_value(x, y, width, value, font, style, maximum_lines, ink)
    local wrapped = punri.wrapped_text(value, width, font, style, maximum_lines)
    local align = has_rtl(value) and "right" or "left"
    local anchor = align == "right" and x + width or x
    for i, line in ipairs(wrapped.lines) do
        punri.text(anchor, y + (i - 1) * punri.line_height(font), line, font, style, align, ink)
    end
    return wrapped.total_height
end

local function box_label(x, y, width, height, label, font, style, ink)
    punri.text(x + floor(width / 2), line_y(y, height, font), clip(label, width - 20, font, style), font, style, "center", ink)
end

local function card_title(card)
    return card and card.fields and card.fields.title or ""
end

local function draw_library(app)
    local width, height, metrics = bounds()
    header("QR Cards", string.format("%d/%d", #app.cards, Cards.MAX_CARDS))
    UI.targets = {}
    local y = content_top(metrics)
    if app.data_error then
        local warning_h = 66
        punri.rounded_rect(14, y, width - 28, warning_h, 8, false, 2)
        value_text(24, y + 6, width - 48, punri.line_height("ui10"), "Saved data needs attention", "ui10", "bold", true)
        message(app, width, y + 9 + punri.line_height("ui10"), 2)
        y = y + warning_h + 12
    elseif #app.cards == 0 then
        punri.centered_text(y + 45, "No cards yet", "ui12", "bold")
        punri.centered_text(y + 72, "Choose New to create an offline QR card.", "small")
        y = y + 100
    end
    local max_rows = height < 600 and 3 or 5
    local start = math.max(1, math.min(app.selection - floor(max_rows / 2), math.max(1, #app.cards - max_rows + 1)))
    local finish = math.min(#app.cards, start + max_rows - 1)
    for index = start, finish do
        local card, selected = app.cards[index], index == app.selection
        local row_height, card_height = 84, 78
        punri.rounded_rect(14, y, width - 28, card_height, 8, selected, selected and false or 2, selected and false or true)
        local ink = selected_ink(selected)
        value_text(25, y + 5, width - 50, punri.line_height("small"), (selected and "> " or "") .. Cards.label_for(card.type), "small", "bold", ink)
        value_text(25, y + 7 + punri.line_height("small"), width - 50, punri.line_height("ui12"), card_title(card), "ui12", "bold", ink)
        value_text(25, y + 9 + punri.line_height("small") + punri.line_height("ui12"), width - 50, punri.line_height("small"), "Changed: " .. (card.modified or "Clock unavailable"), "small", "regular", ink)
        add_target("open:" .. index, 14, y, width - 28, card_height)
        y = y + row_height
    end
    local button_y = height - (metrics.button_hints_height or 40) - 54
    local button_width, right_x = floor((width - 54) / 2), width - 18 - floor((width - 54) / 2)
    punri.rounded_rect(18, button_y, button_width, 42, 8, false, 2)
    punri.rounded_rect(right_x, button_y, button_width, 42, 8, false, 2)
    box_label(18, button_y, button_width, 42, "New", "ui10", "bold", true)
    box_label(right_x, button_y, button_width, 42, "Actions", "ui10", "bold", true)
    add_target("new", 18, button_y, button_width, 42)
    add_target("actions", right_x, button_y, button_width, 42)
    punri.button_hints("Exit", "Open", "Previous", "Next")
end

local function draw_type_picker(app)
    local width, _, metrics = bounds()
    header("New QR card", "Choose type")
    UI.targets = {}
    local y = content_top(metrics)
    for index, item in ipairs(Cards.types) do
        local selected = index == app.type_selection
        punri.rounded_rect(18, y, width - 36, 56, 8, selected, selected and false or 2, selected and false or true)
        value_text(32, y, width - 64, 56, item.label, "ui12", "bold", selected_ink(selected))
        add_target("type:" .. item.id, 18, y, width - 36, 56)
        y = y + 66
    end
    punri.button_hints("Back", "Choose", "Previous", "Next")
end

local function draw_actions(app)
    local width, height, metrics = bounds()
    header("Card actions", #app.cards > 0 and card_title(app.cards[app.selection]) or "No card")
    UI.targets = {}
    local choices = {"Open", "New", "Edit", "Delete", "Move up", "Move down", "Privacy", "Back"}
    local y = content_top(metrics, 10)
    local content_bottom = height - (metrics.button_hints_height or 42) - 12
    local gap = 5
    local row_height = math.max(38, math.min(42, floor((content_bottom - y - gap * 7) / 8)))
    for index, label in ipairs(choices) do
        local selected = index == app.action_selection
        punri.rounded_rect(18, y, width - 36, row_height, 7, selected, selected and false or 2, selected and false or true)
        value_text(32, y, width - 64, row_height, label, "ui10", selected and "bold" or "regular", selected_ink(selected))
        add_target("action:" .. index, 18, y, width - 36, row_height)
        y = y + row_height + gap
    end
    punri.button_hints("Back", "Choose", "Previous", "Next")
end

local function preview_lines(card)
    local f = card.fields
    if card.type == "link" then return {f.content} end
    if card.type == "contact" then return {f.name, f.phone ~= "" and f.phone or "No phone", f.email ~= "" and f.email or "No email"} end
    if card.type == "wifi" then return {"Network: " .. f.ssid, "Security: " .. f.security, "Password: saved but hidden"} end
    return {f.message, f.contact ~= "" and "QR contact is available" or "No QR contact added"}
end

local function draw_preview(app)
    local width, height, metrics = bounds()
    local card = app.cards[app.selection]
    header(Cards.label_for(card.type), "Preview")
    UI.targets = {}
    local show_height = 42
    local show_y = height - (metrics.button_hints_height or 40) - show_height - 12
    local body_top = content_top(metrics)
    punri.rounded_rect(16, body_top, width - 32, show_y - body_top - 12, 10, false, 2)
    value_text(30, body_top + 10, width - 60, 32, card_title(card), "ui12", "bold", true)
    local y = body_top + 56
    if card.type == "emergency" then
        y = y + wrapped_value(30, y, width - 60, card.fields.message, "ui12", "bold", 7, true) + 12
    else
        for _, line in ipairs(preview_lines(card)) do
            y = y + wrapped_value(30, y, width - 60, line, "ui10", "regular", 3, true) + 10
        end
    end
    punri.rounded_rect(24, show_y, width - 48, show_height, 8, false, 2)
    box_label(24, show_y, width - 48, show_height, card.type == "emergency" and "Show contact QR" or "Show QR", "ui10", "bold", true)
    add_target("show_qr", 24, show_y, width - 48, show_height)
    punri.button_hints("Back", "Show QR", "Edit", "Actions")
end

local function draw_form(app)
    local width, height, metrics = bounds()
    local card = app.draft
    local fields = Cards.field_names(card.type)
    header("Edit " .. Cards.label_for(card.type), string.format("%d/%d", app.form_index, #fields))
    UI.targets = {}
    local y, row_height, gap = content_top(metrics), 58, 8
    local notice_y = height - (metrics.button_hints_height or 42) - 2 * punri.line_height("small") - 10
    local rows = math.max(1, floor((notice_y - y + gap) / (row_height + gap)))
    local first = math.max(1, math.min(app.form_index - floor(rows / 2), math.max(1, #fields - rows + 1)))
    local last = math.min(#fields, first + rows - 1)
    for index = first, last do
        local field = fields[index]
        local selected = index == app.form_index
        local value = card.fields[field]
        local display = field == "password" and (value == "" and "(empty)" or "Saved value hidden") or (value == "" and "(empty)" or value)
        local ink = selected_ink(selected)
        punri.rounded_rect(16, y, width - 32, row_height, 8, selected, selected and false or 2, ink)
        value_text(28, y + 5, width - 56, punri.line_height("small"), Cards.display_field(field), "small", "bold", ink)
        value_text(28, y + 7 + punri.line_height("small"), width - 56, punri.line_height("ui10"), display, "ui10", "regular", ink)
        add_target("field:" .. index, 16, y, width - 32, row_height)
        y = y + row_height + gap
    end
    message(app, width, notice_y, 2)
    punri.button_hints("Cancel", "Edit", "Previous", "Next/Save")
end

local function draw_confirmation(app)
    local width, height = bounds()
    header("Delete card", "Confirm")
    UI.targets = {}
    punri.centered_text(height / 2 - 85, "Delete this card?", "ui12", "bold")
    punri.centered_text(height / 2 - 55, "The default choice keeps it.", "small")
    local keep = not app.confirm_delete
    local left, button_width = 24, floor((width - 64) / 2)
    punri.rounded_rect(left, height / 2, button_width, 48, 8, keep, keep and false or 2, keep and false or true)
    punri.rounded_rect(width - left - button_width, height / 2, button_width, 48, 8, not keep, (not keep) and false or 2, (not keep) and false or true)
    box_label(left, height / 2, button_width, 48, "Keep", "ui10", "bold", selected_ink(keep))
    box_label(width - left - button_width, height / 2, button_width, 48, "Delete", "ui10", "bold", selected_ink(not keep))
    add_target("keep", left, height / 2, button_width, 48)
    add_target("delete", width - left - button_width, height / 2, button_width, 48)
    message(app, width, height / 2 + 65, 2)
    punri.button_hints("Back", "Confirm", "Keep", "Delete")
end

local function draw_privacy(app, pre_share)
    local width, height, metrics = bounds()
    header(pre_share and "Wi-Fi privacy" or "Privacy", "Local only")
    UI.targets = {}
    local text = pre_share
        and "This QR reveals the network name and password to anyone who scans or sees it. Card data is stored as readable text on the SD card."
        or "Cards are stored as readable text on the SD card. Anyone who sees a QR can read its contents. This app does not encrypt, upload, or sync data."
    local body_top = content_top(metrics)
    local wrapped = punri.wrapped_text(text, width - 50, "ui10", "regular", 8)
    for i, line in ipairs(wrapped.lines) do punri.text(25, body_top + (i - 1) * punri.line_height("ui10"), line, "ui10") end
    if pre_share then
        local button_y = height - (metrics.button_hints_height or 40) - 46 - 12
        punri.rounded_rect(25, button_y, width - 50, 46, 8, false, 2)
        box_label(25, button_y, width - 50, 46, "I understand — show QR", "ui10", "bold", true)
        add_target("privacy_continue", 25, button_y, width - 50, 46)
        punri.button_hints("Back", "Continue", "", "")
    else
        punri.button_hints("Back", "", "", "")
    end
end

local function draw_qr(app)
    local width, height, metrics = bounds()
    local card, code = app.cards[app.selection], app.qr
    header(Cards.label_for(card.type), "Scan with phone")
    UI.targets = {}
    local top = content_top(metrics, 8)
    if card.type == "emergency" then
        local line = clip(card.fields.message, width - 40, "small", "bold")
        punri.text(floor(width / 2), line_y(top, punri.line_height("small"), "small"), line, "small", "bold", "center")
        top = top + punri.line_height("small") + 8
    end
    local done_height = 42
    local done_y = height - (metrics.button_hints_height or 42) - done_height - 14
    local bottom = done_y - 10
    local available = math.max(0, math.min(width - 24, bottom - top))
    local scale = floor(available / (code.size + 8))
    punri.rounded_rect(24, done_y, width - 48, done_height, 8, false, 2)
    box_label(24, done_y, width - 48, done_height, "Done", "ui10", "bold", true)
    add_target("done_qr", 24, done_y, width - 48, done_height)
    if scale < 1 then
        punri.centered_text(top + 20, "Not enough space for this QR layout", "ui10", "bold")
        punri.button_hints("Done", "", "", "")
        return
    end
    local outer = (code.size + 8) * scale
    local left, y0 = floor((width - outer) / 2), top + floor((bottom - top - outer) / 2)
    local matrix_left, matrix_top = left + 4 * scale, y0 + 4 * scale
    for y = 0, code.size - 1 do
        local x = 0
        while x < code.size do
            while x < code.size and not QR.is_dark(code, x, y) do x = x + 1 end
            local run = x
            while x < code.size and QR.is_dark(code, x, y) do x = x + 1 end
            if x > run then punri.rect(matrix_left + run * scale, matrix_top + y * scale, (x - run) * scale, scale, true, true) end
        end
    end
    if card.type == "wifi" then
        punri.button_hints("Done", "", "Delete Wi-Fi", "")
    else
        punri.button_hints("Done", "", "", "")
    end
end

function UI.draw(app)
    if app.screen == "library" then draw_library(app)
    elseif app.screen == "type" then draw_type_picker(app)
    elseif app.screen == "actions" then draw_actions(app)
    elseif app.screen == "preview" then draw_preview(app)
    elseif app.screen == "form" then draw_form(app)
    elseif app.screen == "confirm_delete" then draw_confirmation(app)
    elseif app.screen == "privacy" then draw_privacy(app, false)
    elseif app.screen == "wifi_privacy" then draw_privacy(app, true)
    elseif app.screen == "qr" then draw_qr(app)
    else draw_library(app) end
end

return UI
