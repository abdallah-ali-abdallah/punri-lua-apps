-- Shared analyzer controller, loaded once per VM by either standalone package.
-- This factory is called once at startup, never from drawing or polling.
return function(bluetooth)
local scan = punri.dofile("radio_scan.lua")
local ui = punri.dofile("radio_ui.lua")
local title = bluetooth and "Bluetooth Analyzer" or "Wi-Fi Analyzer"
local analysis_name = bluetooth and "Adverts" or "Channels"
local snapshot_complete, info_page = false, 1
-- Cached only after observations/selection; no advertisement parsing in on_draw.
local info_lines = {}
local target, target_dirty = nil, false
local screen, focus, running, role, notice = "choose", 2, false, "choose", ""
local next_scan, last_redraw = 0, 0
local raw_page_seen, alias_focus, alias_info_page = false, nil, nil
-- Reuse 60 sample records; the oldest completed scan is overwritten at capacity.
local history, head, count, minimum, maximum, average, valid_count = {}, 1, 0, nil, nil, nil, 0
local labels = {"Exit", "Scan", analysis_name, "Export"}
local graph_levels = {-20, -60, -100}
local analysis_labels = {"Connectable", "Named", "Public / identity"}
local analysis_values = {0, 0, 0}

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
    local raw = bluetooth and ("PUNRI_BLE_TARGET_1\n" .. target.address .. "\n" .. target.address_type .. "\n" .. target.name) or
        ("PUNRI_SIGNAL_TARGET_1\n" .. target.address .. "\n" .. target.name)
    if punri.write_file("target.dat", raw) then
        target_dirty = false
        return true
    end
    target_dirty = true
    notice = "Target save failed. Export retries it."
    punri.log(title .. ": target SD save failed")
    return false
end

local function record(result)
    local index
    if count < 60 then count = count + 1; index = (head + count - 2) % 60 + 1
    else index = head; head = head % 60 + 1 end
    local entry, row = history[index], result == "complete" and scan.find(target.address, target.address_type) or nil
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
    if scan.start() then snapshot_complete, role = false, "measure"; return true end
    running, next_scan = false, 0
    return false
end

local function pause()
    running, next_scan = false, 0
    if scan.request then scan.cancel() else scan.close() end
end

local function choose_screen()
    running, next_scan = false, 0
    if scan.request then scan.status = "Scan stopped" end
    scan.close() -- No automatic scans survive navigation away from the meter.
    screen, focus, role = "choose", 2, "choose"
end

local field_names = {[1] = "Flags", [2] = "UUID16", [3] = "UUID16", [4] = "UUID32", [5] = "UUID32",
    [6] = "UUID128", [7] = "UUID128", [8] = "Short name", [9] = "Name", [10] = "TX power",
    [22] = "Service data", [255] = "Manufacturer"}

local function hex(data, limit)
    -- Cold detail/export path, at most 16 bytes per rendered AD field.
    return (data:sub(1, limit):gsub(".", function(c) return string.format("%02X", c:byte()) end))
end

local function info_per_page()
    return math.max(1, math.floor((ui.bottom - ui.body - 116) / 32))
end

