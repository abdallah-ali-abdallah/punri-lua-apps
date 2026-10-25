-- Stopwatch entry point. The model, layout and input mapping deliberately stay
-- separate so buttons and touch targets always use the same actions.

local Stopwatch = punri.dofile("stopwatch.lua")
local UI = punri.dofile("ui.lua")
local Input = punri.dofile("input.lua")

local stopwatch = Stopwatch.new()

local function request_draw_if(changed)
    if changed and punri and punri.request_update then punri.request_update() end
end

function on_init()
    stopwatch:load()
    -- The manifest keeps the released default, but the app narrows it here:
    -- auto-sleep is blocked only for an actively running stopwatch.
    stopwatch:update_sleep_policy()
    UI.refresh()
end

function on_draw()
    UI.draw(stopwatch)
end

function on_update()
    -- This only requests a redraw while running (or once when the bounded
    -- session reaches its maximum); elapsed time itself never depends on FPS.
    request_draw_if(stopwatch:needs_redraw())
end

function on_button(button, pressed)
    if not pressed then return end
    -- LuaAppActivity already schedules a render after input. Do not request a
    -- second app-level redraw here; disabled actions also return false.
    Input.handle_button(stopwatch, UI, button)
end

function on_tap(x, y)
    -- LuaAppActivity invokes on_tap and then on_touch(x, y, "tap") for one
    -- physical touch. This app intentionally defines only on_tap.
    Input.handle_tap(stopwatch, UI, x, y)
end

function on_exit()
    -- on_exit cannot cancel a pending exit, so the visible Exit action retries
    -- failed persistence before asking the activity to leave. This is only a
    -- best-effort fallback for forced exits.
    stopwatch:save_on_exit()
    stopwatch:set_awake(false)
end
