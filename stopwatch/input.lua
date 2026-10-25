-- All touch and physical-button paths dispatch to this single action map.

local Input = {}

local function save_if_needed(model, should_save)
    if should_save then model:save() end
end

function Input.dispatch(model, ui, action)
    if action == nil then return false end
    local changed, should_save = false, false
    if action == "toggle" then
        changed, should_save = model:toggle_running()
    elseif action == "lap" then
        changed, should_save = model:add_lap()
    elseif action == "reset" then
        changed, should_save = model:request_reset()
    elseif action == "keep" then
        changed, should_save = model:cancel_reset()
    elseif action == "confirm" then
        -- The touch target is an explicit destructive choice. Physical
        -- Confirm is mapped to the current selection in handle_button(), so
        -- it keeps its keyboard-style behaviour.
        model:select_reset("confirm")
        changed, should_save = model:confirm_reset()
    elseif action == "previous" then
        changed, should_save = model:change_lap_page(1, ui.visible_laps())
    elseif action == "next" then
        changed, should_save = model:change_lap_page(-1, ui.visible_laps())
    elseif action == "exit" then
        changed = select(1, model:retry_or_exit(function() punri.exit() end))
    end
    save_if_needed(model, should_save)
    return changed
end

function Input.handle_tap(model, ui, x, y)
    return Input.dispatch(model, ui, ui.hit_action(model, x, y))
end

function Input.handle_button(model, ui, button)
    if model.reset_pending then
        if button == "back" or button == "btn1" or button == "left" or button == "page_back" or button == "up" then
            return Input.dispatch(model, ui, "keep")
        elseif button == "right" or button == "page_forward" or button == "down" then
            model:select_reset("confirm")
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
