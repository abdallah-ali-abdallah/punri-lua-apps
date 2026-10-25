local root = assert(arg[1])
local B = dofile(root .. "/bigint.lua")
local D = dofile(root .. "/decimal.lua")(B)
local N = dofile(root .. "/number.lua")(B,D)
local P = dofile(root .. "/parser.lua")
local E = dofile(root .. "/engine.lua")(B,D,N,P)
local Editor = dofile(root .. "/editor.lua")(P)
local Store = dofile(root .. "/storage.lua")
local I = dofile(root .. "/i18n.lua")
local Tools = dofile(root .. "/tools.lua")(B,D,N,E,P)
local orientation, clock, saved, failed_write, exited = "portrait", 0, {}, false, false
local sizes = {small = {8,18}, ui10 = {10,22}, ui12 = {12,28}}
punri = {
    millis = function() return clock end,
    get_bounds = function() return orientation == "portrait" and 480 or 800, orientation == "portrait" and 800 or 480 end,
    get_metrics = function() return {header_height = 84, top_padding = 4, button_hints_height = 40, content_side_padding = 20} end,
    text_width = function(text,font) return #tostring(text)*sizes[font or "ui10"][1] end,
    line_height = function(font) return sizes[font or "ui10"][2] end,
    wrapped_text = function(text,w,font,style,maxlines)
        local out, chars = {}, math.max(1,w//sizes[font or "ui10"][1])
        for i=1,math.min(#text,chars*(maxlines or 3)),chars do out[#out+1]=text:sub(i,i+chars-1) end
        return out
    end,
    read_file = function(path) return saved[path] end,
    write_file = function(path,value) if failed_write then return false end; saved[path]=value; return true end,
    has_feature = function() return true end,
    set_orientation = function(value) orientation=value end,
    get_memory = function() return {lua_kb=math.floor(collectgarbage("count")),lua_max_kb=2048} end,
    log = function() end, request_update = function() end, full_refresh = function() end,
    exit = function() exited=true end, keyboard = function() return true end,
    clear = function() end, text = function() end, line = function() end, rect = function() end,
}
local UI = dofile(root .. "/ui.lua")(I,P,N,D)
local app = dofile(root .. "/app.lua")(E,Editor,Store,Tools,UI,I)
local checks = 0
local function check(condition, message) assert(condition,message); checks=checks+1 end
local function tap(id,value)
    for _,c in ipairs(UI.controls) do if c.id==id and c.value==value then app:tap(c.x+c.w/2,c.y+c.h/2);return end end
    error("Missing control "..id..":"..tostring(value))
end
local function geometry()
    local w,h=punri.get_bounds()
    for _,c in ipairs(UI.controls) do check(c.x>=0 and c.y>=0 and c.x+c.w<=w+1 and c.y+c.h<=h+1,"Control out of bounds: "..c.id) end
    check(#UI.commands<2400,"Drawing budget")
end
app:init(); geometry()
app:button("confirm",true);check(app.state.editor.source=="7","Button Confirm enters a digit exactly once")
tap("key","Clear");tap("template","fraction");tap("key","3");tap("action","next_field");tap("key","4");tap("key","=")
check(app.state.answer=="0.75","Touch fraction result")
tap("rotate",nil);geometry();check(orientation=="landscape" and app.state.editor.source=="(3)/(4)","Rotation preserves work")
tap("view","functions");tap("edit_function",1);Editor.set(app.state.editor,"sin(x)");app:dispatch("key","=")
check(app.state.functions[1].source=="sin(x)" and app.state.editor.source=="(3)/(4)","Function editor preserves calculator draft")
for _,mode in ipairs({"portrait","landscape"}) do
    orientation=mode;app.state.orientation=mode
    for _,view in ipairs({"calculate","functions","graph","table","tools"}) do
        app:dispatch("view",view)
        for _=1,150 do app:update() end
        geometry();UI.draw()
    end
    for _,tool in ipairs({"solve","statistics","matrix","complex","base","units","settings"}) do app:dispatch("tool",tool);geometry() end
end
app:dispatch("view","graph")
app.state.functions={{source="1/x",enabled=true},{source="",enabled=false},{source="",enabled=false},{source="",enabled=false}}
app.state.graph.dirty=true
for _=1,150 do app:update() end
for _,line in ipairs(app.state.graph.lines) do check(not(line[1]<0.5 and line[3]>0.5),"No segment bridges the 1/x pole") end
app:dispatch("view","calculate");Editor.set(app.state.editor,"(x)^(2)=9");app:dispatch("key","=")
check(app.state.sheet.kind=="form" and app.state.sheet.tool=="solve","Equation opens solver")
app:dispatch("run_tool")
for _=1,80 do app:update() end
check(app.state.sheet.kind=="result" and app.state.sheet.rows[1][2]=="3","Async numerical solve")
app:dispatch("tool","solve");app:dispatch("run_tool");app:dispatch("back");check(not app.state.job,"Cancel solver")
app:dispatch("view","calculate");Editor.set(app.state.editor,"1234567890123+1");app:dispatch("key","=")
clock=clock+2500;app:update();check(saved[Store.FILE]~=nil,"Debounced snapshot")
local old=saved[Store.FILE]
failed_write=true;Editor.set(app.state.editor,"8");app:dispatch("key","=");clock=clock+2500;app:update()
check(app.state.save_failed and saved[Store.FILE]==old,"Failed write preserves prior snapshot")
app:dispatch("back");check(app.state.sheet.kind=="save_error" and not exited,"Exit save failure is reviewable")
failed_write=false;app:dispatch("retry_exit");check(exited,"Retry saves then exits")
app:init();check(app.state.editor.source=="8" and app.state.answer=="8","Reopen persisted calculator")
saved[Store.FILE]="PUNRI_CALCULATIONS_2\nfuture data"
app:init();check(app.state.readonly,"Unknown schema is read-only")
Editor.set(app.state.editor,"9");app.state.dirty=true;app:save();check(saved[Store.FILE]:find("future data",1,true),"Unknown schema retained")
app:dispatch("reset_confirm");check(not app.state.readonly and app.state.editor.source=="","Explicit reset")
collectgarbage("collect");local baseline=collectgarbage("count")
for _=1,20 do app:dispatch("view","graph");for _=1,100 do app:update() end;app:dispatch("view","calculate") end
collectgarbage("collect");local retained=collectgarbage("count")
check(retained-baseline<128,"No progressive graph workspace growth")
print("PASS "..checks.." controller/layout/persistence checks; retained Lua="..math.floor(retained).."KB")
