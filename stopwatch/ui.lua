-- Original vector-LCD chronograph. Drawing and hit testing share these boxes.
local UI, feedback = {}, nil
local layout = {width=0,height=0,time={},laps={},modal={},buttons={{action="toggle"},{action="lap"},{action="reset"},{action="exit"}},previous={action="previous"},next={action="next"},page={},keep={action="keep"},confirm={action="confirm"},visible_laps=4}
local segments = {0x3f,0x06,0x5b,0x4f,0x66,0x6d,0x7d,0x07,0x7f,0x6f}
local function box(r,x,y,w,h) r.x,r.y,r.w,r.h=x,y,w,h end
local function lh(f) return math.max(1,punri.line_height(f)) end
local function inside(r,x,y) return x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
local function fit(value,width,font,style)
    if punri.text_width(value,font,style)<=width then return value end
    local last=#value
    while last>0 do
        local shown=value:sub(1,last).."..."
        if punri.text_width(shown,font,style)<=width then return shown end
        last=last-1
        while last>0 and value:byte(last+1)>=128 and value:byte(last+1)<192 do last=last-1 end
    end
    return ""
end
local function text(x,y,value,font,style,align,ink,width)
    punri.text(x,y,fit(value,width or layout.width-32,font,style),font,style,align or "left",ink~=false)
