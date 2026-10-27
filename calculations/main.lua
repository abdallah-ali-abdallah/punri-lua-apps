-- Calculations is entirely app-owned; no runtime or SDK changes are required.
local B = punri.dofile("bigint.lua")
local D = punri.dofile("decimal.lua")(B)
local N = punri.dofile("number.lua")(B, D)
local P = punri.dofile("parser.lua")
local Editor = punri.dofile("editor.lua")(P)
local E = punri.dofile("engine.lua")(B, D, N, P)
local Store = punri.dofile("storage.lua")
local I = punri.dofile("i18n.lua")
local Tools = punri.dofile("tools.lua")(B, D, N, E, P)
local UI = punri.dofile("ui.lua")(I, P, N, D)
local app = punri.dofile("app.lua")(E, Editor, Store, Tools, UI, I)

function on_init() app:init() end
function on_draw() app.ui.draw() end
function on_update() app:update() end
function on_tap(x, y)
    local id = UI.feedback.hit(x, y)
    if type(id) == "string" and id:match("^footer_") then app:button(id:sub(8), true)
    else app:tap(x, y) end
end
function on_button(button, pressed) app:button(button, pressed) end
function on_keyboard(text, cancelled) app:keyboard_result(text, cancelled) end
function on_exit() app:exit() end
