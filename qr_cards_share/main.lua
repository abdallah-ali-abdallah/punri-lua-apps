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
    APP.selection = #APP.cards == 0 and 0 or 1
end

function on_draw()
    UI.draw(APP)
end

function on_update() UI.feedback.update() end

function on_button(button, pressed)
    if not pressed or UI.feedback.busy() then return end
    local id
    if button == "back" then id = APP.screen == "form" and "cancel" or APP.screen == "confirm_delete" and "keep" or "back"
    elseif button == "confirm" then
        id = UI.feedback.focus or (APP.screen == "preview" and "show_qr")
    elseif button == "left" or button == "page_back" then id = "previous"
    elseif button == "right" or button == "page_forward" then id = "next" end
    if button == "back" or button == "confirm" then
        if UI.feedback.defer(id, function() Input.button(APP, button) end) then return end
    else UI.feedback.press(id) end
    Input.button(APP, button)
end

-- Do not define on_touch: LuaAppActivity already calls on_tap then on_touch(..., "tap").
function on_tap(x, y)
    if UI.feedback.busy() then return end
    local id = UI.feedback.hit(x, y)
    if not id then return end
    if id == "previous" or id == "next" or id == "action:5" or id == "action:6" then
        UI.feedback.press(id)
        Input.tap(APP, x, y)
    else UI.feedback.defer(id, function() Input.tap(APP, x, y) end) end
end

function on_keyboard(value, cancelled)
    Input.keyboard_result(APP, value, cancelled)
end

function on_exit()
    if punri.prevent_sleep then punri.prevent_sleep(false) end
end
