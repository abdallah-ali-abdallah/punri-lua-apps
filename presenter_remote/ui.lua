-- One-bit presentation clicker. Drawing and hit testing share the live geometry.
-- The bounded control/body records are allocated once and reused on every draw.
local M = {settings_open = false, settings_focus = 1, feedback = punri.dofile("press_feedback.lua")}
local layout = {controls = {{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}}, body = {}}

local function control(index, id, label, x, y, w, h, shape)
    local c = layout.controls[index]
    c.id, c.label, c.x, c.y, c.w, c.h, c.shape = id, label, x, y, w, h, shape
end

local function wrapped(x, y, width, text, max_lines)
    for i, value in ipairs(punri.wrapped_text(text, width, "small", "regular", max_lines)) do
        punri.text(x, y + (i - 1) * layout.small_h, value, "small", "regular", "left", true)
    end
end

function M.compute()
    local w, h = punri.get_bounds()
    local metrics = punri.get_metrics and punri.get_metrics() or {}
    local l, b = layout, layout.body
    l.w, l.h, l.side = w, h, metrics.content_side_padding or 12
    l.small_h, l.label_h = punri.line_height("small"), punri.line_height("ui12")
    l.header_y = (metrics.top_padding or 4) + 2
    l.header_bottom = l.header_y + l.label_h + l.small_h + 16
    l.bottom = h - math.max(40, metrics.button_hints_height or 0) - 8
    l.landscape = w > h
    local side, gap = l.side, 10
    local content_w = w - side * 2
    b.y = l.header_bottom + 10
    local action_h, row_h = math.max(44, l.label_h + 14), math.max(44, l.label_h + 12)
    local pad, head_h = 16, punri.line_height("ui10") + 8
    if not l.landscape then
        control(1, "primary", "Pair / Advertise", side, l.bottom - action_h, content_w, action_h)
        local row_y = l.controls[1].y - gap - row_h
        local mode_w = math.floor((content_w - gap) * 0.56)
        control(2, "mode", "Arrow keys", side, row_y, mode_w, row_h)
        control(3, "settings", "Settings", side + mode_w + gap, row_y, content_w - mode_w - gap, row_h)
        l.status_x, l.status_w, l.status_y = side, content_w, row_y - l.small_h * 2 - 12
        b.w = math.min(300, math.floor(content_w * 0.70))
        b.x, b.h = math.floor((w - b.w) / 2), l.status_y - gap - b.y
        local minor_h, key_h = math.max(62, l.small_h + 46), math.max(44, l.label_h + 16)
        local d = math.min(b.w - pad * 2,
            math.floor((b.h - pad * 2 - head_h - minor_h - key_h - gap * 3 - l.label_h * 2) / 2))
        local x, y = math.floor((w - d) / 2), b.y + pad + head_h
        control(7, "right", "Next", x, y, d, d + l.label_h, "circle")
        y = y + d + l.label_h + gap
        control(5, "left", "Back", x, y, d, d + l.label_h, "circle")
        y = y + d + l.label_h + gap
        local minor_w = math.min(minor_h - l.small_h, math.floor((b.w - pad * 2 - gap) / 2))
        local mid = math.floor(w / 2)
        control(4, "up", "Up", mid - gap - minor_w, y, minor_w, minor_h, "circle")
        control(6, "down", "Down", mid + gap, y, minor_w, minor_h, "circle")
        local key_pad = 32 -- Keep the lower buttons inside the capsule's curved ends.
        local key_w = math.floor((b.w - key_pad * 2 - gap) / 2)
        y = y + minor_h + gap
        control(8, "enter", "Enter", b.x + key_pad, y, key_w, key_h)
        control(9, "space", "Space", b.x + b.w - key_pad - key_w, y, key_w, key_h)
    else
        b.x, b.w, b.h = side, math.floor(content_w * 0.60), l.bottom - b.y
        local panel_x = b.x + b.w + 20
        local panel_w = w - side - panel_x
        local row_y = l.bottom - action_h - gap - row_h
        control(1, "primary", "Pair / Advertise", panel_x, l.bottom - action_h, panel_w, action_h)
        control(2, "mode", "Arrow keys", panel_x, row_y - row_h - gap, panel_w, row_h)
        control(3, "settings", "Settings", panel_x, row_y, panel_w, row_h)
        l.status_x, l.status_y, l.status_w = panel_x, b.y + 12, panel_w
        local minor_h = math.max(60, l.small_h + 44)
        local d = math.min(math.floor((b.w - pad * 2 - 24) / 2),
            b.h - pad * 2 - head_h - minor_h - gap * 2 - l.label_h)
        local center, y = b.x + math.floor(b.w / 2), b.y + pad + head_h
        control(5, "left", "Back", center - 12 - d, y, d, d + l.label_h, "circle")
        control(7, "right", "Next", center + 12, y, d, d + l.label_h, "circle")
        y = b.y + b.h - pad - minor_h
        local key_w = math.floor((b.w - pad * 2 - gap * 3) / 4)
        control(4, "up", "Up", b.x + pad, y, key_w, minor_h, "circle")
        control(6, "down", "Down", b.x + pad + key_w + gap, y, key_w, minor_h, "circle")
        control(8, "enter", "Enter", b.x + pad + (key_w + gap) * 2, y, key_w, minor_h)
        control(9, "space", "Space", b.x + pad + (key_w + gap) * 3, y, key_w, minor_h)
    end
    local settings_w = math.min(content_w, 480)
    local settings_x = math.floor((w - settings_w) / 2)
    control(10, "close_settings", "Back to remote", settings_x, l.bottom - action_h, settings_w, action_h)
    control(11, "forget", "Forget pairing", settings_x, b.y + l.label_h + l.small_h * 3 + 34, settings_w, action_h)
    return l
