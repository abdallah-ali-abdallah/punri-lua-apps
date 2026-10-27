-- Exercise actual contact sampling, with and without native tap callbacks.
TEST_FEEDBACK_UNWRAP()
local UI = punri.dofile("ui.lua")
local feedback = TEST_FEEDBACKS[1]
local now, x, y = 1000, nil, nil
punri.millis = function() return now end
punri.get_touch = function() return x, y end
local native = TEST_CASE == "live_native"
local function step(ms)
    now = now + (ms or 30)
    on_update()
end
local function control(id)
    for _, c in ipairs(UI.compute().controls) do if c.id == id then return c end end
    error("missing control: " .. id)
end
local function tap(id)
    local c = control(id)
    local cx, cy = c.x + c.w // 2, c.y + c.h // 2
    x, y = cx, cy
    step()
    x, y = nil, nil
    if native then on_tap(cx, cy) end
    step()
    assert(feedback.active(id), "touch must start press feedback: " .. id)
    -- A late native callback must not replay a contact already handled live.
    if not native then on_tap(cx, cy) end
    on_draw()
    step(499)
    assert(feedback.active(id), "feedback ended before 500 ms: " .. id)
    step(1)
    assert(not feedback.active(), "feedback did not restore: " .. id)
    on_draw()
end

on_draw()
tap("right")
assert(#HID_TEST.keys == 0, "unpaired taps must show feedback without sending a key")
on_button("confirm", true); step()
HID_TEST.connect(); step(); on_draw()
for _, id in ipairs({"up", "left", "down", "right", "enter", "space"}) do tap(id) end
assert(table.concat(HID_TEST.keys, ",") == "up,left,down,right,enter,space",
    "one contact must produce exactly one host key")

-- Sliding farther than the normal tap slop must not turn into a fallback tap.
if not native then
    local c = control("right")
    x, y = c.x + c.w // 2, c.y + c.h // 2; step()
    x = x + 61; step()
    x, y = nil, nil; step()
    assert(#HID_TEST.keys == 6, "a swipe must not send a host key")
end
on_button("up", true); step(); on_button("down", true); step()
on_button("page_back", true); step(); on_button("page_forward", true); step()
assert(table.concat(HID_TEST.keys, ",") == "up,left,down,right,enter,space,left,right,left,right",
    "both firmware side-button names must map to backward/forward")
on_draw()
tap("settings")
on_button("up", true); on_button("down", true); step()
assert(#HID_TEST.keys == 10, "settings must consume side buttons locally")
tap("close_settings")
tap("space")
assert(HID_TEST.keys[11] == "space", "returning from settings must restore touch")
