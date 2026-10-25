-- Monitor one Wi-Fi BSSID using sequential scans, not a connection or distance estimate.
local scan = punri.dofile("wifi_scan.lua")
local ui = punri.dofile("wifi_ui.lua")
local target, target_dirty = nil, false
local screen, focus, running, role, notice = "choose", 2, false, "choose", ""
local next_scan, last_redraw = 0, 0
-- Reuse 60 sample records; the oldest completed scan is overwritten at capacity.
local history, head, count, minimum, maximum, average, valid_count = {}, 1, 0, nil, nil, nil, 0
local labels = {"Exit", "Scan", "Target", "Export"}

local function refresh()
    punri.request_update()
    last_redraw, scan.dirty = punri.millis(), false
end

local function sample(index)
    return history[(head + index - 2) % 60 + 1]
end

local function clear_history()
    head, count, minimum, maximum, average, valid_count = 1, 0, nil, nil, nil, 0
end

local function remember_target()
    if not target then return true end
    if punri.write_file("target.dat", "PUNRI_SIGNAL_TARGET_1\n" .. target.address .. "\n" .. target.name) then
        target_dirty = false
        return true
    end
    target_dirty = true
    notice = "Target save failed. Export retries it."
    punri.log("Signal Meter: target SD save failed")
    return false
end

local function record(result)
    local index
    if count < 60 then count = count + 1; index = (head + count - 2) % 60 + 1
    else index = head; head = head % 60 + 1 end
    local entry, row = history[index], result == "complete" and scan.find(target.address) or nil
    entry.time, entry.rssi, entry.channel = punri.millis(), row and row.rssi or nil, row and row.channel or nil
    entry.dropped, entry.capped, entry.invalid = scan.dropped, scan.capped, scan.invalid
    if result ~= "complete" then entry.status = "error:" .. result
    elseif row then entry.status = scan.partial() and "partial" or "ok"
    else entry.status = scan.partial() and "unknown" or "not_seen" end
    local sum = 0
    minimum, maximum, average, valid_count = nil, nil, nil, 0
    for i = 1, count do
        local value = sample(i).rssi
        if value then
            minimum = minimum and math.min(minimum, value) or value
            maximum = maximum and math.max(maximum, value) or value
            sum, valid_count = sum + value, valid_count + 1
        end
    end
    if valid_count > 0 then average = sum / valid_count end
end

local function start_measure()
    if scan.start() then role = "measure"; return true end
    running, next_scan = false, 0
    return false
end

local function pause()
    running, next_scan = false, 0
    if scan.request then scan.cancel() else scan.close() end
end

local function choose_screen()
    running, next_scan = false, 0
    scan.close() -- No automatic scans survive navigation away from the meter.
    screen, focus, role = "choose", 2, "choose"
end

local function select_target(index)
    if scan.request then notice = "Wait for scan completion"; return end
    local row = scan.rows[index]
    if not row then return end
    target = {address = row.address, name = row.name}
    clear_history()
    remember_target()
    screen, focus, running = "meter", 2, true
    start_measure()
end

local function export()
    if target_dirty and not remember_target() then return end
    if not target or count == 0 then notice = "No completed signal samples to export"; return end
    local parts = {"uptime_ms,ssid,bssid,rssi_dbm,channel,status,simulated,dropped,capped,invalid\n"}
    for i = 1, count do
        local row = sample(i)
        parts[#parts + 1] = string.format("%d,%s,%s,%s,%s,%s,%s,%d,%d,%d\n", row.time,
            scan.csv(target.name), scan.csv(target.address), row.rssi and tostring(row.rssi) or "",
            row.channel and tostring(row.channel) or "", row.status, tostring(scan.simulated),
            row.dropped, row.capped, row.invalid)
    end
    -- At most 60 records. Only an explicit Export writes measurement history.
    if punri.write_file("signal.csv", table.concat(parts)) then notice = "Saved signal.csv to SD"
    else notice = "SD export failed. Retry."; punri.log("Signal Meter: SD export failed") end
end

local function activate(index)
    notice = ""
    if index == 1 then
        if screen == "choose" then scan.close(); punri.exit() else choose_screen() end
    elseif index == 2 then
        if screen == "choose" then
            if scan.request then scan.cancel() elseif scan.start() then role = "choose" end
        elseif running then pause()
        elseif scan.request then notice = "Wait for cancellation to finish"
        else running = true; start_measure() end
    elseif index == 3 then
        if screen == "meter" then choose_screen()
        elseif target then scan.close(); screen, focus = "meter", 2
        else notice = "Select a network first" end
    elseif index == 4 then export()
    elseif screen == "choose" then select_target(index - 4) end
    refresh()
end

local function draw_graph(y, height)
    local x, width = ui.margin + 36, ui.w - ui.margin * 2 - 48
    punri.rect(x, y, width, height, false)
    for _, level in ipairs({-20, -60, -100}) do
        local py = y + math.floor((-20 - level) / 80 * height)
        punri.text(x - 6, py - 7, tostring(level), "small", "regular", "right")
        if level == -60 then punri.line(x, py, x + width, py) end
    end
    local previous_x, previous_y = nil, nil
    for i = 1, count do
        local row = sample(i)
        if row.rssi then
            local px = x + math.floor((i - 1) / 59 * (width - 2)) + 1
            local value = math.max(-100, math.min(-20, row.rssi))
            local py = y + math.floor((-20 - value) / 80 * (height - 2)) + 1
            if previous_x then punri.line(previous_x, previous_y, px, py, 2) end
            punri.circle(px, py, 2, true)
            previous_x, previous_y = px, py
        else previous_x, previous_y = nil, nil end
    end
