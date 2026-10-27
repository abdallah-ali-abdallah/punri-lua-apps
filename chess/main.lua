-- Every visible action owns a matching press target in its app sandbox.
PRESS_FEEDBACK = punri.dofile("press_feedback.lua")
local PRESS = PRESS_FEEDBACK
local PRESS_LABELS, PRESS_IDS = {}, {"footer:back", "footer:confirm", "footer:left", "footer:right"}
function press_hints(a, b, c, d)
    PRESS_LABELS[1], PRESS_LABELS[2], PRESS_LABELS[3], PRESS_LABELS[4] = a, b, c, d
    PRESS.footer(PRESS_LABELS, PRESS_IDS)
end
function press_ink(id, x, y, width, height, dark, shape, radius, enabled)
    PRESS.target(id, x, y, width, height, enabled, shape or "rounded", radius or 5, dark)
    local ink = PRESS.paint(id)
    if ink == nil then return dark ~= true end
    return ink
end

G = { board = {}, history = {}, dirty = {}, diff = 2, mode = "ai_white", menu_i = 1 }

function mark_dirty_sq(s)
  if s and s >= 1 and s <= 64 then G.dirty[s] = true end
end

function mark_dirty_rc(r, c)
  if r and c and r >= 1 and r <= 8 and c >= 1 and c <= 8 then
    local f = G.mode == "ai_black"
    G.dirty[(((f and (9 - r) or r) - 1) << 3) + (f and (9 - c) or c)] = true
  end
end

punri.log("0 BOOT: " .. collectgarbage("count"))
dofile("engine.lua"); collectgarbage()
punri.log("1 ENGINE: " .. collectgarbage("count"))
dofile("ui.lua"); collectgarbage()
punri.log("2 UI: " .. collectgarbage("count"))
dofile("logic.lua"); collectgarbage()
punri.log("3 LOGIC: " .. collectgarbage("count"))
dofile("input.lua"); collectgarbage()
punri.log("4 INPUT: " .. collectgarbage("count"))

function on_update()
  if G and G.hint_pending then
    G.hint_pending = nil
    G.ai_depth = 2
    local bm = dofile("ai.lua")
    if bm then
      local f, t = bm & 127, (bm >> 7) & 127
      G.hint_move = bm
      G.status = string.char(96 + ((f - 1) & 7) + 1, 48 + 8 - ((f - 1) >> 3)) .. "->" .. string.char(96 + ((t - 1) & 7) + 1, 48 + 8 - ((t - 1) >> 3))
      mark_dirty_sq(f); mark_dirty_sq(t)
      G.status_dirty = true
    end
    punri.request_update()
  elseif G and G.ai_pending then
    local now = punri.millis and punri.millis() or 0
    if not G.need_full_draw and not next(G.dirty) and now >= G.ai_start_time then
      G.ai_pending = nil; G.ai_busy = true; ai_step()
    end
  elseif G and G.ai_busy then ai_step() end
end
update = on_update

on_exit = function() dofile("save.lua") end
dofile("load.lua"); collectgarbage()
punri.log("CHESS READY: " .. collectgarbage("count") .. " KB")


-- Keep press lifetime separate from gameplay selection and persisted state.
punri.dofile("feedback.lua")(PRESS, {
    view = function() return G.menu and "menu" or "board" end,
    invalidate = function() G.need_full_draw = true end,
    transition = function(id) return id == "footer:back" or G.menu and id ~= "footer:left" and id ~= "footer:right" end,
    map_button = function(button) if button == "confirm" and G.menu then return "menu:" .. G.menu_i end end
})
