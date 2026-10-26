local Controller = punri.dofile("controller.lua")
local UI = punri.dofile("ui.lua")

local function act(action)
    if action == "pair" then Controller.start()
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
    Controller.update()
end

function on_draw()
    UI.draw(Controller)
end

function on_button(button, pressed)
    if not pressed then return end
    if UI.settings_open then
        if button == "back" then act("close_settings")
        elseif button == "confirm" then act(UI.settings_focus == 1 and "forget" or "close_settings")
        elseif button == "left" or button == "right" or button == "up" or button == "down"
            or button == "page_back" or button == "page_forward" then
            UI.settings_focus = 3 - UI.settings_focus
            punri.request_update()
        end
        return
    end
    if button == "back" then
        Controller.exit()
        punri.exit()
    elseif button == "confirm" then
        act(Controller.connected and "disconnect" or "pair")
    elseif button == "up" or button == "down" or button == "left" or button == "right" then
        act(button)
    elseif button == "page_back" then
        act("left")
    elseif button == "page_forward" then
        act("right")
    end
end

-- Deliberately define only on_tap: Activity dispatches a compatibility
-- on_touch callback for the same physical tap, so defining both would send
-- a host key twice.
function on_tap(x, y)
    act(UI.hit(x, y, Controller))
end

function on_exit()
    Controller.exit()
end
