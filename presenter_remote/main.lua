local Controller = punri.dofile("controller.lua")
local UI = punri.dofile("ui.lua")
-- Persistent scalar state: no per-frame contact tables or input queue.
local touch_x, touch_y, touch_down, touch_cancelled, touch_route
local tap_action

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
    touch_x, touch_y, touch_down, touch_cancelled, touch_route = nil, nil, false, false, nil
    Controller.init()
end

function on_update()
    UI.feedback.update()
    Controller.update()
    -- API 5 exposes live contact independently of completed-tap delivery. Pick
    -- one route for this session so a native release cannot repeat a fallback.
    if type(punri.get_touch) ~= "function" or touch_route == "tap" then return end
    local x, y = punri.get_touch()
    if x then
        if not touch_down then
            touch_x, touch_y, touch_down, touch_cancelled = x, y, true, false
        elseif math.abs(x - touch_x) >= 60 or math.abs(y - touch_y) >= 60 then
            touch_cancelled = true
        end
    elseif touch_down then
        touch_down = false
        if not touch_cancelled then
            if not touch_route then punri.log("Presenter Remote input: live contact fallback") end
            touch_route = "live"
            tap_action(touch_x, touch_y)
        end
    end
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
    elseif button == "left" or button == "right" then
        feedback_action(button)
    elseif button == "up" or button == "page_back" then
        feedback_action("left")
    elseif button == "down" or button == "page_forward" then
        feedback_action("right")
    end
end

-- Deliberately define only on_tap: Activity dispatches a compatibility
-- on_touch callback for the same physical tap, so defining both would send
-- a host key twice.
tap_action = function(x, y)
    if UI.feedback.busy() then return end
    -- Input uses live controls, including arrow labels. Painted feedback targets
    -- can still describe the frame before pairing or a mode/settings change.
    local action = UI.hit(x, y, Controller)
    if not action then
        local footer = UI.settings_open and "close_settings" or "exit"
        if UI.feedback.hit(x, y) == footer then action = footer end
    end
    feedback_action(action)
end

function on_tap(x, y)
    if touch_route == "live" then return end
    if not touch_route then punri.log("Presenter Remote input: native tap") end
    touch_route = "tap"
    tap_action(x, y)
end

function on_exit()
    Controller.exit()
end
