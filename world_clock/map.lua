local cities = punri.dofile("cities.lua")

local M = {width = cities.map_width, height = cities.map_height, asset_error = false}
local bitmap = nil
local BYTES = M.width * M.height / 8
local HIT_RADIUS = 11
local SIDE_MARGIN = 12
local SELECTOR_GAP = 8
local SELECTOR_HEIGHT = 30

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
        frame.y = math.floor((top + bottom - M.height) / 2)
        local side_width = math.max(104, math.floor((screen_width - M.width) / 2) - 2 * SIDE_MARGIN)
        local left_x, right_x = SIDE_MARGIN, screen_width - SIDE_MARGIN - side_width
        local first_y = frame.y + 22
        for index, region in ipairs(cities.regions) do
            local left_column = index <= 2
            frame.selectors[index] = {
                region = region,
                x = left_column and left_x or right_x,
                y = first_y + ((index - 1) % 2) * (SELECTOR_HEIGHT + SELECTOR_GAP),
                w = side_width,
                h = SELECTOR_HEIGHT,
            }
        end
    else
        local selector_rows = 2 * SELECTOR_HEIGHT + SELECTOR_GAP
        local selector_top = bottom - 44 - selector_rows
        frame.y = math.floor((top + selector_top - M.height) / 2)
        local selector_width = math.floor((screen_width - 2 * SIDE_MARGIN - SELECTOR_GAP) / 2)
        local first_y = frame.y + M.height + SELECTOR_GAP
        for index, region in ipairs(cities.regions) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            frame.selectors[index] = {
                region = region,
                x = SIDE_MARGIN + column * (selector_width + SELECTOR_GAP),
                y = first_y + row * (SELECTOR_HEIGHT + SELECTOR_GAP),
                w = selector_width,
                h = SELECTOR_HEIGHT,
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
        local outer = city.id == selected_id and 6 or 4
        local inner = city.id == selected_id and 4 or 2
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
