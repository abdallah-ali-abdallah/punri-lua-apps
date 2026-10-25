-- Foreground policy for the Bluetooth Page Turner.  Pairing/bonds and HID
-- reports are native radio work; this file only renders state and submits the
-- deliberately small arrow-key command surface.
local M = {}

M.supported, M.simulated = false, false
M.state, M.notice = "unavailable", "Checking Bluetooth HID support"
M.connected, M.subscribed, M.was_connected = false, false, false
M.pending_id, M.pending_kind = nil, nil
M.close_when_idle = false
M.mode, M.sent = "arrows", 0

local function request_update()
    if punri.request_update then punri.request_update() end
end

local function finish_pending(kind)
    if M.pending_kind == kind then
        M.pending_id, M.pending_kind = nil, nil
    end
end

local function close_radio()
    M.pending_id, M.pending_kind, M.close_when_idle = nil, nil, false
    if radio and radio.close then radio.close() end
end

local function start_request(kind, invoke)
    if M.pending_id then
        M.notice = "Please wait for the current Bluetooth action."
        request_update()
        return false
    end
    local id, error_code = invoke()
    if not id then
        M.notice = "Bluetooth action unavailable: " .. (error_code or "failed")
        request_update()
        return false
    end
    M.pending_id, M.pending_kind = id, kind
    request_update()
    return true
end

function M.init()
    local caps = radio and radio.capabilities and radio.capabilities() or nil
    M.supported = caps and caps.ble and caps.hid_keyboard_peripheral or false
    M.simulated = caps and caps.simulated or false
    M.connected, M.subscribed, M.was_connected = false, false, false
    M.pending_id, M.pending_kind, M.close_when_idle, M.sent = nil, nil, false, 0
    if M.supported then
        M.state, M.notice = "ready", "Pair a host to begin."
    else
        M.state = "unavailable"
        M.notice = "Bluetooth HID keyboard peripheral is unavailable on this build."
    end
    request_update()
end

function M.start()
    if not M.supported then return false end
    if M.state == "advertising" or M.state == "connecting" then return false end
    M.state, M.notice = "connecting", "Advertising for up to 30 seconds."
    return start_request("start", function()
        return ble.hid_keyboard_start {name = "PUNRI Remote", bonding = true, timeout_ms = 30000}
    end)
end

function M.stop(forget)
    if not M.supported then return false end
    if not radio.stats().open then
        M.notice = "Pair a host in this session before disconnecting or forgetting it."
        request_update()
        return false
    end
    M.state, M.notice = "disconnecting", forget and "Disconnecting and forgetting this host." or "Disconnecting."
    return start_request(forget and "forget" or "stop", function()
        if forget then return ble.hid_forget_pairing {} end
        return ble.hid_keyboard_stop {}
    end)
end

function M.send(key)
    if not M.supported or M.state ~= "connected" or not M.subscribed then
        M.notice = "Connect and finish pairing before sending a key."
        request_update()
        return false
    end
    return start_request("key", function() return ble.hid_key_tap(key) end)
end

function M.toggle_mode()
    M.mode = M.mode == "arrows" and "pages" or "arrows"
    M.notice = M.mode == "pages" and "Page mode: Left and Right turn pages." or "Arrow mode: all four keys are shown."
    request_update()
end

local function handle_state(event)
    M.state = event.state or "error"
    M.connected = event.state == "connected"
    M.subscribed = event.subscribed and M.connected or false
    if M.connected then
        M.was_connected = true
        M.notice = M.subscribed and "Connected. Keys are ready." or "Connected. Completing secure key setup."
    elseif M.state == "advertising" then
        M.notice = M.was_connected and "Reconnecting: advertising for the paired host." or "Advertising: select PUNRI Remote on your host."
    elseif M.state == "closed" then
        M.connected, M.subscribed = false, false
        M.close_when_idle = true
        if M.pending_kind ~= "stop" and M.pending_kind ~= "forget" then
            M.notice = "Advertising ended. Pair again when ready."
        end
    elseif M.state == "error" then
        M.connected, M.subscribed = false, false
        M.notice = "Secure Bluetooth setup failed. Disconnect and try again."
    end
end

function M.update()
    if not M.supported then return end
    for _ = 1, 8 do
        local event = radio.poll()
        if not event then break end
        if event.kind == "hid_state" then
            handle_state(event)
        elseif event.kind == "complete" then
            if event.id == M.pending_id then
                local completed = M.pending_kind
                finish_pending(completed)
                if completed == "key" then
                    M.sent = M.sent + 1
                    M.notice = "Key sent."
                elseif completed == "stop" or completed == "forget" then
                    close_radio()
                    M.state, M.connected, M.subscribed = "ready", false, false
                    M.notice = completed == "forget" and "Pairing forgotten for the current host." or "Disconnected."
                end
            end
        elseif event.kind == "error" and event.id == M.pending_id then
            local failed = M.pending_kind
            finish_pending(failed)
            M.notice = "Bluetooth action failed: " .. (event.error or "failed")
            if failed == "start" or failed == "stop" or failed == "forget" then
                close_radio()
                M.state, M.connected, M.subscribed = "ready", false, false
            end
        end
        request_update()
    end
    if M.close_when_idle and not M.pending_id then
        M.close_when_idle = false
        close_radio()
        M.state = "ready"
        request_update()
    end
end

function M.exit()
    -- Lua app exit has no async continuation.  Native close stops advertising,
    -- detaches callbacks and attempts a release before it releases the session.
    close_radio()
end

return M
