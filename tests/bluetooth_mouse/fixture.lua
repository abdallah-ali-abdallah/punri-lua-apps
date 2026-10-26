-- Deliberate deterministic replay, never a physical Bluetooth test.
local queue, sequence, pending, opened = {}, 0, nil, false
local connected, encrypted, subscribed = false, false, false
MOUSE_TEST = {moves = {}, clicks = {}, closes = 0, starts = 0, now = 1000, redraws = 0}
punri.millis = function() return MOUSE_TEST.now end
local request_update = punri.request_update
punri.request_update = function()
    MOUSE_TEST.redraws = MOUSE_TEST.redraws + 1
    request_update()
end
local load = punri.dofile
punri.dofile = function(name)
    local module = load(name)
    if name == "controller.lua" then MOUSE_TEST.controller = module end
    if name == "ui.lua" then MOUSE_TEST.ui = module end
    return module
end
local function push(e) queue[#queue + 1] = e end
local function begin()
    if pending then return nil, "busy" end
    sequence = sequence + 1; pending = sequence; return sequence
end
local function done(id, err) push {id = id, kind = err and "error" or "complete", error = err} end
function MOUSE_TEST.state(name, secure)
    connected, encrypted, subscribed = name == "connected", secure, secure
    push {kind = "hid_state", id = 1, state = name, bonded = secure, encrypted = secure, subscribed = secure}
end
radio = {
    capabilities = function() return {ble = not MOUSE_TEST_UNSUPPORTED, hid_mouse_peripheral = not MOUSE_TEST_UNSUPPORTED, simulated = true} end,
    stats = function() return {open = opened, busy = pending ~= nil} end,
    close = function() opened, pending, queue = false, nil, {}; MOUSE_TEST.closes = MOUSE_TEST.closes + 1 end,
    poll = function()
        if MOUSE_TEST.hold then return nil end
        local e = table.remove(queue, 1)
        if e and (e.kind == "complete" or e.kind == "error") then pending = nil end
        return e
    end,
}
ble = {}
function ble.hid_mouse_start(opts)
    assert(opts.name == "PUNRI Mouse" and opts.bonding and opts.timeout_ms == 30000)
    local id, err = begin(); if not id then return nil, err end
    opened = true; MOUSE_TEST.starts = MOUSE_TEST.starts + 1
    if MOUSE_TEST.start_error then done(id, MOUSE_TEST.start_error)
    else MOUSE_TEST.state("advertising", false); done(id) end
    return id
end
function ble.hid_mouse_move(opts)
    assert(connected and encrypted and subscribed)
    assert(opts.dx >= -127 and opts.dx <= 127 and opts.dy >= -127 and opts.dy <= 127)
    assert(opts.dx % 1 == 0 and opts.dy % 1 == 0)
    local id, err = begin(); if not id then return nil, err end
    local fail = MOUSE_TEST.fail_next; MOUSE_TEST.fail_next = nil
    if not fail then MOUSE_TEST.moves[#MOUSE_TEST.moves + 1] = {opts.dx, opts.dy} end
    done(id, fail); return id
end
function ble.hid_mouse_click(button)
    assert(connected and encrypted and subscribed)
    assert(button == "left" or button == "right")
    local id, err = begin(); if not id then return nil, err end
    local fail = MOUSE_TEST.fail_next; MOUSE_TEST.fail_next = nil
    MOUSE_TEST.clicks[#MOUSE_TEST.clicks + 1] = button
    done(id, fail); return id
end
function ble.hid_forget_pairing()
    local id, err = begin(); if not id then return nil, err end
    MOUSE_TEST.forgot = true; MOUSE_TEST.state("closed", false); done(id); return id
end
