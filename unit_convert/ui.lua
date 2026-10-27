local F = punri.dofile("press_feedback.lua")
local M = {feedback = F}

M.keys = {"7", "8", "9", "Del", "4", "5", "6", "Clear", "1", "2", "3", "+/-", "0", "."}
local layout = {}
local CATEGORY_COLUMNS = 3
local CATEGORY_GAP = 4

function M.key_count()
    return #M.keys + ((punri.has_touch and punri.has_touch()) and 1 or 0)
end

function M.key_label(index)
    if index <= #M.keys then return M.keys[index] end
    return "Exit"
end

local function line_height(font)
    return math.max(1, punri.line_height(font))
end

-- Lua text coordinates are the top of the text line. Keep this calculation in
-- one place so labels use the real font metrics instead of guessed baselines.
local function text_y(y, height, font)
    return y + math.max(0, math.floor((height - line_height(font)) / 2))
end

local function fit_text(text, width, font, style)
    if width <= 0 then return "" end
    if punri.text_width(text, font, style) <= width then return text end
    -- The runner's wrapper is UTF-8-aware and adds an ellipsis when one line
    -- cannot fit. This path is uncommon and never runs for short fixed labels.
    local wrapped = punri.wrapped_text(text, width, font, style, 1)
    return wrapped[1] or ""
end

local function draw_in_rect(x, y, width, height, text, font, style, align, ink)
    local padding = 7
    local available = math.max(1, width - padding * 2)
    local visible = fit_text(text, available, font, style)
    local anchor = x + padding
    if align == "center" then anchor = x + math.floor(width / 2)
    elseif align == "right" then anchor = x + width - padding end
    punri.text(anchor, text_y(y, height, font), visible, font, style, align, ink ~= false)
end

local function draw_field(x, y, width, height, label, value, selected, id)
    local label_font, label_style = "small", "bold"
    local value_font, value_style = "ui10", "regular"
    local padding = 7
    local label_width = math.min(math.floor(width * 0.30), punri.text_width(label, label_font, label_style) + padding * 2)
    local value_x = x + label_width
    local value_width = math.max(1, width - label_width - padding)

    if selected then punri.rect_dither(x, y, width, height, false) end
    punri.rounded_rect(x, y, width, height, 5, false, selected and 2 or 1)
    local ink
    if id then F.target(id, x, y, width, height, true, "rounded", 5, false); ink = F.paint(id) end
    draw_in_rect(x, y, label_width, height, label, label_font, label_style, "left", ink)
    draw_in_rect(value_x, y, value_width, height, value, value_font, value_style, "right", ink)
end

local function picker_row_height(l, count)
    return math.max(25, math.min(38, math.floor((l.picker_bottom - l.picker_y - 2) / count)))
end

function M.compute(width, height, metrics, category_count)
    local l = layout
    l.w, l.h = width, height
    l.left = metrics.content_side_padding or 12
    l.right = width - l.left
    l.content_w = l.right - l.left
    l.bottom = height - math.max(40, metrics.button_hints_height or 0) - 3
    l.top = (metrics.top_padding or 0) + (metrics.header_height or 48) + 4
    local compact = height <= 520
    local columns = compact and width > height and 6 or CATEGORY_COLUMNS
    l.category_columns = math.min(columns, category_count or CATEGORY_COLUMNS)
    l.category_rows = math.ceil((category_count or CATEGORY_COLUMNS) / l.category_columns)
    l.category_gap = CATEGORY_GAP
    l.category_col_w = math.floor((l.content_w - l.category_gap * (l.category_columns - 1)) / l.category_columns)

    -- A landscape e-ink screen has to retain four keypad rows below these
    -- larger category controls, so compact fields reclaim the needed height.
    l.category_row_h = compact and 30 or 34
    l.category_y = l.top
    l.category_h = l.category_rows * l.category_row_h + (l.category_rows - 1) * l.category_gap
    l.input_y, l.input_h = l.category_y + l.category_h + 5, compact and 36 or 40
    l.from_y, l.row_h = l.input_y + l.input_h + 5, compact and 28 or 32
    l.swap_y, l.swap_h = l.from_y + l.row_h + 3, math.max(compact and 23 or 25, line_height("ui10") + 2)
    l.to_y = l.swap_y + l.swap_h + 3
    l.result_y, l.result_h = l.to_y + l.row_h + 5, compact and 38 or 43
    l.key_font = compact and "ui10" or "ui12"
    l.key_gap = 4
    local usable = l.bottom - (l.result_y + l.result_h) - 10
    l.key_h = math.max(26, math.min(68, math.floor((usable - l.key_gap * 3) / 4)))
    l.key_w = math.floor((l.content_w - l.key_gap * 3) / 4)
    l.key_y = l.bottom - (l.key_h * 4 + l.key_gap * 3)
    l.key_x = l.left
    l.picker_back_x, l.picker_back_y, l.picker_back_w, l.picker_back_h = l.left, l.top, 72, 31
    l.picker_title_x = l.picker_back_x + l.picker_back_w + 4
    l.picker_title_w = l.right - l.picker_title_x
    l.picker_y = l.top + 35
    l.picker_bottom = l.bottom
    return l
