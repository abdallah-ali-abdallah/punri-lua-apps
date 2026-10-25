-- Foreground Wi-Fi discovery: no connection, passwords or packet capture.
local scan = punri.dofile("wifi_scan.lua")
local ui = punri.dofile("wifi_ui.lua")
local screen, focus, detail_address, notice = "networks", 2, nil, ""
local last_redraw, snapshot_complete = 0, false
local labels = {"Exit", "Scan", "Channels", "Export"}

local function refresh()
    punri.request_update()
    last_redraw, scan.dirty = punri.millis(), false
end

local function start_scan()
    notice = ""
    if scan.request then scan.cancel()
    elseif scan.start() then
        snapshot_complete, screen, focus = false, "networks", 2
    end
end

local function export()
    if scan.request or not snapshot_complete then notice = "Finish a successful scan before exporting"; return end
    local parts = {"ssid,bssid,rssi_dbm,channel,auth_code,simulated,dropped,capped,invalid\n"}
    for _, row in ipairs(scan.rows) do
        parts[#parts + 1] = string.format("%s,%s,%d,%d,%d,%s,%d,%d,%d\n", scan.csv(row.name),
            scan.csv(row.address), row.rssi, row.channel, row.auth, tostring(scan.simulated),
            scan.dropped, scan.capped, scan.invalid)
    end
    -- At most 32 short AP records; build once for this explicit SD operation.
    if punri.write_file("last_scan.csv", table.concat(parts)) then notice = "Saved last_scan.csv to SD"
    else notice = "SD export failed. Retry."; punri.log("Wi-Fi Analyzer: SD export failed") end
end

local function activate(index)
    notice = ""
    if index == 1 then
        if screen == "networks" then scan.close(); punri.exit()
        else screen, focus = "networks", 2 end
    elseif index == 2 then start_scan()
    elseif index == 3 then
        screen = screen == "networks" and "channels" or "networks"
        focus = 3
    elseif index == 4 then export()
    elseif screen == "networks" and scan.rows[index - 4] then
        if scan.request then notice = "Wait for scan completion"
        else detail_address, screen, focus = scan.rows[index - 4].address, "detail", 1 end
    end
    refresh()
end

local function draw_channels()
    punri.centered_text(ui.body, "Observed access points per channel", "ui12", "bold")
    local x, width = ui.margin + 8, ui.w - ui.margin * 2 - 16
    local y, height = ui.body + 42, math.min(220, ui.bottom - ui.body - 112)
    local maximum = 1
    for channel = 1, 14 do maximum = math.max(maximum, scan.channels[channel]) end
    local step = width / 14
    punri.line(x, y + height, x + width, y + height)
    for channel = 1, 14 do
        local count = scan.channels[channel]
        local bar = math.floor(count / maximum * (height - 24))
        local bx = x + math.floor((channel - 1) * step)
        if bar > 0 then punri.rect(bx + 3, y + height - bar, math.max(2, math.floor(step) - 6), bar, true) end
        punri.text(bx + math.floor(step / 2), y + height + 6, tostring(channel), "small", "regular", "center")
        if count > 0 then punri.text(bx + math.floor(step / 2), y + height - bar - 20,
            tostring(count), "small", "bold", "center") end
    end
    punri.centered_text(y + height + 32, "Counts are not RF congestion or airtime measurements.", "small")
end

local function draw_detail()
    local row = scan.find(detail_address)
    if not row then punri.centered_text(ui.body + 32, "No current observation", "ui12"); return end
    punri.centered_text(ui.body, ui.clip(row.name ~= "" and row.name or "(hidden SSID)", ui.w - ui.margin * 2),
        "ui12", "bold")
    punri.centered_text(ui.body + 34, row.address, "small")
    local height = math.min(90, math.floor((ui.bottom - ui.body - 160) / 2))
    ui.meter(row.rssi, ui.body + 62, height)
    punri.centered_text(ui.body + 66 + height, "dBm / " .. ui.quality(row.rssi), "ui12", "bold")
    punri.centered_text(ui.body + 104 + height, "Channel " .. tostring(row.channel) .. "  /  Auth code " .. tostring(row.auth), "small")
end

function on_init()
    ui.layout()
    scan.init()
    refresh()
end

function on_update()
    local result = scan.update()
    if result then
        snapshot_complete = result == "complete"
        if snapshot_complete and #scan.rows > 0 and screen == "networks" then focus = 5 end
        scan.close() -- Single scans do not keep Wi-Fi resident while reading the result.
        refresh()
    elseif scan.dirty and punri.millis() - last_redraw >= 1000 then refresh() end
end

function on_draw()
    ui.begin("Wi-Fi Analyzer", scan.simulated)
    labels[1] = screen == "networks" and "Exit" or "Back"
    labels[2] = scan.request and (scan.cancelling and "Wait" or "Cancel") or "Scan"
    labels[3] = screen == "networks" and "Channels" or "Networks"
    ui.toolbar(labels, focus)
    ui.status(notice ~= "" and notice or scan.status)
    if screen == "channels" then draw_channels()
    elseif screen == "detail" then draw_detail()
    else ui.networks(scan.rows, focus) end
    local summary = tostring(scan.count) .. " APs  /  " .. tostring(scan.dropped) .. " dropped"
    if scan.capped > 0 or scan.invalid > 0 then summary = summary .. "  /  " .. tostring(scan.capped) .. " capped / " .. tostring(scan.invalid) .. " invalid" end
    if scan.partial() then summary = "PARTIAL: " .. summary end
    if screen == "networks" and #scan.rows > 0 then summary = summary .. "  /  Page " .. tostring(math.ceil(ui.first(focus) / ui.per_page)) end
    ui.footer(summary)
end

function on_button(btn, pressed)
    if not pressed then return end
    ui.layout()
    notice = ""
    if btn == "back" then activate(1); return
    elseif btn == "confirm" then activate(focus); return end
    local count = screen == "networks" and #scan.rows + 4 or 4
    if btn == "left" then focus = (focus - 2) % count + 1
    elseif btn == "right" then focus = focus % count + 1
    elseif btn == "up" or btn == "page_back" then focus = math.max(1, focus - ui.per_page)
    elseif btn == "down" or btn == "page_forward" then focus = math.min(count, focus + ui.per_page) end
    refresh()
end

function on_tap(x, y)
    ui.layout()
    local action = ui.toolbar_hit(x, y)
    if action then focus = action; activate(action); return end
    if screen == "networks" then
        local index = ui.network_hit(x, y, focus, #scan.rows)
        if index then focus = index + 4; activate(focus) end
    end
end

function on_swipe(direction)
    ui.layout()
    if screen ~= "networks" or #scan.rows == 0 then return end
    if direction == "up" then focus = math.min(#scan.rows + 4, math.max(5, focus) + ui.per_page)
    elseif direction == "down" then focus = math.max(5, focus - ui.per_page) end
    refresh()
end

function on_exit()
    scan.close()
end
