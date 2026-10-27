-- World Clock is an offline, minute-resolution reference utility.  It does
-- not use punri.time(), os.time(), or os.date(): those cannot express a
-- verified UTC source on every supported firmware build.
local time = punri.dofile("time_math.lua")
local zones = punri.dofile("zones.lua")
local cities = punri.dofile("cities.lua")
local map = punri.dofile("map.lua")
local ui = punri.dofile("ui.lua")
local input = punri.dofile("input.lua")

local STATE_FILE = "world_clock_state.txt"
local MAX_FAVORITES = 6
local settings = {home = nil, use24 = true, favorites = {}}
local screen, cursor, list_page = "setup", 1, 1
local setup_page_size, list_page_size, favorite_page_size, chooser_page_size = 6, 5, 6, 6
local selected_id, chooser = "cairo", nil
local chooser_title, chooser_hint, map_frame = nil, nil, nil
local read_only_state, state_notice = false, nil
local pending_settings, pending_after, return_screen = nil, nil, nil
local snapshot_utc, snapshot_source, snapshot_problem = nil, nil, nil
local clock_cache = {}
local last_observed_utc = nil

local function request_draw()
    punri.request_update()
end

local function default_settings()
    return {home = nil, use24 = true, favorites = {}}
end

local function contains(list, id)
    return cities.contains(list, id)
end

local function serialize_state(value)
    return "PUNRI_WORLD_CLOCK_1\n" ..
        "home=" .. (value.home or "") .. "\n" ..
        "format=" .. (value.use24 and "24" or "12") .. "\n" ..
        "favorites=" .. table.concat(value.favorites, ",") .. "\n"
end