end

function M.category_rect(index)
    local l = layout
    local zero = index - 1
    local column = zero % l.category_columns
    local row = math.floor(zero / l.category_columns)
    local x = l.left + column * (l.category_col_w + l.category_gap)
    local width = column == l.category_columns - 1 and l.right - x or l.category_col_w
    return x, l.category_y + row * (l.category_row_h + l.category_gap), width, l.category_row_h
end

function M.category_at(x, y, count)
    for index = 1, count do
        local cx, cy, cw, ch = M.category_rect(index)
        if punri.in_rect(x, y, cx, cy, cw, ch) then return index end
    end
    return nil
end

function M.key_rect(index)
    local l = layout
    local zero = index - 1
    local column = zero % 4
    local row = math.floor(zero / 4)
    return l.key_x + column * (l.key_w + l.key_gap), l.key_y + row * (l.key_h + l.key_gap), l.key_w, l.key_h
end

function M.key_at(x, y)
    local l = layout
    for index = 1, M.key_count() do
        local kx, ky, kw, kh = M.key_rect(index)
        if punri.in_rect(x, y, kx, ky, kw, kh) then return index end
    end
    return nil
end

function M.draw_main(state)
    local l = layout
    punri.clear()
    punri.header("Unit Convert", state.category.short)

    for index, category in ipairs(state.categories) do
        local x, y, width, height = M.category_rect(index)
        local selected = category.id == state.category.id
        if selected then punri.rect_dither(x, y, width, height, false) end
        punri.rect(x, y, width, height, false, selected and 2 or 1)
        F.target("category:" .. index, x, y, width, height, true, "rect", 0, false)
        local ink = F.paint("category:" .. index)
        draw_in_rect(x, y, width, height, category.short, "ui10", selected and "bold" or "regular", "center", ink)
    end

    draw_field(l.left, l.input_y, l.content_w, l.input_h, "Input", state.input == "" and "Tap keypad" or state.input,
               state.focus == 5)
    draw_field(l.left, l.from_y, l.content_w, l.row_h, "From", state.from.label .. " (" .. state.from.symbol .. ")",
               state.focus == 2, "from")
    local swap_selected = state.focus == 4
    if swap_selected then punri.rect_dither(l.left, l.swap_y, l.content_w, l.swap_h, false) end
    punri.rounded_rect(l.left, l.swap_y, l.content_w, l.swap_h, 5, false, swap_selected and 2 or 1)
    F.target("swap", l.left, l.swap_y, l.content_w, l.swap_h, true, "rounded", 5, false)
    draw_in_rect(l.left, l.swap_y, l.content_w, l.swap_h, "Swap  <->", "ui10", "bold", "center", F.paint("swap"))
    draw_field(l.left, l.to_y, l.content_w, l.row_h, "To", state.to.label .. " (" .. state.to.symbol .. ")",
               state.focus == 3, "to")

    local result_text = state.result_text or "--"
    local result_label = state.result_error or ("Result in " .. state.to.label)
    if state.save_failed then result_label = "Save failed - Select or tap result to retry" end
    if state.result_error or state.save_failed then punri.rect_dither(l.left, l.result_y, l.content_w, l.result_h, false) end
    punri.rounded_rect(l.left, l.result_y, l.content_w, l.result_h, 5, false, 1)
    if state.save_failed then F.target("retry", l.left, l.result_y, l.content_w, l.result_h, true, "rounded", 5, false) end
    local result_ink
    if state.save_failed then result_ink = F.paint("retry") end
    if state.result_error or state.save_failed then
        draw_in_rect(l.left, l.result_y, l.content_w, l.result_h, result_label, "small", "regular", "left", result_ink)
    else
        local label_width = math.min(math.floor(l.content_w * 0.62), punri.text_width(result_label, "small", "regular") + 14)
        draw_in_rect(l.left, l.result_y, label_width, l.result_h, result_label, "small", "regular", "left")
        draw_in_rect(l.left + label_width, l.result_y, l.content_w - label_width, l.result_h, result_text, "ui12", "bold", "right")
    end

    for index = 1, M.key_count() do
        local key = M.key_label(index)
        local x, y, width, height = M.key_rect(index)
        local selected = state.focus == 5 and state.key_index == index
        if selected then punri.rect_dither(x, y, width, height, false) end
        punri.rounded_rect(x, y, width, height, 5, false, selected and 2 or 1)
        F.target("key:" .. index, x, y, width, height, true, "rounded", 5, false)
        draw_in_rect(x, y, width, height, key, l.key_font, selected and "bold" or "regular", "center", F.paint("key:" .. index))
    end
    F.footer({"Exit", state.save_failed and "Retry" or "Use", "Prev", "Next"}, {"back", "confirm", "left", "right"})
