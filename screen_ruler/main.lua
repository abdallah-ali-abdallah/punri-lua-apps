-- Screen Ruler for PUNRI. X4 Pro / X4 Classic start with their nominal device
-- scale; independent real-ruler X/Y calibration remains available for tuning.

Ruler = dofile("ruler.lua")
Calibration = dofile("calibration.lua")
UI = dofile("ui.lua")

local state = nil
local foreign_state = nil
local view = "ruler"                 -- ruler, menu, calibration, reset_confirm, retry
local clean = false
local menu_index = 1
local message = ""
local retry_state = nil
local retry_after_save = nil
local retry_return_view = nil
local calibration = nil

local function request_update()
    if punri.request_update then punri.request_update() end
end

local function physical_identity()
    local device = (punri.get_device and punri.get_device()) or "unknown"
    local width, height = punri.get_bounds()
    local orientation = (punri.get_orientation and punri.get_orientation()) or "portrait"
    if orientation == "landscape" or orientation == "landscape_ccw" then width, height = height, width end
    return device, width, height
end

local function has_orientation()
    return punri.has_feature and punri.has_feature("orientation")
end

local function target_orientation(for_state)
    if for_state.orientation == "portrait" then return "portrait" end
    if for_state.orientation == "landscape" then return "landscape" end
    if for_state.mode == "horizontal" then return "landscape" end
    return "portrait"
end

local function apply_orientation(for_state)
    if has_orientation() and punri.set_orientation then punri.set_orientation(target_orientation(for_state)) end
end

local function update_sleep_policy()
    -- Calibration/setup must still obey auto-sleep; only a stationary, usable
    -- ruler keeps the display awake so an object is not interrupted mid-measure.
    if punri.prevent_sleep then punri.prevent_sleep(view == "ruler" and state.calibrated) end
end

local function set_message(text)
    message = text or ""
end

local function persist(proposal, after_success)
    local return_view = view == "retry" and (retry_return_view or "ruler") or view
    local encoded = Calibration.encode(proposal)
    if not encoded or not punri.write_file or not punri.write_file(Calibration.FILE, encoded) then
        retry_state = Calibration.copy(proposal)
        retry_after_save = after_success
        retry_return_view = return_view
        view = "retry"
        update_sleep_policy()
        request_update()
        return false
    end
    state = Calibration.copy(proposal)
    retry_state, retry_after_save = nil, nil
    if after_success then after_success() else view = return_view end
    retry_return_view = nil
    apply_orientation(state)
    update_sleep_policy()
    request_update()
    return true
end