end

local function draw_meter()
    if not target then return end
    local latest = count > 0 and sample(count) or nil
    local rssi = latest and latest.rssi or nil
    punri.centered_text(ui.body, ui.clip(target.name ~= "" and target.name or "(hidden SSID)",
        ui.w - ui.margin * 2), "ui12", "bold")
    punri.centered_text(ui.body + 34, target.address, "small")
    local y = ui.body + 58
    local height = math.min(96, math.floor((ui.bottom - ui.body - 34) * 0.18))
    ui.meter(rssi, y, height)
    local description = "No fresh RSSI"
    if rssi then description = "dBm / " .. ui.quality(rssi)
    elseif latest then
        if latest.status == "unknown" then description = "Unknown: scan incomplete"
        elseif latest.status == "not_seen" then description = "Not seen in this scan"
        else description = latest.status end
    end
    punri.centered_text(y + height + 4, description, "ui10", "bold")
    local bar_width = math.min(280, ui.w - ui.margin * 2 - 40)
    local bar_x, bar_y = math.floor((ui.w - bar_width) / 2), y + height + 31
    punri.rect(bar_x, bar_y, bar_width, 8, false)
    if rssi then
        local fill = math.floor(ui.strength(rssi) / 100 * (bar_width - 4))
        if fill > 0 then punri.rect(bar_x + 2, bar_y + 2, fill, 4, true) end
    end
    local stats_y = y + height + 48
    local stats = "No valid samples yet"
    if average then stats = string.format("Min %d / Avg %.1f / Max %d dBm", minimum, average, maximum) end
    punri.centered_text(stats_y, stats, "small")
    local graph_y = stats_y + 30
    local graph_h = math.max(32, math.min(210, ui.bottom - graph_y - 55))
    draw_graph(graph_y, graph_h)
    punri.centered_text(graph_y + graph_h + 12, "Last 60 scans; gaps have no valid RSSI.", "small")
end

function on_init()
    ui.layout()
    scan.init()
    for i = 1, 60 do history[i] = {} end
    local raw = punri.read_file("target.dat", 129)
    if raw then
        local address, name = raw:match("^PUNRI_SIGNAL_TARGET_1\n([%x:]+)\n(.*)$")
        if #raw <= 128 and scan.valid_address(address) and #name <= 32 then
            target, screen = {address = address:lower(), name = scan.safe_name(name)}, "meter"
        else notice = "Saved target invalid; choose a network"; punri.log("Signal Meter: invalid target.dat") end
    end
    refresh()
end

function on_update()
    local result = scan.update()
    if result then
        if role == "measure" and target and result ~= "cancelled" then record(result) end
        if running and result == "complete" then next_scan = punri.millis() + 3000
        else
            running, next_scan = false, 0
            scan.close()
            if role == "choose" and result == "complete" and #scan.rows > 0 then focus = 5 end
        end
        refresh()
    elseif scan.dirty and punri.millis() - last_redraw >= 1000 then refresh() end
    if screen == "meter" and running and not scan.request and next_scan > 0 and punri.millis() >= next_scan then
        next_scan = 0
        start_measure()
        refresh()
    end
end

function on_draw()
    ui.begin("Signal Meter", scan.simulated)
    if screen == "choose" then
        labels[1], labels[2], labels[3] = "Exit", scan.request and "Cancel" or "Scan", "Target"
    else
        labels[1], labels[2], labels[3] = "Back", running and "Pause" or "Start", "Choose"
    end
    ui.toolbar(labels, focus)
    local status = scan.status
    if screen == "meter" and not running and not scan.request and scan.supported then status = "Paused / press Start to measure" end
    ui.status(notice ~= "" and notice or status)
    if screen == "choose" then ui.networks(scan.rows, focus) else draw_meter() end
    local footer = screen == "choose" and "Select a BSSID, not just a shared network name" or
        (tostring(count) .. "/60 scans  /  " .. tostring(valid_count) .. " valid  /  RSSI is not distance")
    if target_dirty then footer = "TARGET NOT SAVED: Export retries the SD write" end
    if scan.partial() then footer = "PARTIAL SCAN / " .. footer end
    ui.footer(footer)
end

function on_button(btn, pressed)
    if not pressed then return end
    ui.layout()
    if btn == "back" then activate(1); return
    elseif btn == "confirm" then activate(focus); return end
    local total = screen == "choose" and #scan.rows + 4 or 4
    if btn == "left" then focus = (focus - 2) % total + 1
    elseif btn == "right" then focus = focus % total + 1
    elseif btn == "up" or btn == "page_back" then focus = math.max(1, focus - ui.per_page)
    elseif btn == "down" or btn == "page_forward" then focus = math.min(total, focus + ui.per_page) end
    refresh()
end

function on_tap(x, y)
    ui.layout()
    local action = ui.toolbar_hit(x, y)
    if action then focus = action; activate(action); return end
    if screen == "choose" then
        local index = ui.network_hit(x, y, focus, #scan.rows)
        if index then focus = index + 4; activate(focus) end
    end
end

function on_swipe(direction)
    ui.layout()
    if screen ~= "choose" or #scan.rows == 0 then return end
    if direction == "up" then focus = math.min(#scan.rows + 4, math.max(5, focus) + ui.per_page)
    elseif direction == "down" then focus = math.max(5, focus - ui.per_page) end
    refresh()
end

function on_exit()
    running, next_scan = false, 0
    scan.close()
end
