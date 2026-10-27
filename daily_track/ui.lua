-- Rendering is deliberately passive: it writes no files and emits reusable
-- hit rectangles only.  main.lua maps those rectangles to the same actions as
-- physical buttons.
local F = punri.dofile("press_feedback.lua")
local ui = {feedback = F}
local calendar = punri.dofile("calendar.lua")
local model = punri.dofile("model.lua")

local function metrics()
    local m = punri.get_metrics and punri.get_metrics() or {}
    local w, h = punri.get_bounds()
    return w, h, math.max(12, m.content_side_padding or 16),
        (m.top_padding or 4) + (m.header_height or 52) + 12,
        h - (m.button_hints_height or 54) - 12
end

function ui.begin(view)
    view.hit_count = 0
end

local function hit(view, x, y, w, h, action)
    view.hit_count = view.hit_count + 1
    local item = view.hits[view.hit_count] or {}
    item.x, item.y, item.w, item.h, item.action = x, y, w, h, action
    view.hits[view.hit_count] = item
end

function ui.hit_at(view, x, y)
    for i = view.hit_count, 1, -1 do
        local item = view.hits[i]
        if punri.in_rect(x, y, item.x, item.y, item.w, item.h) then return item.action end
    end
    return nil
end

-- Truncate by UTF-8 codepoint and by measured pixels, never by byte count.
-- Tracker names are user input and may be Arabic or mixed-script text.
local function fit_text(value, max_width, font, style)
    value = tostring(value or "")
    if max_width <= 0 or punri.text_width(value, font, style) <= max_width then return value end
    local suffix = "..."
    if punri.text_width(suffix, font, style) > max_width then return "" end
    local index, last = 1, 0
    while index <= #value do
        local byte = value:byte(index)
        local length = byte < 128 and 1 or (byte < 224 and 2 or (byte < 240 and 3 or 4))
        if index + length - 1 > #value then break end
        local candidate = value:sub(1, index + length - 1) .. suffix
        if punri.text_width(candidate, font, style) > max_width then break end
        last, index = index + length - 1, index + length
    end
    return last > 0 and value:sub(1, last) .. suffix or suffix
end

local function button_width(label, minimum)
    return math.max(minimum or 0, punri.text_width(label, "ui10", "regular") + 12)
end

local function button(view, x, y, w, h, label, action, selected)
    punri.rounded_rect(x, y, w, h, 5, selected and true or false)
    F.target(action, x, y, w, h, true, "rounded", 5, selected)
    local ink = F.paint(action)
    if ink == nil then ink = not selected end
    -- `punri.text` uses the top of the glyph box, not a baseline.  The UI_10
    -- font is taller than the old fixed 14-pixel estimate on the X4 display,
    -- which put the lower half of labels outside short controls.  Centre using
    -- the renderer's real line height so every button size and orientation
    -- stays aligned.
    local line_h = punri.line_height("ui10")
    local shown = fit_text(label, math.max(1, w - 12), "ui10", "regular")
    punri.text(x + math.floor(w / 2), y + math.floor((h - line_h) / 2), shown,
        "ui10", "regular", "center", ink)
    hit(view, x, y, w, h, action)
end

local function tracker_header(title, tracker, width)
    local available = math.max(48, width - punri.text_width(title, "ui12", "bold") - 48)
    punri.header(title, fit_text(tracker.name, available, "small", "regular"))
end

local function footer(view, w, bottom, margin, message)
    local gap, count = 6, 3
    local bw = math.floor((w - margin * 2 - gap * (count - 1)) / count)
    local footer_h, y = 44, bottom - 44
    button(view, margin, y, bw, footer_h, "Manage", "manage")
    local retry = message and message:find("Retry", 1, true)
    button(view, margin + bw + gap, y, bw, footer_h, retry and "Retry" or "Export", retry and "retry" or "export")
    button(view, margin + (bw + gap) * 2, y, bw, footer_h, "Exit", "exit")