end

local function arrow(cx, cy, size, direction, ink)
    local tip, shaft = math.floor(size / 2), math.max(4, math.floor(size / 5))
    if direction == "left" or direction == "right" then
        local sign = direction == "right" and 1 or -1
        punri.rect(cx - tip, cy - math.floor(shaft / 2), size, shaft, true, ink)
        punri.triangle(cx + sign * tip, cy, cx, cy - tip, cx, cy + tip, true, ink)
    else
        local sign = direction == "down" and 1 or -1
        punri.rect(cx - math.floor(shaft / 2), cy - tip, shaft, size, true, ink)
        punri.triangle(cx, cy + sign * tip, cx - tip, cy, cx + tip, cy, true, ink)
    end
end

local function bluetooth(x, y)
    punri.line(x + 6, y, x + 6, y + 24, 2, true)
    punri.line(x + 6, y, x + 14, y + 7, 2, true)
    punri.line(x + 14, y + 7, x, y + 18, 2, true)
    punri.line(x, y + 6, x + 14, y + 17, 2, true)
    punri.line(x + 14, y + 17, x + 6, y + 24, 2, true)
end

local function state_label(c)
    if not c.supported then return "Unavailable" end
    if c.connected then return c.subscribed and "Connected" or "Securing..." end
    if c.state == "advertising" or c.state == "connecting" then return "Pairing..." end
    if c.state == "disconnecting" then return "Disconnecting" end
    return "Not connected"
end

