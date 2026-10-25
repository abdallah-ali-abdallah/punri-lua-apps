-- Exact, bounded ruler arithmetic for Screen Ruler.
-- Lua on PUNRI uses 32-bit integers/floats. Keep every integer intermediate
-- below 2^31 and calculate every mark from the origin, never the prior mark.

local Ruler = {}

Ruler.MAX_NUMERATOR = 80000       -- 800px calibration span * 100 hundredths/mm
Ruler.MAX_DENOMINATOR = 50000     -- 500.00 mm reference length
Ruler.MAX_TICK_INDEX = 5000       -- well below 2^31 even at MAX_NUMERATOR

local function is_integer(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value % 1 == 0
end

local function gcd(a, b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end

function Ruler.normalize(numerator, denominator)
    if not is_integer(numerator) or not is_integer(denominator) or numerator <= 0 or denominator <= 0 then
        return nil
    end
    if numerator > Ruler.MAX_NUMERATOR or denominator > Ruler.MAX_DENOMINATOR then
        return nil
    end
    local divisor = gcd(numerator, denominator)
    return { n = numerator // divisor, d = denominator // divisor }
end

function Ruler.is_valid(scale)
    if type(scale) ~= "table" then return false end
    local normalized = Ruler.normalize(scale.n, scale.d)
    if not normalized then return false end
    -- A calibration below 0.25 px/mm cannot make a useful ruler; above
    -- 20 px/mm is implausible for the supported 800x480 panels. Products
    -- remain at most 1,000,000, safely exact in PUNRI's 32-bit Lua integers.
    return normalized.n * 4 >= normalized.d and normalized.n <= normalized.d * 20
end

function Ruler.from_span(span_px, millimeters_hundredths)
    if not is_integer(span_px) or not is_integer(millimeters_hundredths) then return nil end
    if span_px < 20 or span_px > 800 or millimeters_hundredths < 100 or millimeters_hundredths > 50000 then
        return nil
    end
    local scale = Ruler.normalize(span_px * 100, millimeters_hundredths)
    if not Ruler.is_valid(scale) then return nil end
    return scale
end

-- Metric indices are mm; inch indices are sixteenths (exactly 127/80 mm).
-- Split whole/remainder products so even the largest saved scale stays below
-- 2^31. Multiplying index * numerator * 127 directly would overflow on-device.
function Ruler.tick_position(origin, index, scale, units)
    if not is_integer(origin) or not is_integer(index) or index < 0 then return nil end
    if not Ruler.is_valid(scale) or index > Ruler.MAX_TICK_INDEX then return nil end
    if units == "in" then
        local distance = index * 127
        local product = (distance // 80) * scale.n
        local whole = product // scale.d
        local remainder = (product % scale.d) * 80 + (distance % 80) * scale.n
        local denominator = scale.d * 80
        return origin + whole + (remainder + denominator // 2) // denominator
    end
    local product = index * scale.n
    if product > 2000000000 then return nil end
    return origin + (product + scale.d // 2) // scale.d
end

-- Largest whole-mm mark whose rounded coordinate is inside [origin, limit).
function Ruler.max_index(origin, limit, scale, units)
    if not is_integer(origin) or not is_integer(limit) or limit <= origin or not Ruler.is_valid(scale) then return 0 end
    if units == "in" then
        local low, high = 0, Ruler.MAX_TICK_INDEX
        while low < high do
            local middle = (low + high + 1) // 2
            if Ruler.tick_position(origin, middle, scale, units) < limit then low = middle else high = middle - 1 end
        end
        return low
    end
    local available = limit - origin - 1
    -- round(q / d) <= available iff q + floor(d/2) < (available + 1) * d.
    local bound = (available + 1) * scale.d - 1 - scale.d // 2
    if bound <= 0 then return 0 end
    local result = bound // scale.n
    if result < 0 then return 0 end
    return math.min(result, Ruler.MAX_TICK_INDEX)
end

-- Do not draw overlapping 1-mm marks. This is the smallest integral-mm
-- subdivision that can advance by at least one physical pixel.
function Ruler.minor_step(scale, units)
    if not Ruler.is_valid(scale) then return nil end
    if units == "in" then
        local step = 1
        while step * scale.n * 127 < scale.d * 80 do step = step * 2 end
        return step
    end
    if scale.n >= scale.d then return 1 end
    return (scale.d + scale.n - 1) // scale.n
end

function Ruler.should_draw_tick(index, minor_step, units)
    return index == 0 or index % minor_step == 0 or index % (units == "in" and 4 or 5) == 0
end

function Ruler.tick_label(index, units)
    local major = units == "in" and 16 or 10
    if index <= 0 or index % major ~= 0 then return nil end
    return tostring(units == "mm" and index or index // major)
end

function Ruler.tick_length(index, units)
    if units == "in" then
        if index % 16 == 0 then return 18, 2 end
        if index % 8 == 0 then return 15, 1 end
        if index % 4 == 0 then return 12, 1 end
        return index % 2 == 0 and 9 or 6, 1
    end
    return index % 10 == 0 and 18 or (index % 5 == 0 and 13 or 8), index % 10 == 0 and 2 or 1
end

-- Hundredths of the selected display unit for a pixel distance. Compute the
-- quotient first; pixels * denominator * 500 could exceed 32-bit Lua limits.
function Ruler.measure_pixels(pixels, scale, units)
    if not is_integer(pixels) or pixels < 0 or pixels > 2000 or not Ruler.is_valid(scale) then return nil end
    local product = pixels * scale.d
    local whole, remainder = product // scale.n, product % scale.n
    if units == "in" then
        local converted = whole * 500
        local tail = (converted % 127) * scale.n + remainder * 500
        local denominator = scale.n * 127
        return converted // 127 + (tail + denominator // 2) // denominator
    end
    local factor = units == "cm" and 10 or 100
    return whole * factor + (remainder * factor + scale.n // 2) // scale.n
end

function Ruler.tick_hundredths(index, units)
    if units == "in" then return (index * 100 + 8) // 16 end
    return index * (units == "cm" and 10 or 100)
end

function Ruler.format_scale(scale)
    if not Ruler.is_valid(scale) then return "--" end
    local whole = scale.n // scale.d
    local hundredths = ((scale.n % scale.d) * 100 + scale.d // 2) // scale.d
    if hundredths >= 100 then
        whole, hundredths = whole + 1, 0
    end
    return string.format("%d.%02d px/mm", whole, hundredths)
end

return Ruler
