-- Replacement digital chronograph; the bounded model preserves stopwatch.dat.
local Stopwatch=punri.dofile("stopwatch.lua")
local Feedback=punri.dofile("press_feedback.lua")
local UI=punri.dofile("ui.lua")
local Input=punri.dofile("input.lua")
local stopwatch=Stopwatch.new()
UI.bind(Feedback)
function on_init()
    Input.reset_pending(UI)
    stopwatch:load()
    stopwatch:update_sleep_policy()
    UI.refresh()
end
function on_draw() UI.draw(stopwatch) end
function on_update()
    Feedback.update()
    if stopwatch:needs_redraw() then punri.request_update() end
end
function on_button(button,pressed)
    if pressed then Input.handle_button(stopwatch,UI,button) end
end
-- Only one callback: the runtime also emits compatibility on_touch for this tap.
function on_tap(x,y) Input.handle_tap(stopwatch,UI,x,y) end
function on_exit()
    Input.reset_pending(UI)
    stopwatch:save_on_exit()
    stopwatch:set_awake(false)
end
if _G.TEST_APP=="stopwatch" then STOPWATCH_TEST={model=stopwatch,ui=UI,feedback=Feedback} end
