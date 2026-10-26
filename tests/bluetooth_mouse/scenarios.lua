local T = MOUSE_TEST
local C, UI = T.controller, T.ui
local function tick(count)
    for _ = 1, count or 1 do T.now = T.now + 30; on_update() end
end
local function connect()
    on_button("confirm", true); tick()
    T.state("connected", true); tick()
    assert(C.ready)
end
local function tap(b) on_tap(b.x + math.floor(b.w / 2), b.y + math.floor(b.h / 2)) end
local function move_sum()
    local x, y = 0, 0
    for _, d in ipairs(T.moves) do x, y = x + d[1], y + d[2] end
    return x, y
end
local layout = UI.compute()
if TEST_CASE == "native_touch" then
    connect()
    punri.millis = function() T.now = T.now + 30; return T.now end
    local exit = on_exit
    function on_exit()
        local x, y = move_sum()
        assert(x == 70 and y == -30, "native live contact delta mismatch")
        assert(table.concat(T.clicks, ",") == "left,right")
        exit()
    end
    return
elseif TEST_CASE == "unsupported" then
    assert(not C.supported)
    on_button("confirm", true); on_draw(); tick()
    assert(T.starts == 0)
elseif TEST_CASE == "secure" then
    on_button("confirm", true); tick()
    T.state("connected", false); tick()
    tap(layout.clicks[1]); C.sample(20, 20, true); C.sample(30, 30, true); tick(4)
    assert(not C.ready and #T.moves == 0 and #T.clicks == 0)
    T.state("connected", true); tick()
    tap(layout.clicks[1]); tick(2)
    assert(T.clicks[1] == "left")
elseif TEST_CASE == "motion" then
    connect()
    C.sample(100, 100, true); C.sample(420, 90, true); C.sample(nil)
    tick(6)
    local x, y = move_sum(); assert(x == 320 and y == -10)
    -- A new stroke starts at its own position, without an absolute jump.
    C.sample(20, 20, true); C.sample(30, 25, true); C.sample(nil); tick(3)
    x, y = move_sum(); assert(x == 330 and y == -5)
    local n = #T.moves
    C.sample(10, 10, false); C.sample(30, 30, true); C.sample(nil); tick(2)
    assert(#T.moves == n)
    C.sample(50, 50, true); C.sample(70, 50, false); C.sample(90, 50, true); C.sample(nil); tick(2)
    assert(#T.moves == n)
elseif TEST_CASE == "clicks" then
    connect()
    tap(layout.clicks[1]); tap(layout.clicks[2]); tick(5)
    assert(table.concat(T.clicks, ",") == "left,right")
    -- Only on_tap is installed: compatibility dispatch cannot duplicate clicks.
    assert(on_touch == nil)
    local n = #T.clicks
    for _ = 1, 12 do C.click("left") end
    tick(12); assert(#T.clicks == n + 4)
    tap(layout.settings); on_button("left", true); on_button("right", true); tick(2)
    assert(#T.clicks == n + 4)
elseif TEST_CASE == "bounded" then
    connect()
    C.sample(0, 0, true)
    for i = 1, 10000 do C.sample(i * 100, -i * 100, true) end
    C.sample(nil); tick(25)
    local x, y = move_sum(); assert(x == 1024 and y == -1024)
    local n = #T.moves
    C.set_speed(1); C.sample(0, 0, true); C.sample(1, 1, true); tick(2)
    assert(#T.moves == n)
    C.sample(1, 1, true); C.sample(2, 2, true); C.sample(nil); tick(2)
    x, y = move_sum(); assert(x == 1025 and y == -1023)
elseif TEST_CASE == "clock_wrap" then
    connect()
    T.now = 4294967290
    C.sample(0, 0, true); C.sample(5, 0, true); C.sample(nil); C.update()
    T.now = 4
    C.sample(0, 0, true); C.sample(5, 0, true); C.sample(nil); C.update()
    T.now = 40; C.update()
    local x, y = move_sum(); assert(x == 10 and y == 0 and #T.moves == 2)
elseif TEST_CASE == "busy" then
    connect()
    T.fail_next = "busy"
    C.sample(0, 0, true); C.sample(-70, 20, true); C.sample(nil); tick(4)
    local x, y = move_sum(); assert(x == -70 and y == 20)
    T.fail_next = "failed"; C.click("right"); tick(5)
    assert(#T.clicks == 1) -- Failed click must never be retried.
    T.hold = true
    C.sample(0, 0, true); C.sample(12, 0, true); tick()
    C.stop(false); assert(not radio.stats().open and not C.ready)
    T.hold = false; tick(3)
elseif TEST_CASE == "disconnect" then
    connect()
    C.sample(0, 0, true); C.sample(100, 100, true); C.click("right")
    T.state("advertising", false); tick(3)
    assert(not C.ready and #T.moves == 0 and #T.clicks == 0)
    T.state("connected", true); tick(4)
    assert(#T.moves == 0 and #T.clicks == 0)
    tap(layout.settings); tap(UI.compute().forget); tick(3)
    assert(T.forgot and not radio.stats().open)
elseif TEST_CASE == "start_error" then
    T.start_error = "busy"; C.start(); tick(3)
    assert(not radio.stats().open and not C.ready)
    T.start_error = nil; C.start(); tick(); T.state("closed", false); tick(2)
    assert(not radio.stats().open)
    C.start(); tick(); assert(T.starts == 3)
elseif TEST_CASE == "layout" then
    local function within(b)
        assert(b.w >= 40 and b.h >= 40)
        assert(b.x >= 0 and b.y >= 0 and b.x + b.w <= layout.w and b.y + b.h <= layout.bottom)
    end
    within(layout.pad); within(layout.primary)
    for i, b in ipairs(layout.clicks) do within(b); assert(UI.hit(b.x + 3, b.y + 3, C, false) == b.id) end
    for _, b in ipairs(layout.speeds) do within(b); tap(b) end
    assert(C.speed == 3 and layout.pad.w == layout.pad.h)
    assert(layout.clicks[1].y >= layout.pad.y + layout.pad.h)
    assert(layout.clicks[2].x >= layout.clicks[1].x + layout.clicks[1].w)
    assert(UI.hit(layout.pad.x + 4, layout.pad.y + 4, C, false) == nil)
    on_draw(); tap(layout.settings); on_draw(); tap(layout.back); on_draw()
elseif TEST_CASE == "redraw" then
    connect(); tick(2)
    local redraws = T.redraws
    for i = 1, 100 do
        C.sample(i - 1, i - 1, true); C.sample(i, i, true); C.sample(nil); tick()
    end
    assert(T.redraws == redraws, "motion must not redraw the e-ink screen")
elseif TEST_CASE == "repeated" then
    for _ = 1, 200 do
        connect(); C.click("left"); tick(2); C.stop(false)
        assert(not radio.stats().open and not punri.is_prevent_sleep())
    end
else error("Unknown mouse scenario: " .. TEST_CASE) end
on_exit()
assert(not radio.stats().open and not punri.is_prevent_sleep())
punri.log("Bluetooth Mouse scenario passed: " .. TEST_CASE)