local function button(c, selected, enabled)
    punri.rounded_rect(c.x, c.y, c.w, c.h, math.min(18, math.floor(c.h / 2)), selected, 2, true)
    M.feedback.target(c.id, c.x, c.y, c.w, c.h, enabled, "rounded", math.min(18, c.h // 2), selected)
    local ink = M.feedback.paint(c.id)
    if ink == nil then ink = not selected end
    punri.text(c.x + math.floor(c.w / 2), c.y + math.floor((c.h - layout.label_h) / 2),
        c.label, "ui12", "bold", "center", ink)
end

local function key(c, controller)
    local prominent = c.id == "right" or c.id == "left"
    if c.shape == "circle" then
        local d = math.min(c.w, c.h - (prominent and layout.label_h or layout.small_h))
        local r = math.floor(d / 2)
        local cx, cy = c.x + math.floor(c.w / 2), c.y + r
        local filled = c.id == "right"
        punri.circle(cx, cy, r, filled, 2, true)
        M.feedback.target(c.id, cx - r, cy - r, d, d, controller.connected and controller.subscribed, "circle", r, filled)
        local ink = M.feedback.paint(c.id)
        if ink == nil then ink = not filled end
        arrow(cx, cy, math.floor(d * 0.48), c.id, ink)
        if controller.pending_key == c.id then punri.circle(cx, cy, r - 5, false, 2, not filled) end
        punri.text(cx, c.y + d, c.label, prominent and "ui12" or "small", "bold", "center", true)
    else
        button(c, false, controller.connected and controller.subscribed and controller.enter_space_supported)
    end
end

function M.visible(c, controller)
    if not controller.supported then return false end
    if M.settings_open then return c.id == "forget" or c.id == "close_settings" end
    if c.id == "forget" or c.id == "close_settings" then return false end
    return controller.mode ~= "pages" or (c.id ~= "up" and c.id ~= "down")
end

function M.draw(controller)
    local l = M.compute()
    M.feedback.begin(M.settings_open and "settings" or controller.mode)
    punri.clear()
    punri.text(l.side, l.header_y, "Presenter Remote", "ui12", "bold", "left", true)
    local label = state_label(controller)
    local label_w = punri.text_width(label, "small", "bold")
    bluetooth(l.w - l.side - label_w - 24, l.header_y)
    punri.text(l.w - l.side, l.header_y + 4, label, "small", "bold", "right", true)
    punri.text(l.side, l.header_y + l.label_h + 4,
        controller.simulated and "SIMULATION / Bluetooth HID" or "Bluetooth HID", "small", "regular", "left", true)
    punri.line(l.side, l.header_bottom, l.w - l.side, l.header_bottom, 1, true)
    if not controller.supported then
        wrapped(l.side, l.body.y + 12, l.w - l.side * 2,
            "Presenter Remote requires X4 Pro firmware with Bluetooth HID keyboard support.", 4)
        M.feedback.footer({"Exit", "", "", ""}, {"exit"})
        return
    end
    if M.settings_open then
        local f, back = l.controls[11], l.controls[10]
        punri.text(f.x, l.body.y, "Settings", "ui12", "bold", "left", true)
        wrapped(f.x, l.body.y + l.label_h + 12, f.w,
            "Forget pairing removes only the host connected during this open app session.", 3)
        button(f, M.settings_focus == 1)
        wrapped(f.x, f.y + f.h + 12, f.w, controller.notice, 3)
        button(back, M.settings_focus == 2)
        M.feedback.footer({"Remote", "", "", ""}, {"close_settings"})
        return
    end
    local b = l.body
    punri.rounded_rect(b.x, b.y, b.w, b.h, math.min(70, math.floor(b.w / 3)), false, 3, true)
    punri.text(b.x + math.floor(b.w / 2), b.y + 16, "PUNRI Remote", "ui10", "bold", "center", true)
    local primary = l.controls[1]
    primary.label = controller.connected and "Disconnect" or
        ((controller.state == "advertising" or controller.state == "connecting") and "Pairing..." or "Pair / Advertise")
    l.controls[2].label = controller.mode == "pages" and "Page turns" or "Arrow keys"
    for i = 4, 9 do
        if M.visible(l.controls[i], controller) then key(l.controls[i], controller) end
    end
    wrapped(l.status_x, l.status_y, l.status_w, controller.notice, 2)
    button(l.controls[2], true)
    button(l.controls[3], false)
    button(primary, false)
    M.feedback.footer({"Exit", "", "", ""}, {"exit"})
end

function M.hit(x, y, controller)
    for _, c in ipairs(M.compute().controls) do
        if M.visible(c, controller) and punri.in_rect(x, y, c.x, c.y, c.w, c.h) then
            if c.id == "primary" then return controller.connected and "disconnect" or "pair" end
            return c.id
        end
    end
    return nil
end

return M
