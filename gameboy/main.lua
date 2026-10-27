-- Offline library; the native engine owns ROM validation, memory and refresh limits.
local Feedback = punri.dofile("press_feedback.lua")
local items, selected, directory, cursor, next_cursor = {}, 1, "", 0, nil
local message, available = "", false
local top, row, width, height = 130, 48, 0, 0
local labels, ids = {"Back", "Open", "Up", "Down"}, {"back", "open", "up", "down"}
local function load()
    Feedback.clear()
    local err
    items, next_cursor, err = punri.gameboy.list(directory, cursor, 8)
    selected = 1
    message = err and "Create /roms/gb/ and add .gb files." or ""
    if #items == 0 and message == "" then message = "No Game Boy ROMs in this folder." end
    punri.request_update()
end
local function open()
    local item = items[selected]
    if not item or not available then return end
    local path = directory == "" and item.name or directory .. "/" .. item.name
    if item.directory then directory, cursor = path, 0; load()
    elseif not punri.gameboy.launch(path) then
        message = "Launch unavailable. Stop active radios first."
        punri.request_update()
    end
end
local function back()
    if directory ~= "" then directory = directory:match("^(.*)/[^/]+$") or ""; cursor = 0; load()
    elseif cursor > 0 then cursor = 0; load()
    else punri.exit() end
end
local function next_page()
    if next_cursor then cursor = next_cursor; load() end
end
function on_init()
    available = punri.has_feature("gameboy_dmg")
    punri.set_orientation("portrait")
    width, height = punri.get_bounds()
    if available then load() else message = "This firmware does not support Game Boy." end
end
function on_draw()
    Feedback.begin(directory .. ":" .. tostring(cursor))
    punri.clear()
    punri.header("Game Boy", "/roms/gb/" .. directory)
    Feedback.button("header:back", 16, 76, 112, 42, "Back", "ui12")
    for i, item in ipairs(items) do
        local y, id = top + (i - 1) * row, "rom:" .. tostring(i)
        Feedback.target(id, 16, y, width - 32, row - 4, true, "rect")
        if i == selected then punri.rect(16, y, width - 32, row - 4, false) end
        local ink = Feedback.paint(id)
        if ink == nil then ink = true end
        local name = (item.directory and "[+] " or "") .. item.name
        punri.text(28, y + 10, name, "ui12", "regular", "left", ink)
    end
    if message ~= "" then
        local lines = punri.wrapped_text(message, width - 48, "small", "regular", 3)
        for i, line in ipairs(lines) do punri.text(24, height - 170 + (i - 1) * 24, line, "small") end
    end
    if next_cursor then Feedback.button("next", width - 156, height - 100, 140, 48, "Next page", "ui12") end
    Feedback.footer(labels, ids)
    Feedback.finish()
end
function on_update() Feedback.update() end
function on_button(button, pressed)
    if not pressed or Feedback.busy() then return end
    if button == "back" then Feedback.defer("back", back)
    elseif button == "confirm" and available then Feedback.defer("open", open)
    elseif button == "up" or button == "page_back" or button == "left" then
        Feedback.press("up"); selected = math.max(1, selected - 1); punri.request_update()
    elseif button == "down" or button == "page_forward" or button == "right" then
        if selected == #items and next_cursor then Feedback.defer("down", next_page)
        else Feedback.press("down"); selected = math.min(#items, selected + 1); punri.request_update() end
    end
end
-- The firmware also emits compatibility on_touch for this physical tap.
function on_tap(x, y)
    if Feedback.busy() then return end
    local id = Feedback.hit(x, y)
    if id == "header:back" or id == "back" then Feedback.defer(id, back)
    elseif id == "open" then Feedback.defer(id, open)
    elseif id == "next" then Feedback.defer(id, next_page)
    elseif id == "up" then on_button("up", true)
    elseif id == "down" then on_button("down", true)
    elseif id and id:match("^rom:") then
        selected = tonumber(id:match("%d+"))
        Feedback.defer(id, open)
    end
end
function on_gameboy_result(status, error)
    load()
    message = status == "closed" and "Game closed." or (status .. " (" .. tostring(error) .. ")")
    punri.request_update()
end
function on_exit() Feedback.clear() end
