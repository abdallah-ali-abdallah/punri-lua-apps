-- Marker coordinates are integer pixels in the 432x216 equirectangular
-- world.raw coordinate space. The source map and city coordinates share the
-- same longitude/latitude projection, so a marker remains on its continent.
local M = {}

M.map_width = 432
M.map_height = 216
M.all = {
    {id = "cairo", name = "Cairo", zone = "Africa/Cairo", x = 254, y = 72, region = "europe_africa"},
    {id = "london", name = "London", zone = "Europe/London", x = 216, y = 47, region = "europe_africa"},
    {id = "paris", name = "Paris", zone = "Europe/Paris", x = 219, y = 50, region = "europe_africa"},
    {id = "new_york", name = "New York", zone = "America/New_York", x = 128, y = 59, region = "americas"},
    {id = "toronto", name = "Toronto", zone = "America/Toronto", x = 122, y = 56, region = "americas"},
    {id = "los_angeles", name = "Los Angeles", zone = "America/Los_Angeles", x = 75, y = 68, region = "americas"},
    {id = "sao_paulo", name = "Sao Paulo", zone = "America/Sao_Paulo", x = 161, y = 137, region = "americas"},
    {id = "mexico_city", name = "Mexico City", zone = "America/Mexico_City", x = 98, y = 86, region = "americas"},
    {id = "dubai", name = "Dubai", zone = "Asia/Dubai", x = 282, y = 78, region = "west_asia_india"},
    {id = "riyadh", name = "Riyadh", zone = "Asia/Riyadh", x = 272, y = 78, region = "west_asia_india"},
    {id = "delhi", name = "Delhi", zone = "Asia/Kolkata", x = 309, y = 75, region = "west_asia_india"},
    {id = "kathmandu", name = "Kathmandu", zone = "Asia/Kathmandu", x = 318, y = 75, region = "west_asia_india"},
    {id = "bangkok", name = "Bangkok", zone = "Asia/Bangkok", x = 338, y = 92, region = "east_asia_pacific"},
    {id = "singapore", name = "Singapore", zone = "Asia/Singapore", x = 341, y = 107, region = "east_asia_pacific"},
    {id = "tokyo", name = "Tokyo", zone = "Asia/Tokyo", x = 384, y = 65, region = "east_asia_pacific"},
    {id = "sydney", name = "Sydney", zone = "Australia/Sydney", x = 398, y = 149, region = "east_asia_pacific"},
}

M.regions = {
    {id = "americas", label = "Americas", city_ids = {"los_angeles", "mexico_city", "new_york", "toronto", "sao_paulo"}, max_x = 111},
    {id = "europe_africa", label = "Europe / Africa", city_ids = {"london", "paris", "cairo"}, max_x = 172},
    {id = "west_asia_india", label = "West Asia / India", city_ids = {"riyadh", "dubai", "delhi", "kathmandu"}, max_x = 222},
    {id = "east_asia_pacific", label = "East Asia / Pacific", city_ids = {"bangkok", "singapore", "tokyo", "sydney"}, max_x = M.map_width},
}

M.by_id = {}
for _, city in ipairs(M.all) do M.by_id[city.id] = city end

M.regions_by_id = {}
for _, region in ipairs(M.regions) do M.regions_by_id[region.id] = region end

function M.get(id)
    return M.by_id[id]
end

function M.region(id)
    return M.regions_by_id[id]
end

function M.contains(ids, id)
    for _, current in ipairs(ids or {}) do if current == id then return true end end
    return false
end

function M.copy_settings(value)
    local copy = {home = value.home, use24 = value.use24, favorites = {}}
    for i, id in ipairs(value.favorites or {}) do copy.favorites[i] = id end
    return copy
end

return M
