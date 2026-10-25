-- Codex: Ink & Iron — Victory Screen

local screen = {}

function screen.draw()
    punri.header("Victory!", "The Grimoire is Complete")
    local m = punri.get_metrics()
    local topY = m.top_padding + m.header_height + 2
    local bottomY = h - m.button_hints_height - 2
    draw_page_frame(topY, bottomY)

    punri.centered_text(250, "THE CODEX IS WRITTEN", "ui12", "bold", true)
    punri.centered_text(290, "Thou hast conquered all 15 Pages of Chapter 1!", "small", "regular", true)
    punri.button_hints("Back", "Play Again", "", "")
end

function screen.on_button(btn, pressed)
    if not pressed then return end
    if btn == "back" or btn == "confirm" then
        delete_save_state()
        state.inRun = false
        set_screen("title")
    end
end

function screen.on_tap(x, y)
    screen.on_button("confirm", true)
end

return screen
