-- A single action map serves touch and hardware buttons. Only navigation waits
-- for its visual acknowledgement; Start/Stop/Lap timestamps are immediate.
local Input = {}
local pending_action

local function apply(model, ui, action)
    local changed, save = false, false
    if action == "toggle" then changed, save = model:toggle_running()
    elseif action == "lap" then changed, save = model:add_lap()
    elseif action == "reset" then changed, save = model:request_reset()
    elseif action == "keep" then changed, save = model:cancel_reset()
    elseif action == "confirm" then
        model:select_reset("confirm")
        changed, save = model:confirm_reset()
    elseif action == "previous" then changed, save = model:change_lap_page(1, ui.visible_laps())
    elseif action == "next" then changed, save = model:change_lap_page(-1, ui.visible_laps())
    elseif action == "exit" then changed = select(1, model:retry_or_exit(function() punri.exit() end)) end
    if save then model:save() end
    return changed
end

function Input.reset_pending(ui)
    pending_action = nil
    ui.clear()
end

function Input.dispatch(model, ui, action)
    if not action then return false end
    if pending_action then
        -- Back can cancel a queued transition, but another Confirm cannot
        -- enqueue a second destructive action or leave a stale callback.
        if action ~= "exit" and action ~= "keep" then return false end
        Input.reset_pending(ui)
    end
    if not ui.action_enabled(model, action) then return false end
    if action == "reset" or action == "keep" or action == "confirm" or action == "exit" then
        pending_action = action
        local queued = ui.defer(action, function()
            pending_action = nil
            apply(model, ui, action)
            punri.request_update()
        end)
        if queued then return true end
        -- A physical key can arrive before the initial frame registered its
        -- targets. The command must still work; the next frame owns feedback.
        pending_action = nil
    else
        ui.press(action)
    end
    return apply(model, ui, action)
end

function Input.handle_tap(model, ui, x, y)
    return Input.dispatch(model, ui, ui.hit_action(model, x, y))
end

function Input.handle_button(model, ui, button)
    if model.reset_pending then
        if button == "back" or button == "btn1" or button == "left" or button == "page_back" or button == "up" then
            return Input.dispatch(model, ui, "keep")
        elseif button == "right" or button == "page_forward" or button == "down" then
            return Input.dispatch(model, ui, "confirm")
        elseif button == "confirm" or button == "btn2" then
            return Input.dispatch(model, ui, model.reset_choice)
        end
        return false
    end
    if button == "back" or button == "btn1" then return Input.dispatch(model, ui, "exit") end
    if button == "confirm" or button == "btn2" then return Input.dispatch(model, ui, "toggle") end
    if button == "left" or button == "btn3" then return Input.dispatch(model, ui, "lap") end
    if button == "right" or button == "btn4" then return Input.dispatch(model, ui, "reset") end
    if button == "up" or button == "page_back" then return Input.dispatch(model, ui, "previous") end
    if button == "down" or button == "page_forward" then return Input.dispatch(model, ui, "next") end
    return false
end
return Input
