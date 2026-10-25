-- Civil-date helpers.  Dates stay in YYYY-MM-DD form so lexical order is
-- chronological order.  The firmware clock is intentionally not treated as
-- authoritative here: main.lua asks the person using the device to confirm it.
local calendar = {}
-- Keep the full four-digit civil-date domain.  History navigation needs dates
-- outside the current clock year (for example the 35 days before 1 January),
-- so a narrow device-clock window must not make valid persisted cells unreadable.
local MIN_YEAR, MAX_YEAR = 1, 9999

local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

function calendar.days_in_month(year, month)
    local days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if month == 2 and leap(year) then return 29 end
    return days[month] or 0
end

function calendar.parse(iso)
    if type(iso) ~= "string" then return nil end
    local ys, ms, ds = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    local year, month, day = tonumber(ys), tonumber(ms), tonumber(ds)
    if not year or not month or not day or year < MIN_YEAR or year > MAX_YEAR or
        month < 1 or month > 12 or day < 1 or day > calendar.days_in_month(year, month) then
        return nil
    end
    return year, month, day
end

function calendar.format(year, month, day)
    if year < MIN_YEAR or year > MAX_YEAR or month < 1 or month > 12 or day < 1 or
        day > calendar.days_in_month(year, month) then
        return nil
    end
    return string.format("%04d-%02d-%02d", year, month, day)
end

function calendar.add_days(iso, delta)
    local year, month, day = calendar.parse(iso)
    if not year or type(delta) ~= "number" or delta ~= math.floor(delta) then return nil end
    while delta > 0 do
        day = day + 1
        if day > calendar.days_in_month(year, month) then
            day = 1
            month = month + 1
            if month > 12 then year, month = year + 1, 1 end
        end
        delta = delta - 1
    end
    while delta < 0 do
        day = day - 1
        if day < 1 then
            month = month - 1
            if month < 1 then year, month = year - 1, 12 end
            day = calendar.days_in_month(year, month)
        end
        delta = delta + 1
    end
    return calendar.format(year, month, day)
end

function calendar.compare(a, b)
    if not calendar.parse(a) or not calendar.parse(b) then return nil end
    if a == b then return 0 end
    return a < b and -1 or 1
end

function calendar.local_date()
    local t = punri.get_date and punri.get_date() or nil
    if type(t) ~= "table" then return nil end
    local iso = calendar.format(tonumber(t.year) or 0, tonumber(t.month) or 0, tonumber(t.day) or 0)
    if not iso then return nil end
    return iso, tonumber(t.offset_minutes) or 0
end

return calendar
