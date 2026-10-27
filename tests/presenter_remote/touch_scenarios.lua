-- Regression scenario loaded by the firmware LuaRunner tests in portrait and
-- landscape. Run LuaAppsTest.PresenterRemote* from the firmware test suite.
local UI = punri.dofile("ui.lua")
local function update() on_update() end
local function tap_control(id)
    for _, c in ipairs(UI.compute().controls) do
        if c.id == id then
            on_tap(c.x + math.floor(c.w / 2), c.y + math.floor(c.h / 2))
            return
        end
    end
    error("missing control: " .. id)
end

-- Use the real event order: radio readiness can change after the last
-- frame. Do not let the shared test driver draw before every input.
TEST_FEEDBACK_UNWRAP()
local now = 1000
punri.millis = function() return now end
tap_control("right")
update()
local text, lines = punri.text, {}
punri.text = function(x, y, value, ...)
    lines[#lines + 1] = value
    return text(x, y, value, ...)
end
on_draw()
punri.text = text
assert(table.concat(lines, " "):find("Connect and finish pairing", 1, true),
    "an unpaired touch must explain why no key was sent")
assert(#HID_TEST.keys == 0, "an unpaired touch must not send a host key")
on_button("confirm", true)
update()
HID_TEST.connect()
update()
for _, id in ipairs({"up", "left", "down", "right", "enter", "space"}) do
    tap_control(id)
    update()
end
assert(table.concat(HID_TEST.keys, ",") == "up,left,down,right,enter,space",
    "all six touch keys must work before the connected frame is drawn")
on_draw()
-- The text below an arrow and the corners of its control belong to the
-- same target; feedback's smaller painted circle must not swallow them.
for _, id in ipairs({"up", "left", "down", "right", "enter", "space"}) do
    for _, c in ipairs(UI.compute().controls) do
        if c.id == id then on_tap(c.x + 1, c.y + c.h - 2); break end
    end
    update()
end
assert(table.concat(HID_TEST.keys, ",") ==
    "up,left,down,right,enter,space,up,left,down,right,enter,space",
    "the whole visible key target must send exactly one command")
tap_control("mode")
tap_control("up")
tap_control("down")
update()
assert(#HID_TEST.keys == 12, "stale arrow targets must not leak through page mode")
tap_control("enter")
update()
tap_control("space")
update()
assert(#HID_TEST.keys == 14, "Enter and Space must work immediately after a mode change")
on_draw()
tap_control("settings")
on_draw()
now = now + 500
update()
-- Settings is now open, but the most recent drawn targets are still the
-- remote. No stale target may send a key or toggle the remote's mode.
tap_control("enter")
tap_control("space")
on_button("page_forward", true)
update()
assert(#HID_TEST.keys == 14, "settings must isolate host keys before its first draw")
on_draw()
on_button("back", true)
on_draw()
now = now + 500
update()
tap_control("left")
update()
assert(HID_TEST.keys[15] == "left", "returning to the remote must not require an extra draw")