end

function M.draw_picker(state)
    local l = layout
    punri.clear()
    punri.header("Choose " .. state.picker_target, state.category.short)
    punri.rounded_rect(l.picker_back_x, l.picker_back_y, l.picker_back_w, l.picker_back_h, 5, false, 1)
    F.target("back", l.picker_back_x, l.picker_back_y, l.picker_back_w, l.picker_back_h, true, "rounded", 5, false)
    draw_in_rect(l.picker_back_x, l.picker_back_y, l.picker_back_w, l.picker_back_h, "Back", "small", "bold", "center", F.paint("back"))
    draw_in_rect(l.picker_title_x, l.top, l.picker_title_w, l.picker_y - l.top, "Select a unit", "ui10", "regular", "center")
    local count = #state.category.units
    local row_h = picker_row_height(l, count)
    l.picker_row_h = row_h
    for index, item in ipairs(state.category.units) do
        local y = l.picker_y + (index - 1) * row_h
        local selected = index == state.picker_index
        if selected then punri.rect_dither(l.left, y, l.content_w, row_h - 2, false) end
        punri.rect(l.left, y, l.content_w, row_h - 2, false, selected and 2 or 1)
        F.target("unit:" .. index, l.left, y, l.content_w, row_h - 2, true, "rect", 0, false)
        local ink = F.paint("unit:" .. index)
        local symbol_width = math.min(math.floor(l.content_w * 0.35), punri.text_width(item.symbol, "ui10", "bold") + 14)
        draw_in_rect(l.left, y, l.content_w - symbol_width, row_h - 2, item.label, "ui10", selected and "bold" or "regular", "left", ink)
        draw_in_rect(l.right - symbol_width, y, symbol_width, row_h - 2, item.symbol, "ui10", "bold", "right", ink)
    end
    F.footer({"Back", "Select", "Prev", "Next"}, {"back", "confirm", "left", "right"})
end

function M.picker_at(x, y, count)
    local l = layout
    if x < l.left or x > l.right or y < l.picker_y then return nil end
    -- An early tap can arrive before the requested picker redraw. Derive the
    -- same row geometry here instead of depending on draw_picker side effects.
    local row_h = l.picker_row_h or picker_row_height(l, count)
    local index = math.floor((y - l.picker_y) / row_h) + 1
    if index >= 1 and index <= count then return index end
    return nil
end

function M.layout()
    return layout
end

return M
