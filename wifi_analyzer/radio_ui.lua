-- Bezel-safe e-paper UI; identical copies in the two standalone analyzers.
local U = {w = 0, h = 0, margin = 0, top = 0, bottom = 0, body = 0, row_h = 0, per_page = 0}
local digit_masks = {63,6,91,79,102,109,125,7,127,111}

function U.layout()
    U.w, U.h = punri.get_bounds()
    local m = punri.get_metrics()
    U.margin = math.max(14, m.content_side_padding)
    U.top = m.top_padding + m.header_height + 10
    U.bottom = U.h - m.button_hints_height - 10
    U.body = U.top + 82
    U.row_h = math.max(62, punri.line_height("ui12") + punri.line_height("small") + 16)
    U.per_page = math.max(1, math.floor((U.bottom - U.body - 34) / U.row_h))
end

function U.clip(text, width, font)
    font = font or "ui12"
    if punri.text_width(text, font) <= width then return text end
    local at = #text + 1
    repeat
        at = at - 1
        while at > 1 and text:byte(at) >= 128 and text:byte(at) < 192 do at = at - 1 end
    until at <= 1 or punri.text_width(text:sub(1, at - 1) .. "...", font) <= width
    return text:sub(1, at - 1) .. "..."
end

function U.begin(title, simulated, bluetooth)
    U.layout()
    punri.clear()
    punri.header(title, simulated and "SIMULATED" or (bluetooth and "BLE" or "2.4 GHz"))
end

function U.toolbar(labels, focus)
    local width = (U.w - U.margin * 2) / 4
    for i, label in ipairs(labels) do
        local x = U.margin + math.floor((i - 1) * width)
        local chosen = i == focus
        punri.rounded_rect(x + 2, U.top, math.floor(width) - 4, 40, 5, chosen)
        punri.text(x + math.floor(width / 2), U.top + 8, U.clip(label, width - 12, "ui10"),
            "ui10", "regular", "center", not chosen)
    end
end

function U.toolbar_hit(x, y)
    if x < U.margin or x >= U.w - U.margin or y < U.top or y >= U.top + 40 then return nil end
    return math.floor((x - U.margin) / ((U.w - U.margin * 2) / 4)) + 1
end

function U.status(text)
    punri.text(U.margin, U.top + 49, U.clip(text, U.w - U.margin * 2, "small"), "small")
end

function U.footer(text)
    punri.text(U.margin, U.bottom - 22, U.clip(text, U.w - U.margin * 2, "small"), "small")
    punri.button_hints("Back", "Select", "Up", "Down")
end

function U.first(focus)
    local index = math.max(1, focus - 4)
    return math.floor((index - 1) / U.per_page) * U.per_page + 1
end

function U.networks(rows, focus, bluetooth, target)
    local first, offset = U.first(focus), target and 1 or 0
    for i = first, math.min(#rows + offset, first + U.per_page - 1) do
        local row = target and i == 1 and target or rows[i - offset]
        local y, chosen = U.body + (i - first) * U.row_h, focus == i + 4
        punri.rounded_rect(U.margin, y + 2, U.w - U.margin * 2, U.row_h - 4, 5, chosen)
        local name = row.name ~= "" and row.name or (bluetooth and "(unnamed device)" or "(hidden SSID)")
        if row == target then name = "Resume: " .. name end
        punri.text(U.margin + 10, y + 8, U.clip(name, U.w - U.margin * 2 - 112),
            "ui12", "regular", "left", not chosen)
        punri.text(U.w - U.margin - 10, y + 8, row == target and "Saved" or (row.rssi .. " dBm"),
            "small", "bold", "right", not chosen)
        local detail = row.address .. (row == target and "" or (bluetooth and ("  Type " .. tostring(row.address_type)) or
            ("  Ch " .. tostring(row.channel))))
        punri.text(U.margin + 10, y + 12 + punri.line_height("ui12"),
            U.clip(detail, U.w - U.margin * 2 - 20, "small"), "small", "regular", "left", not chosen)
    end
    if #rows == 0 and not target then punri.centered_text(U.body + 32,
        bluetooth and "Press Scan to find BLE devices" or "Press Scan to find networks", "ui12") end
end

function U.network_hit(x, y, focus, count)
    if x < U.margin or x >= U.w - U.margin or y < U.body then return nil end
    local index = U.first(focus) + math.floor((y - U.body) / U.row_h)
    if index <= count and index < U.first(focus) + U.per_page then return index end
end

function U.strength(rssi)
    return math.max(0, math.min(100, math.floor((rssi + 100) * 100 / 70)))
end

function U.quality(rssi)
    if rssi >= -50 then return "Excellent"
    elseif rssi >= -60 then return "Good"
    elseif rssi >= -70 then return "Fair"
    elseif rssi >= -80 then return "Weak" end
    return "Very weak"
end

function U.meter(rssi, y, height)
    local value = rssi and tostring(rssi) or "--"
    local width, gap = math.floor(height / 2), math.max(4, math.floor(height / 10))
    local x = math.floor((U.w - #value * (width + gap) + gap) / 2)
    local thick = math.max(3, math.floor(height / 12))
    local half = math.floor(height / 2)
    for i = 1, #value do
        local ch = value:sub(i, i)
        if ch == "-" then
            punri.rect(x + thick, y + half - math.floor(thick / 2), width - thick * 2, thick, true)
        else
            local mask = digit_masks[tonumber(ch) + 1]
            if mask & 1 ~= 0 then punri.rect(x + thick, y, width - thick * 2, thick, true) end
            if mask & 2 ~= 0 then punri.rect(x + width - thick, y + thick, thick, half - thick, true) end
            if mask & 4 ~= 0 then punri.rect(x + width - thick, y + half, thick, half - thick, true) end
            if mask & 8 ~= 0 then punri.rect(x + thick, y + height - thick, width - thick * 2, thick, true) end
            if mask & 16 ~= 0 then punri.rect(x, y + half, thick, half - thick, true) end
            if mask & 32 ~= 0 then punri.rect(x, y + thick, thick, half - thick, true) end
            if mask & 64 ~= 0 then punri.rect(x + thick, y + half - math.floor(thick / 2), width - thick * 2, thick, true) end
        end
        x = x + width + gap
    end
end

return U
