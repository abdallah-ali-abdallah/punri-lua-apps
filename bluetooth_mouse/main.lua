local Mouse = punri.dofile("controller.lua")
local UI = punri.dofile("ui.lua")
local settings = false

function on_init()
    settings = false
    Mouse.init()
end

function on_update()
    UI.feedback.update()
    Mouse.update()
    if settings or not Mouse.supported then return end
    local x, y = punri.get_touch()
    Mouse.sample(x, y, x and UI.in_pad(x, y) or false)
end

function on_draw() UI.draw(Mouse, settings); UI.feedback.finish() end

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
local function feedback_action(action)
    if not action or UI.feedback.busy() then return end
    local id = (action == "pair" or action == "disconnect") and "primary" or action
    if action == "settings" or action == "close_settings" or action == "exit" then
        if UI.feedback.defer(id, function() act(action) end) then return end
    else UI.feedback.press(id) end
    act(action)
end
function on_tap(x, y)
    -- Match the current layout even before its next feedback frame is painted.
    feedback_action(UI.hit(x, y, Mouse, settings))
end

function on_button(button, pressed)
    if not pressed then return end
    if button == "back" then feedback_action(settings and "close_settings" or "exit")
    elseif not settings and button == "confirm" then
        feedback_action((Mouse.connected or Mouse.state == "advertising" or Mouse.state == "connecting") and "disconnect" or "pair")
    elseif not settings and (button == "up" or button == "page_back" or button == "left") then feedback_action("left")
    elseif not settings and (button == "down" or button == "page_forward" or button == "right") then feedback_action("right")
    end
end

function on_exit() Mouse.exit() end
