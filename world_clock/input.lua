-- One tap is delivered as both on_tap and on_touch by current firmware.  The
-- application registers hit rectangles here and exposes only on_tap, avoiding
-- a duplicate user action while retaining button access on X4 Classic.
local M = {}
local hits = {}

function M.begin()
    hits = {}
end

function M.add(id, x, y, w, h)
    hits[#hits + 1] = {id = id, x = x, y = y, w = w, h = h}
end

function M.hit(x, y)
    for index = #hits, 1, -1 do
        local item = hits[index]
        if punri.in_rect(x, y, item.x, item.y, item.w, item.h) then return item.id end
    end
    return nil
end

return M
