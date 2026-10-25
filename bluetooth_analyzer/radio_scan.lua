-- Identical standalone copies in Wi-Fi Analyzer and Bluetooth Analyzer.
-- Allocate 32 mutable records once; bound BLE payloads to the API's 512 bytes.
local S = {rows = {}, channels = {}, count = 0, dropped = 0, capped = 0, invalid = 0,
    request = nil, cancelling = false, supported = false, simulated = false, status = "Ready", dirty = false}
local pool, name_parts, dropped_before = {}, {}, 0
local function stronger(a, b)
    if a.rssi ~= b.rssi then return a.rssi > b.rssi end
    return a.key < b.key
end

function S.valid_address(address)
    return type(address) == "string" and #address == 17 and
        address:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

-- Radio names are arbitrary bytes. Preserve valid UTF-8, replace controls and
-- malformed sequences, and keep the native name's 32-byte bound.
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
    if text:match("^%s*[=+@%-]") then text = "'" .. text end
    return '"' .. text:gsub('"', '""') .. '"'
end

function S.identity(address, address_type)
    return S.bluetooth and (address .. "/" .. tostring(address_type)) or address
end

function S.init(bluetooth)
    S.bluetooth = bluetooth
    for i = 1, 32 do pool[i] = {} end
    for i = 1, 14 do S.channels[i] = 0 end
    local api
    if bluetooth then api = ble else api = wifi end
    S.supported = type(radio) == "table" and type(api) == "table" and type(api.scan_start) == "function"
    if S.supported then
        local caps = radio.capabilities()
        S.supported, S.simulated = (bluetooth and caps.ble or not bluetooth and caps.wifi) == true, caps.simulated == true
    end
    if not S.supported then
        S.status = S.simulated and "Restart: RADIO_SIMULATION=1" or
            (bluetooth and "BLE unavailable in this build" or "Wi-Fi unavailable in this build")
    end
end

function S.start()
    if not S.supported or S.request then return false end
    local baseline = radio.stats().dropped or 0
    local id, error_code
    if S.bluetooth then
        id, error_code = ble.scan_start {timeout_ms = 5000, active = false, interval_ms = 100, window_ms = 50}
    else id, error_code = wifi.scan_start {timeout_ms = 10000} end
    if not id then
        S.error_code = error_code or "failed"
        S.status, S.dirty = "Cannot scan: " .. tostring(S.error_code), true
        radio.close() -- Never closes another activity's native radio ownership.
        punri.log("Radio scan request failed: " .. tostring(error_code))
        return false
    end
    for i = 1, #S.rows do S.rows[i] = nil end
    -- Drop old payload references even if a later scan sees fewer devices.
    for i = 1, 32 do pool[i].data = nil end
    for i = 1, 14 do S.channels[i] = 0 end
    S.count, S.dropped, S.capped, S.invalid = 0, 0, 0, 0
    dropped_before, S.error_code = baseline, nil
    S.request, S.cancelling, S.status, S.dirty = id, false, "Scanning...", true
    return true
end

local function integer(value, minimum, maximum)
    return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

local function observe(event)
    if not S.valid_address(event.address) or not integer(event.rssi, -127, 0) or
        (S.bluetooth and not integer(event.address_type, 0, 3)) or
        (not S.bluetooth and not integer(event.channel, 1, 14)) then
        S.invalid = S.invalid + 1
        return
    end
    local address, row = event.address:lower(), nil
    local key = S.identity(address, event.address_type)
    for _, existing in ipairs(S.rows) do if existing.key == key then row = existing; break end end
    if not row then
        if S.count == 32 then S.capped = S.capped + 1; return end
        S.count = S.count + 1
        row = pool[S.count]
        row.observations = 0
        S.rows[S.count] = row
    end
    row.key, row.address, row.name, row.rssi = key, address, S.safe_name(event.name), event.rssi
    row.observations = math.min(65535, row.observations + 1)
    if S.bluetooth then
        row.address_type, row.connectable = event.address_type, event.connectable == true
        row.advertisement_type = integer(event.advertisement_type, 0, 255) and event.advertisement_type or 0
        local data = type(event.data) == "string" and event.data or ""
        row.truncated = event.truncated == true or #data > 512
        row.data = #data > 512 and data:sub(1, 512) or data
    else row.channel, row.auth = event.channel, tonumber(event.status) or 0 end
    S.dirty = true
end

-- scan_complete is not terminal. Reuse only after the reserved complete/error.
function S.update()
    if not S.request then return nil end
    for _ = 1, 8 do
        local event = radio.poll()
        if not event then break end
        if event.id == S.request then
            if event.kind == (S.bluetooth and "advertisement" or "network") then observe(event)
            elseif event.kind == "complete" or event.kind == "error" then
                S.dropped = math.max(0, (radio.stats().dropped or 0) - dropped_before)
                table.sort(S.rows, stronger)
                if not S.bluetooth then
                    for _, row in ipairs(S.rows) do S.channels[row.channel] = S.channels[row.channel] + 1 end
                end
                local result = event.kind == "complete" and "complete" or tostring(event.error)
                if S.cancelling then result = "cancelled" end
                S.error_code = result ~= "complete" and result ~= "cancelled" and result or nil
                S.request, S.cancelling, S.dirty = nil, false, true
                S.status = result == "complete" and "Scan complete" or ("Scan: " .. result)
                if result ~= "complete" and result ~= "cancelled" then punri.log("Radio scan failed: " .. result) end
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

function S.find(address, address_type)
    local key = S.identity(address, address_type)
    for _, row in ipairs(S.rows) do if row.key == key then return row end end
end

return S