local function cache_info(row)
    for i = 1, #info_lines do info_lines[i] = nil end
    if not bluetooth then
        info_lines[1] = "Channel " .. row.channel .. " / Auth code " .. row.auth
        info_lines[2] = "Last observed RSSI: " .. row.rssi .. " dBm"
        return
    end
    info_lines[1] = "Address type " .. row.address_type .. " / " .. (row.connectable and "Connectable" or "Non-connectable")
    info_lines[2] = "Advert type " .. row.advertisement_type .. " / " .. row.observations .. " received observations"
    if row.truncated then info_lines[3] = "Truncated payload; details not decoded"; return end
    local fields, error_code = ble.parse(row.data)
    if not fields then
        info_lines[3] = "Malformed advertisement: " .. tostring(error_code)
        punri.log(title .. ": malformed advertisement payload")
        return
    end
    info_lines[3] = #row.data .. " payload bytes / " .. #fields .. " AD fields"
    for i = 1, math.min(#fields, 16) do
        local field = fields[i]
        local label = field_names[field.type] or string.format("AD 0x%02X", field.type)
        if field.type == 255 and #field.data >= 2 then
            label = label .. string.format(" 0x%04X", field.data:byte(1) + field.data:byte(2) * 256)
        end
        info_lines[#info_lines + 1] = label .. ": " .. hex(field.data, 16) .. (#field.data > 16 and "..." or "")
    end
    if #fields > 16 then info_lines[#info_lines + 1] = "Additional AD fields omitted (16-field display cap)" end
end

local function select_target(index)
    if scan.request then notice = "Wait for scan completion"; return end
    local row = scan.rows[index]
    if not row then return end
    target = {address = row.address, name = row.name, address_type = row.address_type}
    clear_history()
    info_page = 1
    cache_info(row)
    remember_target()
    screen, focus, running = "meter", 2, true
    start_measure()
end

local function export_scan()
    if scan.request or not snapshot_complete then notice = "Finish a successful scan before exporting"; return end
    local parts = {bluetooth and "name,address,address_type,rssi_dbm,connectable,advert_type,observations,payload_truncated,simulated,dropped,capped,invalid\n" or
        "ssid,bssid,rssi_dbm,channel,auth_code,simulated,dropped,capped,invalid\n"}
    for _, row in ipairs(scan.rows) do
        if bluetooth then
            parts[#parts + 1] = string.format("%s,%s,%d,%d,%s,%d,%d,%s,%s,%d,%d,%d\n", scan.csv(row.name),
                scan.csv(row.address), row.address_type, row.rssi, tostring(row.connectable), row.advertisement_type,
                row.observations, tostring(row.truncated), tostring(scan.simulated), scan.dropped, scan.capped, scan.invalid)
        else
            parts[#parts + 1] = string.format("%s,%s,%d,%d,%d,%s,%d,%d,%d\n", scan.csv(row.name),
                scan.csv(row.address), row.rssi, row.channel, row.auth, tostring(scan.simulated), scan.dropped, scan.capped, scan.invalid)
        end
    end
    if punri.write_file("last_scan.csv", table.concat(parts)) then notice = "Saved last_scan.csv to SD"
    else notice = "SD export failed. Retry."; punri.log(title .. ": SD export failed") end
end

local function export()
    if screen == "choose" or screen == "analysis" then export_scan(); return end
    if target_dirty and not remember_target() then return end
    if not target or count == 0 then notice = "No completed signal samples to export"; return end
    local parts = {bluetooth and "uptime_ms,name,address,rssi_dbm,address_type,status,simulated,dropped,capped,invalid\n" or
        "uptime_ms,ssid,bssid,rssi_dbm,channel,status,simulated,dropped,capped,invalid\n"}
    for i = 1, count do
        local row = sample(i)
        parts[#parts + 1] = string.format("%d,%s,%s,%s,%s,%s,%s,%d,%d,%d\n", row.time,
            scan.csv(target.name), scan.csv(target.address), row.rssi and tostring(row.rssi) or "",
            bluetooth and tostring(target.address_type) or (row.channel and tostring(row.channel) or ""),
            row.status, tostring(scan.simulated),
            row.dropped, row.capped, row.invalid)
    end
    -- At most 60 records. Only an explicit Export writes measurement history.
    if punri.write_file("signal.csv", table.concat(parts)) then notice = "Saved signal.csv to SD"
    else notice = "SD export failed. Retry."; punri.log(title .. ": SD export failed") end
end

local function activate(index)
    notice = ""
    if index == 1 then
        if screen == "choose" then scan.close(); punri.exit()
        elseif screen == "info" then screen, focus = "meter", 1
        elseif screen == "analysis" then screen, focus = "choose", 2
        else choose_screen() end
    elseif index == 2 then
        if screen == "choose" or screen == "analysis" then
            if scan.request then scan.cancel()
            elseif scan.start() then snapshot_complete, role, screen, focus = false, "choose", "choose", 2 end
        elseif running then pause()
        elseif scan.request then notice = "Wait for cancellation to finish"
        else running = true; start_measure() end
    elseif index == 3 then
        if screen == "choose" then screen, focus = "analysis", 3
        elseif screen == "analysis" then screen, focus = "choose", 3
        else screen, focus = screen == "meter" and "info" or "meter", 3 end
    elseif index == 4 then export()
    elseif screen == "choose" then
        local offset = target and 1 or 0
        if target and index == 5 then
            if scan.request then notice = "Wait for scan completion"
            else scan.close(); screen, focus, running = "meter", 2, false end
        else select_target(index - 4 - offset) end
    end
    refresh()
end

local function draw_graph(y, height)
    local x, width = ui.margin + 36, ui.w - ui.margin * 2 - 48
    punri.rect(x, y, width, height, false)
    for _, level in ipairs(graph_levels) do
        local py = y + math.floor((-20 - level) / 80 * height)
        punri.text(x - 6, py - 7, tostring(level), "small", "regular", "right")
        if level == -60 then punri.line(x, py, x + width, py) end
    end
    local previous_x, previous_y = nil, nil
    for i = 1, count do
        local row = sample(i)
        if row.rssi then
            local px = count == 1 and x + math.floor(width / 2) or
                x + math.floor((i - 1) / (count - 1) * (width - 2)) + 1
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
    punri.centered_text(ui.body, ui.clip(target.name ~= "" and target.name or (bluetooth and "(unnamed device)" or "(hidden SSID)"),
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

local function draw_analysis()
    if bluetooth then
        local connectable, named, public = 0, 0, 0
        for _, row in ipairs(scan.rows) do
            if row.connectable then connectable = connectable + 1 end
            if row.name ~= "" then named = named + 1 end
            if row.address_type == 0 or row.address_type == 2 then public = public + 1 end
        end
        punri.centered_text(ui.body, "Observed BLE address/type pairs", "ui12", "bold")
        local names, values = analysis_labels, analysis_values
        values[1], values[2], values[3] = connectable, named, public
        local width = ui.w - ui.margin * 2 - 210
        for i = 1, 3 do
            local y = ui.body + 44 + (i - 1) * 50
            punri.text(ui.margin, y, names[i], "small")
            punri.rect(ui.margin + 160, y, width, 14, false)
            local fill = scan.count > 0 and math.floor(values[i] / scan.count * (width - 4)) or 0
            if fill > 0 then punri.rect(ui.margin + 162, y + 2, fill, 10, true) end
            punri.text(ui.w - ui.margin, y, values[i] .. "/" .. scan.count, "small", "regular", "right")
        end
        punri.centered_text(ui.body + 201, "BLE radio channels are not exposed by this API.", "small")
    else
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
end

local function draw_info()
    info_page = math.max(1, math.min(info_page, math.ceil(#info_lines / info_per_page())))
    punri.centered_text(ui.body, ui.clip(target.name ~= "" and target.name or target.address,
        ui.w - ui.margin * 2), "ui12", "bold")
    punri.centered_text(ui.body + 34, target.address, "small")
    punri.centered_text(ui.body + 62, "Last observed details / page " .. info_page, "small")
    local per_page = info_per_page()
    local first = (info_page - 1) * per_page + 1
    for i = first, math.min(#info_lines, first + per_page - 1) do
        punri.text(ui.margin, ui.body + 94 + (i - first) * 32,
            ui.clip(info_lines[i], ui.w - ui.margin * 2, "small"), "small")
    end
    if #info_lines == 0 then punri.centered_text(ui.body + 100, "Scan to obtain details", "small") end
end

local function feedback_activate(index)
    local F = ui.feedback
    if F.busy() then return end
    if index == 1 or index == 3 or index >= 5 then
        if F.defer(index, function() activate(index) end) then return end
    else F.press(index) end
    activate(index)
end

function on_init()
    ui.layout()
    scan.init(bluetooth)
    for i = 1, 60 do history[i] = {} end
    local raw = punri.read_file("target.dat", 129)
    if raw then
        local address, name, address_type
        if bluetooth then
            local type_text
            address, type_text, name = raw:match("^PUNRI_BLE_TARGET_1\n([%x:]+)\n([0-3])\n(.*)$")
            address_type = tonumber(type_text)
        else address, name = raw:match("^PUNRI_SIGNAL_TARGET_1\n([%x:]+)\n(.*)$") end
        if #raw <= 128 and scan.valid_address(address) and name and #name <= 32 then
            target, screen = {address = address:lower(), name = scan.safe_name(name), address_type = address_type}, "meter"
        else notice = "Saved target invalid; choose a device"; punri.log(title .. ": invalid target.dat") end
    end
    refresh()
end

function on_update()
    ui.feedback.update()
    -- LuaAppActivity calls Update after dispatching the current input batch.
    raw_page_seen, alias_focus, alias_info_page = false, nil, nil
    local result = scan.update()
    if result then
        snapshot_complete = result == "complete"
        if role == "measure" and target and result ~= "cancelled" then
            record(result)
            local row = result == "complete" and scan.find(target.address, target.address_type) or nil
            if row then cache_info(row) end
        end
        if running and result == "complete" then next_scan = punri.millis() + 3000
        else
            running, next_scan = false, 0
            scan.close()
            if role == "choose" and screen == "choose" and result == "complete" and #scan.rows > 0 then focus = target and 6 or 5 end
        end
        refresh()
    elseif scan.dirty and punri.millis() - last_redraw >= 1000 then refresh() end
    if (screen == "meter" or screen == "info") and running and not scan.request and next_scan > 0 and punri.millis() >= next_scan then
        next_scan = 0
        start_measure()
        refresh()
    end
end

function on_draw()
    ui.feedback.begin(screen)
    ui.begin(title, scan.simulated, bluetooth)
    if screen == "choose" or screen == "analysis" then
        labels[1] = screen == "choose" and "Exit" or "Back"
        labels[2] = scan.request and (scan.cancelling and "Wait" or "Cancel") or "Scan"
        labels[3] = screen == "choose" and analysis_name or (bluetooth and "Devices" or "Networks")
    else
        labels[1], labels[2], labels[3] = "Back", running and "Pause" or "Start", screen == "meter" and "Info" or "Graph"
    end
    ui.toolbar(labels, focus)
    local status = scan.status
    if (screen == "meter" or screen == "info") and not running and not scan.request and scan.supported and not scan.error_code then
        status = "Paused / press Start to measure"
    end
    ui.status(notice ~= "" and notice or status)
    if screen == "choose" then ui.networks(scan.rows, focus, bluetooth, target)
    elseif screen == "analysis" then draw_analysis()
    elseif screen == "info" then draw_info()
    else draw_meter() end
    local footer
    if screen == "choose" or screen == "analysis" then
        footer = scan.count .. (bluetooth and " devices" or " APs") .. " / " .. scan.dropped .. " dropped"
        if scan.capped > 0 or scan.invalid > 0 then footer = footer .. " / " .. scan.capped .. " capped / " .. scan.invalid .. " invalid" end
    else footer = count .. "/60 scans / " .. valid_count .. " valid / RSSI is not distance" end
    if target_dirty then footer = "TARGET NOT SAVED: Export retries the SD write" end
    if scan.partial() then footer = "PARTIAL: " .. footer end
    ui.footer(footer)
    ui.feedback.finish()
end

function on_button(btn, pressed)
    if not pressed then return end
    -- LuaAppActivity can emit a raw menu direction and a mapped page alias for
    -- one physical release. Let the menu direction win, even with inverted
    -- reader-side mappings; standalone page callbacks are still supported.
    if btn == "up" or btn == "down" then
        -- With reversed side mappings, the alias can arrive before the raw
        -- direction. Restore its checkpoint so that release still acts once.
        if alias_focus then focus, info_page = alias_focus, alias_info_page end
        alias_focus, alias_info_page, raw_page_seen = nil, nil, true
    elseif btn == "page_back" or btn == "page_forward" then
        if raw_page_seen then return end
        if not alias_focus then alias_focus, alias_info_page = focus, info_page end
    end
    ui.layout()
    if btn == "back" then feedback_activate(1); return
    elseif btn == "confirm" then feedback_activate(focus); return end
    if screen == "info" and (btn == "up" or btn == "page_back" or btn == "down" or btn == "page_forward") then
        local pages = math.max(1, math.ceil(#info_lines / info_per_page()))
        local direction = (btn == "up" or btn == "page_back") and -1 or 1
        info_page = math.max(1, math.min(pages, info_page + direction))
        refresh(); return
    end
    local total = screen == "choose" and #scan.rows + 4 + (target and 1 or 0) or 4
    if btn == "left" then focus = (focus - 2) % total + 1
    elseif btn == "right" then focus = focus % total + 1
    elseif btn == "up" or btn == "page_back" then focus = math.max(1, focus - ui.per_page)
    elseif btn == "down" or btn == "page_forward" then focus = math.min(total, focus + ui.per_page) end
    refresh()
end

function on_tap(x, y)
    ui.layout()
    local action = ui.toolbar_hit(x, y)
    if action then focus = action; feedback_activate(action); return end
    if screen == "choose" then
        local index = ui.network_hit(x, y, focus, #scan.rows + (target and 1 or 0))
        if index then focus = index + 4; feedback_activate(focus) end
    end
end

function on_swipe(direction)
    ui.layout()
    if screen == "info" then
        local pages = math.max(1, math.ceil(#info_lines / info_per_page()))
        if direction == "up" then info_page = math.min(pages, info_page + 1)
        elseif direction == "down" then info_page = math.max(1, info_page - 1) end
    elseif screen == "choose" then
        local total = #scan.rows + (target and 1 or 0)
        if total == 0 then return end
        if direction == "up" then focus = math.min(total + 4, math.max(5, focus) + ui.per_page)
        elseif direction == "down" then focus = math.max(5, focus - ui.per_page) end
    else return end
    refresh()
end

function on_exit()
    running, next_scan = false, 0
    scan.close()
end
end
