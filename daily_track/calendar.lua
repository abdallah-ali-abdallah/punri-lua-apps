-- Civil-date helpers.  Dates stay in YYYY-MM-DD form so lexical order is
-- chronological order.  A modern PUNRI clock exposes `valid=false` for its
-- compatibility fallback; that placeholder must never become tracker history.
local calendar = {}
-- Keep the full four-digit civil-date domain.  History navigation needs dates
-- outside the current clock year (for example the 35 days before 1 January),
-- so a narrow device-clock window must not make valid persisted cells unreadable.
local MIN_YEAR, MAX_YEAR = 1, 9999
local month_names = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

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

function calendar.month_start(iso)
    local year, month = calendar.parse(iso)
    return year and calendar.format(year, month, 1) or nil
end

function calendar.month_end(iso)
    local year, month = calendar.parse(iso)
    return year and calendar.format(year, month, calendar.days_in_month(year, month)) or nil
end

function calendar.add_months(iso, delta)
    local year, month = calendar.parse(iso)
    if not year or type(delta) ~= "number" or delta ~= math.floor(delta) then return nil end
    local absolute = (year - 1) * 12 + month - 1 + delta
    if absolute < 0 or absolute >= MAX_YEAR * 12 then return nil end
    year, month = math.floor(absolute / 12) + 1, absolute % 12 + 1
    return calendar.format(year, month, 1)
end

-- Sunday is 0, followed by Monday through Saturday.  This proleptic
-- Gregorian calculation covers Daily Track's whole persisted date range.
function calendar.weekday(iso)
    local year, month, day = calendar.parse(iso)
    if not year then return nil end
    local offsets = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
    if month < 3 then year = year - 1 end
    return (year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400) + offsets[month] + day) % 7
end

function calendar.month_label(iso)
    local year, month = calendar.parse(iso)
    return year and string.format("%s %04d", month_names[month], year) or nil
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
    if type(t) ~= "table" or t.valid == false then return nil end
    local iso = calendar.format(tonumber(t.year) or 0, tonumber(t.month) or 0, tonumber(t.day) or 0)
    if not iso then return nil end
    return iso, tonumber(t.offset_minutes) or 0
end

return calendar
