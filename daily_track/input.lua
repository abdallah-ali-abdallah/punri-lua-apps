-- Input adapters share actions with the touch layer.  The actual firmware
-- delivers both on_tap and on_touch("tap") for one physical tap, so main.lua
-- intentionally calls this from on_tap only.
local input = {}

function input.button_delta(button)
    if button == "left" or button == "up" or button == "page_back" then return -1 end
    if button == "right" or button == "down" or button == "page_forward" then return 1 end
    return 0
end

function input.number(value)
    if type(value) ~= "string" or not value:match("^%d+$") then return nil end
    local number = tonumber(value)
    if not number or number ~= math.floor(number) then return nil end
    return number
end

return input
