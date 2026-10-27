-- Every visible action owns a matching press target in its app sandbox.
PRESS_FEEDBACK = punri.dofile("press_feedback.lua")
local PRESS = PRESS_FEEDBACK
local PRESS_LABELS, PRESS_IDS = {}, {"footer:back", "footer:confirm", "footer:left", "footer:right"}
function press_hints(a, b, c, d)
    PRESS_LABELS[1], PRESS_LABELS[2], PRESS_LABELS[3], PRESS_LABELS[4] = a, b, c, d
    PRESS.footer(PRESS_LABELS, PRESS_IDS)
end
function press_ink(id, x, y, width, height, dark, shape, radius, enabled)
    PRESS.target(id, x, y, width, height, enabled, shape or "rounded", radius or 5, dark)
    local ink = PRESS.paint(id)
    if ink == nil then return dark ~= true end
    return ink
end

-- Codex: Ink & Iron for PUNRI (Lua)
-- Modular roguelike deckbuilder with dynamic screen loading and low heap footprint

w, h = 480, 800

dofile("state.lua")
dofile("ui_base.lua")
collectgarbage("collect")

active_screen = nil
active_screen_name = nil
pending_screen = nil
pending_screen_arg = nil

function set_screen(name, arg)
    pending_screen = name
    pending_screen_arg = arg
end

function apply_screen_transition()
    if not pending_screen then return end
    local name = pending_screen
    local arg = pending_screen_arg
    pending_screen = nil
    pending_screen_arg = nil

    if active_screen_name == name and active_screen then
        collectgarbage("collect")
        if active_screen.enter then
            active_screen.enter(arg)
        end
        punri.request_update()
        return
    end

    if active_screen and active_screen.exit then
        active_screen.exit()
    end
    active_screen = nil
    collectgarbage("collect")
    collectgarbage("collect")

    if not kCards and (name == "combat" or name == "reward" or name == "shop" or name == "deck_view") then
        dofile("cards.lua")
        collectgarbage("collect")
    end

    if name == "combat" or name == "reward" then
        if not play_card then
            dofile("combat_engine.lua")
            collectgarbage("collect")
        end
        if not draw_card_item then
            dofile("card_ui.lua")
            collectgarbage("collect")
        end
    end

    active_screen_name = name
    active_screen = dofile("screens/" .. name .. ".lua")
    collectgarbage("collect")

    if active_screen and active_screen.enter then
        active_screen.enter(arg)
    end
    collectgarbage("collect")
    punri.request_update()
end

function on_init()
    w, h = punri.get_bounds()
    math.randomseed(os.time())
    local loader = dofile("load_save.lua")
    if loader then loader() end
    loader = nil
    collectgarbage("collect")
    set_screen("title")
    apply_screen_transition()
end

function on_draw()
    if pending_screen then
        apply_screen_transition()
    end
    punri.clear()
    if active_screen and active_screen.draw then
        active_screen.draw()
    end
    collectgarbage("step", 50)
end

function on_button(btn, pressed)
    if active_screen and active_screen.on_button then
        active_screen.on_button(btn, pressed)
    end
    if pending_screen then
        apply_screen_transition()
    end
    collectgarbage("step", 50)
end

function on_tap(x, y)
    local m = punri.get_metrics()
    if y > h - math.max(40, m.button_hints_height or 0) then
        if x < w / 4 then
            on_button("back", true)
        elseif x < w / 2 then
            on_button("confirm", true)
        elseif x < 3 * w / 4 then
            on_button("left", true)
        else
            on_button("right", true)
        end
        return
    end

    if active_screen and active_screen.on_tap then
        active_screen.on_tap(x, y)
    end
end

-- Keep press lifetime separate from gameplay selection and persisted state.
punri.dofile("feedback.lua")(PRESS, {
    view = function() return active_screen_name or "loading" end,
    transition = function(id)
        return id == "footer:back" or active_screen_name == "title" or active_screen_name == "scriptorium"
            or active_screen_name == "outcome" or active_screen_name == "game_over" or active_screen_name == "victory"
            or id:sub(1, 10) == "deck_menu:" or id:sub(1, 7) == "reward:" or id:sub(1, 5) == "shop:"
            or id:sub(1, 5) == "hand:" and tonumber(id:sub(6)) == state.selectedHandIdx
    end,
    map_button = function(button)
        if button == "confirm" and active_screen then return active_screen.press_id end
    end,
    tap = function(x, y)
        local id = PRESS.hit(x, y)
        if id and id:sub(1, 7) == "footer:" then on_button(id:sub(8), true)
        elseif id and active_screen and active_screen.press_action then
            active_screen.press_action(id, x, y)
            if pending_screen then apply_screen_transition() end
        end
    end
})
