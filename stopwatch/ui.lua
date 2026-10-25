-- Drawing and hit-test geometry. Rectangles are created once and mutated so
-- every draw and input callback shares the exact same targets.
--
-- Lua text coordinates are the top of the font line box (LuaRunner adds the
-- font ascender before it draws glyphs). Keep vertical placement derived from
-- line_height(), not a guessed baseline or a font-name-specific offset.

local UI = {}

local layout = {
    width = 0, height = 0, landscape = false, visible_laps = 4,
    time = {}, laps = {},
    buttons = {
        {action = "toggle"}, {action = "lap"}, {action = "reset"}, {action = "exit"},
    },
    previous = {action = "previous"}, page = {}, next = {action = "next"},
    keep = {action = "keep"}, confirm = {action = "confirm"}, modal = {},
    modal_lines = {},
}

local function set_rect(rect, x, y, width, height)
    rect.x, rect.y, rect.w, rect.h = x, y, width, height
end

local function contains(rect, x, y)
    return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

local function line_height(font)
    return math.max(1, punri.line_height(font))
end

-- Truncate by complete UTF-8 codepoints. The platform measures the same
-- shaped/bidi-aware glyph stream it draws, so this is safe for future localised
-- labels as well as the current English app strings.
local function fit_text(text, max_width, font, style)
    if punri.text_width(text, font, style) <= max_width then return text end
    local suffix = "…"
    if punri.text_width(suffix, font, style) > max_width then return "" end
    local bytes = #text
    while bytes > 0 do
        local candidate = string.sub(text, 1, bytes) .. suffix
        if punri.text_width(candidate, font, style) <= max_width then return candidate end
        bytes = bytes - 1
        while bytes > 0 and string.byte(text, bytes + 1) >= 0x80 and string.byte(text, bytes + 1) < 0xC0 do
            bytes = bytes - 1
        end
    end
    return suffix
end

local function centered_y(y, height, font)
    return y + math.floor((height - line_height(font)) / 2)
end

local function draw_centered(x, y, width, height, text, font, style, color, padding)
    local inset = padding or 0
    local label = fit_text(text, math.max(1, width - inset * 2), font, style)
    punri.text(x + math.floor(width / 2), centered_y(y, height, font), label, font, style, "center", color)
end

local function draw_fitted(x, y, width, text, font, style, align, color)
    punri.text(x, y, fit_text(text, math.max(1, width), font, style), font, style, align, color)
end

function UI.refresh()
    local width, height = punri.get_bounds()
    local metrics = punri.get_metrics()
    local landscape = width > height
    if layout.width == width and layout.height == height and layout.landscape == landscape then return layout end

    layout.width, layout.height, layout.landscape = width, height, landscape
    local side = math.max(14, metrics.content_side_padding)
    local top = metrics.top_padding + metrics.header_height + 10
    local bottom = height - metrics.button_hints_height - 10
    local gap = 12

    if landscape then
        local available = width - side * 2 - gap
        local left_width = math.floor(available * 0.45)
        local right_width = available - left_width
        local right_x = side + left_width + gap
        set_rect(layout.time, side, top, left_width, 96)
        local button_y = top + layout.time.h + 14
        local button_width = math.floor((left_width - gap) / 2)
        local button_height = 62
        set_rect(layout.buttons[1], side, button_y, button_width, button_height)
        set_rect(layout.buttons[2], side + button_width + gap, button_y, button_width, button_height)
        set_rect(layout.buttons[3], side, button_y + button_height + gap, button_width, button_height)
        set_rect(layout.buttons[4], side + button_width + gap, button_y + button_height + gap, button_width, button_height)
        set_rect(layout.laps, right_x, top, right_width, bottom - top)
    else
        set_rect(layout.time, side, top, width - side * 2, 96)
        local button_y = top + layout.time.h + 14
        local button_width = math.floor((width - side * 2 - gap) / 2)
        local button_height = 60
        set_rect(layout.buttons[1], side, button_y, button_width, button_height)
        set_rect(layout.buttons[2], side + button_width + gap, button_y, button_width, button_height)
        set_rect(layout.buttons[3], side, button_y + button_height + gap, button_width, button_height)
        set_rect(layout.buttons[4], side + button_width + gap, button_y + button_height + gap, button_width, button_height)
        local laps_y = button_y + button_height * 2 + gap + 14
        set_rect(layout.laps, side, laps_y, width - side * 2, bottom - laps_y)
    end

    local heading_height = line_height("ui12")
    local small_height = line_height("small")
    layout.laps_heading_y = layout.laps.y + 10
    layout.laps_columns_y = layout.laps_heading_y + heading_height + 7
    layout.laps_separator_y = layout.laps_columns_y + small_height + 5
    layout.rows_y = layout.laps_separator_y + 8
    layout.pager_height = math.max(26, small_height + 10)
    local pager_y = layout.laps.y + layout.laps.h - layout.pager_height - 10
    local pager_gap = 8
    local pager_width = math.floor((layout.laps.w - 24 - pager_gap * 2) / 3)
    set_rect(layout.previous, layout.laps.x + 12, pager_y, pager_width, layout.pager_height)
    set_rect(layout.page, layout.previous.x + pager_width + pager_gap, pager_y, pager_width, layout.pager_height)
    set_rect(layout.next, layout.page.x + pager_width + pager_gap, pager_y, pager_width, layout.pager_height)
    layout.best_y = pager_y - small_height - 5
    local row_space = layout.best_y - 6 - layout.rows_y
    layout.visible_laps = math.max(1, math.min(4, math.floor(row_space / math.max(1, small_height + 6))))
    layout.row_height = math.max(small_height + 4, math.floor(row_space / layout.visible_laps))

    local modal_width = math.min(width - side * 2, landscape and 360 or 420)
    local description = "Laps and elapsed time will be cleared."
    local wrapped = punri.wrapped_text(description, modal_width - 24, "small", "regular", 2)
    layout.modal_lines = wrapped.lines
    local modal_height = 12 + heading_height + 7 + wrapped.total_height + 12 + 32 + 12
    local modal_x = math.floor((width - modal_width) / 2)
    local modal_y = math.max(top + 8, math.floor((top + bottom - modal_height) / 2))
    if not landscape then
        -- Start at the laps card instead of cutting through its heading. The
        -- dimming frame otherwise visibly clips "Laps" behind the modal.
        modal_y = math.max(top + 8, layout.laps.y + 4)
    end
    set_rect(layout.modal, modal_x, modal_y, modal_width, modal_height)
    local modal_button_width = math.floor((modal_width - 36) / 2)
    set_rect(layout.keep, modal_x + 12, modal_y + modal_height - 44, modal_button_width, 32)
    set_rect(layout.confirm, layout.keep.x + modal_button_width + 12, modal_y + modal_height - 44, modal_button_width, 32)
    return layout
