-- Bounded Daily Track model.  Every arithmetic bound is below Lua 5.4's
-- configured 32-bit integer limit; period totals top out at 35,000,000.
local model = {
    MAX_TRACKERS = 12,
    MAX_DAYS = 35,
    MAX_NAME_BYTES = 48,
    MAX_VALUE = 1000000,
    MAX_STEP = 100000,
    MAX_GOAL = 1000000,
    MAX_ID = 999999,
}

local calendar = punri.dofile("calendar.lua")

local function integer_in(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

function model.new_state(date)
    return {date = date, latest_date = date, next_id = 1, trackers = {}}
end

function model.find_tracker(state, id)
    for index, tracker in ipairs(state.trackers) do
        if tracker.id == id then return tracker, index end
    end
    return nil
end

function model.find_day(tracker, date)
    for _, day in ipairs(tracker.days) do
        if day.date == date then return day end
    end
    return nil
end

local function sort_and_trim_days(tracker, active_date)
    table.sort(tracker.days, function(a, b) return a.date < b.date end)
    local earliest = calendar.add_days(active_date, -(model.MAX_DAYS - 1))
    local kept = 1
    for _, day in ipairs(tracker.days) do
        if day.date >= earliest and day.date <= active_date then
            tracker.days[kept] = day
            kept = kept + 1
        end
    end
    for i = kept, #tracker.days do tracker.days[i] = nil end
end

function model.add_tracker(state, kind, name)
    if #state.trackers >= model.MAX_TRACKERS then return nil, "Tracker limit reached" end
    if kind ~= "habit" and kind ~= "counter" then return nil, "Invalid tracker type" end
    if not integer_in(state.next_id, 1, model.MAX_ID) then return nil, "Tracker ID limit reached" end
    local tracker = {
        id = state.next_id,
        kind = kind,
        name = name,
        goal = 0,
        step = 1,
        settled = 0,
        best = 0,
        days = {},
    }
    state.next_id = state.next_id + 1
    state.trackers[#state.trackers + 1] = tracker
    return tracker
end

function model.has_history(tracker)
    return #tracker.days > 0 or tracker.settled > 0 or tracker.best > 0
end

function model.set_name(tracker, name)
    tracker.name = name
end

function model.set_goal(tracker, goal, active_date)
    if tracker.kind ~= "counter" or not integer_in(goal, 0, model.MAX_GOAL) then return nil, "Goal must be 0 to 1000000" end
    local current = model.find_day(tracker, active_date)
    tracker.goal = goal
    -- A day that already has a measurement keeps its original threshold.  This
    -- is what makes historical completion immutable when a goal changes later.
    return current ~= nil
end

function model.set_step(tracker, step)
    if tracker.kind ~= "counter" or not integer_in(step, 1, model.MAX_STEP) then return false, "Step must be 1 to 100000" end
    tracker.step = step
    return true
end

local function completed(tracker, day)
    if tracker.kind == "habit" then return day.value == 1 end
    return day.goal > 0 and day.value >= day.goal
end

local function ensure_day(tracker, date)
    local day = model.find_day(tracker, date)
    if day then return day end
    day = {date = date, value = 0, goal = tracker.kind == "counter" and tracker.goal or 0, complete = false}
    tracker.days[#tracker.days + 1] = day
    return day
end

function model.toggle(tracker, date)
    if tracker.kind ~= "habit" then return false, "Not a habit" end
    local day = ensure_day(tracker, date)
    day.value = day.value == 1 and 0 or 1
    day.complete = completed(tracker, day)
    sort_and_trim_days(tracker, date)
    return true
end

function model.increment(tracker, date)
    if tracker.kind ~= "counter" then return false, "Not a counter" end
    local day = ensure_day(tracker, date)
    if day.value > model.MAX_VALUE - tracker.step then return false, "Daily value limit reached" end
    day.value = day.value + tracker.step
    day.complete = completed(tracker, day)
    sort_and_trim_days(tracker, date)
    return true
end

function model.undo(tracker, date)
    local day = model.find_day(tracker, date)
    if not day then return false, "Nothing to undo" end
    if tracker.kind == "habit" then
        if day.value == 0 then return false, "Nothing to undo" end
        day.value = 0
    else
        if day.value == 0 then return false, "Nothing to undo" end
        day.value = math.max(0, day.value - tracker.step)
    end
    day.complete = completed(tracker, day)
    return true
end

local function settle_tracker(tracker, date)
    local day = model.find_day(tracker, date)
    if tracker.kind == "counter" and (not day or day.goal == 0) then
        tracker.settled = 0
        return
    end
    if day and day.complete then
        tracker.settled = tracker.settled + 1
        if tracker.settled > tracker.best then tracker.best = tracker.settled end
    else
        tracker.settled = 0
    end
end

function model.roll_to(state, next_date)
    local order = calendar.compare(next_date, state.date)
    if order == nil then return false, "Invalid date" end
    if order < 0 then return false, "Clock moved backwards" end
    if order == 0 then return true end
    local day_after = calendar.add_days(state.date, 1)
    if day_after == next_date then
        for _, tracker in ipairs(state.trackers) do settle_tracker(tracker, state.date) end
    else
        -- The active day is still settled so a completion is counted.  At least
        -- one missing day follows, which breaks every active chain without
        -- walking thousands of dates after a dormant device has been restarted.
        for _, tracker in ipairs(state.trackers) do
            settle_tracker(tracker, state.date)
            tracker.settled = 0
        end
    end
    state.date, state.latest_date = next_date, next_date
    for _, tracker in ipairs(state.trackers) do sort_and_trim_days(tracker, next_date) end
    return true
end

function model.streaks(tracker, active_date)
    if tracker.kind == "counter" then
        local current_day = model.find_day(tracker, active_date)
        if (current_day and current_day.goal == 0) or (not current_day and tracker.goal == 0) then return nil, nil end
    end
    local current = tracker.settled
    local day = model.find_day(tracker, active_date)
    if day and day.complete then current = current + 1 end
    return current, math.max(tracker.best, current)
end

function model.day_status(tracker, date, active_date)
    if calendar.compare(date, active_date) == 1 then return "future" end
    local day = model.find_day(tracker, date)
    if not day then return "empty" end
    return day.complete and "complete" or "logged"
end

function model.period_stats(tracker, active_date)
    if tracker.kind ~= "counter" then return nil end
    local first = calendar.add_days(active_date, -(model.MAX_DAYS - 1))
    local total, recorded = 0, 0
    for _, day in ipairs(tracker.days) do
        if day.date >= first and day.date <= active_date then
            total, recorded = total + day.value, recorded + 1
        end
    end
    return total, recorded, recorded > 0 and math.floor(total / recorded) or nil
end

function model.delete_tracker(state, id)
    local _, index = model.find_tracker(state, id)
    if not index then return false end
    table.remove(state.trackers, index)
    return true
end

function model.move_tracker(state, id, delta)
    local _, index = model.find_tracker(state, id)
    if not index then return false end
    local target = index + delta
    if target < 1 or target > #state.trackers then return false end
    state.trackers[index], state.trackers[target] = state.trackers[target], state.trackers[index]
    return true
end

return model
