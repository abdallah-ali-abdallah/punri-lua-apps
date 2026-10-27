-- Run from the firmware root with its own 32-bit Lua sources, or a compatible
-- Lua interpreter: lua apps/tests/stopwatch/scenarios.lua. No SD fixture mutates.
local app = "apps/stopwatch/"
local clock, width, height, touch, stored, fail_write, exits, writes, awake, requests
local labels, shapes = {}, {}
local tests, assertions = 0, 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message or "assertion failed")
end
local function shape(kind,x,y,w,h,...)
    shapes[#shapes+1]={kind=kind,x=x,y=y,w=w,h=h}
    check(x>=0 and y>=0 and w>0 and h>0 and x+w<=width and y+h<=height,
        string.format("%s outside %dx%d: %d,%d %dx%d",kind,width,height,x,y,w,h))
end
local function fixture(w,h,has_touch,saved)
    clock,width,height,touch,stored,fail_write,exits,writes,awake,requests=0,w or 480,h or 800,has_touch~=false,saved,false,0,0,false,0
    punri={
        millis=function() return clock end,
        get_bounds=function() return width,height end,
        get_metrics=function() return {top_padding=4,content_side_padding=12,header_height=48,button_hints_height=40} end,
        has_touch=function() return touch end,
        line_height=function(font) return font=="ui12" and 30 or 20 end,
        text_width=function(value,font) return #value*(font=="ui12" and 13 or 9) end,
        text=function(x,y,value,font,style,align,ink) labels[#labels+1]={x=x,y=y,value=value,font=font,align=align,ink=ink} end,
        rect=function(x,y,w,h,...) shape("rect",x,y,w,h,...) end,
        rounded_rect=function(x,y,w,h,...) shape("rounded",x,y,w,h,...) end,
        rect_dither=function(x,y,w,h,...) shape("dither",x,y,w,h,...) end,
        circle=function(x,y,r,...) shape("circle",x-r,y-r,r*2,r*2,...) end,
        line=function() end,
        clear=function() end,
        button_hints=function() end,
        prevent_sleep=function(value) awake=value end,
        read_file=function() return stored end,
        write_file=function(_,data) writes=writes+1;if fail_write then return false end;stored=data;return true end,
        request_update=function() requests=requests+1 end,
        exit=function() exits=exits+1 end,
        dofile=function(path) return dofile(app..path) end,
    }
    TEST_APP="stopwatch"
    dofile(app.."main.lua")
    on_init()
    labels,shapes={},{}
    on_draw()
    return STOPWATCH_TEST.model,STOPWATCH_TEST.ui,STOPWATCH_TEST.feedback
end
local function draw() labels,shapes={},{};on_draw() end
local function shown(value)
    for _,label in ipairs(labels) do if label.value==value then return true end end
    return false
end
local function tick(delta)
    clock=clock+delta
    on_update()
end
local function tap(action)
    local l=STOPWATCH_TEST.ui.refresh()
    local target=l[action]
    if not target then for _,b in ipairs(l.buttons) do if b.action==action then target=b;break end end end
    check(target~=nil,"missing target "..action)
    on_tap(target.x+target.w//2,target.y+target.h//2)
end
local function settle()
    draw();tick(500);draw()
end
local function test(name,callback)
    tests=tests+1
    callback()
    io.write("PASS ",name,"\n")
end

test("immediate timestamps and half-second feedback",function()
    local m,_,f=fixture()
    check(shown("00:00:00.00"))
    check(on_touch==nil,"only one touch callback")
    tap("toggle");check(m.running and awake)
    draw();check(f.active("toggle"))
    tick(499);check(f.active("toggle") and m:elapsed()==499)
    tick(1);check(not f.active() and m:elapsed()==500)
    tick(734);tap("lap");check(#m.laps==1 and m.laps[1].lap_ms==1234)
    draw();tick(266);tap("toggle")
    check(not m.running and m.accumulated_ms==1500 and not awake)
    draw();tick(500);check(m:elapsed()==1500 and not f.active())
end)

test("disabled actions and exact hit boundaries",function()
    local m,ui,f=fixture()
    local l=ui.refresh()
    local before=writes
    tap("lap");tap("reset");check(not f.active() and writes==before and not m.running)
    on_tap(l.buttons[1].x-1,l.buttons[1].y+5);check(not m.running)
    on_tap(l.buttons[1].x+l.buttons[1].w,l.buttons[1].y+5);check(not m.running)
    on_button("confirm",false);check(not m.running)
    on_button("confirm",true);check(m.running)
    on_button("confirm",true);check(not m.running)
end)

test("reset navigation paints before changing the view",function()
    local m,_,f=fixture()
    tap("toggle");tick(1000);tap("toggle");draw()
    tap("reset");check(not m.reset_pending and f.busy())
    draw();tick(499);check(not m.reset_pending)
    tick(1);check(m.reset_pending and m.accumulated_ms==1000)
    draw();tap("keep");check(m.reset_pending)
    settle();check(not m.reset_pending and m.accumulated_ms==1000)
    tap("reset");settle();tap("confirm");draw()
    tap("confirm");check(m.reset_pending,"duplicate confirm cannot execute early")
    tick(500);draw();check(not m.reset_pending and m:elapsed()==0 and #m.laps==0)
end)

test("clock keeps running while visual feedback is pending",function()
    local m=fixture()
    tap("toggle");draw();tick(1234);tap("reset");draw();tick(500)
    check(m.reset_pending and m.accumulated_ms==1734)
    draw();tick(2000);tap("keep");settle()
    check(m.running and m:elapsed()==1734)
    tick(10);check(m:elapsed()==1744)
end)

test("save failure survives feedback and retries before exit",function()
    local m=fixture()
    tap("toggle");tick(444);fail_write=true;tap("lap");draw()
    check(m.save_error~=nil and exits==0)
    tick(500);draw();check(m.save_error~=nil and shown("Retry save"))
    tap("exit");settle();check(exits==0 and m.save_error~=nil)
    fail_write=false;tap("exit");check(exits==0);settle();check(exits==1 and m.save_error==nil)
end)

test("legacy snapshots restore stopped and invalid data stays intact",function()
    local saved="1;12340\n5000;5000\n7340;12340"
    local m=fixture(480,800,true,saved)
    check(not m.running and m:elapsed()==12340 and #m.laps==2 and stored==saved)
    check(m.notice=="Stopped after restart")
    saved="1;nan\n5000;12340"
    m=fixture(480,800,true,saved)
    check(m.load_error~=nil and m:elapsed()==0)
    on_exit();check(stored==saved)
end)

test("fifty laps, paging, fastest and disabled final lap",function()
    local m,ui,f=fixture()
    tap("toggle")
    for i=1,50 do tick(i);tap("lap");draw() end
    check(#m.laps==50 and not m:is_lap_enabled())
    check(f.active("lap"),"last accepted lap remains visibly acknowledged")
    tick(500);draw();local before=writes;tap("lap");check(writes==before)
    local best,worst=m:best_worst();check(best==1 and worst==50)
    check(ui.visible_laps()==4)
    on_button("up",true);check(m.lap_page==1)
    on_button("down",true);check(m.lap_page==0)
end)

test("32-bit wrap, precision and elapsed bound",function()
    local m=fixture()
    local Model=punri.dofile("stopwatch.lua")
    check(math.maxinteger==2147483647,"run with production 32-bit Lua")
    check(Model.format_time(359999990)=="99:59:59.99")
    check(Model.elapsed_delta(2147483600,-2147483600)==96)
    check(Model.elapsed_delta(-100,100)==200)
    check(Model.elapsed_delta(1000,999)==0)
    check(Model.elapsed_delta(-2147483600,2147483600)==0,"a huge stale interval cannot become negative elapsed")
    clock=2147483600;tap("toggle");draw();clock=-2147483600;on_update()
    check(m:elapsed()==96)
    m.running=false;m.accumulated_ms=359999980;clock=0;tap("toggle");tick(20)
    check(not m.running and m:elapsed()==359999990 and not awake)
end)

for _,size in ipairs({{480,800,true},{800,480,true},{480,800,false},{800,480,false}}) do
    test(string.format("bounded vector layout %dx%d touch=%s",size[1],size[2],tostring(size[3])),function()
        local m,ui=fixture(size[1],size[2],size[3])
        check(shown("STOPWATCH") and shown("Start") and shown("Lap") and shown("Reset") and shown("Exit"))
        check(shown("CHRONOGRAPH") and shown("1/100 SEC") and shown("No laps yet"))
        tap("toggle");draw();tick(1000);tap("lap");draw();tap("toggle");draw()
        tap("reset");settle();check(m.reset_pending)
        tap("confirm");settle();check(m:elapsed()==0)
        local l=ui.refresh()
        check(l.time.x+l.time.w<=size[1] and l.laps.y+l.laps.h<=size[2])
    end)
end
io.write(string.format("Validated %d Stopwatch scenarios, %d assertions.\n",tests,assertions))
