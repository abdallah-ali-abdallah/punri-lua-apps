-- Geometry is shared with hit testing. Fixed records are reused on each draw.
local M = {}
local l = {pad = {}, clicks = {{}, {}}, speeds = {{}, {}, {}}, primary = {}, settings = {}, back = {}, forget = {}, exit = {}}
local function box(b, x, y, w, h, id, label)
    b.x, b.y, b.w, b.h, b.id, b.label = x, y, w, h, id, label
end
function M.compute()
    local w, h = punri.get_bounds()
    if w == l.w and h == l.h then return l end
    local m = punri.get_metrics()
    l.w, l.h, l.side = w, h, math.max(16, m.content_side_padding or 12)
    l.small, l.label = punri.line_height("small"), punri.line_height("ui12")
    l.top = (m.top_padding or 4) + 8
    l.header = l.top + l.label + l.small + 22
    l.bottom = h - (m.button_hints_height or 40) - 10
    local side, gap, content_w = l.side, 10, w - 2 * l.side
    local button_h, speed_h, click_h = math.max(48, l.label + 18), math.max(40, l.small + 16), math.max(60, l.label + 26)
    local top = l.header + l.small + 24
    if w <= h then
        box(l.primary, side, l.bottom - button_h, content_w, button_h, "primary", "Pair / Connect")
        l.speed_y = l.primary.y - gap - speed_h
        l.notice_y, l.notice_x, l.notice_w = l.speed_y - l.small * 2 - 16, side, content_w
        local d = math.min(content_w - 12, l.notice_y - top - click_h - 32)
        box(l.pad, math.floor((w - d) / 2), top, d, d)
    else
        local panel_w = math.floor(content_w * 0.40)
        local panel_x = w - side - panel_w
        box(l.primary, panel_x, l.bottom - button_h, panel_w, button_h, "primary", "Pair / Connect")
        l.speed_y = l.primary.y - gap - speed_h
        l.notice_x, l.notice_y, l.notice_w = panel_x, top + l.small + 22, panel_w
        local d = math.min(panel_x - side - 28, l.bottom - top - click_h - gap)
        box(l.pad, side + math.floor((panel_x - side - 28 - d) / 2), top, d, d)
    end
    local p = l.pad
    local cw = math.floor((p.w - gap) / 2)
    box(l.clicks[1], p.x, p.y + p.h + gap, cw, click_h, "left", "Left click")
    box(l.clicks[2], p.x + cw + gap, p.y + p.h + gap, p.w - cw - gap, click_h, "right", "Right click")
    local sw = math.floor((l.primary.w - gap * 2) / 3)
    for i, id in ipairs({"slow", "normal", "fast"}) do
        box(l.speeds[i], l.primary.x + (sw + gap) * (i - 1), l.speed_y, sw, speed_h, id, ({"Slow", "Normal", "Fast"})[i])
    end
    box(l.settings, w - side - 90, l.header - l.small - 5, 90, l.small + 10, "settings", "Settings")
    local mw = math.min(content_w, 460)
    box(l.back, math.floor((w - mw) / 2), l.bottom - button_h, mw, button_h, "close_settings", "Back to mouse")
    box(l.forget, l.back.x, top + l.label + l.small * 3 + 32, mw, button_h, "forget", "Forget current host")
    box(l.exit, 0, h - (m.button_hints_height or 40), w, m.button_hints_height or 40, "exit", "Exit")
    return l
end
local function inside(x, y, b) return punri.in_rect(x, y, b.x, b.y, b.w, b.h) end
function M.in_pad(x, y) return inside(x, y, M.compute().pad) end
local function wrapped(x, y, width, text, lines)
    for i, line in ipairs(punri.wrapped_text(text, width, "small", "regular", lines)) do
        punri.text(x, y + (i - 1) * l.small, line, "small", "regular", "left", true)
    end
end
local function button(b, filled, font)
    punri.rounded_rect(b.x, b.y, b.w, b.h, 12, filled, 2, true)
    local f = font or "ui12"
    punri.text(b.x + math.floor(b.w / 2), b.y + math.floor((b.h - punri.line_height(f)) / 2), b.label, f, "bold", "center", not filled)
