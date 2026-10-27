-- Lua text positions are top-left positions (LuaRunner forwards them to
-- GfxRenderer::drawText, which adds the font ascender).  All vertical layout
-- below therefore uses the measured line height instead of a guessed baseline.
local F = punri.dofile("press_feedback.lua")
local M = {feedback = F, ids = {}}
function M.key(x, y) return math.floor(y) * 4096 + math.floor(x) end

local HORIZONTAL_PADDING = 8
local ROW_GAP = 8

function M.content_bounds()
    local width, height = punri.get_bounds()
    local metrics = punri.get_metrics()
    return width, height, metrics, metrics.top_padding + metrics.header_height + 8,
        height - math.max(40, metrics.button_hints_height or 0) - 8
end

function M.fit(text, width, font, style)
    if width <= 0 then return "" end
    local wrapped = punri.wrapped_text(tostring(text or ""), width, font, style, 1)
    return wrapped.lines[1] or ""
end

function M.row_height(with_secondary)
    if with_secondary then
        return punri.line_height("ui10") + punri.line_height("small") + 8
    end
    return punri.line_height("ui12") + 12
end

local function text_top(y, height, font)
    return y + math.max(0, math.floor((height - punri.line_height(font)) / 2))
end

function M.text_in_rect(x, y, width, height, text, font, style, align, color, padding)
    padding = padding == nil and HORIZONTAL_PADDING or padding
    align = align or "left"
    color = color == nil and true or color
    local value = M.fit(text, width - 2 * padding, font, style)
    local anchor = x + padding
    if align == "center" then anchor = x + math.floor(width / 2)
    elseif align == "right" then anchor = x + width - padding end
    punri.text(anchor, text_top(y, height, font), value, font, style, align, color)
    return value
end

function M.paired_text(x, y, width, height, label, detail, font, style, label_color, detail_color)
    local padding = HORIZONTAL_PADDING
    label_color = label_color == nil and true or label_color
    detail_color = detail_color == nil and true or detail_color
    local detail_value = M.fit(detail, math.max(44, math.floor((width - 2 * padding) * 0.42)), font, style)
    local detail_width = punri.text_width(detail_value, font, style)
    local label_width = math.max(24, width - 2 * padding - detail_width - ROW_GAP)
    local label_value = M.fit(label, label_width, font, style)
    local top = text_top(y, height, font)
    punri.text(x + padding, top, label_value, font, style, "left", label_color)
    if detail_value ~= "" then
        punri.text(x + width - padding, top, detail_value, font, style, "right", detail_color)
    end
    return label_value, detail_value
end

function M.row(x, y, width, height, label, selected, detail, secondary)
    if selected then
        -- E-ink fonts are not guaranteed to have a usable white glyph pass on
        -- every built-in face.  A double outline keeps keyboard focus obvious
        -- without turning its label into invisible black-on-black text.
        punri.rounded_rect(x, y, width, height, 5, false, 2, true)
        punri.rounded_rect(x + 3, y + 3, width - 6, height - 6, 3, false, 1, true)
    else
        punri.rounded_rect(x, y, width, height, 5, false, 1, true)
    end
    local id = M.key(x, y)
    F.target(id, x, y, width, height, true, "rounded", 5, true)
    if selected then F.focus = id end
    local foreground = F.paint(id)
    if foreground == nil then foreground = true end
    if secondary then
        local primary_font, secondary_font = "ui10", "small"
        local primary_height = punri.line_height(primary_font)
        local secondary_height = punri.line_height(secondary_font)
        local combined = primary_height + secondary_height
        local top = y + math.max(2, math.floor((height - combined) / 2))
        local padding = HORIZONTAL_PADDING
        local detail_value = M.fit(detail, math.max(44, math.floor((width - 2 * padding) * 0.42)), primary_font, "regular")
        local detail_width = punri.text_width(detail_value, primary_font, "regular")
        local label_value = M.fit(label, math.max(24, width - 2 * padding - detail_width - ROW_GAP), primary_font,
            selected and "bold" or "regular")
        punri.text(x + padding, top, label_value, primary_font, selected and "bold" or "regular", "left", foreground)
        if detail_value ~= "" then
            punri.text(x + width - padding, top, detail_value, primary_font, "regular", "right", foreground)
        end
        local secondary_value = M.fit(secondary, width - 2 * padding, secondary_font, "regular")
        punri.text(x + width - padding, top + primary_height, secondary_value, secondary_font, "regular", "right", foreground)
        return
    end
    if detail then
        M.paired_text(x, y, width, height, label, detail, "ui12", selected and "bold" or "regular", foreground, foreground)
    else
        M.text_in_rect(x, y, width, height, label, "ui12", selected and "bold" or "regular", "center", foreground)
    end
end

function M.button(x, y, width, height, label, selected, feedback_id)
    if selected then
        punri.rounded_rect(x, y, width, height, 5, false, 2, true)
        punri.rounded_rect(x + 3, y + 3, width - 6, height - 6, 3, false, 1, true)
    else
        punri.rounded_rect(x, y, width, height, 5, false, 1, true)
    end
    local id = feedback_id or M.key(x, y)
    F.target(id, x, y, width, height, true, "rounded", 5, true)
    if selected then F.focus = id end
    local ink = F.paint(id)
    if ink == nil then ink = true end
    M.text_in_rect(x, y, width, height, label, "ui10", "bold", "center", ink)
end

function M.message(x, y, width, text, max_lines, font, style)
    font, style = font or "ui10", style or "regular"
    local wrapped = punri.wrapped_text(text, width, font, style, max_lines or 4)
    local line_height = punri.line_height(font)
    for index, line in ipairs(wrapped.lines) do
        punri.text(x, y + (index - 1) * line_height, line, font, style)
    end
    return #wrapped.lines * line_height
end

function M.notice(x, y, width, text, selected)
    local padding = HORIZONTAL_PADDING
    local message_height = punri.wrapped_text(text, width - 2 * padding, "ui10", "bold", 2).total_height
    local height = math.max(34, message_height + 2 * padding)
    punri.rounded_rect(x, y, width, height, 5, selected, 1, true)
    M.message(x + padding, y + math.floor((height - message_height) / 2), width - 2 * padding, text, 2, "ui10", "bold")
    return height
end

-- Rows stop before the action bar. Windowing keeps every city reachable
-- without drawing a partially covered final row on short landscape screens.
function M.rows_fit(top, bottom, row_height, maximum)
    return math.max(1, math.min(maximum or 100, math.floor((bottom - 32 - 8 - top + 6) / (row_height + 6))))
end

function M.row_window(cursor, count, per_page)
    local first = math.floor((math.max(1, cursor) - 1) / per_page) * per_page + 1
    return first, math.min(count, first + per_page - 1)
end

function M.bottom_actions(width, bottom, count)
    local side, gap, height = 12, 8, 32
    local button_width = math.floor((width - 2 * side - (count - 1) * gap) / count)
    local y = bottom - height
    local result = {}
    for index = 1, count do
        result[index] = {x = side + (index - 1) * (button_width + gap), y = y, w = button_width, h = height}
    end
    return result
end

function M.centered_line(y, width, text, font, style, color)
    color = color == nil and true or color
    local value = M.fit(text, width - 24, font, style)
    punri.text(math.floor(width / 2), y, value, font, style, "center", color)
    return punri.line_height(font)
end

return M
