-- Tic-tac-toe for PUNRI: play the device or pass the reader to a friend.
local game = punri.dofile("engine.lua")
local board = {0,0,0,0,0,0,0,0,0}
local scores = {0,0,0}
local mode, turn, selected, mode_selected = 1, 1, 1, 1
local screen, message, result, winning_line = "mode", "", nil, nil
local w, h, margin, top, bottom, cell, gx, gy, action_y, action_w = 0,0,0,0,0,0,0,0,0,0
local mode_names = {"Play the device", "Two players"}

local function geometry()
    w, h = punri.get_bounds()
    local m = punri.get_metrics()
    margin = math.max(16, m.content_side_padding)
    top = m.top_padding + m.header_height + 12
    bottom = h - m.button_hints_height - 12
    cell = math.floor(math.min(w - margin * 2, bottom - top - 144) / 3)
    gx, gy = math.floor((w - cell * 3) / 2), top + 64
    action_y, action_w = gy + cell * 3 + 12, math.floor((w - margin * 2 - 12) / 2)
end

local function button(x, y, width, label, chosen)
    punri.rounded_rect(x, y, width, 44, 6, chosen)
    punri.text(x + math.floor(width / 2), y + 10, label, "ui12", "regular", "center", not chosen)
end

local function new_game()
    for i = 1, 9 do board[i] = 0 end
    turn, selected, result, winning_line, message, screen = 1, 1, nil, nil, "", "game"
end

local function finish_turn()
    result, winning_line = game.result(board)
    if result ~= nil then
        local index = result == 0 and 3 or result
        scores[index] = scores[index] + 1
        selected = 10
        return true
    end
    return false
end

local function play(index)
    if result ~= nil then message = "Round over. Select New game."; return end
    if board[index] ~= 0 then message = "That square is occupied"; return end
    board[index], message = turn, ""
    if finish_turn() then return end
    turn = 3 - turn
    if mode == 1 and turn == 2 then
        -- One response per human move, never an animation/tick-driven search.
        local move = game.best_move(board)
        if move then board[move] = 2 end
        if not finish_turn() then turn = 1 end
    end
end

local function status()
    if message ~= "" then return message end
    if result == 0 then return "Draw!"
    elseif result == 1 then return mode == 1 and "You win!" or "X wins!"
    elseif result == 2 then return mode == 1 and "Device wins!" or "O wins!" end
    return mode == 1 and "Your turn (X)" or (turn == 1 and "X's turn" or "O's turn")
end

function on_init()
    geometry()
end

function on_draw()
    geometry()
    punri.clear()
    punri.header("Tic-tac-toe", screen == "game" and (mode == 1 and "Solo" or "Two players") or "New game")
    -- Touch profiles hide firmware button hints: show an explicit escape target.
    if punri.has_touch() then button(margin, top, 80, "Back", false) end
    if screen == "mode" then
        local y = top + 64
        punri.centered_text(y, "Choose an opponent", "ui12", "bold")
        for i, label in ipairs(mode_names) do
            button(margin, y + 44 + (i - 1) * 56, w - margin * 2, label, i == mode_selected)
        end
        punri.centered_text(y + 172, "Device plays O and cannot be beaten.", "small")
        punri.button_hints("Exit", "Play", "Up", "Down")
        return
    end
    punri.text(w - margin, top + 12, status(), "small", "regular", "right")
    for i = 1, 9 do
        local x = gx + ((i - 1) % 3) * cell
        local y = gy + math.floor((i - 1) / 3) * cell
        if selected == i and result == nil then punri.rect_dither(x + 5, y + 5, cell - 10, cell - 10, false) end
        local inset = math.floor(cell * 0.24)
        if board[i] == 1 then
            punri.line(x + inset, y + inset, x + cell - inset, y + cell - inset, 4)
            punri.line(x + cell - inset, y + inset, x + inset, y + cell - inset, 4)
        elseif board[i] == 2 then
            punri.circle(x + math.floor(cell / 2), y + math.floor(cell / 2), math.floor(cell * 0.27), false, 4)
        end
    end
    for i = 0, 3 do
        punri.line(gx + i * cell, gy, gx + i * cell, gy + 3 * cell, 3)
        punri.line(gx, gy + i * cell, gx + 3 * cell, gy + i * cell, 3)
    end
    if winning_line then
        local a, b = winning_line[1], winning_line[3]
        punri.line(gx + ((a - 1) % 3 + 0.5) * cell, gy + (math.floor((a - 1) / 3) + 0.5) * cell,
            gx + ((b - 1) % 3 + 0.5) * cell, gy + (math.floor((b - 1) / 3) + 0.5) * cell, 5)
    end
    button(margin, action_y, action_w, "New game", selected == 10)
    button(margin + action_w + 12, action_y, action_w, "Change mode", selected == 11)
    punri.centered_text(action_y + 50, string.format("X: %d   O: %d   Draws: %d (this session)",
        scores[1], scores[2], scores[3]), "small")
    punri.button_hints("Back", "Select", "Prev", "Next")
end

function on_button(btn, pressed)
    if not pressed then return end
    message = ""
    if screen == "mode" then
        if btn == "back" then punri.exit()
        elseif btn == "confirm" then
            if mode ~= mode_selected then for i = 1, 3 do scores[i] = 0 end end
            mode = mode_selected
            new_game()
        elseif btn == "left" or btn == "up" or btn == "page_back" or
            btn == "right" or btn == "down" or btn == "page_forward" then mode_selected = 3 - mode_selected end
    else
        if btn == "back" then screen, mode_selected = "mode", mode
        elseif btn == "confirm" then
            if selected == 10 then new_game()
            elseif selected == 11 then screen, mode_selected = "mode", mode
            else play(selected) end
        elseif btn == "left" then selected = (selected - 2) % 11 + 1
        elseif btn == "right" then selected = selected % 11 + 1
        elseif btn == "up" or btn == "page_back" then
            selected = selected <= 3 and 10 or (selected <= 9 and selected - 3 or 8)
        elseif btn == "down" or btn == "page_forward" then
            selected = selected <= 6 and selected + 3 or (selected <= 9 and 10 or 2)
        end
    end
    punri.request_update()
end

function on_tap(x, y)
    geometry()
    if punri.has_touch() and punri.in_rect(x, y, margin, top, 80, 44) then on_button("back", true); return end
    if screen == "mode" then
        for i = 1, 2 do
            if punri.in_rect(x, y, margin, top + 108 + (i - 1) * 56, w - margin * 2, 44) then
                mode_selected = i
                on_button("confirm", true)
                return
            end
        end
    elseif punri.in_rect(x, y, gx, gy, cell * 3, cell * 3) then
        selected = math.floor((y - gy) / cell) * 3 + math.floor((x - gx) / cell) + 1
        play(selected)
        punri.request_update()
    elseif punri.in_rect(x, y, margin, action_y, action_w, 44) then selected = 10; on_button("confirm", true)
    elseif punri.in_rect(x, y, margin + action_w + 12, action_y, action_w, 44) then selected = 11; on_button("confirm", true) end
end

function on_exit()
    -- Games and scores are intentionally session-only; no SD writes during play.
end