end
local function mouse_icon(cx, y, size, ink)
    local half = math.floor(size / 2)
    punri.rounded_rect(cx - half, y, size, math.floor(size * 1.4), half, false, 2, ink)
    punri.line(cx, y, cx, y + half, 2, ink)
    punri.line(cx - half, y + half, cx + half, y + half, 2, ink)
end
function M.draw(c, settings)
    M.compute()
    punri.clear()
    punri.text(l.side, l.top, "Bluetooth Mouse", "ui12", "bold", "left", true)
    local status = not c.supported and "Unavailable" or (c.ready and "Connected" or (c.connected and "Securing..." or
        ((c.state == "advertising" or c.state == "connecting") and "Pairing..." or "Not connected")))
    punri.text(l.side, l.top + l.label + 6, status, "small", "bold", "left", true)
    punri.text(l.w - l.side, l.top, c.simulated and "SIMULATION" or "BLE HID", "small", "bold", "right", true)
    punri.line(l.side, l.header + 8, l.w - l.side, l.header + 8, 1, true)
    if not c.supported then
        wrapped(l.side, l.header + 40, l.w - 2 * l.side, c.notice, 4)
        punri.button_hints("Exit", "", "", "")
        return
    end
    if settings then
        local b = l.forget
        punri.text(b.x, l.pad.y, "Pairing settings", "ui12", "bold", "left", true)
        wrapped(b.x, l.pad.y + l.label + 12, b.w,
            "Forget removes only the bonded host connected during this open session.", 3)
        button(b, false)
        wrapped(b.x, b.y + b.h + 18, b.w, c.notice, 3)
        button(l.back, true)
        punri.button_hints("Mouse", "", "", "")
        return
    end
    punri.text(l.settings.x + l.settings.w, l.settings.y, "Settings", "small", "bold", "right", true)
    local p = l.pad
    punri.text(p.x, p.y - l.small - 4, "TOUCHPAD", "small", "bold", "left", true)
    punri.rounded_rect(p.x, p.y, p.w, p.h, 18, false, 2, true)
    -- Sparse dotted lines approximate a light grid on a one-bit display.
    for x = p.x + 24, p.x + p.w - 18, 24 do
        for y = p.y + 12, p.y + p.h - 12, 8 do punri.line(x, y, x, y + 1, 1, true) end
    end
    for y = p.y + 24, p.y + p.h - 18, 24 do
        for x = p.x + 12, p.x + p.w - 12, 8 do punri.line(x, y, x + 1, y, 1, true) end
    end
    local cx, cy = p.x + math.floor(p.w / 2), p.y + math.floor(p.h / 2)
    punri.rounded_rect(cx - 84, cy - 58, 168, 116, 16, true, 1, false)
    mouse_icon(cx, cy - 46, 34, true)
    punri.text(cx, cy + 14, "Slide to move", "small", "bold", "center", true)
    button(l.clicks[1], true, l.clicks[1].w < 160 and "small" or "ui12")
    button(l.clicks[2], false, l.clicks[2].w < 160 and "small" or "ui12")
    wrapped(l.notice_x, l.notice_y, l.notice_w, c.notice, 2)
    for i, b in ipairs(l.speeds) do button(b, i == c.speed, "small") end
    l.primary.label = (c.connected or c.state == "advertising" or c.state == "connecting") and "Disconnect" or "Pair / Connect"
    button(l.primary, false)
    punri.button_hints("Exit", c.connected and "Disconnect" or "Pair", "Left", "Right")
end
function M.hit(x, y, c, settings)
    M.compute()
    if not c.supported then return nil end
    if settings then
        if inside(x, y, l.forget) then return "forget" end
        if inside(x, y, l.back) then return "close_settings" end
        return nil
    end
    if inside(x, y, l.settings) then return "settings" end
    if inside(x, y, l.primary) then
        return (c.connected or c.state == "advertising" or c.state == "connecting") and "disconnect" or "pair"
    end
    for _, b in ipairs(l.clicks) do if inside(x, y, b) then return b.id end end
    for _, b in ipairs(l.speeds) do if inside(x, y, b) then return b.id end end
    return nil
end
return M