local function parse_state(text)
    if text == nil then return default_settings(), nil, false end
    if type(text) ~= "string" or #text > 512 then return nil, "Saved settings unavailable", false end
    local fields = {}
    local count = 0
    for line in text:gmatch("[^\n]+") do
        count = count + 1
        if count == 1 then
            if line ~= "PUNRI_WORLD_CLOCK_1" then return nil, "Saved settings unavailable", false end
        else
            local key, value = line:match("^([a-z_]+)=(.*)$")
            if not key or fields[key] ~= nil then return nil, "Saved settings unavailable", false end
            fields[key] = value
        end
    end
    if count ~= 4 or fields.home == nil or fields.format == nil or fields.favorites == nil then
        return nil, "Saved settings unavailable", false
    end
    if fields.format ~= "24" and fields.format ~= "12" then return nil, "Saved settings unavailable", false end

    local parsed = {home = fields.home ~= "" and fields.home or nil, use24 = fields.format == "24", favorites = {}}
    local missing_city = false
    if parsed.home and not cities.get(parsed.home) then
        parsed.home = nil
        missing_city = true
    end
    if fields.favorites ~= "" then
        for id in fields.favorites:gmatch("[^,]+") do
            if #parsed.favorites >= MAX_FAVORITES or contains(parsed.favorites, id) then
                return nil, "Saved settings unavailable", false
            end
            if cities.get(id) then
                parsed.favorites[#parsed.favorites + 1] = id
            else
                missing_city = true
            end
        end
    end
    return parsed, missing_city and "A saved city is unavailable" or nil, missing_city
end

local function load_state()
    local parsed, notice, lock = parse_state(punri.read_file(STATE_FILE, 512))
    if not parsed then
        settings = default_settings()
        read_only_state = true
        state_notice = notice
        screen = "storage_error"
        return
    end
    settings = parsed
    read_only_state = lock
    state_notice = notice
    if settings.home then selected_id = settings.home end
    screen = settings.home and "map" or "setup"
end

local function reset_clock_cache()
    clock_cache = {}
end

local function trusted_utc()
    if not (punri.has_feature and punri.has_feature("clock_validity")) then
        return nil, nil, "Update PUNRI for verified clock status"
    end
    local local_clock = punri.get_date and punri.get_date() or nil
    if type(local_clock) ~= "table" or local_clock.valid ~= true then
        return nil, nil, "Set device clock"
    end
    local utc = time.utc_from_local_fields(local_clock, local_clock.offset_minutes)
    if not time.supports_utc_minute(utc) then return nil, nil, "Timezone data unavailable" end
    return utc, local_clock.source, nil
end

local function refresh_snapshot(force)
    local utc, source, problem = trusted_utc()
    if not force and utc == last_observed_utc and problem == snapshot_problem then return false end
    last_observed_utc, snapshot_utc, snapshot_source, snapshot_problem = utc, utc, source, problem
    reset_clock_cache()
    return true
end

local function city_clock(id)
    local existing = clock_cache[id]
    if existing then return existing end
    local city = cities.get(id)
    if not city or not snapshot_utc then return nil end
    local offset, dst, problem = zones.resolve(city.zone, snapshot_utc)
    if offset == nil then
        snapshot_problem = problem == "range" and "Timezone data unavailable" or "Timezone data missing"
        return nil
    end
    local local_time = time.local_from_utc(snapshot_utc, offset)
    if not local_time then
        snapshot_problem = "Timezone data unavailable"
        return nil
    end
    local value = {city = city, time = local_time, offset = offset, dst = dst}
    clock_cache[id] = value
    return value
end

local function format_offset_difference(city_value, home_value)
    if not city_value or not home_value then return "Unavailable" end
    local minutes = city_value.offset - home_value.offset
    if minutes == 0 then return "Same time" end
    local sign = minutes < 0 and "-" or "+"
    minutes = math.abs(minutes)
    if minutes % 60 == 0 then return sign .. tostring(math.floor(minutes / 60)) .. "h" end
    return string.format("%s%d:%02d", sign, math.floor(minutes / 60), minutes % 60)
end

local function set_screen(value)
    screen = value
    map_frame = nil
    cursor, list_page = 1, 1
    request_draw()
end

local function commit_settings(next_settings, after, failed_from)
    if read_only_state then
        pending_settings, pending_after, return_screen = next_settings, after, failed_from or screen
        screen = "save_error"
        state_notice = "Saved settings are protected; repair the file first"
        request_draw()
        return false
    end
    if punri.write_file(STATE_FILE, serialize_state(next_settings)) then
        settings = next_settings
        pending_settings, pending_after = nil, nil
        state_notice = nil
        set_screen(after)
        return true
    end
    pending_settings, pending_after, return_screen = next_settings, after, failed_from or screen
    screen = "save_error"
    state_notice = "SD save failed"
    request_draw()
    return false
end

local function retry_save()
    if not pending_settings then return end
    if read_only_state then
        state_notice = "Saved settings are protected; repair the file first"
        request_draw()
        return
    end
    if punri.write_file(STATE_FILE, serialize_state(pending_settings)) then
        settings = pending_settings
        local after = pending_after or "map"
        pending_settings, pending_after, state_notice = nil, nil, nil
        set_screen(after)
    else
        state_notice = "SD save failed"
        request_draw()
    end
end

local function choose_home(id)
    local next_settings = cities.copy_settings(settings)
    next_settings.home = id
    if #next_settings.favorites == 0 then next_settings.favorites[1] = id end
    selected_id = id
    commit_settings(next_settings, "map", "setup")
end

local function toggle_favorite()
    if not settings.home then return end
    local next_settings = cities.copy_settings(settings)
    local found = nil
    for index, id in ipairs(next_settings.favorites) do
        if id == selected_id then found = index break end
    end
    if found then
        table.remove(next_settings.favorites, found)
    elseif #next_settings.favorites < MAX_FAVORITES then
        next_settings.favorites[#next_settings.favorites + 1] = selected_id
    else
        state_notice = "Favorite limit is 6"
        request_draw()
        return
    end
    commit_settings(next_settings, "detail", "detail")
end

local function move_favorite(delta)
    if #settings.favorites < 2 then return end
    local next_settings = cities.copy_settings(settings)
    local target = cursor + delta
    if target < 1 or target > #next_settings.favorites then return end
    next_settings.favorites[cursor], next_settings.favorites[target] = next_settings.favorites[target], next_settings.favorites[cursor]
    if commit_settings(next_settings, "manage") then cursor = target end
end

local function toggle_format()
    local next_settings = cities.copy_settings(settings)
    next_settings.use24 = not next_settings.use24
    commit_settings(next_settings, "manage", "manage")
end

local function remove_favorite()
    if not settings.favorites[cursor] then return end
    local next_settings = cities.copy_settings(settings)
    table.remove(next_settings.favorites, cursor)
    if commit_settings(next_settings, "manage") and cursor > #next_settings.favorites then
        cursor = math.max(1, #next_settings.favorites)
    end
end

local function move_list_cursor(delta, per_page)
    cursor = math.max(1, math.min(#cities.all, cursor + delta))
    list_page = math.floor((cursor - 1) / per_page) + 1
    request_draw()
end

local function select_previous(delta)
    local current = 1
    for index, city in ipairs(cities.all) do if city.id == selected_id then current = index break end end
    current = ((current - 1 + delta) % #cities.all) + 1
    selected_id = cities.all[current].id
    request_draw()
end

local function draw_clock_problem(top)
    if snapshot_problem then
        local width = punri.get_bounds()
        return top + ui.notice(12, top, width - 24, snapshot_problem, false) + 8
    end
    return top
end

local function add_actions(width, bottom, actions)
    local rects = ui.bottom_actions(width, bottom, #actions)
    for index, action in ipairs(actions) do
        local rect = rects[index]
        ui.button(rect.x, rect.y, rect.w, rect.h, action.label, action.selected)
        input.add(action.id, rect.x, rect.y, rect.w, rect.h)
    end
    return rects
end

local function draw_setup()
    local width, _, _, top, bottom = ui.content_bounds()
    punri.header("World Clock", "Setup")
    top = draw_clock_problem(top)
    top = top + ui.message(16, top, width - 32, "Device clock must show the local time in Home city.", 2) + 10
    punri.text(16, top, "Choose Home city", "ui12", "bold")
    top = top + punri.line_height("ui12") + 7
    local row_height = ui.row_height(false)
    setup_page_size = ui.rows_fit(top, bottom, row_height, 6)
    local per_page = setup_page_size
    list_page = math.min(list_page, math.ceil(#cities.all / per_page))
    local first = (list_page - 1) * per_page + 1
    local last = math.min(#cities.all, first + per_page - 1)
    input.begin()
    for index = first, last do
        local city = cities.all[index]
        local y = top + (index - first) * (row_height + 6)
        ui.row(12, y, width - 24, row_height, city.name, index == cursor, city.zone)
        input.add("setup:" .. city.id, 12, y, width - 24, row_height)
    end
    add_actions(width, bottom, {{id = "setup_next", label = "More cities"}})
    punri.button_hints("Exit", "Select", "Prev", "Next")
end

local function draw_map()
    local width, height, _, top, bottom = ui.content_bounds()
    local city_value = city_clock(selected_id)
    local home_value = city_clock(settings.home)
    local selected = cities.get(selected_id)
    punri.header("World Clock", snapshot_source or "Offline")
    top = draw_clock_problem(top)
    if city_value then
        ui.paired_text(8, top, width - 16, punri.line_height("ui12"), selected.name,
            time.format_time(city_value.time, settings.use24), "ui12", "bold", true, true)
        top = top + punri.line_height("ui12")
        if width <= height then
            punri.text(16, top, ui.fit(format_offset_difference(city_value, home_value) .. " vs Home", width - 32, "small", "regular"), "small")
            top = top + punri.line_height("small")
        end
    else
        ui.centered_line(top, width, selected.name, "ui12", "bold")
        top = top + punri.line_height("ui12")
    end
    local map_instruction = map.asset_error and "Map asset unavailable; choose a time-zone region or Cities." or
        "Tap a marker or time-zone region"
    if width > height and city_value then
        map_instruction = format_offset_difference(city_value, home_value) .. " vs Home · " .. map_instruction
    end
    ui.centered_line(top, width, map_instruction, "small", "regular")
    top = top + punri.line_height("small") + 4
    local action_top = ui.bottom_actions(width, bottom, 3)[1].y
    map_frame = map.layout(width, height, top + 8, action_top - 8)
    input.begin()
    map.draw(map_frame, selected_id)
    input.add("map", map_frame.x, map_frame.y, map_frame.width, map_frame.height)
    for _, selector in ipairs(map_frame.selectors) do
        ui.button(selector.x, selector.y, selector.w, selector.h, selector.region.label, false)
        input.add("region:" .. selector.region.id, selector.x, selector.y, selector.w, selector.h)
    end
    add_actions(width, bottom, {
        {id = "cities", label = "Cities"},
        {id = "favorites", label = "Favorites"},
        {id = "details", label = "Details"},
    })
    punri.button_hints("Back", "Details", "City", "Cities")
end

local function draw_list()
    local width, _, _, top, bottom = ui.content_bounds()
    top = draw_clock_problem(top)
    input.begin()
    local row_height = ui.row_height(true)
    list_page_size = ui.rows_fit(top, bottom, row_height, 5)
    local per_page = list_page_size
    list_page = math.min(list_page, math.ceil(#cities.all / per_page))
    punri.header("Cities", string.format("%d/%d", list_page, math.ceil(#cities.all / per_page)))
    local first = (list_page - 1) * per_page + 1
    local last = math.min(#cities.all, first + per_page - 1)
    local home_value = city_clock(settings.home)
    for index = first, last do
        local city = cities.all[index]
        local value = city_clock(city.id)
        local detail = value and time.format_time(value.time, settings.use24) or "--:--"
        local y = top + (index - first) * (row_height + 6)
        local secondary = value and home_value and format_offset_difference(value, home_value) or "Unavailable"
        ui.row(12, y, width - 24, row_height, city.name, index == cursor, detail, secondary)
        input.add("city:" .. city.id, 12, y, width - 24, row_height)
    end
    add_actions(width, bottom, {{id = "map_view", label = "Map"}, {id = "list_next", label = "Next page"}})
    punri.button_hints("Back", "Details", "Prev", "Next")
end

local function draw_detail()
    local width, _, _, top, bottom = ui.content_bounds()
    local city = cities.get(selected_id)
    local value, home_value = city_clock(selected_id), city_clock(settings.home)
    punri.header(city.name, city.zone)
    top = draw_clock_problem(top)
    if value then
        top = top + 8
        top = top + ui.centered_line(top, width, time.format_time(value.time, settings.use24), "ui12", "bold") + 10
        top = top + ui.centered_line(top, width, time.format_date(value.time), "ui10", "regular") + 8
        top = top + ui.centered_line(top, width, format_offset_difference(value, home_value) .. " from Home", "ui10", "regular") + 8
        ui.centered_line(top, width, value.dst and "DST" or "Standard", "ui10", "bold")
    end
    input.begin()
    local favorite_label = contains(settings.favorites, selected_id) and "Remove favorite" or "Add favorite"
    local favorite_y = bottom - 72
    ui.button(12, favorite_y, width - 24, 32, favorite_label, false)
    input.add("favorite", 12, favorite_y, width - 24, 32)
    add_actions(width, bottom, {{id = "cities", label = "Cities"}, {id = "map_view", label = "Map"}})
    punri.button_hints("Back", favorite_label, "Cities", "Map")
end

local function draw_favorites()
    local width, _, _, top, bottom = ui.content_bounds()
    punri.header("Favorites", tostring(#settings.favorites) .. "/6")
    top = draw_clock_problem(top)
    input.begin()
    if #settings.favorites == 0 then
        ui.message(16, top + 20, width - 32, "No favorites yet. Open a city detail to add one.")
    end
    local home_value = city_clock(settings.home)
    local row_height = ui.row_height(true)
    favorite_page_size = ui.rows_fit(top, bottom, row_height, MAX_FAVORITES)
    local first, last = ui.row_window(cursor, #settings.favorites, favorite_page_size)
    for index = first, last do
        local id = settings.favorites[index]
        local city, value = cities.get(id), city_clock(id)
        if city then
            local y = top + (index - first) * (row_height + 6)
            local secondary = value and home_value and format_offset_difference(value, home_value) or "Unavailable"
            ui.row(12, y, width - 24, row_height, city.name, index == cursor,
                value and time.format_time(value.time, settings.use24) or "--:--", secondary)
            input.add("favorite_city:" .. id, 12, y, width - 24, row_height)
        end
    end
    local actions = {{id = "manage", label = "Manage"}, {id = "cities", label = "Cities"}}
    if #settings.favorites > favorite_page_size then actions[#actions + 1] = {id = "favorites_next", label = "More"} end
    add_actions(width, bottom, actions)
    punri.button_hints("Back", "Details", "Manage", "Cities")
end

local function draw_manage()
    local width, _, _, top, bottom = ui.content_bounds()
    punri.header("Manage favorites", "Up/Down moves")
    input.begin()
    local row_height = ui.row_height(false)
    if #settings.favorites == 0 then
        ui.message(16, top + 20, width - 32, "No favorites to manage.")
    end
    favorite_page_size = ui.rows_fit(top, bottom, row_height, MAX_FAVORITES)
    local first, last = ui.row_window(cursor, #settings.favorites, favorite_page_size)
    for index = first, last do
        local id = settings.favorites[index]
        local city = cities.get(id)
        local y = top + (index - first) * (row_height + 6)
        ui.row(12, y, width - 24, row_height, city.name, index == cursor, tostring(index))
        input.add("manage_city:" .. index, 12, y, width - 24, row_height)
    end
    add_actions(width, bottom, {
        {id = "remove", label = "Remove"},
        {id = "format", label = settings.use24 and "Use 12h" or "Use 24h"},
        {id = "favorites", label = "Done"},
    })
    punri.button_hints("Back", "Remove", "Format", "Move")
end

local function draw_chooser()
    local width, _, _, top, bottom = ui.content_bounds()
    punri.header(chooser_title or "Choose city")
    top = top + ui.message(16, top, width - 32, chooser_hint or "Markers are close together. Choose a city.") + 10
    input.begin()
    local row_height = ui.row_height(false)
    chooser_page_size = ui.rows_fit(top, bottom, row_height)
    local first, last = ui.row_window(cursor, #(chooser or {}), chooser_page_size)
    for index = first, last do
        local id = chooser[index]
        local city = cities.get(id)
        local y = top + (index - first) * (row_height + 6)
        ui.row(12, y, width - 24, row_height, city.name, index == cursor, city.zone)
        input.add("choose:" .. id, 12, y, width - 24, row_height)
    end
    local actions = {{id = "map_view", label = "Cancel"}}
    if #(chooser or {}) > chooser_page_size then actions[#actions + 1] = {id = "chooser_next", label = "More cities"} end
    add_actions(width, bottom, actions)
    punri.button_hints("Back", "Select", "Prev", "Next")
end

local function draw_save_error()
    local width, _, _, top, bottom = ui.content_bounds()
    punri.header("World Clock", "Save")
    top = top + 20
    top = top + ui.message(16, top, width - 32, state_notice or "SD save failed", 2) + 20
    ui.message(16, top, width - 32, "Your previous settings are still active. Retry while this app remains open.", 3)
    input.begin()
    add_actions(width, bottom, {{id = "cancel_save", label = "Cancel"}, {id = "retry_save", label = "Retry", selected = true}})
    punri.button_hints("Cancel", "Retry", "", "")
end

local function draw_storage_error()
    local width, _, _, top, bottom = ui.content_bounds()
    punri.header("World Clock", "Saved data")
    top = top + 16
    top = top + ui.message(16, top, width - 32, state_notice or "Saved settings unavailable", 2) + 18
    ui.message(16, top, width - 32, "The saved file was not erased. Use temporary settings, or repair it on SD before saving.", 4)
    input.begin()
    add_actions(width, bottom, {{id = "temporary", label = "Use temporary settings"}, {id = "exit", label = "Exit"}})
    punri.button_hints("Exit", "Temporary", "", "")
end

local function draw_current()
    if screen == "setup" then draw_setup()
    elseif screen == "map" then draw_map()
    elseif screen == "list" then draw_list()
    elseif screen == "detail" then draw_detail()
    elseif screen == "favorites" then draw_favorites()
    elseif screen == "manage" then draw_manage()
    elseif screen == "chooser" then draw_chooser()
    elseif screen == "save_error" then draw_save_error()
    else draw_storage_error() end
end

local function pick_city(id, destination)
    selected_id = id
    set_screen(destination or "detail")
end

local function open_chooser(ids, title, hint)
    chooser = ids
    chooser_title = title or "Choose city"
    chooser_hint = hint or "Markers are close together. Choose a city."
    screen, cursor, list_page = "chooser", 1, 1
    map_frame = nil
    request_draw()
end

local function handle_tap(action, x, y)
    if not action then return end
    if action == "map" then
        if not map_frame then return end
        local matches = map.hit(x, y, map_frame)
        if #matches == 1 then pick_city(matches[1], "detail")
        elseif #matches > 1 then
            open_chooser(matches, "Choose city", "Markers are close together. Choose a city.")
        else
            local region = map.region_at(x, y, map_frame)
            if region then open_chooser(region.city_ids, region.label, "Choose a common city in this time-zone region.") end
        end
    elseif action:match("^region:") then
        local region = cities.region(action:sub(#"region:" + 1))
        if region then open_chooser(region.city_ids, region.label, "Choose a common city in this time-zone region.") end
    elseif action == "cities" then set_screen("list")
    elseif action == "favorites" then set_screen("favorites")
    elseif action == "details" then set_screen("detail")
    elseif action == "map_view" then set_screen("map")
    elseif action == "list_next" then
        list_page = list_page % math.ceil(#cities.all / list_page_size) + 1
        cursor = (list_page - 1) * list_page_size + 1
        request_draw()
    elseif action == "setup_next" then
        list_page = list_page % math.ceil(#cities.all / setup_page_size) + 1
        cursor = (list_page - 1) * setup_page_size + 1
        request_draw()
    elseif action == "favorites_next" then
        cursor = ((cursor - 1) // favorite_page_size + 1) % math.ceil(#settings.favorites / favorite_page_size) * favorite_page_size + 1
        request_draw()
    elseif action == "chooser_next" then
        cursor = ((cursor - 1) // chooser_page_size + 1) % math.ceil(#chooser / chooser_page_size) * chooser_page_size + 1
        request_draw()
    elseif action == "favorite" then toggle_favorite()
    elseif action == "manage" then set_screen("manage")
    elseif action == "remove" then remove_favorite()
    elseif action == "format" then toggle_format()
    elseif action == "retry_save" then retry_save()
    elseif action == "cancel_save" then
        pending_settings, pending_after = nil, nil
        set_screen(return_screen or "map")
    elseif action == "temporary" then screen = "setup"; request_draw()
    elseif action == "exit" then punri.exit()
    else
        local id = action:match("^setup:(.+)$")
        if id then choose_home(id); return end
        id = action:match("^city:(.+)$")
        if id then pick_city(id, "detail"); return end
        id = action:match("^favorite_city:(.+)$")
        if id then pick_city(id, "detail"); return end
        id = action:match("^choose:(.+)$")
        if id then pick_city(id, "detail"); return end
        local index = action:match("^manage_city:(%d+)$")
        if index then cursor = tonumber(index); request_draw() end
    end
end

function on_init()
    map.load()
    load_state()
    refresh_snapshot(true)
end

function on_draw()
    ui.feedback.begin(screen)
    ui.feedback.focus = nil
    punri.clear()
    draw_current()
    local width, height = punri.get_bounds()
    local bh = math.max(36, punri.get_metrics().button_hints_height or 40)
    ui.button(3, height - bh, width // 2 - 6, bh - 3, "Back", false, "back")
    ui.feedback.finish()
end

-- Deliberately no on_touch: LuaAppActivity currently calls on_tap(x,y) and
-- then on_touch(x,y,"tap") for one physical contact.
function on_tap(x, y)
    handle_tap(input.hit(x, y), x, y)
end

function on_button(button, pressed)
    if not pressed then return end
    if button == "back" then
        if screen == "map" or screen == "setup" or screen == "storage_error" then
            punri.exit()
        elseif screen == "save_error" then
            pending_settings, pending_after = nil, nil
            set_screen(return_screen or "map")
        elseif screen == "detail" or screen == "chooser" then set_screen("map")
        elseif screen == "manage" then set_screen("favorites")
        else set_screen("map") end
        return
    end
    if screen == "setup" then
        if button == "confirm" then choose_home(cities.all[cursor].id)
        elseif button == "left" or button == "up" or button == "page_back" then move_list_cursor(-1, setup_page_size)
        elseif button == "right" or button == "down" or button == "page_forward" then move_list_cursor(1, setup_page_size) end
    elseif screen == "map" then
        if button == "confirm" then set_screen("detail")
        elseif button == "left" or button == "page_back" then select_previous(-1)
        elseif button == "right" then select_previous(1)
        elseif button == "up" then set_screen("favorites")
        elseif button == "down" or button == "page_forward" then set_screen("list") end
    elseif screen == "list" then
        if button == "confirm" then selected_id = cities.all[cursor].id; set_screen("detail")
        elseif button == "left" or button == "up" or button == "page_back" then move_list_cursor(-1, list_page_size)
        elseif button == "right" or button == "down" then move_list_cursor(1, list_page_size)
        elseif button == "page_forward" then list_page = list_page % math.ceil(#cities.all / list_page_size) + 1; cursor = (list_page - 1) * list_page_size + 1; request_draw() end
    elseif screen == "detail" then
        if button == "confirm" then toggle_favorite()
        elseif button == "left" or button == "up" then set_screen("list")
        elseif button == "right" or button == "down" then set_screen("map") end
    elseif screen == "favorites" then
        if button == "confirm" and settings.favorites[cursor] then selected_id = settings.favorites[cursor]; set_screen("detail")
        elseif button == "left" then
            set_screen("manage")
        elseif button == "up" then
            cursor = math.max(1, cursor - 1); request_draw()
        elseif button == "down" then
            cursor = math.min(#settings.favorites, cursor + 1); request_draw()
        elseif button == "right" or button == "page_forward" then set_screen("list") end
    elseif screen == "manage" then
        if button == "confirm" then remove_favorite()
        elseif button == "up" or button == "left" then move_favorite(-1)
        elseif button == "down" then move_favorite(1)
        elseif button == "right" then toggle_format()
        elseif button == "page_forward" then toggle_format() end
    elseif screen == "chooser" then
        if button == "confirm" and chooser and chooser[cursor] then pick_city(chooser[cursor], "detail")
        elseif button == "left" or button == "up" then cursor = math.max(1, cursor - 1); request_draw()
        elseif button == "right" or button == "down" then cursor = math.min(#chooser, cursor + 1); request_draw() end
    elseif screen == "save_error" and button == "confirm" then retry_save()
    elseif screen == "storage_error" and button == "confirm" then screen = "setup"; request_draw() end
end

function on_update()
    ui.feedback.update()
    -- The activity invokes on_update frequently, but only a changed UTC minute
    -- schedules a render.  Lua requests a redraw; LuaAppActivity owns the one
    -- actual e-ink refresh after that request.
    if refresh_snapshot(false) then request_draw() end
end

-- Geometry identities match the exact row/button rectangles; map taps remain map taps.
local input_add = input.add
input.add = function(id, x, y, w, h)
    ui.ids[id] = ui.key(x, y)
    input_add(id, x, y, w, h)
end
local tap_now, button_now = on_tap, on_button
function on_tap(x, y)
    local F = ui.feedback
    if F.busy() then return end
    local id = F.hit(x, y)
    if id == "back" then
        F.defer(id, function() button_now("back", true) end)
        return
    end
    local action = input.hit(x, y)
    if not id then tap_now(x, y); return end
    if action == "favorite" or action == "format" or action == "remove" or action == "retry_save"
        or action == "list_next" or action == "setup_next" or (action and action:match("^manage_city:")) then
        F.press(id); tap_now(x, y)
    else F.defer(id, function() tap_now(x, y) end) end
end
function on_button(button, pressed)
    local F = ui.feedback
    if not pressed or F.busy() then return end
    local id = button == "back" and "back" or nil
    if button == "confirm" then
        id = screen == "detail" and ui.ids.favorite or screen == "map" and ui.ids.details
            or screen == "manage" and ui.ids.remove or F.focus
    end
    local immediate = screen == "detail" or screen == "manage" or screen == "save_error"
    if id and not immediate then
        if F.defer(id, function() button_now(button, pressed) end) then return end
    else F.press(id) end
    button_now(button, pressed)
end
