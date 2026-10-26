local Controller = punri.dofile("controller.lua")
local UI = punri.dofile("ui.lua")

local function act(action)
    if action == "pair" then Controller.start()
    elseif action == "disconnect" then Controller.stop(false)
    elseif action == "forget" then Controller.stop(true)
    elseif action == "mode" then Controller.toggle_mode()
    elseif action == "up" or action == "down" or action == "left" or action == "right"
        or action == "enter" or action == "space" then Controller.send(action)
    end
end

function on_init()
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
