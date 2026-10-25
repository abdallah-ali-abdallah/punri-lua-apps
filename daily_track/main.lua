-- Daily Track: offline daily habits and counters.  The model, storage and UI
-- modules are loaded once here; drawing and idle updates never write to SD.
local calendar = punri.dofile("calendar.lua")
local model = punri.dofile("model.lua")
local storage = punri.dofile("storage.lua")
local ui = punri.dofile("ui.lua")
local input = punri.dofile("input.lua")

local state = nil
local view = {hits = {}, hit_count = 0, selected = 1, today_page = 1, manage_selected = 1, edit_selected = 1,
    detail_month = nil}
local screen, active_id, candidate_date = "date_confirm", nil, nil
local clock_confirmed, protected_data = false, false
local dirty, autosave_armed, retries = false, false, 0
local last_change, status, keyboard_purpose = 0, "", nil
local SAVE_DELAY_MS, MAX_RETRIES = 1200, 3

local function now_ms()
    return punri.millis and punri.millis() or 0
end

local function active_tracker()
    return state and active_id and model.find_tracker(state, active_id) or nil
end

local function selected_tracker()
    if not state or #state.trackers == 0 then return nil end
    view.selected = math.max(1, math.min(view.selected, #state.trackers))
    return state.trackers[view.selected]
end

local function request()
    if punri.request_update then punri.request_update() end
end

local function mark_dirty(message)
    dirty, autosave_armed, retries = true, true, 0
    last_change = now_ms()
    status = message or "Unsaved changes"
end

local function save_now(is_retry)
    if not dirty or protected_data then return true end
    if is_retry and retries >= MAX_RETRIES then
        status = "Retry limit reached; keep the app open and check the SD card."
        return false
    end
    local ok, err = storage.save(state)
    if ok then
        dirty, autosave_armed, retries, status = false, false, 0, "Saved"
        return true
    end
    if is_retry then retries = retries + 1 end
    autosave_armed = false -- A failure never becomes a write loop.
    status = err or "Save failed — Retry"
    return false
end

local function needs_keyboard(purpose, title, initial, maximum)
    if not punri.has_feature or not punri.has_feature("keyboard") or not punri.keyboard then
        status = "Keyboard unsupported by this firmware"
        return false
    end
    keyboard_purpose = purpose
    if not punri.keyboard(title, initial or "", maximum, false) then
        keyboard_purpose = nil
        status = "Keyboard request was not accepted"
        return false
    end
    return true
end

local function set_selected(index)
    if not state or #state.trackers == 0 then return end
    view.selected = (index - 1) % #state.trackers + 1
    if view.cards_per_page and view.cards_per_page > 0 then
        view.today_page = math.floor((view.selected - 1) / view.cards_per_page) + 1
    end
end

local function move_detail_month(delta)
    local current = calendar.month_start(state.date)
    local earliest = calendar.month_start(model.history_start(state.date))
    local shown = calendar.month_start(view.detail_month or current) or current
    local target = calendar.add_months(shown, delta)
    if not target or calendar.compare(target, earliest) == -1 then
        status = "Only the latest 35 days are stored"
    elseif calendar.compare(target, current) == 1 then
        status = "Already at the current month"
    else
        view.detail_month, status = target, ""
    end
end

local function export_csv()
    local number, path = 1, nil
    while number <= 999 do
        local candidate = string.format("daily_track_export_%03d_partial.csv", number)
        if not punri.file_exists(candidate) then path = candidate break end
        number = number + 1
    end
    if not path then status = "Export name limit reached" return end
    -- The suffix and final marker make an interrupted append unmistakable.
    if not punri.write_file(path, "# Daily Track CSV: partial until # COMPLETE\n" ..
        "date,name,type,value,goal_used,complete\n") then
        status = "Export failed; no file was published"
        return
    end
    local function csv(value)
        value = tostring(value)
        if value:sub(1, 1):match("[=+%-@]") then value = "'" .. value end
        return '"' .. value:gsub('"', '""') .. '"'
    end
    local first = calendar.add_days(state.date, -(model.MAX_DAYS - 1))
    for _, tracker in ipairs(state.trackers) do
        for _, day in ipairs(tracker.days) do
            if day.date >= first and day.date <= state.date then
                local line = table.concat({csv(day.date), csv(tracker.name), csv(tracker.kind), csv(day.value),
                    csv(day.goal), csv(day.complete and 1 or 0)}, ",") .. "\n"
                -- Each append is under 180 bytes under the documented limits.
                -- A failure leaves the intentionally named *_partial.csv file.
                if not punri.write_file(path, line, true) then
                    status = "Export failed; " .. path .. " is incomplete"
                    return
                end
            end
        end
    end
    if not punri.write_file(path, "# COMPLETE\n", true) then
        status = "Export failed; " .. path .. " is incomplete"
        return
    end
    status = "Export saved: " .. path
end

local function action_primary(tracker)
    local ok, message
    if tracker.kind == "habit" then ok, message = model.toggle(tracker, state.date)
    else ok, message = model.increment(tracker, state.date) end
    if ok then mark_dirty("Unsaved changes") else status = message end
end

local function edit_row(row)
    local tracker = active_tracker()
    if not tracker then screen = "manage" return end
    if row == 1 then
        needs_keyboard("name:" .. tracker.id, "Tracker name", tracker.name, model.MAX_NAME_BYTES)
    elseif row == 2 and tracker.kind == "counter" then
        needs_keyboard("goal:" .. tracker.id, "Daily goal (0 means no goal)", tostring(tracker.goal), 7)
    elseif row == 3 and tracker.kind == "counter" then
        needs_keyboard("step:" .. tracker.id, "Counter step", tostring(tracker.step), 6)
    elseif row == 4 then
        if model.move_tracker(state, tracker.id, -1) then mark_dirty("Order changed") else status = "Already first" end
    elseif row == 5 then
        if model.move_tracker(state, tracker.id, 1) then mark_dirty("Order changed") else status = "Already last" end
    elseif row == 6 then
        screen = "delete"
    elseif row == 7 then
        screen = "manage"
    else
        status = "Habits have no numeric goal or step"
    end
end

local function use_candidate_date()
    if not candidate_date or not calendar.parse(candidate_date) then
        status = "Enter a valid YYYY-MM-DD date"
        return
    end
    local rolled = false
    if not state then
        state = model.new_state(candidate_date)
    else
        local comparison = calendar.compare(candidate_date, state.date)
        if comparison and comparison >= 0 then
            local ok, err = model.roll_to(state, candidate_date)
            if not ok then status = err return end
            rolled = comparison == 1
        else
            screen, status = "clock_back", "Clock moved backwards; saved data remains unchanged."
            return
        end
    end
    clock_confirmed, screen, status = true, "today", ""
    if rolled then mark_dirty("Date updated") end
    set_selected(view.selected)
end

local function perform(action)
    if not action then return false end
    local kind, value = action:match("^([^:]+):(.+)$")
    if kind == "primary" then
        local tracker = model.find_tracker(state, tonumber(value))
        if tracker then action_primary(tracker) end
    elseif kind == "undo" then
        local tracker = model.find_tracker(state, tonumber(value))
        if tracker then
            local ok, message = model.undo(tracker, state.date)
            if ok then mark_dirty("Unsaved changes") else status = message end
        end
    elseif kind == "details" then
        active_id, screen, status = tonumber(value), "details", ""
        view.detail_month = calendar.month_start(state.date)
    elseif kind == "edit" then
        active_id, screen, status = tonumber(value), "edit", ""
    elseif kind == "add" then
        if #state.trackers >= model.MAX_TRACKERS then status = "Tracker limit reached" else
            needs_keyboard("new:" .. value, value == "habit" and "Habit name" or "Counter name", "", model.MAX_NAME_BYTES)
        end
    elseif kind == "edit_action" then
        edit_row(tonumber(value))
    elseif action == "manage" then
        screen, status = "manage", ""
    elseif action == "today" then
        screen, status = "today", ""
    elseif action == "month_prev" then
        move_detail_month(-1)
    elseif action == "month_next" then
        move_detail_month(1)
    elseif action == "month_current" then
        view.detail_month, status = calendar.month_start(state.date), ""
    elseif action == "confirm_date" then
        use_candidate_date()
    elseif action == "manual_date" then
        needs_keyboard("manual_date", "Local date YYYY-MM-DD", candidate_date or "", 10)
    elseif action == "confirm_delete" then
        local tracker = active_tracker()
        if tracker and model.delete_tracker(state, tracker.id) then
            active_id, screen = nil, "manage"
            set_selected(1)
            mark_dirty("Tracker deleted")
        end
    elseif action == "cancel_delete" then
        screen, status = "edit", ""
    elseif action == "retry" then
        save_now(true)
    elseif action == "export" then
        export_csv()
    elseif action == "exit" then
        -- Exit is a save boundary: failure keeps the app open with its Retry
        -- action, because on_exit is followed immediately by Lua destruction.
        if save_now(false) then punri.exit() end
    end
    request()
    return true
end

function on_init()
    local loaded, load_error = storage.load()
    local observed = calendar.local_date()
    candidate_date = observed
    if load_error then
        protected_data, screen, status = true, "error", load_error
        return
    end
    state = loaded
    if not observed then
        screen, status = "date_confirm", "Device date unavailable; enter it manually."
        return
    end
    if state and calendar.compare(observed, state.date) == -1 then
        screen, status = "clock_back", "Clock moved backwards; saved data is protected."
        return
    end
    if not state then
        state = model.new_state(observed)
    elseif observed ~= state.date then
        local ok, err = model.roll_to(state, observed)
        if not ok then
            screen, status = "date_confirm", err
            return
        end
        -- A real device date is available, so move forward and save it instead
        -- of making people approve the same clock value every time they open
        -- the app.  Backward jumps above remain read-only protection.
        mark_dirty("Date updated")
    end
    clock_confirmed, screen, status = true, "today", status
    set_selected(view.selected)
end

function on_draw()
    if dirty and (screen == "today" or screen == "manage" or screen == "edit" or screen == "details") and status == "" then
        status = "Unsaved changes"
    end
    ui.draw(state or model.new_state(candidate_date or "2026-01-01"), view, screen, active_tracker(), candidate_date, status)
end

function on_keyboard(value, cancelled)
    local purpose = keyboard_purpose
    keyboard_purpose = nil
    if cancelled or not purpose then request() return end
    local kind, id = purpose:match("^([^:]+):(.+)$")
    if kind == "new" then
        if not storage.valid_text(value) then status = "Name must be 1–48 valid UTF-8 bytes"
        else
            local tracker, err = model.add_tracker(state, id, value)
            if tracker then
                active_id, screen = tracker.id, "edit"
                set_selected(#state.trackers)
                mark_dirty("Tracker created")
            else status = err end
        end
    elseif kind == "name" then
        local tracker = model.find_tracker(state, tonumber(id))
        if tracker and storage.valid_text(value) then model.set_name(tracker, value); mark_dirty("Name changed")
        else status = "Name must be 1–48 valid UTF-8 bytes" end
    elseif kind == "goal" then
        local tracker, number = model.find_tracker(state, tonumber(id)), input.number(value)
        if not tracker or not number then status = "Goal must be a whole number"
        else
            local existing, err = model.set_goal(tracker, number, state.date)
            if err then status = err else mark_dirty(existing and "Today's recorded target stays unchanged" or "Goal changed") end
        end
    elseif kind == "step" then
        local tracker, number = model.find_tracker(state, tonumber(id)), input.number(value)
        local ok, err = tracker and number and model.set_step(tracker, number) or false, "Step must be a whole number"
        if ok then mark_dirty("Step changed") else status = err end
    elseif purpose == "manual_date" then
        if calendar.parse(value) then candidate_date, screen, status = value, "date_confirm", "Confirm the entered date"
        else status = "Use a valid YYYY-MM-DD date" end
    end
    request()
end

function on_button(button, pressed)
    if not pressed then return end
    if screen == "error" or screen == "clock_back" then
        if button == "back" or button == "confirm" then perform("exit") end
        return
    end
    if screen == "date_confirm" then
        if button == "back" then perform("exit")
        elseif button == "confirm" then perform("confirm_date")
        elseif button == "up" or button == "page_back" then perform("manual_date") end
        return
    end
    if screen == "today" then
        local tracker = selected_tracker()
        if button == "back" then perform("exit")
        elseif button == "confirm" and tracker then perform("primary:" .. tracker.id)
        elseif button == "up" or button == "page_back" then if tracker then perform("details:" .. tracker.id) end
        elseif button == "down" or button == "page_forward" then perform("manage")
        else
            local delta = input.button_delta(button)
            if delta ~= 0 and tracker then set_selected(view.selected + delta); request() end
        end
    elseif screen == "manage" then
        if button == "back" then perform("today")
        elseif button == "confirm" then
            local index = view.manage_selected
            if index == 1 then perform("add:habit")
            elseif index == 2 then perform("add:counter")
            else perform("edit:" .. state.trackers[index - 2].id) end
        else
            local delta = input.button_delta(button)
            if delta ~= 0 then
                local count = #state.trackers + 2
                view.manage_selected = (view.manage_selected - 1 + delta) % count + 1
                request()
            end
        end
    elseif screen == "edit" then
        if button == "back" then perform("manage")
        elseif button == "confirm" then perform("edit_action:" .. view.edit_selected)
        else
            local delta = input.button_delta(button)
            if delta ~= 0 then view.edit_selected = (view.edit_selected - 1 + delta) % 7 + 1; request() end
        end
    elseif screen == "details" then
        if button == "back" then perform("today")
        elseif button == "confirm" then perform("edit:" .. active_id)
        elseif button == "left" or button == "up" or button == "page_back" then perform("month_prev")
        elseif button == "right" or button == "down" or button == "page_forward" then perform("month_next")
        end
    elseif screen == "delete" then
        if button == "back" or button == "confirm" or button == "left" then perform("cancel_delete")
        elseif button == "right" or button == "down" then perform("confirm_delete") end
    end
end

function on_tap(x, y)
    -- This is the sole touch mutation path.  LuaAppActivity immediately calls
    -- on_touch(x, y, "tap") after this callback for the same physical tap.
    perform(ui.hit_at(view, x, y))
end

function on_touch(x, y, event)
    -- Intentionally empty: see on_tap.  The current runtime has no down/move/up
    -- stream, so interpreting this compatibility callback would double actions.
end

function on_update()
    if state and clock_confirmed and not protected_data then
        local observed = calendar.local_date()
        if observed and observed ~= state.date then
            candidate_date = observed
            if calendar.compare(observed, state.date) == 1 then
                local ok, err = model.roll_to(state, observed)
                if ok then mark_dirty("Date updated") else status = err end
            else
                screen, clock_confirmed, status = "clock_back", false, "Clock moved backwards; data is protected."
            end
            request()
            return
        end
    end
    if dirty and autosave_armed and now_ms() - last_change >= SAVE_DELAY_MS then
        save_now(false)
        request()
    end
end

function on_exit()
    -- Do not write here.  Any dirty exit is intercepted by perform("exit") so a
    -- failed write remains visible and retryable while the Lua state is alive.
end

-- The production package does not use this table.  It lets the production
-- LuaRunner scenarios assert state without duplicating model logic in tests.
if rawget(_G, "TEST_CASE") then
    DAILY_TRACK_TEST = {
        state = function() return state end,
        screen = function() return screen end,
        dirty = function() return dirty end,
        retry_count = function() return retries end,
        hit_at = function(x, y) return ui.hit_at(view, x, y) end,
    }
end
