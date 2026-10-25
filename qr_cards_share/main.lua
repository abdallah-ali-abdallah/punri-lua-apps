QR = dofile("qr.lua")
Cards = dofile("cards.lua")
Storage = dofile("storage.lua")
UI = dofile("ui.lua")
Input = dofile("input.lua")

APP = {
    cards = {}, selection = 1, screen = "library", action_selection = 1, type_selection = 1,
    notice = nil, data_error = nil, draft = nil, form_index = 1, pending_field = nil,
    qr = nil, confirm_delete = false, return_screen = nil,
}

function on_init()
    local cards, error = Storage.load()
    if cards then APP.cards = cards else APP.cards, APP.data_error, APP.notice = {}, error, error end
end

function on_draw()
    UI.draw(APP)
end

function on_button(button, pressed)
    if pressed then Input.button(APP, button) end
end

-- Do not define on_touch: LuaAppActivity already calls on_tap then on_touch(..., "tap").
function on_tap(x, y)
    Input.tap(APP, x, y)
end

function on_keyboard(value, cancelled)
    Input.keyboard_result(APP, value, cancelled)
end

function on_exit()
    if punri.prevent_sleep then punri.prevent_sleep(false) end
end
