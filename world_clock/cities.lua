-- Marker coordinates are integer pixels in the 288x144 equirectangular
-- world.raw coordinate space. They are not recalculated from longitude at
-- runtime, so changing the source map requires updating these documented
-- coordinates together with it.
local M = {}

M.map_width = 288
M.map_height = 144
M.all = {
    {id = "cairo", name = "Cairo", zone = "Africa/Cairo", x = 169, y = 48},
    {id = "london", name = "London", zone = "Europe/London", x = 144, y = 31},
    {id = "paris", name = "Paris", zone = "Europe/Paris", x = 146, y = 34},
    {id = "new_york", name = "New York", zone = "America/New_York", x = 85, y = 40},
    {id = "toronto", name = "Toronto", zone = "America/Toronto", x = 82, y = 37},
    {id = "los_angeles", name = "Los Angeles", zone = "America/Los_Angeles", x = 49, y = 45},
    {id = "sao_paulo", name = "Sao Paulo", zone = "America/Sao_Paulo", x = 103, y = 90},
    {id = "mexico_city", name = "Mexico City", zone = "America/Mexico_City", x = 61, y = 57},
    {id = "dubai", name = "Dubai", zone = "Asia/Dubai", x = 188, y = 57},
    {id = "riyadh", name = "Riyadh", zone = "Asia/Riyadh", x = 187, y = 55},
    {id = "delhi", name = "Delhi", zone = "Asia/Kolkata", x = 205, y = 49},
    {id = "kathmandu", name = "Kathmandu", zone = "Asia/Kathmandu", x = 212, y = 49},
    {id = "bangkok", name = "Bangkok", zone = "Asia/Bangkok", x = 220, y = 62},
    {id = "singapore", name = "Singapore", zone = "Asia/Singapore", x = 222, y = 71},
    {id = "tokyo", name = "Tokyo", zone = "Asia/Tokyo", x = 255, y = 43},
    {id = "sydney", name = "Sydney", zone = "Australia/Sydney", x = 260, y = 98},
}

M.by_id = {}
for _, city in ipairs(M.all) do M.by_id[city.id] = city end

function M.get(id)
    return M.by_id[id]
end

function M.contains(ids, id)
    for _, current in ipairs(ids or {}) do
        if current == id then return true end
    end
    return false
end

function M.copy_settings(value)
    local copy = {home = value.home, use24 = value.use24, favorites = {}}
    for i, id in ipairs(value.favorites or {}) do copy.favorites[i] = id end
    return copy
end

return M
