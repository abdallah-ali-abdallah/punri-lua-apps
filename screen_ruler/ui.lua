-- Rendering helpers. The Lua API has metrics but no bezel-safe rectangle or
-- rotated-glyph primitive, so labels are deliberately horizontal and inset.

local Ruler = Ruler or dofile("ruler.lua")
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

function UI.toolbar_controls(units)
    local w, h = UI.bounds()
    local height = UI.toolbar_height() - 6
    local y = h - UI.toolbar_height() + 3
    -- The current unit is the control label: tapping it moves predictably
    -- through mm → cm → inch without opening another screen.
    local labels = { "Mode", UI.unit_label(units), "Calibrate", "Rotate", "Clean", "Exit" }
    local controls = {}
    for index, label in ipairs(labels) do
        local left = ((index - 1) * w) // #labels + 2
        local right = (index * w) // #labels - 2
        controls[index] = { x = left, y = y, w = math.max(1, right - left), h = height, label = label }
    end
    return controls
end

function UI.draw_toolbar(units)
    for _, control in ipairs(UI.toolbar_controls(units)) do UI.draw_button(control, control.label, false) end
end

function UI.hit(controls, x, y)
    for index, control in ipairs(controls) do
        if punri.in_rect(x, y, control.x, control.y, control.w, control.h) then return index end
    end
    return nil
end

function UI.format_distance(mm, units)
    if units == "cm" then return string.format("%d cm", mm // 10) end
    if units == "in" then
        -- Keep this conversion in hundredths: mm / 25.40, no float drift.
        local hundredths = (mm * 10000 + 1270) // 2540
        return string.format("%d.%02d in", hundredths // 100, hundredths % 100)
    end
    return string.format("%d mm", mm)
end

local function label_for_tick(mm, units)
    if units == "in" then
        -- Ticks remain metric (the physical calibration is metric), while an
        -- inch view shows a rounded truthful conversion every 10 mm. Do not
        -- pretend that a 25 mm mark is exactly one inch.
        if mm > 0 and mm % 10 == 0 then
            local hundredths = (mm * 10000 + 1270) // 2540
            return string.format("%d.%02d", hundredths // 100, hundredths % 100)
        end
        return nil
    end
    if mm > 0 and mm % 10 == 0 then
        return units == "cm" and tostring(mm // 10) or tostring(mm)
    end
    return nil
end

local function vertical_label_lane_width(state, max_mm)
    -- Size this lane from the last label that can actually appear on THIS
    -- screen, instead of reserving room for an arbitrary five-thousand-mm
    -- value. The vertical labels still remain wholly left of their ruler.
    local last_labeled_mm = (max_mm // 10) * 10
    local widest = label_for_tick(last_labeled_mm, state.units) or "0"
    local label_width = math.max(punri.text_width(widest, "small", "bold"),
        punri.text_width("0", "small", "bold"))
    return label_width + 4
end

function UI.axis_scale(state, horizontal)
    local orientation = (punri.get_orientation and punri.get_orientation()) or "portrait"
    local landscape = orientation == "landscape" or orientation == "landscape_ccw"
    if landscape then return horizontal and state.y or state.x end
    return horizontal and state.x or state.y
end

local function draw_horizontal(origin_x, baseline_y, limit_x, state, show_origin_label)
    local scale = UI.axis_scale(state, true)
    local max_mm = Ruler.max_index(origin_x, limit_x, scale)
    local step = Ruler.minor_step(scale)
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
    for mm = 0, max_mm do
        if Ruler.should_draw_tick(mm, step) then
            local position = Ruler.tick_position(origin_x, mm, scale)
            if position and position > last_position and position < limit_x then
                local long = mm % 10 == 0
                local medium = mm % 5 == 0
                local length = long and 18 or (medium and 13 or 8)
                punri.line(position, baseline_y, position, baseline_y + length, long and 2 or 1, true)
                local label = label_for_tick(mm, state.units)
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
    return max_mm, step
end

local function draw_vertical(origin_y, baseline_x, limit_y, state, show_origin_label)
    local scale = UI.axis_scale(state, false)
    local max_mm = Ruler.max_index(origin_y, limit_y, scale)
    local step = Ruler.minor_step(scale)
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
    for mm = 0, max_mm do
        if Ruler.should_draw_tick(mm, step) then
            local position = Ruler.tick_position(origin_y, mm, scale)
            if position and position > last_position and position < limit_y then
                local long = mm % 10 == 0
                local medium = mm % 5 == 0
                local length = long and 18 or (medium and 13 or 8)
                punri.line(baseline_x, position, baseline_x + length, position, long and 2 or 1, true)
                local label = label_for_tick(mm, state.units)
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
    return max_mm, step
end

function UI.draw_ruler(state, clean)
    local w, h = UI.bounds()
    local edge = UI.safe_edge()
    local bottom = h - (clean and edge or UI.toolbar_height())
    -- Reserve one measured small-text line plus a 4px gap above the ruler.
    -- `punri.text` uses a top Y coordinate, not a baseline.
    local label_space = punri.line_height("small") + 4
    local origin_y = math.max(edge + 18, label_space + edge)
    local horizontal_limit, vertical_limit = w - edge, bottom - edge
    local vertical_lane = 0
    if state.mode == "vertical" or state.mode == "both" then
        local max_vertical_mm = Ruler.max_index(origin_y, vertical_limit, UI.axis_scale(state, false))
        vertical_lane = vertical_label_lane_width(state, max_vertical_mm)
    end
    local origin_x = math.max(edge + 18, edge + vertical_lane + 5, 28)
    local hm, hs, vm, vs
    if state.mode == "horizontal" or state.mode == "both" then
        hm, hs = draw_horizontal(origin_x, origin_y, horizontal_limit, state, state.mode == "horizontal")
    end
    if state.mode == "vertical" or state.mode == "both" then
        vm, vs = draw_vertical(origin_y, origin_x, vertical_limit, state, true)
    end
    if not clean then
        local top = bottom - 20
        local description = "Screen Ruler"
        if hm then description = description .. "  H 0–" .. UI.format_distance(hm, state.units) end
        if vm then description = description .. "  V 0–" .. UI.format_distance(vm, state.units) end
        local subdivisions = math.max(hs or 1, vs or 1)
        if subdivisions > 1 then description = description .. "  marks: " .. subdivisions .. " mm" end
        punri.text(edge, top, description, "small", "regular", "left", true)
        UI.draw_toolbar(state.units)
    else
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
