local Controller = punri.dofile("controller.lua")
local UI = punri.dofile("ui.lua")

local function act(action)
    if action == "exit" then Controller.exit(); punri.exit()
    elseif action == "pair" then Controller.start()
    elseif action == "disconnect" then Controller.stop(false)
    elseif action == "forget" then Controller.stop(true)
    elseif action == "mode" then Controller.toggle_mode()
    elseif action == "settings" then
        UI.settings_open, UI.settings_focus = true, 2
        punri.request_update()
    elseif action == "close_settings" then
        UI.settings_open = false
        punri.request_update()
    elseif action == "up" or action == "down" or action == "left" or action == "right"
        or action == "enter" or action == "space" then Controller.send(action)
    end
end

function on_init()
    UI.settings_open, UI.settings_focus = false, 2
    Controller.init()
end

function on_update()
    UI.feedback.update()
    Controller.update()
end

function on_draw()
    UI.draw(Controller)
    UI.feedback.finish()
end

local function feedback_action(action)
    if not action or UI.feedback.busy() then return end
    local id = (action == "pair" or action == "disconnect") and "primary" or action
    if action == "settings" or action == "close_settings" or action == "exit" then
        if UI.feedback.defer(id, function() act(action) end) then return end
    else UI.feedback.press(id) end
    act(action)
end

function on_button(button, pressed)
    if not pressed then return end
    if UI.settings_open then
        if button == "back" then feedback_action("close_settings")
        elseif button == "confirm" then feedback_action(UI.settings_focus == 1 and "forget" or "close_settings")
        elseif button == "left" or button == "right" or button == "up" or button == "down"
            or button == "page_back" or button == "page_forward" then
            UI.settings_focus = 3 - UI.settings_focus
            punri.request_update()
        end
        return
    end
    if button == "back" then
        feedback_action("exit")
    elseif button == "confirm" then
        feedback_action(Controller.connected and "disconnect" or "pair")
    elseif button == "up" or button == "down" or button == "left" or button == "right" then
        feedback_action(button)
    elseif button == "page_back" then
        feedback_action("left")
    elseif button == "page_forward" then
        feedback_action("right")
    end
end

-- Deliberately define only on_tap: Activity dispatches a compatibility
-- on_touch callback for the same physical tap, so defining both would send
-- a host key twice.
function on_tap(x, y)
    local id = UI.feedback.hit(x, y)
    if not id and not UI.feedback.busy() then
        local action = UI.hit(x, y, Controller)
        if (action == "enter" or action == "space") and not Controller.enter_space_supported then feedback_action(action) end
        return
    end
    if id == "primary" then id = Controller.connected and "disconnect" or "pair" end
    feedback_action(id)
end

function on_exit()
    Controller.exit()
end
