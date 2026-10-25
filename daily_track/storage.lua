-- Versioned and deliberately small on-card state.  A bad, unreadable or
-- oversized file is never replaced by an empty collection.
local storage = {STATE_FILE = "daily_track_v1.dat", MAX_FILE_BYTES = 24576}
local calendar = punri.dofile("calendar.lua")
local model = punri.dofile("model.lua")

local MAGIC = "PUNRI_DAILY_TRACK_1"

function storage.valid_text(value)
    if type(value) ~= "string" or #value < 1 or #value > model.MAX_NAME_BYTES then return false end
    local i, length = 1, #value
    while i <= length do
        local byte = value:byte(i)
        if byte == 0 or byte < 32 or byte == 127 then return false end
        if byte < 128 then
            i = i + 1
        else
            local need, min, max
            if byte >= 194 and byte <= 223 then need, min, max = 1, 128, 191
            elseif byte >= 224 and byte <= 239 then need, min, max = 2, 128, 191
            elseif byte >= 240 and byte <= 244 then need, min, max = 3, 128, 191
            else return false end
            if i + need > length then return false end
            local next_byte = value:byte(i + 1)
            if not next_byte or next_byte < min or next_byte > max then return false end
            if byte == 224 and next_byte < 160 then return false end
            if byte == 237 and next_byte > 159 then return false end
            if byte == 240 and next_byte < 144 then return false end
            if byte == 244 and next_byte > 143 then return false end
            for offset = 2, need do
                local following = value:byte(i + offset)
                if not following or following < 128 or following > 191 then return false end
            end
            i = i + need + 1
        end
    end
    return value:find("%S") ~= nil
end

local function hex_encode(value)
    return (value:gsub(".", function(byte) return string.format("%02X", byte:byte()) end))
end

