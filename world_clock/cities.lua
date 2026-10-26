-- Marker coordinates are integer pixels in the 400x200 equirectangular
-- world.raw coordinate space. The source map and city coordinates share the
-- same longitude/latitude projection, so a marker remains on its continent.
local M = {}

M.map_width = 400
M.map_height = 200
M.all = {
    {id = "cairo", name = "Cairo", zone = "Africa/Cairo", x = 234, y = 67, region = "europe_africa"},
    {id = "london", name = "London", zone = "Europe/London", x = 200, y = 43, region = "europe_africa"},
    {id = "paris", name = "Paris", zone = "Europe/Paris", x = 203, y = 46, region = "europe_africa"},
    {id = "new_york", name = "New York", zone = "America/New_York", x = 118, y = 54, region = "americas"},
    {id = "toronto", name = "Toronto", zone = "America/Toronto", x = 112, y = 52, region = "americas"},
    {id = "los_angeles", name = "Los Angeles", zone = "America/Los_Angeles", x = 69, y = 62, region = "americas"},
    {id = "sao_paulo", name = "Sao Paulo", zone = "America/Sao_Paulo", x = 148, y = 126, region = "americas"},
    {id = "mexico_city", name = "Mexico City", zone = "America/Mexico_City", x = 90, y = 79, region = "americas"},
    {id = "dubai", name = "Dubai", zone = "Asia/Dubai", x = 261, y = 72, region = "west_asia_india"},
    {id = "riyadh", name = "Riyadh", zone = "Asia/Riyadh", x = 252, y = 72, region = "west_asia_india"},
    {id = "delhi", name = "Delhi", zone = "Asia/Kolkata", x = 286, y = 69, region = "west_asia_india"},
    {id = "kathmandu", name = "Kathmandu", zone = "Asia/Kathmandu", x = 295, y = 69, region = "west_asia_india"},
    {id = "bangkok", name = "Bangkok", zone = "Asia/Bangkok", x = 312, y = 85, region = "east_asia_pacific"},
    {id = "singapore", name = "Singapore", zone = "Asia/Singapore", x = 315, y = 99, region = "east_asia_pacific"},
    {id = "tokyo", name = "Tokyo", zone = "Asia/Tokyo", x = 355, y = 60, region = "east_asia_pacific"},
    {id = "sydney", name = "Sydney", zone = "Australia/Sydney", x = 368, y = 138, region = "east_asia_pacific"},
}

M.regions = {
    {id = "americas", label = "Americas", city_ids = {"los_angeles", "mexico_city", "new_york", "toronto", "sao_paulo"}, max_x = 154},
    {id = "europe_africa", label = "Europe / Africa", city_ids = {"london", "paris", "cairo"}, max_x = 239},
    {id = "west_asia_india", label = "West Asia / India", city_ids = {"riyadh", "dubai", "delhi", "kathmandu"}, max_x = 309},
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
