local M = {}

local function has_exponent(text)
    return text:find("[eE]") ~= nil
end

function M.apply(text, key, max_chars)
    if key == "Del" then
        if #text == 0 then return text, false end
        return text:sub(1, #text - 1), true
    end
    if key == "Clear" then
        if #text == 0 then return text, false end
        return "", true
    end
    if key == "+/-" then
        if text:sub(1, 1) == "-" then return text:sub(2), true end
        if #text >= max_chars then return text, false, "Input is too long." end
        return "-" .. text, true
    end

    if key == "." then
        if has_exponent(text) then text = "" end
        if text:find(".", 1, true) then return text, false, "Only one decimal point is allowed." end
        if #text >= max_chars then return text, false, "Input is too long." end
        if text == "" or text == "-" then return text .. "0.", true end
        return text .. ".", true
    end

    if not key:match("^%d$") then return text, false end
    if has_exponent(text) then text = "" end
    if #text >= max_chars then return text, false, "Input is too long." end
    return text .. key, true
end

return M
