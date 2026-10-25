-- Self-contained text input shared with Notepad; keep the packaged copies identical.
-- The Lua sandbox has no utf8 library: move/delete at UTF-8 byte boundaries.
local E = {}
local lower = {"qwertyuiop", "asdfghjkl", "zxcvbnm.,?"}
local upper = {"QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM.,?"}
local symbols = {"1234567890", "!@#$%&*()-", "+=/:;_'\"[]"}
local actions = {"Space", "Delete", "Aa", "123", "Enter", "Save"}
local text, title, limit, multiline = "", "", 0, false
local row, col, page, message = 1, 1, 1, ""
local w, h, margin, top, bottom, key_y, key_h = 0, 0, 0, 0, 0, 0, 0

local function next_byte(s, at)
    at = at + 1
    while at <= #s and s:byte(at) >= 128 and s:byte(at) < 192 do at = at + 1 end
    return at
end

local function previous_byte(s, at)
    at = at - 1
    while at > 1 and s:byte(at) >= 128 and s:byte(at) < 192 do at = at - 1 end
    return at
end

function E.valid_text(s)
    local at = 1
    while at <= #s do
        local b = s:byte(at)
        local size = b < 128 and 1 or (b >= 194 and b <= 223 and 2 or
            (b >= 224 and b <= 239 and 3 or (b >= 240 and b <= 244 and 4 or 0)))
        if size == 0 or at + size - 1 > #s or (b < 32 and b ~= 9 and b ~= 10) or b == 127 then return false end
        for i = 1, size - 1 do
            local c = s:byte(at + i)
            if c < 128 or c > 191 then return false end
        end
        local second = s:byte(at + 1) or 0
        if (b == 224 and second < 160) or (b == 237 and second > 159) or
            (b == 240 and second < 144) or (b == 244 and second > 143) then return false end
        at = at + size
    end
    return true
end

function E.clip(s, width, font)
    if punri.text_width(s, font or "ui12") <= width then return s end
    local at = #s + 1
    repeat at = previous_byte(s, at) until at <= 1 or
        punri.text_width(s:sub(1, at - 1) .. "...", font or "ui12") <= width
    return s:sub(1, at - 1) .. "..."
end

-- Keep only the current page, not an array of every wrapped page of a note.
-- Returned offset is the first byte on the next page; explicit newlines survive.
function E.lines(s, width, count, offset, font)
    local result, at = {}, offset or 1
    font = font or "ui12"
    while at <= #s and #result < count do
        local start, finish, space = at, at, nil
        while at <= #s and s:sub(at, at) ~= "\n" do
            local following = next_byte(s, at)
            if punri.text_width(s:sub(start, following - 1), font) > width and finish > start then break end
            finish = following
            if s:sub(at, at) == " " then space = at end
            at = following
        end
        if at <= #s and s:sub(at, at) == "\n" then
            result[#result + 1] = s:sub(start, at - 1)
            at = at + 1
        elseif at <= #s and space and space > start then
            result[#result + 1] = s:sub(start, space - 1)
            at = space + 1
        else
            result[#result + 1] = s:sub(start, finish - 1)
            at = finish
        end
    end
    return result, at
end

local function geometry()
    w, h = punri.get_bounds()
    local m = punri.get_metrics()
    margin = math.max(12, m.content_side_padding)
    top = m.top_padding + m.header_height + 12
    if punri.has_touch() then top = top + 44 end
    bottom = h - m.button_hints_height - 12
    key_h = math.min(56, math.floor((bottom - top - 78) / 4))
    key_y = bottom - key_h * 4
end

local function letters()
    return page == 3 and symbols or (page == 2 and upper or lower)
end

local function columns(r)
    return r == 4 and #actions or #letters()[r]
end

local function insert(value)
    if #text + #value > limit then
        message = "Text limit reached"
    else
        text, message = text .. value, ""
    end
end

local function activate()
    if row < 4 then
        insert(letters()[row]:sub(col, col))
    elseif col == 1 then
        insert(" ")
    elseif col == 2 then
        if #text > 0 then text = text:sub(1, previous_byte(text, #text + 1) - 1) end
        message = ""
    elseif col == 3 then
        page = page == 2 and 1 or 2
    elseif col == 4 then
        page = page == 3 and 1 or 3
    elseif col == 5 then
        if multiline then insert("\n") else message = "Single-line text only" end
    elseif col == 6 then
        return "save", text
    end
end

function E.open(label, initial, max_bytes, allow_newlines)
    title, text, limit, multiline = label, initial or "", max_bytes, allow_newlines
    row, col, page, message = 1, 1, 1, ""
end

function E.value()
    return text
end

function E.draw()
    geometry()
    punri.clear()
    punri.header(title, tostring(#text) .. "/" .. tostring(limit))
    if punri.has_touch() then
        punri.rounded_rect(margin, top - 44, 88, 34, 4, false)
        punri.text(margin + 44, top - 39, "Cancel", "ui10", "regular", "center")
    end
    local line_h = punri.line_height("ui12") + 2
    local available = math.max(1, math.floor((key_y - top - 34) / line_h))
    -- Only preview the bounded suffix while typing. The complete note is kept.
    local start = math.max(1, #text - available * 20)
    while start <= #text and text:byte(start) >= 128 and text:byte(start) < 192 do start = start + 1 end
    local preview = E.lines(text:sub(start), w - margin * 2 - 16, available)
    punri.rect(margin, top, w - margin * 2, key_y - top - 28, false)
    if #preview == 0 then preview[1] = "Type using the keys below" end
    for i, line in ipairs(preview) do
        punri.text(margin + 8, top + 6 + (i - 1) * line_h, line, "ui12")
    end
    punri.text(margin, key_y - 24, message ~= "" and message or
        (punri.has_touch() and "Tap keys. Save keeps changes." or "Side buttons: row. Back: cancel."), "small")
    for r = 1, 4 do
        local n = columns(r)
        local kw = (w - margin * 2) / n
        for c = 1, n do
            local x = margin + math.floor((c - 1) * kw)
            local y = key_y + (r - 1) * key_h
            local selected = row == r and col == c
            local label = r == 4 and actions[c] or letters()[r]:sub(c, c)
            punri.rounded_rect(x + 2, y + 2, math.floor(kw) - 4, key_h - 4, 4, selected)
            punri.text(x + math.floor(kw / 2), y + math.floor((key_h - punri.line_height("ui10")) / 2),
                label, "ui10", "regular", "center", not selected)
        end
    end
    punri.button_hints("Cancel", "Type", "Left", "Right")
end

function E.button(btn)
    if btn == "back" then return "cancel" end
    if btn == "confirm" then return activate() end
    if btn == "left" then col = (col - 2) % columns(row) + 1
    elseif btn == "right" then col = col % columns(row) + 1
    elseif btn == "up" or btn == "page_back" then
        row = (row - 2) % 4 + 1
        col = math.min(col, columns(row))
    elseif btn == "down" or btn == "page_forward" then
        row = row % 4 + 1
        col = math.min(col, columns(row))
    end
end

function E.tap(x, y)
    geometry()
    if punri.has_touch() and punri.in_rect(x, y, margin, top - 44, 88, 34) then return "cancel" end
    if x < margin or x >= w - margin or y < key_y or y >= key_y + key_h * 4 then return end
    row = math.floor((y - key_y) / key_h) + 1
    col = math.floor((x - margin) / ((w - margin * 2) / columns(row))) + 1
    return activate()
end

return E
