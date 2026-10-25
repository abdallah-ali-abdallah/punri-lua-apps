-- Versioned, intentionally small persistence model for Screen Ruler.

local Ruler = Ruler or dofile("ruler.lua")
local Calibration = {}

Calibration.FILE = "screen_ruler_v1.txt"
Calibration.SCHEMA = "PUNRI_SCREEN_RULER_1"

local function is_integer(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value % 1 == 0
end

local function copy_scale(scale)
    if not Ruler.is_valid(scale) then return nil end
    return { n = scale.n, d = scale.d }
end

function Calibration.default(device, portrait_width, portrait_height)
    return {
        device = device,
        portrait_width = portrait_width,
        portrait_height = portrait_height,
        calibrated = false,
        mode = "both",
        units = "mm",
        orientation = "auto",
        x = nil,
        y = nil,
    }
end

function Calibration.copy(state)
    return {
        device = state.device,
        portrait_width = state.portrait_width,
        portrait_height = state.portrait_height,
        calibrated = state.calibrated == true,
        mode = state.mode,
        units = state.units,
        orientation = state.orientation,
        x = copy_scale(state.x),
        y = copy_scale(state.y),
    }
end

function Calibration.has_device_profile(state)
    return (state.device == "x4pro" or state.device == "x4") and
        state.portrait_width == 480 and state.portrait_height == 800
end

function Calibration.apply_device_profile(state)
    -- Xteink specifies 219 PPI for X4 Pro and X4 Classic. At 25.4 mm/inch,
    -- px/mm = 219 * 10 / 254 = 1095/127. Keep the nominal factory scale exact
    -- rather than deriving it from the rounded 4.3-inch marketing diagonal.
    -- Sources and the hardware verification procedure are in README.md.
    if not Calibration.has_device_profile(state) then return false end
    state.x, state.y = { n = 1095, d = 127 }, { n = 1095, d = 127 }
    state.calibrated = true
    return true
end

function Calibration.uses_device_profile(state)
    return Calibration.has_device_profile(state) and state.calibrated and
        state.x and state.y and state.x.n == 1095 and state.x.d == 127 and
        state.y.n == 1095 and state.y.d == 127
end

local function valid_identity(device, width, height)
    return type(device) == "string" and device:match("^[a-z0-9_-]+$") ~= nil and
        is_integer(width) and is_integer(height) and width >= 100 and width <= 2000 and height >= 100 and height <= 2000
end

function Calibration.is_valid(state)
    if type(state) ~= "table" or not valid_identity(state.device, state.portrait_width, state.portrait_height) then return false end
    if state.mode ~= "horizontal" and state.mode ~= "vertical" and state.mode ~= "both" then return false end
    if state.units ~= "mm" and state.units ~= "cm" and state.units ~= "in" then return false end
    if state.orientation ~= "auto" and state.orientation ~= "portrait" and state.orientation ~= "landscape" then return false end
    if state.calibrated == true then return Ruler.is_valid(state.x) and Ruler.is_valid(state.y) end
    return state.x == nil and state.y == nil
end

function Calibration.same_identity(state, device, portrait_width, portrait_height)
    return state.device == device and state.portrait_width == portrait_width and state.portrait_height == portrait_height
end

function Calibration.encode(state)
    if not Calibration.is_valid(state) then return nil end
    local x, y = state.x or { n = 0, d = 0 }, state.y or { n = 0, d = 0 }
    return table.concat({
        Calibration.SCHEMA,
        "device=" .. state.device,
        "portrait_width=" .. state.portrait_width,
        "portrait_height=" .. state.portrait_height,
        "calibrated=" .. (state.calibrated and "1" or "0"),
        "x_num=" .. x.n,
        "x_den=" .. x.d,
        "y_num=" .. y.n,
        "y_den=" .. y.d,
        "mode=" .. state.mode,
        "units=" .. state.units,
        "orientation=" .. state.orientation,
        "",
    }, "\n")
end

local function parse_integer(text)
    if type(text) ~= "string" or text:match("^%d+$") == nil or #text > 9 then return nil end
    local value = tonumber(text)
    if not is_integer(value) then return nil end
    return value
end

function Calibration.decode(raw)
    if type(raw) ~= "string" or #raw == 0 or #raw > 512 then return nil, "corrupt" end
    local lines = {}
    for line in raw:gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    if lines[1] ~= Calibration.SCHEMA or #lines ~= 12 then return nil, "corrupt" end
    local fields = {}
    for i = 2, 12 do
        local key, value = lines[i]:match("^([a-z_]+)=(.*)$")
        if not key or fields[key] ~= nil then return nil, "corrupt" end
        fields[key] = value
    end
    local calibrated = fields.calibrated == "1"
    if not calibrated and fields.calibrated ~= "0" then return nil, "corrupt" end
    local state = {
        device = fields.device,
        portrait_width = parse_integer(fields.portrait_width),
        portrait_height = parse_integer(fields.portrait_height),
        calibrated = calibrated,
        mode = fields.mode,
        units = fields.units,
        orientation = fields.orientation,
        x = nil,
        y = nil,
    }
    local x_num, x_den = parse_integer(fields.x_num), parse_integer(fields.x_den)
    local y_num, y_den = parse_integer(fields.y_num), parse_integer(fields.y_den)
    if calibrated then
        state.x = Ruler.normalize(x_num, x_den)
        state.y = Ruler.normalize(y_num, y_den)
    elseif x_num ~= 0 or x_den ~= 0 or y_num ~= 0 or y_den ~= 0 then
        return nil, "corrupt"
    end
    if not Calibration.is_valid(state) then return nil, "corrupt" end
    return state
end

-- Parse decimal millimetres without accepting NaN, exponent notation or a
-- silently rounded value. Return hundredths of a millimetre.
function Calibration.parse_millimeters(text)
    if type(text) ~= "string" or #text == 0 or #text > 7 then return nil end
    local whole, fraction = text:match("^(%d+)%.?(%d*)$")
    if not whole or #whole > 3 or #fraction > 2 then return nil end
    local integral = parse_integer(whole)
    local fractional = fraction == "" and 0 or parse_integer(fraction)
    if integral == nil or fractional == nil then return nil end
    if #fraction == 1 then fractional = fractional * 10 end
    local total = integral * 100 + fractional
    if total < 100 or total > 50000 then return nil end
    return total
end

function Calibration.format_millimeters_hundredths(value)
    if not is_integer(value) or value < 0 then return "--" end
    local whole, fraction = value // 100, value % 100
    if fraction == 0 then return tostring(whole) end
    if fraction % 10 == 0 then return string.format("%d.%d", whole, fraction // 10) end
    return string.format("%d.%02d", whole, fraction)
end

return Calibration
