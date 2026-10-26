-- Layout is recomputed from the live renderer dimensions, so portrait and
-- landscape simulator/device profiles share the same bounded controls.
local M = {}
-- Two extra fixed control records are allocated once with the module and reused.
local layout = {controls = {{}, {}, {}, {}, {}, {}, {}, {}, {}}}

local function set_control(index, id, label, x, y, width, height)
    local control = layout.controls[index]
    control.id, control.label = id, label
    control.x, control.y, control.w, control.h = x, y, width, height
    control.prominent = id == "enter" or id == "space"
end

local function draw_wrapped(x, y, width, text, font, style, max_lines)
    local lines = punri.wrapped_text(text, width, font, style, max_lines)
    local line_h = punri.line_height(font)
    for index, line in ipairs(lines) do
        punri.text(x, y + (index - 1) * line_h, line, font, style, "left", true)
    end
    return #lines * line_h
end

function M.compute()
    local width, height = punri.get_bounds()
    local metrics = punri.get_metrics and punri.get_metrics() or {}
    local side = metrics.content_side_padding or 12
    local top = (metrics.top_padding or 0) + (metrics.header_height or 48) + 8
    local bottom = height - (metrics.button_hints_height or 40) - 8
    local content_w = width - side * 2
    local small_line_h = punri.line_height("small")
    -- Six rows share the usable height: three actions, two arrow rows and one
    -- large Enter/Space row. Keep two status lines and the state line clear.
    local reserved_text_h = small_line_h * 3 + 14
    local action_h = math.max(30, math.min(48, math.floor((bottom - top - reserved_text_h - 42) / 6)))
    layout.w, layout.h, layout.side, layout.top, layout.bottom = width, height, side, top, bottom
    set_control(1, "primary", "Pair / Advertise", side, top, content_w, action_h)
    set_control(2, "mode", "Mode: Arrow keys", side, top + action_h + 6, content_w, action_h)
    set_control(3, "forget", "Forget pairing", side, top + (action_h + 6) * 2, content_w, action_h)

    local pad_top = top + (action_h + 6) * 3 + 8
    -- Reserve two measured status lines and one measured state line.  Lua text
    -- coordinates are top-left, not baselines, so all vertical centering below
    -- is derived from line_height instead of a guessed pixel offset.
    local available_h = bottom - pad_top - reserved_text_h
    local large_h = math.max(48, math.min(84, math.floor((available_h - 16) / 3)))
    -- Reserve a two-line status area below the pad even on the 480-pixel
    -- landscape simulator; controls must never cover an error/retry message.
    local key_h = math.max(30, math.min(72, math.floor((available_h - large_h - 16) / 2)))
    local key_w = math.max(42, math.min(math.floor((content_w - 12) / 3), 110))
    local center_x = math.floor((width - key_w) / 2)
    local left_x = center_x - key_w - 6
    local right_x = center_x + key_w + 6
    set_control(4, "up", "Up", center_x, pad_top, key_w, key_h)
    set_control(5, "left", "Left", left_x, pad_top + key_h + 8, key_w, key_h)
    set_control(6, "down", "Down", center_x, pad_top + key_h + 8, key_w, key_h)
    set_control(7, "right", "Right", right_x, pad_top + key_h + 8, key_w, key_h)
    local large_y = pad_top + key_h * 2 + 16
    local large_w = math.floor((content_w - 12) / 2)
    set_control(8, "enter", "Enter", side, large_y, large_w, large_h)
    set_control(9, "space", "Space", side + large_w + 12, large_y, content_w - large_w - 12, large_h)
    layout.status_y = large_y + large_h + 8
    layout.state_y = bottom - small_line_h
    layout.small_line_h = small_line_h
    return layout
end

local function button(rect, active)
    if active then punri.rect_dither(rect.x, rect.y, rect.w, rect.h, false) end
    punri.rounded_rect(rect.x, rect.y, rect.w, rect.h, 5, false, active and 2 or 1)
    local font = rect.prominent and "ui12" or "ui10"
    local line_h = punri.line_height(font)
    punri.text(rect.x + math.floor(rect.w / 2), rect.y + math.floor((rect.h - line_h) / 2), rect.label,
               font, (active or rect.prominent) and "bold" or "regular", "center", true)
end

local function key_visible(control, controller)
    return controller.mode ~= "pages" or control.id == "left" or control.id == "right" or control.prominent
end

function M.draw(controller)
    local l = M.compute()
    punri.clear()
    local sub = controller.simulated and "SIMULATION / Bluetooth HID" or "Bluetooth HID"
    punri.header("Page Turner", sub)

    if not controller.supported then
        draw_wrapped(l.side, l.top + 10, l.w - l.side * 2,
            "This build cannot act as a Bluetooth HID keyboard. Bluetooth Page Turner requires an X4 Pro firmware build with HID enabled.",
            "ui10", "regular", 5)
        punri.button_hints("Exit", "", "", "")
        return
    end

    local primary = l.controls[1]
    primary.label = controller.connected and "Disconnect" or "Pair / Advertise"
    local mode = l.controls[2]
    mode.label = controller.mode == "pages" and "Mode: Page turns" or "Mode: Arrow keys"
    local forget = l.controls[3]
    forget.label = "Forget pairing"
    -- Confirm always executes this primary control. Keep its visual selection
    -- visible in ready, advertising and connected states so button-only users
    -- never have to infer which action Confirm will perform.
    button(primary, true)
    button(mode, false)
    button(forget, false)

    for index = 4, #l.controls do
        local control = l.controls[index]
        if key_visible(control, controller) then button(control, controller.pending_kind == "key") end
    end
    draw_wrapped(l.side, l.status_y, l.w - l.side * 2, controller.notice, "small", "regular", 2)
    punri.text(l.side, l.state_y, "State: " .. controller.state .. " / keys sent: " .. controller.sent,
               "small", "regular", "left", true)
    punri.button_hints("Exit", controller.connected and "Disconnect" or "Pair", "Mode", "")
end

function M.hit(x, y, controller)
    local l = M.compute()
    for index = 1, #l.controls do
        local control = l.controls[index]
        if punri.in_rect(x, y, control.x, control.y, control.w, control.h) then
            if control.id == "primary" then return controller.connected and "disconnect" or "pair" end
            if control.id == "mode" then return "mode" end
            if control.id == "forget" then return "forget" end
            if key_visible(control, controller) then return control.id end
        end
    end
    return nil
end

return M
