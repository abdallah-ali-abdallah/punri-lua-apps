local cities = punri.dofile("cities.lua")

local M = {width = cities.map_width, height = cities.map_height, asset_error = false}
local bitmap = nil
local BYTES = M.width * M.height / 8
local HIT_RADIUS = 14
local SIDE_MARGIN = 12
local SELECTOR_GAP = 10
local PORTRAIT_SELECTOR_HEIGHT = 48
local LANDSCAPE_SELECTOR_HEIGHT = 42

function M.load()
    local candidate = punri.read_file("world.raw", BYTES)
    if type(candidate) == "string" and #candidate == BYTES then
        bitmap = candidate
        M.asset_error = false
    else
        bitmap = nil
        M.asset_error = true
    end
end

-- Drawing and hit testing receive this same frame, so a marker is never
-- painted in one position while the touch target is calculated elsewhere.
function M.layout(screen_width, screen_height, top, bottom)
    local frame = {width = M.width, height = M.height, selectors = {}}
    frame.x = math.floor((screen_width - M.width) / 2)
    if screen_width > screen_height then
        frame.x = SIDE_MARGIN
        frame.y = math.floor((top + bottom - M.height) / 2)
        local side_width = screen_width - M.width - 3 * SIDE_MARGIN
        local first_x = frame.x + M.width + SIDE_MARGIN
        local selector_block = #cities.regions * LANDSCAPE_SELECTOR_HEIGHT +
            (#cities.regions - 1) * SELECTOR_GAP
        local first_y = frame.y + math.floor((M.height - selector_block) / 2)
        for index, region in ipairs(cities.regions) do
            frame.selectors[index] = {
                region = region,
                x = first_x,
                y = first_y + (index - 1) * (LANDSCAPE_SELECTOR_HEIGHT + SELECTOR_GAP),
                w = side_width,
                h = LANDSCAPE_SELECTOR_HEIGHT,
            }
        end
    else
        local selector_block = #cities.regions * PORTRAIT_SELECTOR_HEIGHT +
            (#cities.regions - 1) * SELECTOR_GAP
        local total_height = M.height + SELECTOR_GAP + selector_block
        frame.y = top + math.max(0, math.floor((bottom - top - total_height) / 2))
        local selector_width = screen_width - 2 * SIDE_MARGIN
        local first_y = frame.y + M.height + SELECTOR_GAP
        for index, region in ipairs(cities.regions) do
            frame.selectors[index] = {
                region = region,
                x = SIDE_MARGIN,
                y = first_y + (index - 1) * (PORTRAIT_SELECTOR_HEIGHT + SELECTOR_GAP),
                w = selector_width,
                h = PORTRAIT_SELECTOR_HEIGHT,
            }
        end
    end
    return frame
end

function M.draw(frame, selected_id)
    if bitmap then punri.draw_sprite(frame.x, frame.y, M.width, M.height, bitmap) end
    for _, city in ipairs(cities.all) do
        local mx, my = frame.x + city.x, frame.y + city.y
        -- Black-outline/white-center pins remain visible on ocean and land.
        local outer = city.id == selected_id and 8 or 5
        local inner = city.id == selected_id and 5 or 3
        punri.circle(mx, my, outer, true, true)
        punri.circle(mx, my, inner, true, false)
        if city.id == selected_id then punri.circle(mx, my, 2, true, true) end
    end
end

-- Return every in-radius marker. Closely placed cities deliberately produce
-- a chooser; a far-away map tap selects its visible time-zone region instead.
function M.hit(x, y, frame)
    local candidates = {}
    local limit = HIT_RADIUS * HIT_RADIUS
    for _, city in ipairs(cities.all) do
        local dx, dy = x - (frame.x + city.x), y - (frame.y + city.y)
        if dx * dx + dy * dy <= limit then candidates[#candidates + 1] = city.id end
    end
    return candidates
end

function M.region_at(x, y, frame)
    if x < frame.x or x >= frame.x + M.width or y < frame.y or y >= frame.y + M.height then return nil end
    local relative_x = x - frame.x
    for _, region in ipairs(cities.regions) do
        if relative_x < region.max_x then return region end
    end
    return nil
end

return M
