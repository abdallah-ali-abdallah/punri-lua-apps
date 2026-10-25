-- Local SD app; radio access uses the functional modules.
local display = ink
local rows, mode, request_id = {}, "BLE", nil
local status, simulated, dropped = "Ready", false, 0
local dirty, last_redraw = true, 0

local function redraw() dirty = true; display.request_update() end
local function stop()
    dropped = radio.stats().dropped
    radio.close()
    request_id = nil
end
local function start()
    stop()
    rows, dropped = {}, 0
    local caps = radio.capabilities()
    simulated = caps.simulated
    if (mode == "BLE" and not caps.ble) or (mode == "Wi-Fi" and not caps.wifi) then
        status = "Unavailable in this build"
    else
        local error_code
        if mode == "BLE" then request_id, error_code = ble.scan_start {timeout_ms=5000}
        else request_id, error_code = wifi.scan_start {timeout_ms=10000} end
        status = request_id and "Scanning" or error_code
    end
    redraw()
end
local function observe(event)
    local key = event.address .. ":" .. event.address_type
    local index
    for i, row in ipairs(rows) do if row.key == key then index=i; break end end
    if not index then
        if #rows >= 24 then return end
        index = #rows + 1
        rows[index] = {key=key}
    end
    local row = rows[index]
    row.name = event.name ~= "" and event.name or event.address
    row.rssi = event.rssi
    row.detail = event.kind == "network" and ("Channel " .. event.channel) or
        (event.truncated and "Truncated advertisement" or ble.classify(event.data))
    dirty = true
end
function on_init()
    local caps = radio.capabilities()
    mode = caps.ble and "BLE" or "Wi-Fi"
    simulated = caps.simulated
    redraw()
end
function on_update()
    if request_id then
        for i=1,8 do
            local event = radio.poll()
            if not event then break end
            if event.kind == "advertisement" or event.kind == "network" then observe(event)
            elseif event.kind == "complete" or event.kind == "error" then
                status = event.kind == "complete" and "Complete" or event.error
                stop(); redraw(); break
            end
        end
    end
    local now = display.millis()
    if dirty and now-last_redraw >= 750 then
        display.request_update(); last_redraw=now; dirty=false
    end
end
function on_draw()
    display.clear()
    local width, height = display.get_bounds()
    display.header("Radio Scanner", (simulated and "SIMULATED / " or "") .. mode .. " / " .. status)
    local y = 100
    for _, row in ipairs(rows) do
        if y+65 > height-75 then break end
        display.text(20, y, row.name, "ui12")
        display.text(20, y+22, row.rssi .. " dBm / " .. row.detail, "small")
        y = y+65
    end
    if #rows == 0 then display.text(20, y, "No observations", "ui12") end
    display.text(20, height-85, #rows .. " observations / " .. dropped .. " dropped", "small")
    display.button_hints("Exit", request_id and "Cancel" or "Scan", "BLE", "Wi-Fi")
end
function on_button(button, pressed)
    if not pressed then return end
    if button == "back" then stop(); display.exit()
    elseif button == "confirm" then if request_id then radio.cancel() else start() end
    elseif button == "up" or button == "left" then stop(); mode="BLE"; status="Ready"; rows={}; redraw()
    elseif button == "down" or button == "right" then stop(); mode="Wi-Fi"; status="Ready"; rows={}; redraw() end
end
function on_tap(x,y)
    local width, height = display.get_bounds()
    if y < height/2 then on_button(mode == "BLE" and "down" or "up",true)
    else on_button("confirm",true) end
end
function on_exit() stop() end
