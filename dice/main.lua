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

-- Dice Roller application for PUNRI (Lua)
-- Faithful reproduction of DiceSimActivity.h

local dice_types = {
    {name = "Coin", sides = 2},
    {name = "D4", sides = 4},
    {name = "D6", sides = 6},
    {name = "D8", sides = 8},
    {name = "D10", sides = 10},
    {name = "D12", sides = 12},
    {name = "D20", sides = 20},
}

local selected_die = 3 -- D6 default (1-indexed)
local current_roll = 0
local roll_history = {}
local running_total = 0
local w, h = 480, 800

function on_init()
    w, h = punri.get_bounds()
    math.randomseed(os.time())
    selected_die = tonumber(punri.load("selected_die", "3")) or 3
    if selected_die < 1 or selected_die > #dice_types then selected_die = 3 end
end

local function roll_dice()
    local die = dice_types[selected_die]
    local val = math.random(1, die.sides)
    current_roll = val

    table.insert(roll_history, {dieName = die.name, value = val})
    running_total = running_total + val
end

local function reset_history()
    roll_history = {}
    running_total = 0
    current_roll = 0
end

local function cycle_die()
    selected_die = (selected_die % #dice_types) + 1
    current_roll = 0
end

function on_draw()
    punri.clear()

    local m = punri.get_metrics()
    local die = dice_types[selected_die]

    -- 1. Standard Header
    punri.header("Dice", die.name)

    -- 2. Formatted Multi-Line History
    local currentY = m.top_padding + m.header_height + 16
    local lineHeight = 34

    if #roll_history > 0 then
        local tokens = {}
        for _, entry in ipairs(roll_history) do
            if entry.dieName == "Coin" then
                table.insert(tokens, string.format("Coin[%s]", entry.value == 1 and "H" or "T"))
            else
                table.insert(tokens, string.format("%s[%d]", entry.dieName, entry.value))
            end
        end
        table.insert(tokens, string.format("= %d", running_total))

        local maxTokensPerLine = 4
        local lineStr = ""
        local countInLine = 0

        for i, tok in ipairs(tokens) do
            if countInLine > 0 then
                lineStr = lineStr .. " "
            end
            lineStr = lineStr .. tok
            countInLine = countInLine + 1

            if countInLine >= maxTokensPerLine or i == #tokens then
                punri.centered_text(currentY, lineStr, 0, false, true)
                currentY = currentY + lineHeight
                lineStr = ""
                countInLine = 0
            end
        end
    else
        punri.centered_text(currentY, "Press Roll to start", 0, false, true)
    end

    -- 3. Visual Die Shape (Rendered with thick lines matching DiceSimActivity.h)
    local centerX = math.floor(w / 2)
    local size = 56
    local bottomMargin = 110
    local centerY = h - bottomMargin - size
    local lineThickness = 3

    if die.name == "Coin" then
        if current_roll == 1 then
            punri.draw_sprite(centerX - 56, centerY - 56, 112, 112, "sprites/coin_heads.raw")
        elseif current_roll == 2 then
            punri.draw_sprite(centerX - 56, centerY - 56, 112, 112, "sprites/coin_tails.raw")
        else
            punri.circle(centerX, centerY, size, false, 5)
            punri.circle(centerX, centerY, size - 8, false, 2)
            punri.circle(centerX, centerY, size - 14, false, 1)
        end
    elseif die.name == "D4" then
        punri.thick_line(centerX, centerY - size, centerX - size, centerY + size, lineThickness)
        punri.thick_line(centerX - size, centerY + size, centerX + size, centerY + size, lineThickness)
        punri.thick_line(centerX + size, centerY + size, centerX, centerY - size, lineThickness)
    elseif die.name == "D6" then
        local left = centerX - size
        local right = centerX + size
        local top = centerY - size
        local bottom = centerY + size
        punri.thick_line(left, top, right, top, lineThickness)
        punri.thick_line(right, top, right, bottom, lineThickness)
        punri.thick_line(right, bottom, left, bottom, lineThickness)
        punri.thick_line(left, bottom, left, top, lineThickness)
    elseif die.name == "D8" then
        punri.thick_line(centerX, centerY - size, centerX + size, centerY, lineThickness)
        punri.thick_line(centerX + size, centerY, centerX, centerY + size, lineThickness)
        punri.thick_line(centerX, centerY + size, centerX - size, centerY, lineThickness)
        punri.thick_line(centerX - size, centerY, centerX, centerY - size, lineThickness)
    elseif die.name == "D10" then
        local waistY = centerY - math.floor(size / 5)
        local waistX = math.floor(size * 9 / 10)
        local bottomY = centerY + size + 5
        punri.thick_line(centerX, centerY - size, centerX + waistX, waistY, lineThickness)
        punri.thick_line(centerX + waistX, waistY, centerX, bottomY, lineThickness)
        punri.thick_line(centerX, bottomY, centerX - waistX, waistY, lineThickness)
        punri.thick_line(centerX - waistX, waistY, centerX, centerY - size, lineThickness)
    elseif die.name == "D12" then
        local p1x, p1y = centerX, centerY - size
        local p2x, p2y = centerX + math.floor(size * 95 / 100), centerY - math.floor(size * 31 / 100)
        local p3x, p3y = centerX + math.floor(size * 59 / 100), centerY + math.floor(size * 81 / 100)
        local p4x, p4y = centerX - math.floor(size * 59 / 100), centerY + math.floor(size * 81 / 100)
        local p5x, p5y = centerX - math.floor(size * 95 / 100), centerY - math.floor(size * 31 / 100)
        punri.thick_line(p1x, p1y, p2x, p2y, lineThickness)
        punri.thick_line(p2x, p2y, p3x, p3y, lineThickness)
        punri.thick_line(p3x, p3y, p4x, p4y, lineThickness)
        punri.thick_line(p4x, p4y, p5x, p5y, lineThickness)
        punri.thick_line(p5x, p5y, p1x, p1y, lineThickness)
    elseif die.name == "D20" then
        local hx1, hy1 = centerX, centerY - size
        local hx2, hy2 = centerX + math.floor(size * 87 / 100), centerY - math.floor(size / 2)
        local hx3, hy3 = centerX + math.floor(size * 87 / 100), centerY + math.floor(size / 2)
        local hx4, hy4 = centerX, centerY + size
        local hx5, hy5 = centerX - math.floor(size * 87 / 100), centerY + math.floor(size / 2)
        local hx6, hy6 = centerX - math.floor(size * 87 / 100), centerY - math.floor(size / 2)

        punri.thick_line(hx1, hy1, hx2, hy2, lineThickness)
        punri.thick_line(hx2, hy2, hx3, hy3, lineThickness)
        punri.thick_line(hx3, hy3, hx4, hy4, lineThickness)
        punri.thick_line(hx4, hy4, hx5, hy5, lineThickness)
        punri.thick_line(hx5, hy5, hx6, hy6, lineThickness)
        punri.thick_line(hx6, hy6, hx1, hy1, lineThickness)

        punri.thick_line(hx1, hy1, hx3, hy3, lineThickness)
        punri.thick_line(hx3, hy3, hx5, hy5, lineThickness)
        punri.thick_line(hx5, hy5, hx1, hy1, lineThickness)
    end

    -- 4. Current Roll centered inside die frame (for numbered dice, no '?')
    if current_roll > 0 and die.name ~= "Coin" then
        punri.centered_text(centerY - 14, tostring(current_roll), 0, false, true)
    end

    -- 5. Selected Die Text Label below shape
    local labelY = centerY + size + 20
    if die.name == "Coin" and current_roll > 0 then
        local coinLabel = (current_roll == 1) and "Coin (Heads)" or "Coin (Tails)"
        punri.centered_text(labelY, coinLabel, 0, false, true)
    else
        punri.centered_text(labelY, die.name, 0, false, true)
    end

    -- 6. Footer Button Hints (matching DiceSimActivity.h exactly)
    press_hints("Back", "Reset", "Dice", "Roll")
end

function on_button(btn, pressed)
    if not pressed then return end

    if btn == "back" then
        punri.save("selected_die", tostring(selected_die))
        punri.exit()
    elseif btn == "confirm" then
        -- Button 2: Reset
        reset_history()
    elseif btn == "up" or btn == "left" or btn == "page_back" then
        -- Button 3: Dice (cycle die)
        cycle_die()
    elseif btn == "down" or btn == "right" or btn == "page_forward" then
        -- Button 4: Roll
        roll_dice()
    end
end

function on_tap(x, y)
    local m = punri.get_metrics()
    if y > h - m.button_hints_height then
        if x < w / 4 then
            punri.save("selected_die", tostring(selected_die))
            punri.exit()
        elseif x < w / 2 then
            reset_history()
        elseif x < 3 * w / 4 then
            cycle_die()
        else
            roll_dice()
        end
        return
    end

    -- Tap center: roll
    roll_dice()
end

-- Keep press lifetime separate from gameplay selection and persisted state.
punri.dofile("feedback.lua")(PRESS, {
    view = function() return "dice" end,
    transition = function(id) return id == "footer:back" end,
    map_tap = function(x, y) return "footer:right" end
})