end

local function retry_button(view, message, screen)
    if not message or not message:find("Retry", 1, true) then return end
    if screen == "today" then return end -- Today places Retry in its footer.
    local w, h, margin, top, bottom = metrics()
    -- Other screens retain an explicit retry target without overlapping the
    -- shared header's date/battery region.
    button(view, w - margin - 70, bottom - 40, 70, 30, "Retry", "retry", false)
end

local function draw_today(state, view, message)
    local w, h, margin, top, bottom = metrics()
    punri.header("Daily Track", state.date)
    local footer_top = bottom - 60
    local columns = w >= 640 and 2 or 1
    -- Lay content out from measured line heights.  The prior fixed positions
    -- let counter metadata touch the primary button on the device font.
    local title_h = punri.line_height("ui12")
    local status_h = punri.line_height("ui12")
    local detail_h = punri.line_height("small")
    local action_h = math.max(34, punri.line_height("ui10") + 8)
    local gap, card_h = 10, 10 + title_h + 2 + status_h + 2 + detail_h + 10 + action_h + 8
    local card_w = math.floor((w - margin * 2 - gap * (columns - 1)) / columns)
    local rows = math.max(1, math.floor((footer_top - top) / (card_h + gap)))
    local per_page = rows * columns
    local page_count = math.max(1, math.ceil(#state.trackers / per_page))
    view.today_page = math.max(1, math.min(view.today_page or 1, page_count))
    view.cards_per_page = per_page
    local first = (view.today_page - 1) * per_page + 1
    local last = math.min(#state.trackers, first + per_page - 1)
    if #state.trackers == 0 then
        punri.centered_text(top + 72, "No daily trackers yet", "ui12", "bold")
        punri.centered_text(top + 102, "Manage to add a Habit or Counter.", "ui10")
    end
    for index = first, last do
        local tracker = state.trackers[index]
        local offset = index - first
        local col, row = offset % columns, math.floor(offset / columns)
        local x, y = margin + col * (card_w + gap), top + row * (card_h + gap)
        local selected = index == view.selected
        -- A thick outline communicates button selection without turning child
        -- controls black-on-black on e-paper displays.
        punri.rounded_rect(x, y, card_w, card_h, 7, false, selected and 2 or 1)
        -- Register the broad card first.  Later, narrower child controls win
        -- hit testing because input.lua walks the reusable array backwards.
        hit(view, x, y, card_w, 82, "primary:" .. tracker.id)
        local detail_w = button_width("Details", 64)
        local detail_x = x + card_w - detail_w - 8
        local title_room = math.max(1, detail_x - (x + 12) - 8)
        local title_y = y + 10
        local status_y = title_y + title_h + 2
        local detail_y = status_y + status_h + 2
        punri.text(x + 12, title_y, fit_text(tracker.name, title_room, "ui12", "bold"), "ui12", "bold", "left", true)
        local current_day = model.find_day(tracker, state.date)
        local status
        if tracker.kind == "habit" then
            status = current_day and current_day.value == 1 and "DONE  [X]" or "Not done  [ ]"
        elseif current_day then
            status = tracker.goal > 0 and string.format("%d / %d", current_day.value, current_day.goal) or
                string.format("%d logged", current_day.value)
        else
            status = tracker.goal > 0 and string.format("0 / %d", tracker.goal) or "0 logged"
        end
        punri.text(x + 12, status_y, fit_text(status, card_w - 24, "ui12", "regular"), "ui12", "regular", "left", true)
        local streak, best = model.streaks(tracker, state.date)
        local footer_text = streak and string.format("Chain %d  Best %d", streak, best) or "No goal: no chain"
        punri.text(x + 12, detail_y, fit_text(footer_text, card_w - 24, "small", "regular"), "small", "regular", "left", true)
        local action_label = tracker.kind == "habit" and "Toggle" or ("+" .. tostring(tracker.step))
        local action_w = math.floor((card_w - 30) * 0.56)
        local action_y = y + card_h - action_h - 8
        button(view, x + 10, action_y, action_w, action_h, action_label, "primary:" .. tracker.id, selected)
        button(view, x + 16 + action_w, action_y, card_w - action_w - 26, action_h, "Undo", "undo:" .. tracker.id, false)
        button(view, detail_x, y + 4, detail_w, action_h, "Details", "details:" .. tracker.id, false)
    end
    if page_count > 1 then
        punri.text(w - margin, footer_top - 16, string.format("Page %d/%d", view.today_page, page_count), "small", "regular", "right")
    end
    if message and message ~= "" then punri.text(margin, footer_top - 16, message, "small") end
    footer(view, w, bottom, margin, message)
    punri.button_hints("Exit", "Do", "Details", "Manage")
end

local function draw_manage(state, view, message)
    local w, h, margin, top, bottom = metrics()
    punri.header("Manage Trackers", string.format("%d/%d", #state.trackers, model.MAX_TRACKERS))
    button(view, margin, top, 76, 28, "Back", "today", false)
    local row_h = 40
    local labels = {"+ Habit", "+ Counter"}
    for _, tracker in ipairs(state.trackers) do labels[#labels + 1] = tracker.name end
    view.manage_selected = math.max(1, math.min(view.manage_selected or 1, #labels))
    for i, label in ipairs(labels) do
        local y = top + 36 + (i - 1) * row_h
        if y + row_h > bottom - 28 then break end
        local chosen = i == view.manage_selected
        local action = i == 1 and "add:habit" or (i == 2 and "add:counter" or "edit:" .. state.trackers[i - 2].id)
        button(view, margin, y, w - margin * 2, row_h - 5, label, action, chosen)
    end
    if message and message ~= "" then punri.text(margin, bottom - 26, message, "small") end
    punri.button_hints("Back", "Select", "Up", "Down")
end

local function draw_edit(state, view, tracker, message)
    local w, h, margin, top, bottom = metrics()
    tracker_header("Edit Tracker", tracker, w)
    local labels = {"Name", tracker.kind == "counter" and ("Goal: " .. tracker.goal) or "Goal: habit",
        tracker.kind == "counter" and ("Step: " .. tracker.step) or "Step: habit", "Move up", "Move down", "Delete", "Back"}
    view.edit_selected = math.max(1, math.min(view.edit_selected or 1, #labels))
    local row_h = 46
    for i, label in ipairs(labels) do
        local y = top + (i - 1) * row_h
        if y + row_h > bottom - 20 then break end
        local action = "edit_action:" .. i
        button(view, margin, y, w - margin * 2, row_h - 5, label, action, i == view.edit_selected)
    end
    if tracker.kind == "counter" then
        local today = model.find_day(tracker, state.date)
        if today then punri.text(margin, bottom - 42, "Today's recorded target stays unchanged.", "small") end
    end
    if message and message ~= "" then punri.text(margin, bottom - 24, message, "small") end
    punri.button_hints("Back", "Select", "Up", "Down")
end

local function draw_details(state, view, tracker, message)
    local w, h, margin, top, bottom = metrics()
    tracker_header("Tracker Details", tracker, w)
    local streak, best = model.streaks(tracker, state.date)
    local cursor
    if streak then
        local summary = string.format("Current %d days    Best %d days (all time)", streak, best)
        if punri.text_width(summary, "ui10", "bold") <= w - margin * 2 then
            punri.text(margin, top, summary, "ui10", "bold")
            cursor = top + punri.line_height("ui10") + 8
        else
            punri.text(margin, top, string.format("Current %d days", streak), "ui10", "bold")
            punri.text(margin, top + punri.line_height("ui10") + 2,
                string.format("Best %d days (all time)", best), "ui10", "bold")
            cursor = top + punri.line_height("ui10") * 2 + 10
        end
    else
        punri.text(margin, top, "Counter without a goal: no chain", "ui10", "bold")
        cursor = top + punri.line_height("ui10") + 8
    end

    local current_month = calendar.month_start(state.date)
    local earliest_month = calendar.month_start(model.history_start(state.date))
    local shown_month = calendar.month_start(view.detail_month or current_month)
    if not shown_month or calendar.compare(shown_month, current_month) == 1 then shown_month = current_month end
    if calendar.compare(shown_month, earliest_month) == -1 then shown_month = earliest_month end
    view.detail_month = shown_month
    punri.text(math.floor(w / 2), cursor, calendar.month_label(shown_month), "ui10", "bold", "center")
    local weekday_y = cursor + punri.line_height("ui10") + 5
    local cell_w = math.max(1, math.floor((w - margin * 2) / 7))
    local weekday_labels = {"S", "M", "T", "W", "T", "F", "S"}
    for col, label in ipairs(weekday_labels) do
        punri.text(margin + math.floor((col - 0.5) * cell_w), weekday_y, label, "small", "bold", "center")
    end
    local grid_y = weekday_y + punri.line_height("small") + 5
    local year, month = calendar.parse(shown_month)
    local first_weekday = calendar.weekday(shown_month)
    local days_in_month = calendar.days_in_month(year, month)
    local rows = math.ceil((first_weekday + days_in_month) / 7)
    local info_lines = tracker.kind == "counter" and 2 or 1
    local footer_h, control_y = 48, bottom - 56
    local grid_h = math.max(rows * 24, math.min(300,
        control_y - grid_y - info_lines * punri.line_height("small") - 18))
    local cell_h = math.max(24, math.floor(grid_h / rows))
    for day = 1, days_in_month do
        local index = first_weekday + day - 1
        local col, row = index % 7, math.floor(index / 7)
        local x, y = margin + col * cell_w, grid_y + row * cell_h
        local date = calendar.format(year, month, day)
        local status = model.day_status(tracker, date, state.date)
        punri.rect(x + 1, y + 1, cell_w - 3, cell_h - 3, false)
        if status == "complete" then
            punri.rect(x + 2, y + 2, cell_w - 4, cell_h - 4, true)
            punri.text(x + math.floor(cell_w / 2), y + math.floor((cell_h - punri.line_height("ui10")) / 2),
                "X", "ui10", "bold", "center", false)
        elseif status == "logged" then
            punri.rect_dither(x + 2, y + 2, cell_w - 4, cell_h - 4)
            punri.text(x + math.floor(cell_w / 2), y + math.floor((cell_h - punri.line_height("ui10")) / 2),
                ".", "ui10", "bold", "center")
        end
        punri.text(x + 3, y + 3, tostring(day), "small", "regular", "left", status == "complete" and false or true)
    end
    local info_y = grid_y + cell_h * rows + 10
    if tracker.kind == "counter" then
        local total, recorded, average = model.month_stats(tracker, shown_month, state.date)
        punri.text(margin, info_y, fit_text(string.format("Month total %d", total), w - margin * 2, "ui10", "regular"), "ui10")
        punri.text(margin, info_y + 20, average and string.format("Average %d from %d recorded days", average, recorded) or
            "Average: no recorded days", "small")
    else
        punri.text(margin, info_y, fit_text("X complete   . logged below goal   outline empty", w - margin * 2, "small", "regular"), "small")
    end
    local gap, count = 6, 5
    local button_w = math.floor((w - margin * 2 - gap * (count - 1)) / count)
    button(view, margin, control_y, button_w, footer_h, "Edit", "edit:" .. tracker.id, false)
    button(view, margin + (button_w + gap), control_y, button_w, footer_h, "Prev", "month_prev", false)
    button(view, margin + (button_w + gap) * 2, control_y, button_w, footer_h, "Next", "month_next", false)
    button(view, margin + (button_w + gap) * 3, control_y, button_w, footer_h, "Today", "month_current", false)
    button(view, margin + (button_w + gap) * 4, control_y, button_w, footer_h, "Back", "today", false)
    if message and message ~= "" then punri.text(margin, control_y - punri.line_height("small") - 3,
        fit_text(message, w - margin * 2, "small", "regular"), "small") end
    punri.button_hints("Back", "Edit", "Prev", "Next")
end

local function draw_confirm(view, candidate, backward, message)
    local w, h, margin, top, bottom = metrics()
    -- The compact PUNRI header reserves its right lane for both the subtitle
    -- and system status.  On the confirmation/error views that squeezed the
    -- app title away.  The body already states the date/clock state, so keep
    -- the stable app title in the header and avoid a competing right label.
    punri.header("Daily Track")
    local has_candidate = candidate and calendar.parse(candidate)
    local title = backward and "Clock moved backwards" or (has_candidate and "Confirm entered date" or "Set a local date")
    punri.centered_text(top + 56, title, "ui12", "bold")
    punri.centered_text(top + 90, candidate or "Date unavailable", "ui12", "regular")
    if backward then
        punri.centered_text(top + 126, "Saved history is read-only until the clock is fixed.", "small")
        button(view, margin, top + 168, w - margin * 2, 38, "Exit", "exit", false)
    else
        punri.centered_text(top + 126, has_candidate and "Use the entered date, or correct it first." or
            "The device did not provide a usable date.", "small")
        if has_candidate then
            button(view, margin, top + 168, w - margin * 2, 42, "Use date", "confirm_date", true)
            button(view, margin, top + 220, w - margin * 2, 42, "Edit date", "manual_date", false)
            button(view, margin, top + 272, w - margin * 2, 42, "Exit", "exit", false)
        else
            button(view, margin, top + 184, w - margin * 2, 42, "Enter date", "manual_date", true)
            button(view, margin, top + 236, w - margin * 2, 42, "Exit", "exit", false)
        end
    end
    if message and message ~= "" then punri.centered_text(bottom - 26, message, "small") end
    punri.button_hints("Exit", has_candidate and "Use" or "Enter", has_candidate and "Edit" or "", "")
end

local function draw_error(view, message)
    local w, h, margin, top, bottom = metrics()
    punri.header("Daily Track")
    punri.centered_text(top + 64, "Saved data unavailable", "ui12", "bold")
    punri.centered_text(top + 96, "Back up daily_track_v1.dat and check the SD card.", "small")
    punri.centered_text(top + 118, "This app will not replace it.", "small")
    button(view, margin, top + 164, w - margin * 2, 38, "Exit", "exit", false)
    if message and message ~= "" then punri.centered_text(bottom - 26, message, "small") end
    punri.button_hints("Exit", "", "", "")
end

local function draw_delete(view, tracker, message)
    local w, h, margin, top, bottom = metrics()
    tracker_header("Delete Tracker", tracker, w)
    punri.centered_text(top + 56, "Delete this tracker and all its history?", "ui12", "bold")
    button(view, margin, top + 104, w - margin * 2, 40, "Keep tracker", "cancel_delete", true)
    button(view, margin, top + 154, w - margin * 2, 40, "Delete permanently", "confirm_delete", false)
    if message and message ~= "" then punri.centered_text(bottom - 26, message, "small") end
    punri.button_hints("Back", "Keep", "", "Delete")
end

function ui.draw(state, view, screen, tracker, candidate, message)
    F.begin(screen)
    ui.begin(view)
    punri.clear()
    if screen == "today" then draw_today(state, view, message)
    elseif screen == "manage" then draw_manage(state, view, message)
    elseif screen == "edit" and tracker then draw_edit(state, view, tracker, message)
    elseif screen == "details" and tracker then draw_details(state, view, tracker, message)
    elseif screen == "delete" and tracker then draw_delete(view, tracker, message)
    elseif screen == "error" then draw_error(view, message)
    else draw_confirm(view, candidate, screen == "clock_back", message) end
    retry_button(view, message, screen)
    F.finish()
end

return ui