local function cycle_mode(direction)
    local modes = { "horizontal", "vertical", "both" }
    local index = 1
    for i, value in ipairs(modes) do if state.mode == value then index = i end end
    index = ((index - 1 + direction) % #modes) + 1
    local proposal = Calibration.copy(state)
    proposal.mode = modes[index]
    persist(proposal)
end

local function cycle_units(direction)
    local values = { "mm", "cm", "in" }
    local index = 1
    for i, value in ipairs(values) do if state.units == value then index = i end end
    index = ((index - 1 + direction) % #values) + 1
    local proposal = Calibration.copy(state)
    proposal.units = values[index]
    persist(proposal)
end

local function cycle_orientation()
    if not has_orientation() then
        set_message("Orientation switching is unavailable in this firmware.")
        request_update()
        return
    end
    local values = { "auto", "portrait", "landscape" }
    local index = 1
    for i, value in ipairs(values) do if state.orientation == value then index = i end end
    index = index % #values + 1
    local proposal = Calibration.copy(state)
    proposal.orientation = values[index]
    persist(proposal)
end

local function calibration_axis_length(axis)
    local width, height = punri.get_bounds()
    return axis == "x" and width or height
end

local function calibration_limits(axis)
    local length = calibration_axis_length(axis)
    return 20, math.max(20, length - UI.safe_edge() * 2 - 20)
end

local function make_calibration(axis, phase, prior_scale, verification_mm)
    -- Calibration always occurs in portrait logical coordinates, giving names
    -- X and Y a stable physical meaning. Landscape ruler drawing swaps scales.
    if has_orientation() and punri.set_orientation then punri.set_orientation("portrait") end
    local minimum, maximum = calibration_limits(axis)
    local span = math.min(maximum, math.max(minimum, 220))
    if prior_scale then
        local target = verification_mm or 40
        span = Ruler.tick_position(0, target, prior_scale) or span
        span = math.max(minimum, math.min(maximum, span))
    end
    -- Keep the completed portrait X measurement while the Y verification
    -- step replaces this transient wizard record.
    local completed_x = calibration and calibration.completed_x or nil
    calibration = {
        axis = axis,
        phase = phase,
        span = span,
        first = prior_scale,
        target_mm = verification_mm,
        completed_x = completed_x,
    }
    view = "calibration"
    update_sleep_policy()
    request_update()
end

local function start_calibration()
    if foreign_state then
        view = "foreign_notice"
        update_sleep_policy()
        request_update()
    else
        make_calibration("x", "first", nil)
    end
end

local function request_length()
    if not (punri.has_feature and punri.has_feature("keyboard") and punri.keyboard) then
        set_message("This firmware needs its built-in keyboard for calibration.")
        request_update()
        return
    end
    local initial = ""
    if calibration.phase == "verify" and calibration.target_mm then initial = tostring(calibration.target_mm) end
    local axis = calibration.axis == "x" and "X (horizontal in portrait)" or "Y (vertical in portrait)"
    if not punri.keyboard("Known " .. axis .. " length in mm", initial, 7, false) then
        set_message("Could not open the keyboard. Try again.")
        request_update()
    end
end

local function verification_target(first_length_hundredths, scale, axis)
    local _, maximum = calibration_limits(axis)
    local max_mm = Ruler.max_index(0, maximum, scale)
    local first_mm = first_length_hundredths // 100
    local target = math.min(50, math.max(10, first_mm // 2))
    if target == first_mm then target = target == 50 and 40 or target + 10 end
    if target >= max_mm then target = math.max(5, max_mm // 2) end
    if target <= 0 or target == first_mm then return nil end
    return target
end

local function relative_difference_percent(first, second)
    -- Values are in [0.25,20]; a float comparison here has a wide 5% guard
    -- band and avoids overflowing a cross product on LUA_32BITS builds.
    local a, b = first.n / first.d, second.n / second.d
    return math.floor((math.abs(a - b) * 10000 / a) + 0.5) // 100
end

local function finish_axis(scale)
    if calibration.axis == "x" then
        calibration.completed_x = scale
        make_calibration("y", "first", nil)
        calibration.completed_x = scale
    else
        local device, width, height = physical_identity()
        local proposal = Calibration.copy(state)
        proposal.device, proposal.portrait_width, proposal.portrait_height = device, width, height
        proposal.calibrated = true
        proposal.x, proposal.y = calibration.completed_x, scale
        foreign_state = nil
        persist(proposal, function()
            view = "ruler"
            clean = false
            set_message("X and Y calibration saved. Verify with a real ruler before relying on it.")
        end)
    end
end

local function accept_length(text)
    local length = Calibration.parse_millimeters(text)
    if not length then
        set_message("Enter 1 to 500 mm with at most two decimal places.")
        request_update()
        return
    end
    local scale = Ruler.from_span(calibration.span, length)
    if not scale then
        set_message("That reference creates an implausible scale. Adjust the line or use a real reference.")
        request_update()
        return
    end
    if calibration.phase == "first" then
        local target = verification_target(length, scale, calibration.axis)
        if not target then
            set_message("The first reference is too short for a separate verification. Use a longer real length.")
            request_update()
            return
        end
        calibration.target_mm = target
        make_calibration(calibration.axis, "verify", scale, target)
        return
    end
    local difference = relative_difference_percent(calibration.first, scale)
    if difference > 5 then
        set_message("The second reference differs by " .. difference .. "%. Measure this axis again.")
        make_calibration(calibration.axis, "first", nil)
        return
    end
    finish_axis(scale)
end

local function reset_calibration()
    local proposal = Calibration.copy(state)
    proposal.calibrated, proposal.x, proposal.y = false, nil, nil
    local automatic = Calibration.apply_device_profile(proposal)
    foreign_state = nil
    persist(proposal, function()
        view = "ruler"
        clean = false
        set_message(automatic and "Automatic device calibration restored." or "Calibration reset. Preferences were kept.")
    end)
end

local function menu_controls()
    local w, h = UI.bounds()
    -- The menu explanation can wrap to two UI-10 lines. Start interactive
    -- rows below that measured text area on the 480px landscape screen.
    local edge, row_h, top = UI.safe_edge(), 42, 148
    local labels = {
        "Mode: " .. state.mode,
        "Units: " .. UI.unit_label(state.units),
        "Orientation: " .. state.orientation,
        "Calibrate X and Y",
        "Reset calibration",
        "Close menu",
    }
    local controls = {}
    for index, label in ipairs(labels) do
        controls[index] = { x = edge, y = top + (index - 1) * (row_h + 6), w = w - edge * 2, h = row_h, label = label,
            selected = index == menu_index }
        if controls[index].y + row_h > h - UI.toolbar_height() then break end
    end
    return controls
end

local function menu_activate(index, direction)
    if index == 1 then cycle_mode(direction or 1)
    elseif index == 2 then cycle_units(direction or 1)
    elseif index == 3 then cycle_orientation()
    elseif index == 4 then start_calibration()
    elseif index == 5 then view = "reset_confirm"; update_sleep_policy(); request_update()
    elseif index == 6 then view = "ruler"; update_sleep_policy(); request_update()
    end
end

local function adjust_calibration(delta)
    local minimum, maximum = calibration_limits(calibration.axis)
    calibration.span = math.max(minimum, math.min(maximum, calibration.span + delta))
    request_update()
end

local function exit_app()
    if punri.prevent_sleep then punri.prevent_sleep(false) end
    punri.exit()
end

function on_init()
    -- A Lua app can be initialized again after an activity transition. Do not
    -- retain a wizard, retry, or foreign-card notice from that earlier view.
    view, clean, menu_index, message = "ruler", false, 1, ""
    foreign_state, retry_state, retry_after_save, retry_return_view, calibration = nil, nil, nil, nil, nil
    local device, width, height = physical_identity()
    state = Calibration.default(device, width, height)
    local raw = punri.read_file and punri.read_file(Calibration.FILE, 512) or nil
    if raw ~= nil then
        local loaded, error = Calibration.decode(raw)
        if loaded and Calibration.same_identity(loaded, device, width, height) then
            state = loaded
        elseif loaded then
            foreign_state = loaded
            set_message("Calibration belongs to " .. loaded.device .. " " .. loaded.portrait_width .. "×" .. loaded.portrait_height ..
                ". Verify X and Y on this screen before use.")
        else
            set_message("Saved calibration is corrupt; it will not be used. Calibrate X and Y.")
        end
    elseif punri.file_exists and punri.file_exists(Calibration.FILE) then
        set_message("Saved calibration could not be read; it will not be used. Calibrate X and Y.")
    else
        set_message("Calibrate X and Y with a real ruler for this device.")
    end
    -- A matching saved manual calibration wins. Missing, uncalibrated,
    -- corrupt or foreign-card records never supply a scale for this board.
    -- The supported hardware's own nominal profile makes it usable at once;
    -- do not rewrite any SD record just because the app was opened.
    if not state.calibrated and Calibration.apply_device_profile(state) then
        foreign_state = nil
        set_message("")
    end
    apply_orientation(state)
    update_sleep_policy()
end

function on_draw()
    punri.clear()
    if view == "ruler" then
        if state.calibrated then
            UI.draw_ruler(state, clean)
            if message ~= "" and not clean then
                local _, h = UI.bounds()
                punri.text(UI.safe_edge(), h - UI.toolbar_height() - 36, message, "small", "regular", "left", true)
            end
        else
            local w, h = UI.bounds()
            local controls = {
                { x = UI.safe_edge(), y = h - 120, w = w - UI.safe_edge() * 2, h = 42, label = "Calibrate X and Y" },
                { x = UI.safe_edge(), y = h - 66, w = (w - UI.safe_edge() * 2) // 2 - 4, h = 42, label = "Menu" },
                { x = w // 2 + 4, y = h - 66, w = (w - UI.safe_edge() * 2) // 2 - 4, h = 42, label = "Exit" },
            }
            UI.draw_message("Screen Ruler", {
                "Automatic calibration is available on X4 Pro and X4 Classic. Calibrate both axes for this device.",
                message,
                "The simulator has no physical millimetres and cannot certify accuracy.",
            }, controls)
        end
    elseif view == "menu" then
        local controls = menu_controls()
        UI.draw_message("Screen Ruler menu", { "Confirm activates the selected row. Left/Right selects it; Up/Down changes it." }, controls)
    elseif view == "foreign_notice" then
        local w, h = UI.bounds()
        UI.draw_message("Calibration confirmation", {
            "The SD card calibration is tied to another board or portrait screen size.",
            "It is not used here. Confirm starts a new real-ruler verification of X and Y.",
        }, {
            { x = UI.safe_edge(), y = h - 118, w = w - UI.safe_edge() * 2, h = 42, label = "Verify X and Y" },
            { x = UI.safe_edge(), y = h - 64, w = w - UI.safe_edge() * 2, h = 42, label = "Back to setup" },
        })
    elseif view == "calibration" then
        local w, h = UI.bounds()
        local edge = UI.safe_edge()
        local horizontal = calibration.axis == "x"
        local axis_label = horizontal and "physical X: portrait horizontal" or "physical Y: portrait vertical"
        local phase_label = calibration.phase == "first" and "1. Align a real reference" or
            ("2. Verify with a different " .. calibration.target_mm .. " mm reference")
        local start = 60
        local end_pos = start + calibration.span
        if horizontal then
            punri.line(start, 240, end_pos, 240, 2, true)
            punri.line(start, 220, start, 262, 2, true)
            punri.line(end_pos, 220, end_pos, 262, 2, true)
        else
            punri.line(240, start, 240, end_pos, 2, true)
            punri.line(220, start, 262, start, 2, true)
            punri.line(220, end_pos, 262, end_pos, 2, true)
        end
        local controls = {
            { x = edge, y = h - 120, w = (w - edge * 2) // 2 - 4, h = 40, label = "− fine" },
            { x = w // 2 + 4, y = h - 120, w = (w - edge * 2) // 2 - 4, h = 40, label = "+ fine" },
            { x = edge, y = h - 70, w = (w - edge * 2) // 3 - 4, h = 40, label = "− coarse" },
            { x = edge + (w - edge * 2) // 3 + 2, y = h - 70, w = (w - edge * 2) // 3 - 4, h = 40, label = "+ coarse" },
            { x = edge + 2 * ((w - edge * 2) // 3) + 4, y = h - 70, w = (w - edge * 2) // 3 - 4, h = 40, label = "Enter mm" },
        }
        UI.draw_message("Calibrate " .. axis_label, {
            phase_label,
            "Move the far marker until it matches a real ruler. Span: " .. calibration.span .. " pixels.",
            "Use the firmware keyboard to enter the known length; no numeric-only keyboard API exists.",
            message,
        }, controls)
    elseif view == "reset_confirm" then
        local w, h = UI.bounds()
        local automatic = Calibration.has_device_profile(state)
        UI.draw_message("Reset calibration?", {
            automatic and "Restore automatic device calibration? Mode, units and orientation stay saved." or
                "This removes only the stored X/Y scales. Mode, units and orientation stay saved."
        }, {
            { x = UI.safe_edge(), y = h - 118, w = (w - UI.safe_edge() * 2) // 2 - 4, h = 42, label = "Keep scales" },
            { x = w // 2 + 4, y = h - 118, w = (w - UI.safe_edge() * 2) // 2 - 4, h = 42,
                label = automatic and "Restore auto" or "Reset scales" },
        })
    elseif view == "retry" then
        local w, h = UI.bounds()
        UI.draw_message("SD save failed", {
            "The previous saved calibration remains active. The new value was not accepted.",
            "Retry while this app stays open, or discard this change.",
        }, {
            { x = UI.safe_edge(), y = h - 118, w = (w - UI.safe_edge() * 2) // 2 - 4, h = 42, label = "Retry" },
            { x = w // 2 + 4, y = h - 118, w = (w - UI.safe_edge() * 2) // 2 - 4, h = 42, label = "Discard" },
        })
    end
end

function on_button(button, pressed)
    if not pressed then return end
    if button == "back" then exit_app(); return end
    if view == "ruler" then
        if not state.calibrated then
            if button == "confirm" then start_calibration()
            elseif button == "left" or button == "right" then view = "menu"; update_sleep_policy(); request_update() end
        elseif button == "confirm" then
            view = "menu"; update_sleep_policy(); request_update()
        elseif button == "up" or button == "page_back" then cycle_mode(-1)
        elseif button == "down" or button == "page_forward" then cycle_mode(1)
        elseif button == "left" then cycle_units(-1)
        elseif button == "right" then start_calibration()
        end
    elseif view == "menu" then
        if button == "left" then menu_index = math.max(1, menu_index - 1); request_update()
        elseif button == "right" then menu_index = math.min(6, menu_index + 1); request_update()
        elseif button == "up" or button == "page_back" then menu_activate(menu_index, -1)
        elseif button == "down" or button == "page_forward" then menu_activate(menu_index, 1)
        elseif button == "confirm" then menu_activate(menu_index, 1)
        end
    elseif view == "foreign_notice" then
        if button == "confirm" then make_calibration("x", "first", nil)
        elseif button == "left" or button == "right" then view = "ruler"; request_update() end
    elseif view == "calibration" then
        if button == "left" then adjust_calibration(-1)
        elseif button == "right" then adjust_calibration(1)
        elseif button == "up" or button == "page_back" then adjust_calibration(-10)
        elseif button == "down" or button == "page_forward" then adjust_calibration(10)
        elseif button == "confirm" then request_length()
        end
    elseif view == "reset_confirm" then
        if button == "confirm" or button == "right" then reset_calibration()
        elseif button == "left" then view = "menu"; request_update() end
    elseif view == "retry" then
        if button == "confirm" or button == "left" then
            local pending, after = retry_state, retry_after_save
            retry_state, retry_after_save = nil, nil
            persist(pending, after)
        elseif button == "right" then view = "ruler"; update_sleep_policy(); request_update() end
    end
end

-- The activity calls on_tap and then on_touch("tap") for one physical tap.
-- Implement only this callback to avoid applying an action twice.
function on_tap(x, y)
    if view == "ruler" then
        if state.calibrated then
            if clean then
                local exit = UI.clean_exit_control()
                if punri.in_rect(x, y, exit.x, exit.y, exit.w, exit.h) then exit_app() end
                return
            end
            local action = UI.hit(UI.toolbar_controls(), x, y)
            if action == 1 then cycle_mode(1)
            elseif action == 2 then cycle_units(1)
            elseif action == 3 then start_calibration()
            elseif action == 4 then cycle_orientation()
            elseif action == 5 then clean = true; update_sleep_policy(); request_update()
            elseif action == 6 then exit_app()
            end
        else
            local w, h = UI.bounds()
            if y >= h - 120 and y < h - 78 then start_calibration()
            elseif y >= h - 70 and x < w // 2 then view = "menu"; update_sleep_policy(); request_update()
            elseif y >= h - 70 then exit_app() end
        end
    elseif view == "menu" then
        local index = UI.hit(menu_controls(), x, y)
        if index then menu_index = index; menu_activate(index, 1) end
    elseif view == "foreign_notice" then
        local _, h = UI.bounds()
        if y >= h - 118 and y < h - 70 then make_calibration("x", "first", nil)
        elseif y >= h - 70 then view = "ruler"; request_update() end
    elseif view == "calibration" then
        local w, h = UI.bounds()
        if y >= h - 120 and y < h - 78 then adjust_calibration(x < w // 2 and -1 or 1)
        elseif y >= h - 70 then
            if x < w // 3 then adjust_calibration(-10)
            elseif x < 2 * w // 3 then adjust_calibration(10)
            else request_length() end
        end
    elseif view == "reset_confirm" then
        local w, h = UI.bounds()
        if y >= h - 118 then
            if x < w // 2 then view = "menu"; request_update() else reset_calibration() end
        end
    elseif view == "retry" then
        local w, h = UI.bounds()
        if y >= h - 118 then
            if x < w // 2 then
                local pending, after = retry_state, retry_after_save
                retry_state, retry_after_save = nil, nil
                persist(pending, after)
            else
                retry_state, retry_after_save = nil, nil
                view = "ruler"
                update_sleep_policy()
                request_update()
            end
        end
    end
end

function on_keyboard(text, cancelled)
    if cancelled then
        set_message("Length entry cancelled. The calibration line is still adjustable.")
        request_update()
        return
    end
    accept_length(text)
end

function on_exit()
    -- A failed write has a visible Retry state before this callback. Do not try
    -- a hidden final save here: the runner is about to destroy the Lua state.
    if punri.prevent_sleep then punri.prevent_sleep(false) end
end
