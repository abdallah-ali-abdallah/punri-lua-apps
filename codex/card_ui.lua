-- Codex: Ink & Iron — Compact Card & Inspector Rendering
function coup_on(c)
    if not c or not c.couplet or c.couplet == "None" then return false end
    if state.playerStatus and state.playerStatus.transcendence then return true end
    local m = state.lastPlayedMeter
    return (c.couplet == "AfterBlade" and m == "Blade") or
           (c.couplet == "AfterWard" and m == "Ward") or
           (c.couplet == "AfterScript" and m == "Script")
end

function draw_card_item(x, y, cw, ch, c, isSel, id)
    if not c then return end
    local coup = coup_on(c)
    punri.rect(x, y, cw, ch, true, false)
    punri.rounded_rect(x, y, cw, ch, 4, false, isSel and 2 or 1)
    local ink = true
    if id then ink = press_ink(id, x, y, cw, ch, false, "rounded", 4, true) end
    punri.circle(x + 13, y + 13, 9, true, 1, ink)
    punri.text(x + 9, y + 4, tostring(c.cost), "small", "bold", "center", not ink)
    punri.text(x + cw - 6, y + 6, c.meter, "small", "bold", "right", ink)
    local divY = y + 26
    punri.line(x + 3, divY, x + cw - 3, divY, 1, ink)
    local nRes = punri.wrapped_text(c.name, cw - 6, "small", "regular", 2)
    local ty = divY + 4
    for _, l in ipairs(nRes and nRes.lines or {}) do
        punri.text(x + math.floor(cw / 2), ty, l, "small", "bold", "center", ink)
        ty = ty + punri.line_height("small") - 1
    end
    ty = ty + 3
    local dRes = punri.wrapped_text(c.desc, cw - 6, "small", "regular", 3)
    for _, dl in ipairs(dRes and dRes.lines or {}) do
        punri.text(x + math.floor(cw / 2), ty, dl, "small", "regular", "center", ink)
        ty = ty + punri.line_height("small") + 2
    end
    if c.cDesc then
        local bH = 44
        local by = y + ch - bH - 4
        punri.rect(x + 3, by, cw - 6, bH, coup, 1, ink)
        local t1 = coup and "COUPLET" or "Couplet:"
        punri.text(x + math.floor(cw / 2), by + 3, t1, "small", coup and "bold" or "regular", "center", coup ~= ink)
        punri.text(x + math.floor(cw / 2), by + 3 + punri.line_height("small"), c.cDesc, "small", "bold", "center", coup ~= ink)
    end
end

function render_card_inspector(ix, iy, iw, ih, c, checkCoup)
    if not c then return end
    local coup = checkCoup and coup_on(c)
    punri.rect(ix, iy, iw, ih, false)
    punri.rect(ix + 2, iy + 2, iw - 4, ih - 4, false)
    local divY = iy + 8 + punri.line_height("ui12") + 4
    punri.text(ix + 10, iy + 8, "[" .. c.cost .. " Ink] " .. c.name, "ui12", "bold", "left", true)
    punri.text(ix + iw - 12, iy + 8, "[" .. string.upper(c.meter) .. "]", "ui12", "bold", "right", true)
    punri.line(ix + 6, divY, ix + iw - 6, divY)
    local dy = divY + 6
    local dRes = punri.wrapped_text(c.desc, iw - 20, "small", "regular", 2)
    for _, l in ipairs(dRes and dRes.lines or {}) do
        punri.text(ix + 10, dy, l, "small", "regular", "left", true)
        dy = dy + punri.line_height("small") + 2
    end
    if c.cDesc then
        local bH = 26
        local by = iy + ih - bH - 6
        punri.rect(ix + 6, by, iw - 12, bH, coup)
        local cond = (c.couplet == "AfterBlade") and "Blade" or ((c.couplet == "AfterWard") and "Ward" or "Script")
        local cBuf = (coup and "COUPLET READY (" or "Couplet (") .. cond .. "): " .. c.cDesc
        punri.text(ix + math.floor(iw / 2), by + math.floor((bH - punri.line_height("small")) / 2), cBuf, "small", coup and "bold" or "regular", "center", not coup)
    end
end
