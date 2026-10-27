-- Bounded stopwatch model and backwards-compatible stopwatch.dat persistence.
-- Lua is built with 32-bit integers on device, so all elapsed values are kept
-- below 100 hours and every addition is checked before it can overflow.

local Stopwatch = {
    DATA_FILE = "stopwatch.dat",
    MAX_LAPS = 50,
    MAX_ELAPSED_MS = 359999990, -- 99:59:59.99; fixed-width readout
    REFRESH_INTERVAL_MS = 250,
}

local MAX_INT = 2147483647
local MAX_SAVE_BYTES = 4096

local Model = {}
Model.__index = Model

local function now_ms()
    if punri and punri.millis then
        local value = punri.millis()
        if type(value) == "number" then return value end
    end
    return 0
end

local function valid_ms(value)
    return type(value) == "number" and value == value and value >= 0 and
        value <= Stopwatch.MAX_ELAPSED_MS and value == math.floor(value)
end

-- millis() reaches Lua as a signed 32-bit value. This calculates a small
-- forward interval across its signed wrap without ever constructing 2^32.
function Stopwatch.elapsed_delta(start_tick, current_tick)
    if current_tick >= start_tick then
        local delta = current_tick - start_tick
        return delta >= 0 and delta <= Stopwatch.MAX_ELAPSED_MS and delta or 0
    end
    if start_tick < 0 or current_tick >= 0 then return 0 end

    local before_wrap = MAX_INT - start_tick
    -- Do not spell INT_MIN here: with Lua's 32-bit float support that literal
    -- loses low bits before subtraction. -MAX_INT is an exact integer; adding
    -- one gives the same distance from INT_MIN with small intermediate values.
    local after_wrap = current_tick - (-MAX_INT) + 1
    if before_wrap < 0 or after_wrap < 0 or before_wrap >= Stopwatch.MAX_ELAPSED_MS then return 0 end
    if after_wrap > Stopwatch.MAX_ELAPSED_MS - before_wrap - 1 then return 0 end
    return before_wrap + 1 + after_wrap
end

function Stopwatch.format_time(value)
    local ms = valid_ms(value) and value or 0
    -- `/` promotes to a 32-bit float in this build and rounds near 100 hours.
    -- Integer floor division keeps the final centiseconds exact.
    local centiseconds = ms // 10
    local cs = centiseconds % 100
    local seconds = ms // 1000
    local sec = seconds % 60
    local minutes = seconds // 60
    local min = minutes % 60
    local hours = minutes // 60
    return string.format("%02d:%02d:%02d.%02d", hours, min, sec, cs)
end

local function parse_record(line)
    local left, right = string.match(line, "^(%d+);(%d+)$")
    if not left or not right then return nil, nil end
    return tonumber(left), tonumber(right)
end

function Stopwatch.new()
    local self = setmetatable({}, Model)
    self.running = false
    self.start_tick = 0
    self.accumulated_ms = 0
    self.last_lap_total = 0
    self.laps = {}
    self.lap_page = 0
    self.last_refresh_tick = 0
    self.reset_pending = false
    self.reset_was_running = false
    self.reset_choice = "keep"
    self.dirty = false
    self.save_error = nil
    self.load_error = nil
    self.notice = nil
    return self
end

function Model:set_awake(enabled)
    if punri and punri.prevent_sleep then punri.prevent_sleep(enabled) end
end

function Model:update_sleep_policy()
    self:set_awake(self.running and not self.reset_pending)
end

function Model:elapsed_at(current_tick)
    if not self.running then return self.accumulated_ms end
    local delta = Stopwatch.elapsed_delta(self.start_tick, current_tick or now_ms())
    local remaining = Stopwatch.MAX_ELAPSED_MS - self.accumulated_ms
    if delta >= remaining then return Stopwatch.MAX_ELAPSED_MS end
    return self.accumulated_ms + delta
end

function Model:elapsed()
    return self:elapsed_at(now_ms())
end

function Model:format_time(value)
    return Stopwatch.format_time(value)
end

