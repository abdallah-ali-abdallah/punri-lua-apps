-- Run with the repository's 32-bit Lua runtime:
-- lua tests/legacy_feedback.lua <apps-root> <app-id> <touch|buttons> [target-id]
-- The native LuaRunner and simulator remain the integration acceptance gates.
local apps_root, app_id = assert(arg[1]), assert(arg[2])
local touch = arg[3] ~= "buttons"
local now, width, height, exits, redraws = 0, 480, 800, 0, 0
local saved, writes, text_calls, fills = {}, 0, {}, 0
local app_root = apps_root .. "/" .. app_id .. "/"
local native_loadfile = loadfile
local function read(path)
    local file = io.open(app_root .. path, "rb")
    if not file then return nil end
    local data = file:read("a"); file:close(); return data
end
local function noop() end
punri = {
    millis = function() return now end,
    get_bounds = function() return width, height end,
    get_metrics = function() return {top_padding=4, header_height=72, content_side_padding=12, button_hints_height=touch and 0 or 40} end,
    has_touch = function() return touch end,
    is_button_down = function() return false end,
    request_update = function() redraws = redraws + 1 end,
    exit = function() exits = exits + 1 end,
    dofile = function(path) return assert(native_loadfile(app_root .. path))() end,
    load = function(key, fallback) if saved[key] == nil then return fallback end; return saved[key] end,
    save = function(key, value) saved[key]=value; writes=writes+1; return true end,
    read_file = function(path) if saved[path] ~= nil then return saved[path] end; return read(path) end,
    write_file = function(path, value) saved[path]=value; writes=writes+1; return true end,
    get_date = function() return {year=2026,month=10,day=27,hour=12,min=34,sec=0,wday=3,yday=300,valid=true,offset_minutes=120} end,
    get_battery = function() return 87 end,
    get_memory = function() return {lua_kb=64, lua_limit_kb=1024, free_heap=100000, largest_block=80000} end,
    line_height = function(font) return font == "small" and 18 or font == "ui12" and 26 or 22 end,
    text_width = function(text, font) return #tostring(text) * (font == "small" and 7 or 10) end,
    in_rect = function(x,y,rx,ry,rw,rh) return x>=rx and y>=ry and x<rx+rw and y<ry+rh end,
    set_orientation = function(orientation)
        if orientation == "landscape" or orientation == "landscape_ccw" then width,height=800,480 else width,height=480,800 end
    end,
    wrapped_text = function(text)
        local lines = {tostring(text)}; lines.lines=lines; return lines
    end,
    text = function(x,y,value,font,style,align,ink)
        assert(type(x)=="number" and type(y)=="number", "invalid text geometry")
        text_calls[#text_calls+1]={text=tostring(value),ink=ink,x=x,y=y}
    end,
    rect = function(x,y,w,h,filled)
        assert(type(x)=="number" and type(y)=="number" and type(w)=="number" and type(h)=="number", "invalid rect")
        if filled then fills=fills+1 end
    end,
    rounded_rect = function(x,y,w,h,r,filled)
        assert(type(x)=="number" and type(y)=="number" and type(w)=="number" and type(h)=="number", "invalid rounded rect")
        if filled then fills=fills+1 end
    end,
    rect_dither = function() fills=fills+1 end,
    clear=noop, header=noop, centered_text=noop, line=noop, thick_line=noop,
    circle=noop, pixel=noop, draw_sprite=noop, invert_screen=noop,
    full_refresh=noop, prevent_sleep=noop, button_hints=noop, log=noop,
}
dofile=punri.dofile
ink=punri
punri.date=punri.get_date
function punri.find_section(path, start_marker, end_marker, callback)
    local data=read(path)
    if not data then return false end
    local found=false
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        line=line:gsub("\r$", "")
        if not found then found=line == start_marker
        elseif line:sub(1,#end_marker)==end_marker then break
        elseif callback(line)==false then break end
    end
    return found
end
assert(native_loadfile(app_root .. "main.lua"))()
if on_init then on_init() end
assert(type(on_draw)=="function" and type(on_update)=="function")
on_draw()
local F=assert(PRESS_FEEDBACK)
assert(F.count>0, app_id .. " exposes no visible actions")
local function tap_target(id)
    local function target(name)
        for i=F.count,1,-1 do if F.targets[i].id==name and F.targets[i].enabled then return F.targets[i] end end
    end
    local clock_surface = id == "@clock"
    if clock_surface then id = "footer:confirm" end
    local t=assert(target(id), app_id .. ": missing enabled target " .. id)
    local x,y=t.x+t.w//2,t.y+t.h//2
    if clock_surface then x,y=width//3,160 end
    now=now+10
    on_tap(x,y)
    assert(F.active(id), app_id .. ": tap did not arm " .. tostring(id))
    -- Firmware invokes the compatibility callback for the same physical tap.
    if on_touch then on_touch(x,y,"tap") end
    assert(F.active(id), app_id .. ": compatibility callback changed feedback")
    -- Time before the first feedback paint must not consume the visible500ms.
    now=now+100
    on_update()
    assert(F.active(id), app_id .. ": expired before its first feedback frame")
    on_draw()
    assert(F.active(id), app_id .. ": first feedback frame was not painted")
    now=now+499
    on_update()
    assert(F.active(id), app_id .. ": feedback expired before500ms")
    now=now+1
    on_update()
    assert(not F.active(), app_id .. ": feedback did not expire at500ms")
    on_draw()
end
local sequences={
    ["2048"]={"footer:left","footer:confirm","footer:back","footer:confirm","footer:confirm"},
    blockdrop={"footer:left","footer:confirm","footer:right"},
    chess={"footer:left","footer:back","menu:1","footer:back","menu:3","menu:1"},
    codex={"title:2","tab:4","deck_menu:2","title:1","footer:left"},
    dashboard={"@clock","footer:confirm","footer:left","footer:right"},
    dice={"footer:left","footer:right","footer:confirm"},
    hourglass={"settings","step1:-","step1:+","step2:-","step2:+","done","footer:confirm","footer:confirm","footer:left"},
    solitaire={"reset","cancel_reset","reset","confirm_reset","footer:left"},
    sudoku={"difficulty:1","new_game","difficulty:2","hint"},
    tictactoe={"mode:1","cell:1","new_game","mode","mode:2","cell:2"},
    watertracker={"footer:confirm","setting:1","setting:2","setting:3","history","footer:back","footer:back","footer:right"},
    wordle={"key:0","key:1","key:28","key:29","footer:back","key:29","footer:confirm"},
}
local sequence=arg[4]=="all" and sequences[app_id] or {arg[4] or "footer:left"}
assert(sequence, "no scenario for " .. app_id)
for _,id in ipairs(sequence) do tap_target(id) end
local refreshed=redraws
now=now+1
on_update()
assert(redraws-refreshed<=1, app_id .. ": unexpected redraw burst")
assert(fills>0 and #text_calls>0, app_id .. ": controls never rendered")
if on_exit then on_exit() end
print(string.format("PASS %s %s actions=%d redraws=%d writes=%d exits=%d", app_id,touch and "touch" or "buttons",#sequence,redraws,writes,exits))
