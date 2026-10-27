-- Run through the firmware's LuaRunner fixture after loading Screen Ruler.
-- The real saved-file API and Lua's device-sized integers remain in use.
local native_text, native_line, native_write = punri.text, punri.line, punri.write_file
local native_device, native_bounds = punri.get_device, punri.get_bounds
local native_draw, native_exit = UI.draw_ruler, punri.exit
local native_button = UI.draw_button
local texts, lines, writes = {}, {}, 0
local grid, px, py, observed
punri.get_device = function() return "x4pro" end
punri.write_file = function(...)
    writes = writes + 1
    return native_write(...)
end
punri.text = function(x, y, value, ...)
    texts[#texts + 1] = value
    return native_text(x, y, value, ...)
end
punri.line = function(x1, y1, x2, y2, thickness, ink)
    lines[#lines + 1] = {x1, y1, x2, y2, thickness, ink}
    return native_line(x1, y1, x2, y2, thickness, ink)
end
UI.draw_ruler = function(state, clean, enabled, x, y)
    observed, grid, px, py = state, enabled, x, y
    return native_draw(state, clean, enabled, x, y)
end
UI.draw_button = function(rect, ...)
    local width, height = punri.get_bounds()
    assert(rect.x >= 0 and rect.y >= 0 and rect.x + rect.w <= width and rect.y + rect.h <= height,
        "a toolbar or menu control extends outside the screen")
    return native_button(rect, ...)
end

local function draw()
    texts, lines = {}, {}
    on_draw()
end
local function sees(fragment)
    for _, text in ipairs(texts) do if text:find(fragment, 1, true) then return true end end
    return false
end
local function line_at(x1, y1, x2, y2, thickness)
    for _, line in ipairs(lines) do
        if line[1] == x1 and line[2] == y1 and line[3] == x2 and line[4] == y2 and
            line[5] == thickness and line[6] == true then return true end
    end
    return false
end
local function toolbar(index)
    local button = assert(UI.toolbar_controls(observed.units, grid)[index])
    on_tap(button.x + button.w // 2, button.y + button.h // 2)
    draw()
end
local function menu(index)
    on_button("confirm", true)
    for _ = 1, 8 do on_button("left", true) end
    for _ = 2, index do on_button("right", true) end
    on_button("confirm", true)
    draw()
end

local nominal = {n = 1095, d = 127}
assert(Ruler.tick_position(0, 16, nominal, "in") == 219)
assert(Ruler.tick_position(0, 32, nominal, "in") == 438)
assert(Ruler.tick_position(0, 8, nominal, "in") == 110)
assert(Ruler.tick_position(0, 4, nominal, "in") == 55)
assert(Ruler.tick_position(0, 1, nominal, "in") == 14)
assert(Ruler.tick_label(16, "in") == "1" and Ruler.tick_label(32, "in") == "2")
assert(Ruler.tick_label(10, "in") == nil, "metric values must not become inch labels")
assert(Ruler.measure_pixels(219, nominal, "in") == 100)
assert(Ruler.measure_pixels(219, nominal, "mm") == 2540)
assert(Ruler.measure_pixels(2000, {n = 79999, d = 50000}, "in") == 4921,
    "inch measurement must remain safe with large persisted denominators")
assert(Ruler.tick_position(0, 5000, {n = 79999, d = 50000}, "in") == 12700)
assert(Ruler.minor_step({n = 1, d = 4}, "in") == 4)

local init = APP_INIT or on_init
init()
draw()
assert(observed.calibrated and not grid and px == nil)
assert(on_touch == nil and type(on_update) == "function", "one tap handler and a nonblocking feedback timer are required")
local idle_requests, request_update = 0, punri.request_update
punri.request_update = function() idle_requests = idle_requests + 1 end
on_update()
punri.request_update = request_update
assert(idle_requests == 0, "an idle ruler must not request periodic redraws")

for _, shape in ipairs({{480, 800, "portrait"}, {800, 480, "landscape"}}) do
    punri.get_bounds = function() return shape[1], shape[2] end
    -- Persist a matching physical identity and explicitly lock its orientation.
    local state = Calibration.default("x4pro", 480, 800)
    assert(Calibration.apply_device_profile(state))
    state.orientation = shape[3]
    assert(native_write(Calibration.FILE, Calibration.encode(state)))
    punri.set_orientation(shape[3])
    init()
    draw()
    toolbar(2); toolbar(2) -- mm -> cm -> inch.
    assert(observed.units == "in")
    local left, top, right, bottom = UI.ruler_bounds(observed, false)
    assert(line_at(left + 219, top, left + 219, top + 18, 2), "one inch tick must be 219 px from zero")
    assert(line_at(left + 55, top, left + 55, top + 12, 1), "quarter-inch tick is missing")
    assert(line_at(left + 14, top, left + 14, top + 6, 1), "sixteenth-inch tick is missing")
    if shape[3] == "landscape" then
        assert(line_at(left + 438, top, left + 438, top + 18, 2), "two-inch tick must be 438 px from zero")
    end
    local last = Ruler.max_index(left, right, nominal, "in")
    assert(Ruler.tick_position(left, last, nominal, "in") < right)
    assert(Ruler.tick_position(left, last + 1, nominal, "in") >= right)

    local before = writes
    on_tap(left + 219, top + 110)
    draw()
    assert(sees("X 1 in  Y 0.50 in"), "touch distances must use the selected physical units")
    assert(line_at(left + 219, top, left + 219, bottom - 1, 1))
    assert(line_at(left, top + 110, right - 1, top + 110, 1))
    on_tap(left + 110, top + 219)
    draw()
    assert(sees("X 0.50 in  Y 1 in"), "a second touch must move both guides")
    assert(px == left + 110 and py == top + 219)
    on_tap(left - 1, top - 1)
    draw()
    assert(px == left + 110 and py == top + 219, "label-area taps must not move a guide")
    assert(writes == before, "touch measurements must not write to SD")

    local no_grid_lines = #lines
    local saved = punri.read_file(Calibration.FILE, 512)
    toolbar(5)
    assert(grid and #lines > no_grid_lines and px == left + 110)
    toolbar(5)
    assert(not grid and #lines == no_grid_lines)
    assert(punri.read_file(Calibration.FILE, 512) == saved and writes == before,
        "grid toggles must not change saved calibration or write to SD")

    toolbar(2) -- inch -> mm: the physical zero and touched point stay fixed.
    local metric_left, metric_top = UI.ruler_bounds(observed, false)
    assert(metric_left == left and metric_top == top, "changing units must not shift the zero corner")
    assert(px == left + 110 and py == top + 219 and sees("X 12.76 mm  Y 25.40 mm"))

    menu(7) -- Clear measurement also returns to the ruler.
    assert(px == nil and py == nil and not sees("X "))
    menu(6) -- The grid is reachable through buttons on X4 Classic too.
    assert(sees("Grid: on"))
    on_button("right", true); on_button("right", true); on_button("confirm", true)
    draw()
    assert(grid)
    toolbar(6) -- Clean mode still supports touch measurements.
    local clean_left, clean_top = UI.ruler_bounds(observed, true)
    on_tap(clean_left + 86, clean_top + 86)
    draw()
    assert(px == clean_left + 86 and py == clean_top + 86 and sees("X "))
    local exited = false
    punri.exit = function() exited = true end
    local exit = UI.clean_exit_control()
    on_tap(exit.x + exit.w // 2, exit.y + exit.h // 2)
    assert(exited, "Clean mode must retain its Exit control")
    punri.exit = native_exit
    init()
    draw()
    assert(not grid and px == nil and py == nil, "measurement tools must reset only when the app restarts")
end

-- Landscape must use the saved portrait Y scale horizontally and X vertically.
local independent = Calibration.default("x4pro", 480, 800)
independent.calibrated, independent.units, independent.orientation = true, "in", "landscape"
independent.x, independent.y = {n = 8, d = 1}, {n = 10, d = 1}
assert(native_write(Calibration.FILE, Calibration.encode(independent)))
punri.get_bounds = function() return 800, 480 end
punri.set_orientation("landscape")
init()
draw()
local left, top = UI.ruler_bounds(observed, false)
assert(line_at(left + 254, top, left + 254, top + 18, 2))
on_tap(left + 254, top + 203)
draw()
assert(sees("X 1 in  Y 1 in"), "touch measurements must swap independently calibrated axes after rotation")
toolbar(4)
assert(px == nil and py == nil, "rotating the display must clear stale screen coordinates")

punri.get_device, punri.get_bounds = native_device, native_bounds
punri.text, punri.line, punri.write_file = native_text, native_line, native_write
UI.draw_ruler, UI.draw_button = native_draw, native_button