function Model:is_toggle_enabled()
    return self.running or self.accumulated_ms < Stopwatch.MAX_ELAPSED_MS
end

function Model:is_lap_enabled()
    return self.running and #self.laps < Stopwatch.MAX_LAPS and not self.reset_pending
end

function Model:is_reset_enabled()
    return (self.accumulated_ms > 0 or self.running or #self.laps > 0) and not self.reset_pending
end

function Model:status()
    if self.running then return "Running" end
    if self.accumulated_ms > 0 or #self.laps > 0 then return "Stopped" end
    return "Ready"
end

function Model:message()
    return self.save_error or self.load_error or self.notice
end

function Model:toggle_running()
    if self.reset_pending or not self:is_toggle_enabled() then return false, false end
    local now = now_ms()
    self.notice = nil
    if self.running then
        self.accumulated_ms = self:elapsed_at(now)
        self.running = false
        self.start_tick = now
        self.dirty = true
        self:set_awake(false)
        return true, true
    end

    self.running = true
    self.start_tick = now
    self.last_refresh_tick = now
    self.dirty = true
    self:set_awake(true)
    return true, false
end

function Model:add_lap()
    if self.reset_pending or not self.running then return false, false end
    if #self.laps >= Stopwatch.MAX_LAPS then return false, false end

    local total = self:elapsed()
    local lap = total - self.last_lap_total
    if lap < 0 then return false, false end
    self.laps[#self.laps + 1] = {lap_ms = lap, total_ms = total}
    self.last_lap_total = total
    self.lap_page = 0
    self.notice = #self.laps == Stopwatch.MAX_LAPS and "Lap limit reached (50)" or nil
    self.dirty = true
    return true, true
end

function Model:request_reset()
    if not self:is_reset_enabled() then return false, false end
    local now = now_ms()
    self.reset_was_running = self.running
    if self.running then
        -- Pause for the confirmation; cancelling resumes from this snapshot and
        -- deliberately does not count time spent deciding.
        self.accumulated_ms = self:elapsed_at(now)
        self.running = false
        self.start_tick = now
        self:set_awake(false)
    end
    self.reset_pending = true
    self.reset_choice = "keep"
    self.notice = nil
    return true, false
end

function Model:cancel_reset()
    if not self.reset_pending then return false, false end
    self.reset_pending = false
    if self.reset_was_running then
        local now = now_ms()
        self.running = true
        self.start_tick = now
        self.last_refresh_tick = now
        self:set_awake(true)
    end
    self.reset_was_running = false
    return true, false
end

function Model:select_reset(choice)
    if not self.reset_pending or (choice ~= "keep" and choice ~= "confirm") then return false, false end
    if self.reset_choice == choice then return false, false end
    self.reset_choice = choice
    return true, false
end

function Model:confirm_reset()
    if not self.reset_pending then return false, false end
    if self.reset_choice == "keep" then return self:cancel_reset() end

    self.running = false
    self.start_tick = 0
    self.accumulated_ms = 0
    self.last_lap_total = 0
    self.laps = {}
    self.lap_page = 0
    self.reset_pending = false
    self.reset_was_running = false
    self.notice = nil
    self.dirty = true
    self:set_awake(false)
    return true, true
end

function Model:change_lap_page(delta, rows)
    if self.reset_pending or rows < 1 or #self.laps <= rows then return false, false end
    local max_page = math.floor((#self.laps - 1) / rows)
    local wanted = self.lap_page + delta
    if wanted < 0 then wanted = 0 end
    if wanted > max_page then wanted = max_page end
    if wanted == self.lap_page then return false, false end
    self.lap_page = wanted
    return true, false
end

function Model:best_worst()
    if #self.laps == 0 then return nil, nil end
    local best = self.laps[1].lap_ms
    local worst = best
    for index = 2, #self.laps do
        local value = self.laps[index].lap_ms
        if value < best then best = value end
        if value > worst then worst = value end
    end
    return best, worst
end

function Model:save()
    if not (punri and punri.write_file) then
        self.save_error = "Storage is unavailable. Retry before exit."
        return false
    end

    local current = self:elapsed()
    local rows = {string.format("%d;%d", self.running and 1 or 0, current)}
    for index = 1, #self.laps do
        local lap = self.laps[index]
        rows[#rows + 1] = string.format("%d;%d", lap.lap_ms, lap.total_ms)
    end
    local ok = punri.write_file(Stopwatch.DATA_FILE, table.concat(rows, "\n"))
    if ok then
        self.dirty = false
        self.save_error = nil
        return true
    end
    self.save_error = "Save failed. Retry before exit."
    return false
end

function Model:save_on_exit()
    -- Do not overwrite a malformed legacy file merely by opening and closing
    -- the app. A later explicit state change is allowed to replace it.
    if self.load_error and not self.dirty then return true end
    if not self.dirty then return true end
    return self:save()
end

function Model:retry_or_exit(exit_callback)
    if self.reset_pending then return self:cancel_reset() end
    if self.dirty or self.save_error then
        if not self:save() then return true, false end
    end
    exit_callback()
    return true, true
end

function Model:load()
    self.running = false
    self.accumulated_ms = 0
    self.last_lap_total = 0
    self.laps = {}
    self.lap_page = 0
    self.load_error = nil
    self.notice = nil
    self.dirty = false

    if not (punri and punri.read_file) then
        self.load_error = "Saved data cannot be read"
        return false
    end
    local content = punri.read_file(Stopwatch.DATA_FILE, MAX_SAVE_BYTES)
    if content == nil or content == "" then return true end
    if #content >= MAX_SAVE_BYTES then
        self.load_error = "Saved data is too large; it was left unchanged"
        return false
    end

    local lines = {}
    for line in string.gmatch(content, "[^\r\n]+") do lines[#lines + 1] = line end
    if #lines == 0 then return true end

    local saved_running, saved_elapsed = parse_record(lines[1])
    if (saved_running ~= 0 and saved_running ~= 1) or not valid_ms(saved_elapsed) then
        self.load_error = "Saved data is invalid; it was left unchanged"
        return false
    end

    local parsed_laps = {}
    local previous_total = 0
    for index = 2, #lines do
        local lap_ms, total_ms = parse_record(lines[index])
        if not valid_ms(lap_ms) or not valid_ms(total_ms) or total_ms < previous_total or
            lap_ms ~= total_ms - previous_total then
            self.load_error = "Saved data is invalid; it was left unchanged"
            return false
        end
        parsed_laps[#parsed_laps + 1] = {lap_ms = lap_ms, total_ms = total_ms}
        previous_total = total_ms
    end
    if previous_total > saved_elapsed then
        self.load_error = "Saved data is invalid; it was left unchanged"
        return false
    end

    local first_lap = math.max(1, #parsed_laps - Stopwatch.MAX_LAPS + 1)
    for index = first_lap, #parsed_laps do self.laps[#self.laps + 1] = parsed_laps[index] end
    self.accumulated_ms = saved_elapsed
    self.last_lap_total = previous_total
    if #parsed_laps > Stopwatch.MAX_LAPS then self.notice = "Showing latest 50 saved laps" end
    if saved_running == 1 then
        -- A monotonic uptime cannot account for time while the device was off.
        -- Preserve the snapshot, but never pretend the timer kept running.
        self.notice = "Stopped after restart"
        self.dirty = true
    end
    return true
end

function Model:needs_redraw()
    if not self.running then return false end
    local now = now_ms()
    local elapsed = self:elapsed_at(now)
    if elapsed >= Stopwatch.MAX_ELAPSED_MS then
        self.accumulated_ms = Stopwatch.MAX_ELAPSED_MS
        self.running = false
        self.start_tick = now
        self.dirty = true
        self.notice = "Maximum duration reached"
        self:set_awake(false)
        self:save()
        return true
    end
    if Stopwatch.elapsed_delta(self.last_refresh_tick, now) >= Stopwatch.REFRESH_INTERVAL_MS then
        self.last_refresh_tick = now
        return true
    end
    return false
end

return Stopwatch
