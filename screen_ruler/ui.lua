-- Rendering helpers. The Lua API has metrics but no bezel-safe rectangle or
-- rotated-glyph primitive, so labels are deliberately horizontal and inset.

local Ruler = Ruler or dofile("ruler.lua")
local Calibration = Calibration or dofile("calibration.lua")
local UI = {}

local function metrics()
    return (punri.get_metrics and punri.get_metrics()) or { top_padding = 4, button_hints_height = 44, content_side_padding = 12 }
end

function UI.bounds()
    return punri.get_bounds()
end

function UI.safe_edge()
    local m = metrics()
    return math.max(6, (m.content_side_padding or 0) + 2)
end

function UI.toolbar_height()
    local m = metrics()
    return math.max(42, (m.button_hints_height or 44))
end

-- `punri.text` takes a top-left Y coordinate (the renderer applies its own
-- ascender before drawing). Keep the same measured font/style here as its
-- centring implementation; never estimate width from character count.
local function next_utf8_character_end(text, start)
    local first = text:byte(start)
    if not first then return start end
    local bytes = 1
    if first >= 0xC2 and first <= 0xDF then bytes = 2
    elseif first >= 0xE0 and first <= 0xEF then bytes = 3
    elseif first >= 0xF0 and first <= 0xF4 then bytes = 4
    end
    local finish = start + bytes - 1
    if finish > #text then return start end
    for index = start + 1, finish do
        local value = text:byte(index)
        if not value or value < 0x80 or value > 0xBF then return start end
    end
    return finish
end

function UI.fit_button_label(label, max_width, style)
    if punri.text_width(label, "small", style) <= max_width then return label end
    local ellipsis = "…"
    if punri.text_width(ellipsis, "small", style) > max_width then return "" end
    local best, start = ellipsis, 1
    while start <= #label do
        local finish = next_utf8_character_end(label, start)
        local candidate = label:sub(1, finish) .. ellipsis
        if punri.text_width(candidate, "small", style) > max_width then break end
        best, start = candidate, finish + 1
    end
    return best
end

function UI.draw_button(rect, label, selected)
    local style = selected and "bold" or "regular"
    local line_height = punri.line_height("small")
    local visible = UI.fit_button_label(label, math.max(1, rect.w - 12), style)
    punri.rounded_rect(rect.x, rect.y, rect.w, rect.h, 5, selected == true, 1, true)
    punri.text(rect.x + rect.w // 2, rect.y + math.max(0, (rect.h - line_height) // 2), visible,
        "small", style, "center", not selected)
end

function UI.unit_label(units)
    if units == "in" then return "inch" end
    if units == "cm" then return "cm" end
    if units == "mm" then return "mm" end
    return "Units"
end

function UI.toolbar_controls(units, grid)
    local w, h = UI.bounds()
    local height = UI.toolbar_height() - 6
    local y = h - UI.toolbar_height() + 3
    -- The current unit is the control label: tapping it moves predictably
    -- through mm → cm → inch without opening another screen.
    local labels = { "Mode", UI.unit_label(units), "Calibrate", "Rotate", "Grid", "Clean", "Exit" }
    local controls = {}
    for index, label in ipairs(labels) do
        local left = ((index - 1) * w) // #labels + 2
        local right = (index * w) // #labels - 2
        controls[index] = { x = left, y = y, w = math.max(1, right - left), h = height, label = label,
            selected = index == 5 and grid == true }
    end
    return controls
end

function UI.draw_toolbar(units, grid)
    for _, control in ipairs(UI.toolbar_controls(units, grid)) do UI.draw_button(control, control.label, control.selected) end
end

function UI.hit(controls, x, y)
    for index, control in ipairs(controls) do
        if punri.in_rect(x, y, control.x, control.y, control.w, control.h) then return index end
    end
    return nil
end