end

function UI.visible_laps()
    return UI.refresh().visible_laps
end

function UI.hit_action(model, x, y)
    local active = UI.refresh()
    if model.reset_pending then
        if contains(active.keep, x, y) then return "keep" end
        if contains(active.confirm, x, y) then return "confirm" end
        return nil
    end
    for index = 1, #active.buttons do
        if contains(active.buttons[index], x, y) then return active.buttons[index].action end
    end
    if contains(active.previous, x, y) then return "previous" end
    if contains(active.next, x, y) then return "next" end
    return nil
end

local function draw_button(rect, label, enabled, primary, selected)
    if enabled and primary then
        punri.rounded_rect(rect.x, rect.y, rect.w, rect.h, 8, true, true)
        draw_centered(rect.x, rect.y, rect.w, rect.h, label, "ui12", "bold", false, 8)
    else
        punri.rounded_rect(rect.x, rect.y, rect.w, rect.h, 8, false, selected and 3 or 1, true)
        if not enabled then punri.rect_dither(rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, false) end
        draw_centered(rect.x, rect.y, rect.w, rect.h, label, "ui12", selected and "bold" or "regular", enabled, 8)
    end
end

local function draw_time(model, rect)
    local message = model:message()
    local time_height = line_height("ui12")
    local small_height = line_height("small")
    local group_height = time_height + 5 + small_height
    if message then group_height = group_height + 3 + small_height end
    local y = rect.y + math.floor((rect.h - group_height) / 2)
    draw_centered(rect.x, y, rect.w, time_height, model:format_time(model:elapsed()), "ui12", "bold", true, 10)
    y = y + time_height + 5
    draw_centered(rect.x, y, rect.w, small_height, model:status(), "small", "bold", true, 10)
    if message then
        y = y + small_height + 3
        draw_centered(rect.x, y, rect.w, small_height, message, "small", "bold", true, 10)
    end
end