end
local function centered(r,value,font,ink)
    text(r.x+r.w//2,r.y+math.max(0,(r.h-lh(font))//2),value,font,"bold","center",ink,r.w-16)
end
function UI.bind(value) feedback=value end
function UI.refresh()
    local w,h=punri.get_bounds()
    if layout.width==w and layout.height==h then return layout end
    local m=punri.get_metrics()
    local side,gap=math.max(16,m.content_side_padding or 12),12
    local top=(m.top_padding or 0)+8
    local touch=punri.has_touch and punri.has_touch()
    local bottom=h-(touch and 12 or (m.button_hints_height or 40)+8)
    layout.width,layout.height,layout.landscape=w,h,w>h
    layout.side,layout.top=side,top
    layout.content_top=top+lh("ui12")+lh("small")+20
    box(layout.buttons[4],w-side-128,top,128,math.max(40,lh("small")+16))
    local left_w=w-side*2
    if layout.landscape then left_w=(left_w-gap)*48//100 end
    local face_h=layout.landscape and 170 or 190
    box(layout.time,side,layout.content_top,left_w,face_h)
    local by,bw=layout.time.y+face_h+gap,(left_w-gap)//2
    local bh=layout.landscape and 60 or 68
    box(layout.buttons[1],side,by,bw,bh)
    box(layout.buttons[2],side+bw+gap,by,left_w-bw-gap,bh)
    box(layout.buttons[3],side,by+bh+gap,left_w,42)
    if layout.landscape then box(layout.laps,side+left_w+gap,layout.content_top,w-side*2-left_w-gap,bottom-layout.content_top)
    else local ly=layout.buttons[3].y+layout.buttons[3].h+16;box(layout.laps,side,ly,left_w,bottom-ly) end
    local c=layout.laps
    layout.heading_y,layout.columns_y=c.y+12,c.y+16+lh("ui12")
    layout.rows_y=layout.columns_y+lh("small")+10
    local ph=math.max(36,lh("small")+12)
    local py,pw=c.y+c.h-ph-10,(c.w-48)//3
    box(layout.previous,c.x+12,py,pw,ph)
    box(layout.page,c.x+24+pw,py,pw,ph)
    box(layout.next,c.x+36+pw*2,py,pw,ph)
    layout.best_y=py-lh("small")-9
    local available=math.max(lh("small")+8,layout.best_y-layout.rows_y-6)
    layout.visible_laps=math.max(1,math.min(4,available//(lh("small")+12)))
    layout.row_height=available//layout.visible_laps
    local mw,mh=math.min(420,w-side*2),198
    box(layout.modal,(w-mw)//2,(h-mh)//2,mw,mh)
    local modal=layout.modal
    local cw=(mw-36)//2
    box(layout.keep,modal.x+12,modal.y+mh-60,cw,46)
    box(layout.confirm,modal.x+24+cw,modal.y+mh-60,cw,46)
    return layout
end
function UI.visible_laps() return UI.refresh().visible_laps end
function UI.action_enabled(model,action)
    if model.reset_pending then return action=="keep" or action=="confirm" end
    if action=="toggle" then return model:is_toggle_enabled() end
    if action=="lap" then return model:is_lap_enabled() end
    if action=="reset" then return model:is_reset_enabled() end
    local pages=math.max(1,(#model.laps+UI.visible_laps()-1)//UI.visible_laps())
    if action=="previous" then return model.lap_page<pages-1 end
    if action=="next" then return model.lap_page>0 end
    return action=="exit"
end
function UI.hit_action(model,x,y)
    local l=UI.refresh()
    if model.reset_pending then
        if inside(l.keep,x,y) then return "keep" end
        if inside(l.confirm,x,y) then return "confirm" end
        return nil
    end
    for _,b in ipairs(l.buttons) do if inside(b,x,y) and UI.action_enabled(model,b.action) then return b.action end end
    if inside(l.previous,x,y) and UI.action_enabled(model,"previous") then return "previous" end
    if inside(l.next,x,y) and UI.action_enabled(model,"next") then return "next" end
end
function UI.press(action) return feedback.press(action) end
function UI.defer(action,callback) return feedback.defer(action,callback) end
function UI.clear() feedback.clear() end
local function draw_button(model,b,label,dark,font,enabled)
    if enabled==nil then enabled=UI.action_enabled(model,b.action) end
    feedback.target(b.action,b.x,b.y,b.w,b.h,enabled or feedback.active(b.action),"rounded",10,dark)
    punri.rounded_rect(b.x,b.y,b.w,b.h,10,true,dark==true)
    punri.rounded_rect(b.x,b.y,b.w,b.h,10,false,enabled and 2 or 1,true)
    if not enabled then punri.rect_dither(b.x+5,b.y+5,b.w-10,b.h-10,false) end
    local ink=feedback.paint(b.action)
    if ink==nil then ink=not dark end
    centered(b,label,font or "ui12",ink)
end
local function digit(x,y,w,h,value)
    local t,g=math.max(3,w//7),2
    local half,mask=h//2,segments[value+1]
    if mask&1~=0 then punri.rect(x+t+g,y,w-t*2-g*2,t,true) end
    if mask&2~=0 then punri.rect(x+w-t,y+t+g,t,half-t-g*2,true) end
    if mask&4~=0 then punri.rect(x+w-t,y+half+g,t,h-half-t-g*2,true) end
    if mask&8~=0 then punri.rect(x+t+g,y+h-t,w-t*2-g*2,t,true) end
    if mask&16~=0 then punri.rect(x,y+half+g,t,h-half-t-g*2,true) end
    if mask&32~=0 then punri.rect(x,y+t+g,t,half-t-g*2,true) end
    if mask&64~=0 then punri.rect(x+t+g,y+half-t//2,w-t*2-g*2,t,true) end
end
local function pair(x,y,w,h,value,gap)
    digit(x,y,w,h,value//10%10);digit(x+w+gap,y,w,h,value%10)
end
local function draw_face(model,f)
    punri.rounded_rect(f.x,f.y,f.w,f.h,16,false,3,true)
    punri.rounded_rect(f.x+5,f.y+5,f.w-10,f.h-10,12,false,1,true)
    local elapsed=model:elapsed()
    local seconds,cs=elapsed//1000,elapsed//10%100
    local hours,minutes=seconds//3600,seconds//60%60
    text(f.x+16,f.y+14,"CHRONOGRAPH","small","bold","left",true,f.w//2)
    text(f.x+f.w-16,f.y+14,"1/100 SEC","small","regular","right",true,f.w//2)
    local dw=math.max(24,math.min(60,(f.w-38)*10//64))
    local dh,dg,sw=dw*17//10,math.max(4,dw//7),dw*55//100
    local sh,col=dh*60//100,math.max(10,dw//3)
    local total=dw*4+dg*5+col+sw*2+8
    local x,y=f.x+(f.w-total)//2,f.y+18+lh("small")+8
    pair(x,y,dw,dh,minutes,dg)
    local cx=x+dw*2+dg*2
    local dot=math.max(4,dw//9)
    punri.rect(cx+(col-dot)//2,y+dh//3-dot//2,dot,dot,true)
    punri.rect(cx+(col-dot)//2,y+dh*2//3-dot//2,dot,dot,true)
    local sx=cx+col+dg
    pair(sx,y,dw,dh,seconds%60,dg)
    local csx=sx+dw*2+dg+8
    punri.rect(csx-6,y+dh-dot,dot,dot,true)
    pair(csx,y+dh-sh,sw,sh,cs,dg)
    local cy=math.min(f.y+f.h-lh("small")-14,y+dh+10)
    text(f.x+16,cy,string.format("HOURS %02d",hours),"small","regular","left",true,f.w//3)
    text(f.x+f.w-16,cy,model:format_time(elapsed),"small","regular","right",true,f.w*2//3)
end
local function draw_laps(model,l)
    local c=l.laps
    punri.rounded_rect(c.x,c.y,c.w,c.h,12,false,1,true)
    text(c.x+12,l.heading_y,"Laps","ui12","bold","left",true,c.w//2)
    text(c.x+c.w-12,l.heading_y+3,string.format("%02d / 50",#model.laps),"small","regular","right",true,c.w//2)
    text(c.x+12,l.columns_y,"LAP","small","bold","left",true,52)
    text(c.x+c.w*52//100,l.columns_y,"SPLIT","small","bold","center",true,c.w//3)
    text(c.x+c.w-12,l.columns_y,"TOTAL","small","bold","right",true,c.w//3)
    punri.line(c.x+12,l.rows_y-5,c.x+c.w-12,l.rows_y-5,1,true)
    local count,best=#model.laps,model:best_worst()
    if count==0 then
        local y=l.rows_y+(l.best_y-l.rows_y-lh("ui12")-lh("small")-8)//2
        text(c.x+c.w//2,y,"No laps yet","ui12","bold","center",true,c.w-24)
        text(c.x+c.w//2,y+lh("ui12")+8,"Start, then tap Lap","small","regular","center",true,c.w-24)
    else
        local start=count-model.lap_page*l.visible_laps
        for row=0,l.visible_laps-1 do
            local index=start-row;if index<1 then break end
            local lap=model.laps[index]
            local y=l.rows_y+row*l.row_height+(l.row_height-lh("small"))//2
            local best_lap=count>1 and lap.lap_ms==best
            text(c.x+12,y,string.format("%02d%s",index,best_lap and "*" or ""),"small",best_lap and "bold" or "regular","left",true,c.w//5)
            text(c.x+c.w*52//100,y,model:format_time(lap.lap_ms),"small",best_lap and "bold" or "regular","center",true,c.w*42//100)
            text(c.x+c.w-12,y,model:format_time(lap.total_ms),"small","regular","right",true,c.w*37//100)
            if row<l.visible_laps-1 and index>1 then punri.line(c.x+12,l.rows_y+(row+1)*l.row_height,c.x+c.w-12,l.rows_y+(row+1)*l.row_height,1,true) end
        end
        if count>1 then text(c.x+12,l.best_y,"* Fastest "..model:format_time(best),"small","regular","left",true,c.w-24) end
    end
    local pages=math.max(1,(count+l.visible_laps-1)//l.visible_laps)
    draw_button(model,l.previous,"Older",false,"small")
    draw_button(model,l.next,"Newer",false,"small")
    punri.rounded_rect(l.page.x,l.page.y,l.page.w,l.page.h,8,false,1,true)
    centered(l.page,string.format("Page %d/%d",model.lap_page+1,pages),"small",true)
end
local function draw_confirmation(model,l)
    local m=l.modal
    punri.rect_dither(0,0,l.width,l.height,false)
    punri.rounded_rect(m.x,m.y,m.w,m.h,14,true,false)
    punri.rounded_rect(m.x,m.y,m.w,m.h,14,false,3,true)
    text(m.x+m.w//2,m.y+16,"Reset stopwatch?","ui12","bold","center",true,m.w-24)
    text(m.x+m.w//2,m.y+24+lh("ui12"),"Elapsed time and laps will clear.","small","regular","center",true,m.w-24)
    text(m.x+m.w//2,m.y+28+lh("ui12")+lh("small"),"Keep returns to this session.","small","regular","center",true,m.w-24)
    draw_button(model,l.keep,"Keep",model.reset_choice=="keep","ui12",true)
    draw_button(model,l.confirm,"Reset now",model.reset_choice=="confirm","ui12",true)
end
function UI.draw(model)
    local l=UI.refresh()
    feedback.begin(model.reset_pending and "stopwatch-reset" or "stopwatch-main")
    punri.clear()
    text(l.side,l.top,"STOPWATCH","ui12","bold","left",true,l.width-l.side*2-144)
    text(l.side,l.top+lh("ui12")+3,model:status(),"small","regular","left",true,l.width-l.side*2-144)
    draw_button(model,l.buttons[4],model.save_error and "Retry save" or "Exit",false,"small",not model.reset_pending)
    draw_face(model,l.time)
    draw_button(model,l.buttons[1],model.running and "Stop" or "Start",true,"ui12")
    draw_button(model,l.buttons[2],"Lap",false,"ui12")
    draw_button(model,l.buttons[3],"Reset",false,"small")
    draw_laps(model,l)
    local message=model:message()
    if message then
        local y=l.time.y+l.time.h-lh("small")-11
        punri.rect(l.time.x+10,y-2,l.time.w-20,lh("small")+4,true,false)
        text(l.time.x+l.time.w//2,y,message,"small","bold","center",true,l.time.w-28)
    end
    if model.reset_pending then draw_confirmation(model,l) end
    punri.button_hints(model.reset_pending and "Keep" or "Exit",model.reset_pending and "Select" or (model.running and "Stop" or "Start"),model.reset_pending and "Keep" or "Lap","Reset")
    feedback.finish()
end
return UI
