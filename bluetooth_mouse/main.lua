local Mouse = punri.dofile("controller.lua")
local UI = punri.dofile("ui.lua")
local settings = false

function on_init()
    settings = false
    Mouse.init()
end

function on_update()
    Mouse.update()
    if settings or not Mouse.supported then return end
    local x, y = punri.get_touch()
    Mouse.sample(x, y, x and UI.in_pad(x, y) or false)
end

function on_draw() UI.draw(Mouse, settings) end

local function act(action)
    if action == "pair" then Mouse.start()
    elseif action == "disconnect" then Mouse.stop(false)
    elseif action == "left" or action == "right" then Mouse.click(action)
    elseif action == "slow" then Mouse.set_speed(1)
    elseif action == "normal" then Mouse.set_speed(2)
    elseif action == "fast" then Mouse.set_speed(3)
    elseif action == "settings" then settings = true; Mouse.pause_input(); punri.request_update()
    elseif action == "close_settings" then settings = false; Mouse.pause_input(); punri.request_update()
    elseif action == "forget" then Mouse.stop(true)
    elseif action == "exit" then Mouse.exit(); punri.exit()
    end
end

-- Only the tap callback: the firmware also sends a compatibility on_touch tap.
function on_tap(x, y) act(UI.hit(x, y, Mouse, settings)) end

function on_button(button, pressed)
    if not pressed then return end
    if button == "back" then act(settings and "close_settings" or "exit")
    elseif not settings and button == "confirm" then
        act((Mouse.connected or Mouse.state == "advertising" or Mouse.state == "connecting") and "disconnect" or "pair")
    elseif not settings and (button == "page_back" or button == "left") then act("left")
    elseif not settings and (button == "page_forward" or button == "right") then act("right")
    end
end

function on_exit() Mouse.exit() end