local function draw_laps(model, active)
    local card = active.laps
    punri.rounded_rect(card.x, card.y, card.w, card.h, 9, false, 2, true)
    draw_fitted(card.x + 12, active.laps_heading_y, card.w - 24, "Laps", "ui12", "bold", "left", true)
    draw_fitted(card.x + 16, active.laps_columns_y, math.floor(card.w * 0.24), "Lap", "small", "bold", "left", true)
    draw_fitted(card.x + math.floor(card.w * 0.54), active.laps_columns_y, math.floor(card.w * 0.30), "Lap time", "small", "bold", "center", true)
    draw_fitted(card.x + card.w - 16, active.laps_columns_y, math.floor(card.w * 0.24), "Total", "small", "bold", "right", true)
    punri.line(card.x + 12, active.laps_separator_y, card.x + card.w - 12, active.laps_separator_y, true)

    local count = #model.laps
    if count == 0 then
        local first_height = line_height("ui12")
        local second_height = line_height("small")
        local group_height = first_height + 6 + second_height
        local y = active.rows_y + math.floor((active.best_y - active.rows_y - group_height) / 2)
        draw_centered(card.x, y, card.w, first_height, "No laps yet", "ui12", "bold", true, 12)
        y = y + first_height + 6
        draw_centered(card.x, y, card.w, second_height, "Start, then tap Lap", "small", "regular", true, 12)
    else
        local best, worst = model:best_worst()
        local page_start = count - model.lap_page * active.visible_laps
        for row = 0, active.visible_laps - 1 do
            local index = page_start - row
            if index < 1 then break end
            local lap = model.laps[index]
            local y = active.rows_y + row * active.row_height + math.floor((active.row_height - line_height("small")) / 2)
            local is_best = best ~= nil and lap.lap_ms == best
            draw_fitted(card.x + 16, y, math.floor(card.w * 0.24), string.format("#%d", index), "small",
                is_best and "bold" or "regular", "left", true)
            draw_fitted(card.x + math.floor(card.w * 0.54), y, math.floor(card.w * 0.30), model:format_time(lap.lap_ms),
                "small", is_best and "bold" or "regular", "center", true)
            draw_fitted(card.x + card.w - 16, y, math.floor(card.w * 0.24), model:format_time(lap.total_ms),
                "small", "regular", "right", true)
            if row < active.visible_laps - 1 and index > 1 then
                local line_y = active.rows_y + (row + 1) * active.row_height - 2
                punri.line(card.x + 12, line_y, card.x + card.w - 12, line_y, true)
            end
        end
        if count > 1 then
            draw_centered(card.x, active.best_y, card.w, line_height("small"),
                "Best " .. model:format_time(best) .. "  Worst " .. model:format_time(worst), "small", "regular", true, 12)
        end
    end

    local pages = math.max(1, math.floor((count - 1) / active.visible_laps) + 1)
    draw_button(active.previous, "Prev", model.lap_page < pages - 1, false, false)
    draw_button(active.next, "Next", model.lap_page > 0, false, false)
    punri.rounded_rect(active.page.x, active.page.y, active.page.w, active.page.h, 8, false, 1, true)
    draw_centered(active.page.x, active.page.y, active.page.w, active.page.h,
        string.format("Page %d/%d", model.lap_page + 1, pages), "small", "regular", true, 4)
end

local function draw_confirmation(model, active)
    local modal = active.modal
    punri.rect_dither(modal.x - 4, modal.y - 4, modal.w + 8, modal.h + 8, false)
    punri.rounded_rect(modal.x, modal.y, modal.w, modal.h, 10, true, false)
    punri.rounded_rect(modal.x, modal.y, modal.w, modal.h, 10, false, 2, true)
    local title_height = line_height("ui12")
    draw_centered(modal.x, modal.y + 12, modal.w, title_height, "Reset stopwatch?", "ui12", "bold", true, 12)
    local body_y = modal.y + 12 + title_height + 7
    for index = 1, #active.modal_lines do
        draw_centered(modal.x, body_y, modal.w, line_height("small"), active.modal_lines[index], "small", "regular", true, 12)
        body_y = body_y + line_height("small")
    end
    draw_button(active.keep, "Keep", true, false, model.reset_choice == "keep")
    draw_button(active.confirm, "Reset now", true, model.reset_choice == "confirm", model.reset_choice == "confirm")
end

function UI.draw(model)
    local active = UI.refresh()
    punri.clear()
    punri.header("Stopwatch", model:status())
    punri.rounded_rect(active.time.x, active.time.y, active.time.w, active.time.h, 9, false, 2, true)
    draw_time(model, active.time)

    local toggle_label = model.running and "Stop" or "Start"
    local exit_label = model.save_error and "Retry save" or "Exit"
    draw_button(active.buttons[1], toggle_label, model:is_toggle_enabled(), true, false)
    draw_button(active.buttons[2], "Lap", model:is_lap_enabled(), false, false)
    draw_button(active.buttons[3], "Reset", model:is_reset_enabled(), false, false)
    draw_button(active.buttons[4], exit_label, true, false, false)
    draw_laps(model, active)

    if model.reset_pending then
        draw_confirmation(model, active)
        punri.button_hints("Keep", "Select", "Keep", "Reset")
    else
        punri.button_hints(model.save_error and "Retry" or "Exit", toggle_label, "Lap", "Reset")
    end
end

return UI
