local cities = punri.dofile("cities.lua")

local M = {width = cities.map_width, height = cities.map_height, asset_error = false}
local bitmap = nil
local BYTES = M.width * M.height / 8
local HIT_RADIUS = 9

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

function M.origin(screen_width, top, bottom)
    return math.floor((screen_width - M.width) / 2), math.floor((top + bottom - M.height) / 2)
end

function M.draw(x, y, selected_id)
    if bitmap then punri.draw_sprite(x, y, M.width, M.height, bitmap) end
    for _, city in ipairs(cities.all) do
        local mx, my = x + city.x, y + city.y
        if city.id == selected_id then
            punri.invert_rect(mx - 4, my - 4, 9, 9)
            punri.rect(mx - 4, my - 4, 9, 9, false, 1, true)
        else
            punri.circle(mx, my, 2, true, 1, true)
        end
    end
end

-- Return every in-radius marker.  Closely placed cities deliberately produce
-- a chooser; a far-away tap never selects an arbitrary nearest city.
function M.hit(x, y, map_x, map_y)
    local candidates = {}
    local limit = HIT_RADIUS * HIT_RADIUS
    for _, city in ipairs(cities.all) do
        local dx, dy = x - (map_x + city.x), y - (map_y + city.y)
        if dx * dx + dy * dy <= limit then candidates[#candidates + 1] = city.id end
    end
    return candidates
end

return M
