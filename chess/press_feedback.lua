-- Shared, bounded press state. The packaged copy lives inside each app sandbox.
-- One active visual and one optional navigation callback; never an input queue.
local F = {duration = 500, MAX_TARGETS = 192, targets = {}, count = 0}
local view, active, started, painted, pending

local function redraw() punri.request_update() end
local function find(id)
    for i = F.count, 1, -1 do
        local t = F.targets[i]
        if t.id == id then return t end
    end
end

function F.clear()
    active, started, painted, pending = nil, nil, false, nil
end

function F.begin(key)
    if view ~= key then F.clear(); view = key end
    F.count, painted = 0, false
end

function F.target(id, x, y, w, h, enabled, shape, radius, dark)
    if id == nil or w <= 0 or h <= 0 or F.count >= F.MAX_TARGETS then return false end
    F.count = F.count + 1
    local t = F.targets[F.count]
    if not t then t = {}; F.targets[F.count] = t end
    t.id, t.x, t.y, t.w, t.h = id, x, y, w, h
    t.enabled, t.shape, t.radius, t.dark = enabled ~= false, shape or "rounded", radius or 6, dark == true
    return active == id and t.enabled
end

function F.hit(x, y)
    if pending then return nil end
    for i = F.count, 1, -1 do
        local t = F.targets[i]
        local inside = x >= t.x and x < t.x + t.w and y >= t.y and y < t.y + t.h
        if inside and t.shape == "circle" then
            local rx, ry = t.w / 2, t.h / 2
            inside = ((x - t.x - rx) / rx)^2 + ((y - t.y - ry) / ry)^2 <= 1
        end
        if t.enabled and inside then return t.id end
    end
end

function F.press(id)
    local t = find(id)
    if pending or not t or not t.enabled then return false end
    active, started, painted = id, nil, false
    redraw()
    return true
end

function F.active(id) return active ~= nil and (id == nil or active == id) end
function F.busy() return pending ~= nil end

-- A bounded callback is used only when the current surface must remain visible
-- before navigating. Gameplay, timers and HID commands execute immediately.
function F.defer(id, callback)
    if type(callback) ~= "function" or not F.press(id) then return false end
    pending = callback
    return true
end

local function dither(x, y, w, h)
    if w <= 0 or h <= 0 then return end
    if punri.rect_dither then punri.rect_dither(x, y, w, h, false)
    else
        -- Compatibility with older API implementations: same light checkerboard.
        punri.rect(x, y, w, h, true, false)
        for py = y, y + h - 1 do
            for px = x + py % 2, x + w - 1, 2 do punri.pixel(px, py, true) end
        end
    end
end

local function gray_shape(t)
    local x, y, w, h = math.floor(t.x), math.floor(t.y), math.floor(t.w), math.floor(t.h)
    if t.shape == "rect" then dither(x, y, w, h); return end
    local r = math.floor(math.min(t.radius, w / 2, h / 2))
    if t.shape == "circle" then
        local rx, ry = w / 2, h / 2
        for row = 0, h - 1 do
            local dy = (row + 0.5 - ry) / ry
            local half = rx * math.sqrt(math.max(0, 1 - dy * dy))
            local left, right = math.ceil(rx - half), math.floor(rx + half)
            dither(x + left, y + row, right - left, 1)
        end
        return
    end
    if r <= 0 then dither(x, y, w, h); return end
    dither(x, y + r, w, h - 2 * r)
    for row = 0, r - 1 do
        local dy = r - row - 0.5
        local inset = math.ceil(r - math.sqrt(math.max(0, r * r - dy * dy)))
        dither(x + inset, y + row, w - inset * 2, 1)
        dither(x + inset, y + h - row - 1, w - inset * 2, 1)
    end
end

-- Paint after the normal background and before drawing its text or icon.
-- Returns the foreground color so an already-black button has visible feedback.
function F.paint(id)
    local t = find(id)
    if active ~= id or not t or not t.enabled then return nil end
    painted = true
    if t.dark then gray_shape(t); return true end
    if t.shape == "circle" then
        punri.circle(t.x + t.w / 2, t.y + t.h / 2, math.min(t.w, t.h) / 2, true, 1, true)
    elseif t.shape == "rect" then punri.rect(t.x, t.y, t.w, t.h, true, true)
    else punri.rounded_rect(t.x, t.y, t.w, t.h, t.radius, true, 1, true) end
    return false
end

function F.finish()
    local target = active and find(active)
    if active and (not target or not target.enabled) then F.clear(); return end
    if active and painted and started == nil then started = punri.millis() end
end

function F.update()
    if not active or started == nil then return false end
    -- Integer subtraction wraps on the firmware's 32-bit Lua runtime. Mask the
    -- short delta, avoiding float conversion or a large future deadline.
    local elapsed = (punri.millis() - started) & 0x7fffffff
    if elapsed < F.duration then return false end
    local callback = pending
    F.clear()
    redraw()
    if callback then callback() end
    return true
end

function F.button(id, x, y, w, h, label, font, dark, enabled, radius)
    font, radius = font or "small", radius or 6
    F.target(id, x, y, w, h, enabled, "rounded", radius, dark)
    punri.rounded_rect(x, y, w, h, radius, true, 1, false)
    punri.rounded_rect(x, y, w, h, radius, dark == true, 1, true)
    local ink = F.paint(id)
    if ink == nil then ink = dark ~= true end
    punri.text(x + w // 2, y + math.max(0, (h - punri.line_height(font)) // 2), label,
        font, "bold", "center", ink)
    return F.active(id)
end

function F.footer(labels, ids)
    local w, h = punri.get_bounds()
    local metrics = punri.get_metrics()
    local bh = math.max(36, metrics.button_hints_height or 40)
    local columns = (not labels[3] or labels[3] == "") and (not labels[4] or labels[4] == "") and 2 or 4
    for i = 1, columns do
        local label = labels[i]
        if label and label ~= "" then
            local x, right = ((i - 1) * w) // columns + 3, (i * w) // columns - 3
            F.button(ids and ids[i] or i, x, h - bh, right - x, bh - 3, label, "small", false, true, 5)
        end
    end
end

return F
