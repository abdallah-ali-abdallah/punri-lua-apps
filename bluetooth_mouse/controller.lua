-- Foreground mouse policy. Native firmware owns bonding and complete click
-- press/release pairs. Motion is coalesced into bounded signed accumulators.
local M = {state = "ready", notice = "Pair your computer to start.", speed = 2}
local gains = {0.6, 1.0, 1.6}
local clicks = {false, false, false, false}
local move = {dx = 0, dy = 0} -- Reused for every report, never allocated per sample.
local pending, pending_kind, pending_x, pending_y
local dx, dy, click_head, click_count, last_submit = 0, 0, 1, 0, -100
local contact, tracking, last_x, last_y = false, false, 0, 0

local function redraw() punri.request_update() end
local function clamp(n, limit) return math.max(-limit, math.min(limit, n)) end
local function reset_input()
    dx, dy, click_head, click_count = 0, 0, 1, 0
    contact, tracking = false, false
    for i = 1, 4 do clicks[i] = false end
end
local function close()
    if radio and radio.close then radio.close() end
    pending, pending_kind = nil, nil
    M.connected, M.ready = false, false
    reset_input()
    if punri.prevent_sleep then punri.prevent_sleep(false) end
end
local function request(kind, id, err)
    if not id then
        M.notice = "Bluetooth: " .. (err or "failed")
        redraw()
        return false
    end
    pending, pending_kind = id, kind
    return true
end

function M.init()
    close()
    local caps = radio and radio.capabilities and radio.capabilities() or {}
    M.supported = caps.ble and caps.hid_mouse_peripheral and punri.has_touch()
        and type(punri.get_touch) == "function" or false
    M.simulated = caps.simulated or false
    M.state, M.speed = "ready", 2
    M.notice = M.supported and "Pair your computer to start." or "Requires X4 Pro with firmware API 5 and Bluetooth mouse support."
    redraw()
end

function M.start()
    if not M.supported or pending or M.connected then return end
    if M.state == "advertising" then return end
    local id, err = ble.hid_mouse_start {name = "PUNRI Mouse", bonding = true, timeout_ms = 30000}
    if request("start", id, err) then
        M.state, M.notice = "connecting", "Select PUNRI Mouse in your computer's Bluetooth settings."
        if punri.prevent_sleep then punri.prevent_sleep(true) end
    else
        close()
        M.state = "ready"
    end
    redraw()
end

function M.stop(forget)
    if not M.supported then return end
    -- Closing is synchronous and always available, even during an in-flight move.
    if not forget then
        close()
        M.state, M.notice = "ready", "Disconnected. Pair again when ready."
        redraw()
        return
    end
    if pending then M.notice = "Please wait for Bluetooth to finish."; redraw(); return end
    if not radio.stats().open then
        M.notice = "Connect a host in this session before forgetting it."
        redraw()
        return
    end
    local id, err = ble.hid_forget_pairing {}
    if request("forget", id, err) then
        M.state, M.ready = "disconnecting", false
        reset_input()
    end
    redraw()
end

function M.set_speed(speed)
    M.speed = math.max(1, math.min(3, speed))
    redraw()
end

function M.click(button)
    if not M.ready then M.notice = "Connect and finish pairing before clicking."; redraw(); return end
    if click_count == 4 then M.notice = "Please wait for queued clicks."; redraw(); return end
    clicks[(click_head + click_count - 1) % 4 + 1] = button
    click_count = click_count + 1
end

function M.sample(x, y, inside)
    if not x then contact, tracking = false, false; return end
    if not contact then
        contact, tracking, last_x, last_y = true, M.ready and inside or false, x, y
        return
    end
    if not inside or not M.ready then tracking = false end
    if tracking then
        dx = clamp(dx + (x - last_x) * gains[M.speed], 1024)
        dy = clamp(dy + (y - last_y) * gains[M.speed], 1024)
    end
    last_x, last_y = x, y
end

function M.pause_input()
    reset_input()
end

local function state(event)
    M.state = event.state or "error"
    M.connected = M.state == "connected"
    M.ready = M.connected and event.bonded and event.encrypted and event.subscribed or false
    if M.ready then
        M.notice = "Connected. Slide on the pad to move the pointer."
    elseif M.connected then
        M.notice = "Connected. Completing secure mouse setup."
    elseif M.state == "advertising" then
        M.notice = "Select PUNRI Mouse in your computer's Bluetooth settings."
    elseif M.state == "error" then
        M.notice = "Secure pairing failed. Disconnect and try again."
    elseif M.state == "closed" then
        M.notice = "Pairing ended. Pair again when ready."
    end
    if not M.ready then reset_input() end
    redraw()
end

function M.update()
    if not M.supported then return end
    local ended = false
    for _ = 1, 8 do
        local event = radio.poll()
        if not event then break end
        if event.kind == "hid_state" then
            state(event)
            ended = event.state == "closed" or event.state == "error"
        elseif event.id == pending and (event.kind == "complete" or event.kind == "error") then
            local kind = pending_kind
            pending, pending_kind = nil, nil
            if event.kind == "error" then
                -- A busy move was never delivered. Preserve its delta for retry;
                -- never retry a failed click because its press may have arrived.
                if kind == "move" and event.error == "busy" and M.ready then
                    dx, dy = clamp(dx + pending_x, 1024), clamp(dy + pending_y, 1024)
                else
                    M.notice = "Bluetooth: " .. (event.error or "failed")
                    if kind == "start" or kind == "forget" then ended = true end
                    redraw()
                end
            elseif kind == "forget" then
                M.notice = "Current host pairing forgotten."
                ended = true
            end
        end
    end
    if ended then
        close()
        M.state = "ready"
        redraw()
    end
    if not M.ready or pending then return end
    local now = punri.millis()
    if now - last_submit < 25 then return end
    local x, y = math.modf(clamp(dx, 127)), math.modf(clamp(dy, 127))
    if x ~= 0 or y ~= 0 then
        move.dx, move.dy = x, y
        local id, err = ble.hid_mouse_move(move)
        if id then
            pending, pending_kind, pending_x, pending_y = id, "move", x, y
            dx, dy = dx - x, dy - y
            last_submit = now
        elseif err ~= "busy" then
            dx, dy = 0, 0
            M.notice = "Mouse movement failed: " .. (err or "failed")
            redraw()
        end
    elseif click_count > 0 then
        local id, err = ble.hid_mouse_click(clicks[click_head])
        if id then
            pending, pending_kind = id, "click"
            clicks[click_head] = false
            click_head, click_count = click_head % 4 + 1, click_count - 1
            last_submit = now
        elseif err ~= "busy" then
            reset_input()
            M.notice = "Mouse click failed: " .. (err or "failed")
            redraw()
        end
    end
end

function M.exit() close() end
return M
