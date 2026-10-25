-- Unit Convert: offline, bounded conversions for PUNRI's 32-bit Lua runtime.
local Units = punri.dofile("units.lua")
local Convert = punri.dofile("convert.lua")(Units)
local Format = punri.dofile("format.lua")
local Input = punri.dofile("input.lua")
local UI = punri.dofile("ui.lua")

local category = Units.category("length")
local selected = {}
for _, item in ipairs(Units.categories) do
    selected[item.id] = {from = item.defaults[1], to = item.defaults[2]}
end

local input = ""
local result, result_text, result_error = nil, nil, nil
local focus, key_index = 1, 1 -- category, from, to, swap, keypad
local mode, picker_target, picker_index = "main", nil, 1
local width, height, metrics = 480, 800, nil
local dirty, save_failed, notice = false, false, nil

local function current_from()
    return Units.unit(category, selected[category.id].from)
end

local function current_to()
    return Units.unit(category, selected[category.id].to)
end

local function state_payload()
    local lines = {"PUNRI_UNIT_CONVERT_1", "category=" .. category.id}
    for _, item in ipairs(Units.categories) do
        local pair = selected[item.id]
        lines[#lines + 1] = item.id .. "=" .. pair.from .. "|" .. pair.to
    end
    -- Input is saved only alongside a meaningful selection change, never after
    -- each key.  Keep incomplete text out of the persisted record.
    local parsed = Format.parse_number(input)
    if parsed ~= nil then lines[#lines + 1] = "input=" .. input end
    return table.concat(lines, "\n")
end

local function save_state()
    if not dirty then return true end
    local ok = punri.write_file("state.dat", state_payload())
    if ok then
        dirty, save_failed, notice = false, false, nil
        return true
    end
    save_failed, notice = true, "Save failed. Retry while this app is open."
    return false
end

local function defaults()
    category = Units.category("length")
    for _, item in ipairs(Units.categories) do
        selected[item.id].from, selected[item.id].to = item.defaults[1], item.defaults[2]
    end
end

local function load_state()
    local raw = punri.read_file("state.dat", 512)
    if raw == nil or raw == "" then return end
    local lines = {}
    for line in raw:gmatch("[^\n]+") do lines[#lines + 1] = line end
    if lines[1] ~= "PUNRI_UNIT_CONVERT_1" then
        notice = "Saved settings ignored."
        return
    end
    local saved_category = nil
    local loaded = {}
    local saved_input = ""
    for i = 2, #lines do
        local id = lines[i]:match("^category=([a-z_]+)$")
        if id then
            saved_category = id
        else
            local key, from, to = lines[i]:match("^([a-z_]+)=([A-Za-z0-9_]+)|([A-Za-z0-9_]+)$")
            if key and Units.category(key) then
                loaded[key] = {from = from, to = to}
            else
                local candidate = lines[i]:match("^input=(.+)$")
                if candidate then saved_input = candidate end
            end
        end
    end
    if not saved_category or not Units.category(saved_category) then
        notice = "Saved settings ignored."
        return
    end
    for _, item in ipairs(Units.categories) do
        local pair = loaded[item.id]
        if not pair or not Units.unit(item, pair.from) or not Units.unit(item, pair.to) then
            notice = "Saved settings ignored."
            return
        end
    end
    category = Units.category(saved_category)
    for _, item in ipairs(Units.categories) do
        selected[item.id].from, selected[item.id].to = loaded[item.id].from, loaded[item.id].to
    end
    if saved_input ~= "" and Format.parse_number(saved_input) ~= nil then input = saved_input end
end

local function recompute()
    result, result_text, result_error = nil, nil, nil
    if input == "" then return end
    local value, parse_error = Format.parse_number(input)
    if value == nil then
        result_error = parse_error
        return
    end
    local converted, convert_error = Convert.convert(value, category, current_from(), current_to())
    if converted == nil then
        result_error = convert_error
        return
    end
    local display = Format.number(converted)
    if not display then
        result_error = "Conversion is outside the display range."
        return
    end
    result, result_text = converted, display
end

local function request()
    recompute()
    punri.request_update()
end

local function set_category(delta)
    local index = 1
    for i, item in ipairs(Units.categories) do if item.id == category.id then index = i break end end
    local next_index = ((index - 1 + delta) % #Units.categories) + 1
    if category.id == Units.categories[next_index].id then return end
    category = Units.categories[next_index]
    dirty = true
    save_state()
    request()
end

local function set_unit(target, delta)
    local pair = selected[category.id]
    local old_id = pair[target]
    local next_item = Units.next_unit(category, old_id, delta)
    if next_item.id == old_id then return end
    pair[target] = next_item.id
    dirty = true
    save_state()
    request()
end

local function choose_picker()
    local pair = selected[category.id]
    pair[picker_target] = category.units[picker_index].id
    mode = "main"
    dirty = true
    save_state()
    request()
end

local function open_picker(target)
    mode, picker_target = "picker", target
    local item = selected[category.id][target]
    picker_index = Units.unit(category, item).index
    punri.request_update()
end

local function apply_key(index)
    local key = UI.key_label(index)
    if key == "Exit" then
        save_state()
        punri.exit()
        return
    end
    local changed, message
    input, changed, message = Input.apply(input, key, Format.MAX_INPUT_CHARS)
    if changed then
        notice = nil
        request()
    elseif message then
        notice = message
        punri.request_update()
    end
end

local function swap()
    if result == nil then
        notice = result_error or "Enter a valid value before swapping."
        punri.request_update()
        return
    end
    local editable = Format.editable(result)
    if not editable then
        notice = "Result cannot be edited."
        punri.request_update()
        return
    end
    local pair = selected[category.id]
    pair.from, pair.to = pair.to, pair.from
    input = editable
    dirty = true
    save_state()
    request()
end

local function main_state()
    return {
        categories = Units.categories, category = category, from = current_from(), to = current_to(), input = input,
        result_text = result_text, result_error = result_error or notice, focus = focus, key_index = key_index,
        save_failed = save_failed, picker_target = picker_target,
    }
end

function on_init()
    width, height = punri.get_bounds()
    metrics = punri.get_metrics()
    UI.compute(width, height, metrics)
    defaults()
    load_state()
    recompute()
end

function on_draw()
    width, height = punri.get_bounds()
    metrics = punri.get_metrics()
    UI.compute(width, height, metrics)
    if mode == "picker" then UI.draw_picker(main_state()) else UI.draw_main(main_state()) end
end

function on_button(button, pressed)
    if not pressed then return end
    if mode == "picker" then
        if button == "back" then
            mode = "main"
        elseif button == "confirm" then
            choose_picker()
            return
        elseif button == "left" or button == "up" or button == "page_back" then
            picker_index = ((picker_index - 2) % #category.units) + 1
        elseif button == "right" or button == "down" or button == "page_forward" then
            picker_index = (picker_index % #category.units) + 1
        end
        punri.request_update()
        return
    end

    if button == "back" then
        save_state()
        punri.exit()
        return
    end
    if button == "confirm" and save_failed then
        -- A failed retry leaves the existing error card intact. Redraw only
        -- after success, when the card needs to disappear and data may need
        -- recomputing; this also avoids a needless full e-ink refresh.
        if save_state() then request() end
        return
    end
    if button == "up" or button == "page_back" then
        focus = ((focus - 2) % 5) + 1
    elseif button == "down" or button == "page_forward" then
        focus = (focus % 5) + 1
    elseif button == "left" then
        if focus == 1 then set_category(-1); return
        elseif focus == 2 then set_unit("from", -1); return
        elseif focus == 3 then set_unit("to", -1); return
        elseif focus == 4 then swap(); return
        else key_index = ((key_index - 2) % UI.key_count()) + 1 end
    elseif button == "right" then
        if focus == 1 then set_category(1); return
        elseif focus == 2 then set_unit("from", 1); return
        elseif focus == 3 then set_unit("to", 1); return
        elseif focus == 4 then swap(); return
        else key_index = (key_index % UI.key_count()) + 1 end
    elseif button == "confirm" then
        if focus == 1 then set_category(1); return
        elseif focus == 2 then open_picker("from"); return
        elseif focus == 3 then open_picker("to"); return
        elseif focus == 4 then swap(); return
        else apply_key(key_index); return end
    end
    punri.request_update()
end

-- LuaAppActivity delivers a touch tap to both on_tap and on_touch.  Define
-- only on_tap so one physical tap can mutate this app only once.
function on_tap(x, y)
    local l = UI.layout()
    if mode == "picker" then
        if punri.in_rect(x, y, l.picker_back_x, l.picker_back_y, l.picker_back_w, l.picker_back_h) then
            on_button("back", true)
            return
        end
        if y > height - metrics.button_hints_height then
            if x < width / 4 then on_button("back", true)
            elseif x < width / 2 then on_button("confirm", true)
            elseif x < 3 * width / 4 then on_button("left", true)
            else on_button("right", true) end
            return
        end
        local item = UI.picker_at(x, y, #category.units)
        if item then picker_index = item; choose_picker() end
        return
    end

    if y > height - metrics.button_hints_height then
        if x < width / 4 then on_button("back", true)
        elseif x < width / 2 then on_button("confirm", true)
        elseif x < 3 * width / 4 then on_button("left", true)
        else on_button("right", true) end
        return
    end
    if save_failed and punri.in_rect(x, y, l.left, l.result_y, l.content_w, l.result_h) then
        if save_state() then request() end
        return
    end
    if punri.in_rect(x, y, l.left, l.category_y, l.content_w, l.category_h) then
        local index = math.floor((x - l.left) / math.floor(l.content_w / #Units.categories)) + 1
        if index > #Units.categories then index = #Units.categories end
        local current = 1
        for i, item in ipairs(Units.categories) do if item.id == category.id then current = i break end end
        set_category(index - current)
        return
    end
    if punri.in_rect(x, y, l.left, l.from_y, l.content_w, l.row_h) then open_picker("from"); return end
    if punri.in_rect(x, y, l.left, l.swap_y, l.content_w, l.swap_h) then swap(); return end
    if punri.in_rect(x, y, l.left, l.to_y, l.content_w, l.row_h) then open_picker("to"); return end
    local key = UI.key_at(x, y)
    if key then focus, key_index = 5, key; apply_key(key) end
end

function on_exit()
    -- Changes that matter to restoration are already saved while the app is
    -- open.  This is only a final attempt, not the sole retry opportunity.
    if dirty then save_state() end
end

-- The test-only view has no effect in installed packages.  It lets the native
-- production LuaRunner scenarios assert real layout and persisted state.
if _G.TEST_APP == "unit_convert" then
    UNIT_CONVERT_TEST = {
        state = function()
            return {category = category.id, from = current_from().id, to = current_to().id, input = input,
                    result = result, result_text = result_text, error = result_error or notice, dirty = dirty,
                    save_failed = save_failed, mode = mode, focus = focus, key_index = key_index,
                    picker_index = picker_index}
        end,
        layout = function() return UI.layout() end,
        categories = function() return Units.categories end,
    }
end