local function hex_decode(value)
    if #value % 2 ~= 0 or #value > model.MAX_NAME_BYTES * 2 or not value:match("^[0-9A-F]*$") then return nil end
    return (value:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end

local function valid_integer(value, low, high)
    if type(value) ~= "string" or not value:match("^%d+$") then return nil end
    local number = tonumber(value)
    if not number or number < low or number > high or number ~= math.floor(number) then return nil end
    return number
end

local function split(line)
    local fields, from = {}, 1
    while true do
        local at = line:find("|", from, true)
        if not at then
            fields[#fields + 1] = line:sub(from)
            return fields
        end
        fields[#fields + 1] = line:sub(from, at - 1)
        from = at + 1
    end
end

function storage.encode(state)
    local pieces = {MAGIC, "\n", string.format("G|%s|%s|%d\n", state.date, state.latest_date, state.next_id)}
    for _, tracker in ipairs(state.trackers) do
        pieces[#pieces + 1] = string.format("T|%d|%s|%s|%d|%d|%d|%d\n", tracker.id,
            tracker.kind == "habit" and "H" or "C", hex_encode(tracker.name), tracker.goal, tracker.step,
            tracker.settled, tracker.best)
        for _, day in ipairs(tracker.days) do
            pieces[#pieces + 1] = string.format("R|%d|%s|%d|%d|%d\n", tracker.id, day.date, day.value,
                day.goal, day.complete and 1 or 0)
        end
    end
    local encoded = table.concat(pieces)
    if #encoded > storage.MAX_FILE_BYTES then return nil, "Storage limit reached" end
    return encoded
end

function storage.decode(raw)
    if type(raw) ~= "string" or #raw == 0 or #raw > storage.MAX_FILE_BYTES or raw:find("%z") or raw:sub(-1) ~= "\n" then
        return nil, "Saved data is invalid or too large"
    end
    local lines = {}
    for line in raw:gmatch("([^\n]*)\n") do
        if line:find("\r", 1, true) then return nil, "Saved data is invalid" end
        lines[#lines + 1] = line
    end
    if lines[1] ~= MAGIC or not lines[2] then return nil, "Saved data is invalid" end
    local global = split(lines[2])
    if #global ~= 4 or global[1] ~= "G" or not calendar.parse(global[2]) or not calendar.parse(global[3]) or
        calendar.compare(global[3], global[2]) ~= 0 then return nil, "Saved data is invalid" end
    local next_id = valid_integer(global[4], 1, model.MAX_ID)
    if not next_id then return nil, "Saved data is invalid" end
    local state = model.new_state(global[2])
    state.latest_date, state.next_id = global[3], next_id
    local by_id = {}
    local record_count = 0
    for index = 3, #lines do
        local f = split(lines[index])
        if f[1] == "T" then
            if #f ~= 8 or #state.trackers >= model.MAX_TRACKERS then return nil, "Saved data is invalid" end
            local id = valid_integer(f[2], 1, model.MAX_ID)
            local kind = f[3] == "H" and "habit" or (f[3] == "C" and "counter" or nil)
            local name = hex_decode(f[4])
            local goal = valid_integer(f[5], 0, model.MAX_GOAL)
            local step = valid_integer(f[6], 1, model.MAX_STEP)
            local settled = valid_integer(f[7], 0, model.MAX_ID)
            local best = valid_integer(f[8], 0, model.MAX_ID)
            if not id or by_id[id] or not kind or not name or not storage.valid_text(name) or not goal or not step or
                not settled or not best or (kind == "habit" and (goal ~= 0 or step ~= 1)) then
                return nil, "Saved data is invalid"
            end
            local tracker = {id = id, kind = kind, name = name, goal = goal, step = step, settled = settled,
                best = best, days = {}}
            state.trackers[#state.trackers + 1] = tracker
            by_id[id] = tracker
        elseif f[1] == "R" then
            if #f ~= 6 then return nil, "Saved data is invalid" end
            local id = valid_integer(f[2], 1, model.MAX_ID)
            local tracker = id and by_id[id] or nil
            local value = valid_integer(f[4], 0, model.MAX_VALUE)
            local goal = valid_integer(f[5], 0, model.MAX_GOAL)
            local complete = valid_integer(f[6], 0, 1)
            if not tracker or not calendar.parse(f[3]) or calendar.compare(f[3], state.date) == 1 or not value or
                not goal or complete == nil or #tracker.days >= model.MAX_DAYS then return nil, "Saved data is invalid" end
            if model.find_day(tracker, f[3]) then return nil, "Saved data is invalid" end
            if tracker.kind == "habit" and (value > 1 or goal ~= 0) then return nil, "Saved data is invalid" end
            if tracker.kind == "counter" and complete == 1 and (goal == 0 or value < goal) then return nil, "Saved data is invalid" end
            if tracker.kind == "habit" and complete ~= value then return nil, "Saved data is invalid" end
            tracker.days[#tracker.days + 1] = {date = f[3], value = value, goal = goal, complete = complete == 1}
            record_count = record_count + 1
            if record_count > model.MAX_TRACKERS * model.MAX_DAYS then return nil, "Saved data is invalid" end
        else
            return nil, "Saved data is invalid"
        end
    end
    for _, tracker in ipairs(state.trackers) do
        table.sort(tracker.days, function(a, b) return a.date < b.date end)
        if tracker.best < tracker.settled then return nil, "Saved data is invalid" end
    end
    return state
end

function storage.load()
    local raw = punri.read_file(storage.STATE_FILE, storage.MAX_FILE_BYTES + 1)
    if raw == nil then
        if punri.file_exists(storage.STATE_FILE) then return nil, "Saved data unavailable" end
        return nil, nil
    end
    return storage.decode(raw)
end

function storage.save(state)
    local raw, err = storage.encode(state)
    if not raw then return false, err end
    if not punri.write_file(storage.STATE_FILE, raw) then return false, "Save failed — Retry" end
    return true
end

return storage
