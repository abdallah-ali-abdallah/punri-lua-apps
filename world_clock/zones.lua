-- Bounded IANA transition reader.  zones.txt is generated from tzdata and is
-- read a zone at a time so a map redraw never leaves all transition tables in
-- Lua memory.  Values are minute serials from time_math.lua's 2000 epoch.
local time = punri.dofile("time_math.lua")

local M = {}
local cache, order = {}, {}
local MAX_CACHED_ZONES = 8

local function remember(name, record)
    if cache[name] then return end
    cache[name] = record
    order[#order + 1] = name
    if #order > MAX_CACHED_ZONES then
        local old = table.remove(order, 1)
        cache[old] = nil
    end
end

local function load_zone(name)
    local existing = cache[name]
    if existing then return existing end
    local section = punri.find_section("zones.txt", "[" .. name .. "]", "[", 2048)
    if type(section) ~= "string" then return nil end

    local record = {transitions = {}}
    for line in section:gmatch("[^\n]+") do
        local offset, dst = line:match("^b=([%-]?%d+),([01])$")
        if offset then
            record.base_offset = tonumber(offset)
            record.base_dst = dst == "1"
        else
            local at, next_offset, next_dst = line:match("^t=(%d+),([%-]?%d+),([01])$")
            if at then
                local transitions = record.transitions
                transitions[#transitions + 1] = {at = tonumber(at), offset = tonumber(next_offset), dst = next_dst == "1"}
            end
        end
    end
    if record.base_offset == nil then return nil end
    remember(name, record)
    return record
end

function M.resolve(name, utc_minutes)
    if not time.supports_utc_minute(utc_minutes) then return nil, nil, "range" end
    local record = load_zone(name)
    if not record then return nil, nil, "data" end
    local offset, dst = record.base_offset, record.base_dst
    for _, transition in ipairs(record.transitions) do
        if utc_minutes < transition.at then break end
        offset, dst = transition.offset, transition.dst
    end
    return offset, dst
end

function M.clear_cache()
    cache, order = {}, {}
end

return M
