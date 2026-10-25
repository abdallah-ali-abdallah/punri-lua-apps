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

-- position(i) = origin + round(i * numerator / denominator).
function Ruler.tick_position(origin, millimeter_index, scale)
    if not is_integer(origin) or not is_integer(millimeter_index) or millimeter_index < 0 then return nil end
    if not Ruler.is_valid(scale) or millimeter_index > Ruler.MAX_TICK_INDEX then return nil end
    local product = millimeter_index * scale.n
    if product > 2000000000 then return nil end
    return origin + (product + scale.d // 2) // scale.d
end

-- Largest whole-mm mark whose rounded coordinate is inside [origin, limit).
function Ruler.max_index(origin, limit, scale)
    if not is_integer(origin) or not is_integer(limit) or limit <= origin or not Ruler.is_valid(scale) then return 0 end
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
function Ruler.minor_step(scale)
    if not Ruler.is_valid(scale) then return nil end
    if scale.n >= scale.d then return 1 end
    return (scale.d + scale.n - 1) // scale.n
end

function Ruler.should_draw_tick(index, minor_step)
    return index == 0 or index % minor_step == 0 or index % 5 == 0
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
