local M = {}

M.MAX_INPUT_CHARS = 16
M.SIGNIFICANT_DIGITS = 6

local function is_nonzero_mantissa(text)
    return text:find("[1-9]") ~= nil
end

function M.parse_number(source)
    if type(source) ~= "string" or #source == 0 then return nil, "Enter a number." end
    if #source > M.MAX_INPUT_CHARS then return nil, "Input is too long." end

    local text = source
    local commas = 0
    for _ in text:gmatch(",") do commas = commas + 1 end
    if commas > 0 then
        if commas ~= 1 or text:find(".", 1, true) then
            return nil, "Use one decimal point or comma, not thousands separators."
        end
        local prefix, suffix = text:match("^([+-]?%d*),(%d+)$")
        if not prefix then return nil, "Invalid decimal comma." end
        -- 12,345 is ambiguous without locale context; 0,500 is not.
        local unsigned = prefix:gsub("^[+-]", "")
        if #suffix == 3 and unsigned ~= "0" and unsigned ~= "" then
            return nil, "Thousands separators are not supported."
        end
        text = prefix .. "." .. suffix
    end

    local sign = ""
    local first = text:sub(1, 1)
    if first == "-" or first == "+" then
        sign = first
        text = text:sub(2)
    end
    if #text == 0 then return nil, "Enter a number." end

    local exponent = ""
    local exponent_start = text:find("[eE]")
    if exponent_start then
        if text:find("[eE]", exponent_start + 1) then return nil, "Invalid exponent." end
        exponent = text:sub(exponent_start + 1)
        text = text:sub(1, exponent_start - 1)
        if not exponent:match("^[+-]?%d+$") then return nil, "Invalid exponent." end
    end

    local dot = text:find(".", 1, true)
    if dot then
        if text:find(".", dot + 1, true) then return nil, "Use only one decimal point." end
        local left, right = text:match("^(%d*)%.(%d*)$")
        if left == nil or (left == "" and right == "") then return nil, "Invalid decimal number." end
    elseif not text:match("^%d+$") then
        return nil, "Invalid number."
    end

    local number = tonumber(sign .. text .. (exponent ~= "" and "e" .. exponent or ""))
    if number == nil or number ~= number then return nil, "Invalid number." end
    if number == 0.0 and is_nonzero_mantissa(text) then
        return nil, "Value is too small for this device."
    end
    return number + 0.0
end

function M.number(value)
    if value == nil or value ~= value then return nil end
    if value == 0.0 then return "0" end
    -- %g supplies six significant digits and switches to an editable exponent
    -- only for very small or large values.  It never turns a nonzero float
    -- into the misleading display value "0".
    local text = string.format("%.6g", value + 0.0)
    if text == "inf" or text == "-inf" or text == "nan" then return nil end
    return text
end

function M.editable(value)
    return M.number(value)
end

return M
