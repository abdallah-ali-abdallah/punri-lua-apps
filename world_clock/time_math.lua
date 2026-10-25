-- Civil-time math for World Clock.  Lua on PUNRI uses 32-bit integers, so
-- every instant is represented as minutes since 2000-01-01 rather than a Unix
-- epoch second (which would overflow in 2038).  The bundled tzdata range is
-- deliberately bounded to 2024-01-01 through 2040-12-31.
local M = {
    BASE_YEAR = 2000,
    MIN_YEAR = 2024,
    MAX_YEAR = 2040,
    -- A UTC instant at either supported edge can display as the adjacent
    -- civil year in a negative or positive offset zone.
    MIN_CIVIL_YEAR = 2023,
    MAX_CIVIL_YEAR = 2041,
}

local MINUTES_PER_DAY = 1440

local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function month_days(year, month)
    local days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if month < 1 or month > 12 then return 0 end
    if month == 2 and leap(year) then return 29 end
    return days[month]
end

function M.valid_fields(value)
    return type(value) == "table" and type(value.year) == "number" and type(value.month) == "number" and
        type(value.day) == "number" and type(value.hour) == "number" and type(value.min) == "number" and
        value.year >= M.MIN_CIVIL_YEAR and value.year <= M.MAX_CIVIL_YEAR and value.month >= 1 and value.month <= 12 and
        value.day >= 1 and value.day <= month_days(value.year, value.month) and value.hour >= 0 and value.hour < 24 and
        value.min >= 0 and value.min < 60
end

local function days_before_year(year)
    local days = 0
    for y = M.BASE_YEAR, year - 1 do
        days = days + (leap(y) and 366 or 365)
    end
    return days
end

function M.civil_to_day(year, month, day)
    if year < M.BASE_YEAR or month < 1 or month > 12 or day < 1 or day > month_days(year, month) then return nil end
    local serial = days_before_year(year)
    for m = 1, month - 1 do serial = serial + month_days(year, m) end
    return serial + day - 1
end

function M.fields_to_utc_minute(value)
    if not M.valid_fields(value) then return nil end
    local day = M.civil_to_day(value.year, value.month, value.day)
    return day * MINUTES_PER_DAY + value.hour * 60 + value.min
end

function M.utc_minute_to_fields(minutes)
    if type(minutes) ~= "number" or minutes < 0 then return nil end
    local day = math.floor(minutes / MINUTES_PER_DAY)
    local minute_of_day = minutes - day * MINUTES_PER_DAY
    local year = M.BASE_YEAR
    while true do
        local length = leap(year) and 366 or 365
        if day < length then break end
        day = day - length
        year = year + 1
    end
    if year < M.MIN_CIVIL_YEAR or year > M.MAX_CIVIL_YEAR then return nil end
    local month = 1
    while day >= month_days(year, month) do
        day = day - month_days(year, month)
        month = month + 1
    end
    -- 2000-01-01 was Saturday.  The public API uses Sunday = 1.
    local absolute_day = M.civil_to_day(year, month, day + 1)
    return {
        year = year,
        month = month,
        day = day + 1,
        hour = math.floor(minute_of_day / 60),
        min = minute_of_day % 60,
        wday = (absolute_day + 6) % 7 + 1,
    }
end

function M.supports_utc_minute(minutes)
    local first = M.civil_to_day(M.MIN_YEAR, 1, 1) * MINUTES_PER_DAY
    local after_last = M.civil_to_day(M.MAX_YEAR + 1, 1, 1) * MINUTES_PER_DAY
    return type(minutes) == "number" and minutes >= first and minutes < after_last
end

-- get_date() is deliberately local for existing applications.  Its additive
-- offset_minutes field is the actual firmware presentation offset, so this is
-- the exact inverse when its separate valid flag says the source is trusted.
function M.utc_from_local_fields(value, offset_minutes)
    local local_minutes = M.fields_to_utc_minute(value)
    if local_minutes == nil or type(offset_minutes) ~= "number" then return nil end
    return local_minutes - offset_minutes
end

function M.local_from_utc(utc_minutes, offset_minutes)
    if type(offset_minutes) ~= "number" then return nil end
    return M.utc_minute_to_fields(utc_minutes + offset_minutes)
end

function M.format_time(value, use_24_hour)
    if not value then return "--:--" end
    if use_24_hour then return string.format("%02d:%02d", value.hour, value.min) end
    local hour = value.hour % 12
    if hour == 0 then hour = 12 end
    return string.format("%d:%02d %s", hour, value.min, value.hour < 12 and "AM" or "PM")
end

function M.format_date(value)
    if not value then return "---- -- --" end
    return string.format("%04d-%02d-%02d", value.year, value.month, value.day)
end

return M
