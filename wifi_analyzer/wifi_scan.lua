-- Shared scan state; keep the Wi-Fi Analyzer and Signal Meter copies identical.
-- 32 reusable AP records bound app memory. SDK queue overflow is reported separately.
local S = {rows = {}, channels = {}, count = 0, dropped = 0, capped = 0, invalid = 0,
    request = nil, cancelling = false, supported = false, simulated = false, status = "Ready", dirty = false}
local pool, name_parts, dropped_before = {}, {}, 0
local function stronger(a, b)
    if a.rssi ~= b.rssi then return a.rssi > b.rssi end
    return a.address < b.address
end

function S.valid_address(address)
    return type(address) == "string" and #address == 17 and
        address:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

-- SSIDs are arbitrary bytes, not guaranteed UTF-8. Replace invalid/control bytes
-- before passing them to the renderer; do not turn a broadcast name into UI markup.
function S.safe_name(name)
    name = type(name) == "string" and name:sub(1, 32) or ""
    local parts, at = name_parts, 1
    for i = 1, #parts do parts[i] = nil end
    while at <= #name do
        local b = name:byte(at)
        local n = b < 128 and 1 or (b >= 194 and b <= 223 and 2 or
            (b >= 224 and b <= 239 and 3 or (b >= 240 and b <= 244 and 4 or 0)))
        local valid = n > 0 and at + n - 1 <= #name
        for i = 1, n - 1 do
            local c = name:byte(at + i) or 0
            if c < 128 or c > 191 then valid = false end
        end
        local second = name:byte(at + 1) or 0
        if (b == 224 and second < 160) or (b == 237 and second > 159) or
            (b == 240 and second < 144) or (b == 244 and second > 143) then valid = false end
        if valid then
            parts[#parts + 1] = (b < 32 or b == 127) and " " or name:sub(at, at + n - 1)
            at = at + n
        else parts[#parts + 1] = "?"; at = at + 1 end
    end
    return table.concat(parts)
end

function S.csv(value)
    local text = tostring(value)
    -- Quoting alone does not prevent spreadsheet formula injection from SSIDs.
    if text:match("^%s*[=+@%-]") then text = "'" .. text end
    return '"' .. text:gsub('"', '""') .. '"'
end

function S.init()
    for i = 1, 32 do pool[i] = {} end
    for i = 1, 14 do S.channels[i] = 0 end
    S.supported = type(radio) == "table" and type(wifi) == "table" and type(wifi.scan_start) == "function"
    if S.supported then
        local caps = radio.capabilities()
        S.supported, S.simulated = caps.wifi == true, caps.simulated == true
    end
    if not S.supported then S.status = "Wi-Fi unavailable in this build" end
end

function S.start()
    if not S.supported then return false end
    if S.request then return false end
    local baseline = radio.stats().dropped or 0
    local id, error_code = wifi.scan_start {timeout_ms = 10000}
    if not id then
        S.status, S.dirty = "Cannot scan: " .. tostring(error_code), true
        radio.close() -- Only the app's session is closed, never another activity's Wi-Fi.
        punri.log("Wi-Fi scan request failed: " .. tostring(error_code))
        return false
    end
    for i = 1, #S.rows do S.rows[i] = nil end
    for i = 1, 14 do S.channels[i] = 0 end
    S.count, S.dropped, S.capped, S.invalid = 0, 0, 0, 0
    dropped_before = baseline
    S.request, S.cancelling, S.status, S.dirty = id, false, "Scanning...", true
    return true
end

local function observe(event)
    if not S.valid_address(event.address) or type(event.rssi) ~= "number" or
        event.rssi % 1 ~= 0 or event.rssi < -127 or event.rssi > 0 or
        type(event.channel) ~= "number" or event.channel % 1 ~= 0 or event.channel < 1 or event.channel > 14 then
        S.invalid = S.invalid + 1
        return
    end
    local address, row = event.address:lower(), nil
    for _, existing in ipairs(S.rows) do if existing.address == address then row = existing; break end end
    if not row then
        if S.count == 32 then S.capped = S.capped + 1; return end
        S.count = S.count + 1
        row = pool[S.count]
        S.rows[S.count] = row
    end
    row.address, row.name, row.rssi, row.channel = address, S.safe_name(event.name), event.rssi, event.channel
    row.auth = tonumber(event.status) or 0
    S.dirty = true
end

-- Return only after consuming the reserved complete/error event. scan_complete
-- is an observation and can be dropped; it is not permission to start a new scan.
function S.update()
    if not S.request then return nil end
    for _ = 1, 8 do
        local event = radio.poll()
        if not event then break end
        if event.id == S.request then
            if event.kind == "network" then observe(event)
            elseif event.kind == "complete" or event.kind == "error" then
                S.dropped = math.max(0, (radio.stats().dropped or 0) - dropped_before)
                table.sort(S.rows, stronger)
                for _, row in ipairs(S.rows) do S.channels[row.channel] = S.channels[row.channel] + 1 end
                local result = event.kind == "complete" and "complete" or tostring(event.error)
                if S.cancelling then result = "cancelled" end
                S.request, S.cancelling, S.dirty = nil, false, true
                S.status = result == "complete" and "Scan complete" or ("Scan: " .. result)
                if event.kind == "error" and result ~= "cancelled" then punri.log("Wi-Fi scan failed: " .. result) end
                return result
            end
        end
    end
end

function S.partial()
    return S.dropped > 0 or S.capped > 0 or S.invalid > 0
end

function S.cancel()
    if S.request and not S.cancelling then
        radio.cancel()
        S.cancelling, S.status, S.dirty = true, "Cancelling...", true
    end
end

function S.close()
    if type(radio) == "table" and type(radio.close) == "function" then radio.close() end
    S.request, S.cancelling = nil, false
end

function S.find(address)
    for _, row in ipairs(S.rows) do if row.address == address then return row end end
end

return S