function UI.format_measurement(hundredths, units)
    local value = hundredths % 100 == 0 and tostring(hundredths // 100) or
        string.format("%d.%02d", hundredths // 100, hundredths % 100)
    return value .. " " .. (units == "in" and "in" or units)
end

function UI.format_distance(index, units)
    return UI.format_measurement(Ruler.tick_hundredths(index, units), units)
end

local function vertical_label_lane_width(origin_y, limit_y, state)
    -- Keep the physical zero corner fixed when units change. Reserve only the
    -- widest label actually possible in any of the three units on this screen.
    local width = punri.text_width("0", "small", "bold")
    local scale = UI.axis_scale(state, false)
    for _, units in ipairs({"mm", "cm", "in"}) do
        local maximum = Ruler.max_index(origin_y, limit_y, scale, units)
        local major = units == "in" and 16 or 10
        local label = Ruler.tick_label((maximum // major) * major, units) or "0"
        width = math.max(width, punri.text_width(label, "small", "bold"))
    end
    return width + 4
end

function UI.axis_scale(state, horizontal)
    local orientation = (punri.get_orientation and punri.get_orientation()) or "portrait"
    local landscape = orientation == "landscape" or orientation == "landscape_ccw"
    if landscape then return horizontal and state.y or state.x end
    return horizontal and state.x or state.y
end

local function draw_horizontal(origin_x, baseline_y, limit_x, state, show_origin_label)
    local scale = UI.axis_scale(state, true)
    local maximum = Ruler.max_index(origin_x, limit_x, scale, state.units)
    local step = Ruler.minor_step(scale, state.units)
    local last_position = -1
    local label_gap = 4
    local last_label_right = -1000
    punri.line(origin_x, baseline_y, limit_x - 1, baseline_y, 1, true)
    punri.line(origin_x, baseline_y - 5, origin_x, baseline_y + 18, 2, true)
    local label_y = math.max(0, baseline_y - punri.line_height("small") - 4)
    if show_origin_label then
        -- A short zero leaves measured room for the first 10-mm label. The
        -- former arrow occupied that room and made the first labels collide.
        local zero_width = punri.text_width("0", "small", "bold")
        punri.text(origin_x, label_y, "0", "small", "bold", "left", true)
        last_label_right = origin_x + zero_width
    end
    for index = 0, maximum do
        if Ruler.should_draw_tick(index, step, state.units) then
            local position = Ruler.tick_position(origin_x, index, scale, state.units)
            if position and position > last_position and position < limit_x then
                local length, thickness = Ruler.tick_length(index, state.units)
                punri.line(position, baseline_y, position, baseline_y + length, thickness, true)
                local label = Ruler.tick_label(index, state.units)
                if label then
                    local width = punri.text_width(label, "small", "bold")
                    local text_x = math.max(origin_x, math.min(position - width // 2, limit_x - width))
                    if text_x > last_label_right + label_gap then
                        -- Labels stay above the horizontal marks: objects can
                        -- sit below the ruler without covering a measurement.
                        punri.text(text_x, label_y, label, "small", "bold", "left", true)
                        last_label_right = text_x + width
                    end
                end
                last_position = position
            end
        end
    end
    return maximum, step
end

local function draw_vertical(origin_y, baseline_x, limit_y, state, show_origin_label)
    local scale = UI.axis_scale(state, false)
    local maximum = Ruler.max_index(origin_y, limit_y, scale, state.units)
    local step = Ruler.minor_step(scale, state.units)
    local last_position = -1
    local last_label_bottom = -1000
    punri.line(baseline_x, origin_y, baseline_x, limit_y - 1, 1, true)
    punri.line(baseline_x - 5, origin_y, baseline_x + 18, origin_y, 2, true)
    local label_height = punri.line_height("small")
    if show_origin_label then
        local zero_width = punri.text_width("0", "small", "bold")
        punri.text(math.max(0, baseline_x - 5 - zero_width), math.max(0, origin_y - label_height), "0",
            "small", "bold", "left", true)
    end
    for index = 0, maximum do
        if Ruler.should_draw_tick(index, step, state.units) then
            local position = Ruler.tick_position(origin_y, index, scale, state.units)
            if position and position > last_position and position < limit_y then
                local length, thickness = Ruler.tick_length(index, state.units)
                punri.line(baseline_x, position, baseline_x + length, position, thickness, true)
                local label = Ruler.tick_label(index, state.units)
                if label and position - label_height // 2 > last_label_bottom + 3 then
                    local label_width = punri.text_width(label, "small", "bold")
                    local text_x = math.max(0, baseline_x - 5 - label_width)
                    local text_y = position - label_height // 2
                    punri.text(text_x, text_y, label, "small", "bold", "left", true)
                    last_label_bottom = text_y + label_height
                end
                last_position = position
            end
        end
    end
    return maximum, step
end

function UI.ruler_bounds(state, clean)
    local w, h = UI.bounds()
    local edge = UI.safe_edge()
    local bottom = h - (clean and edge or UI.toolbar_height())
    -- Reserve one measured small-text line plus a 4px gap above the ruler.
    -- `punri.text` uses a top Y coordinate, not a baseline.
    local label_space = punri.line_height("small") + 4
    local origin_y = math.max(edge + 18, label_space + edge)
    local horizontal_limit, vertical_limit = w - edge, bottom - math.max(edge, clean and 36 or 26)
    local vertical_lane = 0
    if state.mode == "vertical" or state.mode == "both" then
        vertical_lane = vertical_label_lane_width(origin_y, vertical_limit, state)
    end
    local origin_x = math.max(edge + 18, edge + vertical_lane + 5, 28)
    return origin_x, origin_y, horizontal_limit, vertical_limit
end

local function dashed_line(x1, y1, x2, y2)
    if x1 == x2 then
        for y = y1, y2, 8 do punri.line(x1, y, x1, math.min(y + 1, y2), 1, true) end
    else
        for x = x1, x2, 8 do punri.line(x, y1, math.min(x + 1, x2), y1, 1, true) end
    end
end

local function draw_grid(origin_x, origin_y, limit_x, limit_y, state)
    for axis = 1, 2 do
        local horizontal = axis == 1
        local scale = UI.axis_scale(state, horizontal)
        local origin, limit = horizontal and origin_x or origin_y, horizontal and limit_x or limit_y
        local step = state.units == "in" and 4 or 10 -- quarter-inch / one-centimetre grid
        while Ruler.tick_position(0, step, scale, state.units) < 20 do step = step * 2 end
        local maximum = Ruler.max_index(origin, limit, scale, state.units)
        for index = step, maximum, step do
            local position = Ruler.tick_position(origin, index, scale, state.units)
            if horizontal then dashed_line(position, origin_y, position, limit_y - 1)
            else dashed_line(origin_x, position, limit_x - 1, position) end
        end
    end
end

function UI.draw_ruler(state, clean, grid, point_x, point_y)
    local w, h = UI.bounds()
    local edge = UI.safe_edge()
    local bottom = h - (clean and edge or UI.toolbar_height())
    local origin_x, origin_y, horizontal_limit, vertical_limit = UI.ruler_bounds(state, clean)
    if grid then draw_grid(origin_x, origin_y, horizontal_limit, vertical_limit, state) end
    local hm, hs, vm, vs
    if state.mode == "horizontal" or state.mode == "both" then
        hm, hs = draw_horizontal(origin_x, origin_y, horizontal_limit, state, state.mode == "horizontal")
    end
    if state.mode == "vertical" or state.mode == "both" then
        vm, vs = draw_vertical(origin_y, origin_x, vertical_limit, state, true)
    end
    local measured = point_x and point_y and point_x >= origin_x and point_x < horizontal_limit and
        point_y >= origin_y and point_y < vertical_limit
    local reading
    if measured then
        -- A white halo keeps the two solid guides distinct from the dotted grid.
        punri.line(point_x, origin_y, point_x, vertical_limit - 1, 3, false)
        punri.line(origin_x, point_y, horizontal_limit - 1, point_y, 3, false)
        punri.line(point_x, origin_y, point_x, vertical_limit - 1, 1, true)
        punri.line(origin_x, point_y, horizontal_limit - 1, point_y, 1, true)
        reading = "X " .. UI.format_measurement(Ruler.measure_pixels(point_x - origin_x, UI.axis_scale(state, true), state.units), state.units) ..
            "  Y " .. UI.format_measurement(Ruler.measure_pixels(point_y - origin_y, UI.axis_scale(state, false), state.units), state.units)
    end
    if not clean then
        local top = bottom - 20
        local description = Calibration.uses_device_profile(state) and "Screen Ruler (auto)" or "Screen Ruler"
        if hm then description = description .. "  H 0–" .. UI.format_distance(hm, state.units) end
        if vm then description = description .. "  V 0–" .. UI.format_distance(vm, state.units) end
        local subdivisions = math.max(hs or 1, vs or 1)
        if subdivisions > 1 then description = description .. "  marks: " .. subdivisions .. (state.units == "in" and "/16 in" or " mm") end
        punri.text(edge, top, reading or description, "small", measured and "bold" or "regular", "left", true)
        UI.draw_toolbar(state.units, grid)
    else
        if reading then
            local visible = UI.fit_button_label(reading, w - edge - 82, "bold")
            punri.text(edge, h - 28, visible, "small", "bold", "left", true)
        end
        local exit = { x = w - 70, y = h - 30, w = 64, h = 24, label = "Exit" }
        UI.draw_button(exit, exit.label, false)
    end
end

function UI.clean_exit_control()
    local w, h = UI.bounds()
    return { x = w - 70, y = h - 30, w = 64, h = 24 }
end

function UI.draw_message(title, lines, controls)
    local w, h = UI.bounds()
    local edge = UI.safe_edge()
    punri.header(title)
    local y = math.max(88, edge + 70)
    for _, line in ipairs(lines) do
        local wrapped = punri.wrapped_text(line, w - edge * 2, "ui10", "regular", 3)
        for _, wrapped_line in ipairs(wrapped.lines or { line }) do
            punri.text(edge, y, wrapped_line, "ui10", "regular", "left", true)
            y = y + punri.line_height("ui10")
        end
        y = y + 8
    end
    for _, control in ipairs(controls or {}) do UI.draw_button(control, control.label, control.selected) end
end

return UI
