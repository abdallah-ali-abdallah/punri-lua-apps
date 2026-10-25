-- Pure, bounded 3x3 game rules. X = 1, O = 2, empty = 0.
local G = {}
local wins = {{1,2,3}, {4,5,6}, {7,8,9}, {1,4,7}, {2,5,8}, {3,6,9}, {1,5,9}, {3,5,7}}

function G.result(board)
    for _, line in ipairs(wins) do
        local player = board[line[1]]
        if player ~= 0 and player == board[line[2]] and player == board[line[3]] then
            return player, line
        end
    end
    for i = 1, 9 do if board[i] == 0 then return nil end end
    return 0 -- Draw.
end

local function score(board, player, depth)
    local result = G.result(board)
    if result ~= nil then
        if result == 2 then return 10 - depth end
        if result == 1 then return depth - 10 end
        return 0
    end
    local best = player == 2 and -100 or 100
    for i = 1, 9 do
        if board[i] == 0 then
            board[i] = player
            local value = score(board, 3 - player, depth + 1)
            board[i] = 0
            if player == 2 then best = math.max(best, value) else best = math.min(best, value) end
        end
    end
    return best
end

-- Exhaustive minimax has at most nine plies, no growing search-tree tables,
-- and restores every tested cell before returning. The device plays O.
function G.best_move(board)
    if G.result(board) ~= nil then return nil end
    local best, move = -100, nil
    for i = 1, 9 do
        if board[i] == 0 then
            board[i] = 2
            local value = score(board, 1, 1)
            board[i] = 0
            if value > best then best, move = value, i end
        end
    end
    return move
end

return G
