-- Run in the firmware's LuaRunner fixture after loading QR Cards Share.
-- Checks complete user flows, rather than only drawing saved-card fixtures.
local native_write, native_keyboard = punri.write_file, punri.keyboard
local writes, requests = 0, {}
local texts, fills = {}, {}
local native_text, native_rect = punri.text, punri.rounded_rect
local slept
punri.prevent_sleep = function(value) slept = value end
punri.keyboard = function(title, initial, maximum)
    requests[#requests + 1] = {title = title, initial = initial, maximum = maximum}
    return true
end
punri.write_file = function(...)
    writes = writes + 1
    return native_write(...)
end
punri.text = function(x, y, value, font, style, align, ink)
    texts[#texts + 1] = {x = x, y = y, value = value, ink = ink}
    return native_text(x, y, value, font, style, align, ink)
end
punri.rounded_rect = function(x, y, w, h, radius, fill, stroke, ink)
    if fill then fills[#fills + 1] = {x = x, y = y, ink = ink} end
    return native_rect(x, y, w, h, radius, fill, stroke, ink)
end

local function draw()
    texts, fills = {}, {}
    on_draw()
    local width, height = punri.get_bounds()
    for i, item in ipairs(UI.targets) do
        assert(item.x >= 0 and item.y >= 0 and item.x + item.w <= width and item.y + item.h <= height, item.id)
        for j = i + 1, #UI.targets do
            local other = UI.targets[j]
            assert(item.x + item.w <= other.x or other.x + other.w <= item.x or
                item.y + item.h <= other.y or other.y + other.h <= item.y, item.id .. " overlaps " .. other.id)
        end
    end
end

local function target(id)
    draw()
    for _, item in ipairs(UI.targets) do if item.id == id then return item end end
    error("Missing visible control: " .. id .. " on " .. APP.screen)
end

local function tap(id)
    local item = target(id)
    on_tap(item.x + math.floor(item.w / 2), item.y + math.floor(item.h / 2))
end

local function sees(value)
    draw()
    for _, item in ipairs(texts) do if item.value:find(value, 1, true) then return true end end
    return false
end

local function enter(field, value)
    local previous = #requests
    tap("field:" .. field)
    assert(#requests == previous + 1 and APP.pending_field)
    tap("field:" .. field)
    assert(#requests == previous + 1, "A pending keyboard must not be opened twice")
    on_keyboard(value, false)
    assert(APP.pending_field == nil)
end

local values = {
    link = {"Example", "https://example.test"},
    contact = {"Doctor", "اسم عربي", "+20123", "", "", ""},
    wifi = {"Home", "PUNRI-Guest", "private-password"},
    emergency = {"Return", "Please call my family", "+20123"},
}

for _, shape in ipairs({{480, 800}, {800, 480}}) do
    punri.get_bounds = function() return shape[1], shape[2] end
    for _, kind in ipairs({"link", "contact", "wifi", "emergency"}) do
        APP.cards, APP.selection, APP.screen, APP.notice = {}, 0, "library", nil
        tap("new")
        assert(APP.screen == "type")
        tap("type:" .. kind)
        assert(APP.screen == "form")
        assert(sees("Add card"), "The form must visibly offer to save")
        assert(#fills > 0 and fills[1].ink == true, "Focused field must have a black background")
        tap("save")
        assert(APP.screen == "form" and sees("title is required"), "Validation must stay visible")
        for i, value in ipairs(values[kind]) do enter(i, value) end
        if kind == "wifi" then
            local request_count = #requests
            tap("next")
            tap("field:5")
            assert(APP.draft.fields.hidden == "true" and #requests == request_count)
        end
        local previous = writes
        tap("save")
        assert(APP.screen == "preview" and APP.draft == nil and #APP.cards == 1 and writes == previous + 1)
        local loaded = assert(Storage.load())
        assert(#loaded == 1 and loaded[1].fields.title == values[kind][1])
        tap("show_qr")
        if kind == "wifi" then
            assert(APP.screen == "wifi_privacy")
            tap("back")
            tap("show_qr")
            tap("privacy_continue")
        end
        assert(APP.screen == "qr" and slept)
        if kind == "wifi" then
            tap("delete_wifi")
            assert(APP.screen == "confirm_delete" and not slept)
            tap("keep")
            assert(APP.screen == "qr" and slept)
        end
        tap("done_qr")
        assert(APP.screen == "preview" and not slept)
        tap("edit")
        assert(APP.screen == "form" and APP.draft.fields.title == values[kind][1])
        tap("cancel")
        assert(APP.screen == "library" and #APP.cards == 1)
    end
end

-- The Save control is reachable with four-button devices as well as touch.
APP.cards, APP.selection, APP.screen = {}, 0, "library"
on_button("confirm", true)
APP.type_selection = 1
on_button("confirm", true)
on_button("confirm", true)
on_keyboard("Buttons", false)
on_button("confirm", true)
on_keyboard("Text", false)
assert(APP.form_index == 3 and sees("Add card"))
on_button("confirm", true)
assert(APP.screen == "preview" and APP.cards[1].fields.content == "Text")
tap("edit")
tap("field:1")
on_keyboard("", true)
assert(APP.draft.fields.title == "Buttons" and sees("Edit cancelled"))
enter(1, "Changed")
local before = assert(punri.read_file("cards_v1.dat"))
punri.write_file = function() return false end
tap("save")
assert(APP.screen == "form" and APP.draft.fields.title == "Changed" and sees("Save failed"))
assert(punri.read_file("cards_v1.dat") == before)
punri.write_file = native_write
tap("save")
assert(APP.screen == "preview" and APP.cards[1].fields.title == "Changed")
tap("back")
tap("actions")
for _ = 1, 6 do tap("next") end
tap("action:7")
tap("back")
tap("back")
assert(APP.screen == "library")

punri.keyboard = native_keyboard
punri.text, punri.rounded_rect = native_text, native_rect
