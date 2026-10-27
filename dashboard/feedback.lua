-- Callback adapter for the shared, bounded press-feedback state.
return function(F, options)
    local draw_app, update_app, tap_app, button_app, exit_app = on_draw, on_update, on_tap, on_button, on_exit
    local dispatching, waiting = false, false
    local function invalidate()
        if options.invalidate then options.invalidate() end
    end
    local function dispatch(callback, a, b)
        dispatching = true
        callback(a, b)
        dispatching = false
    end
    local function activate(id, callback, a, b)
        if waiting then return end
        invalidate()
        if id and options.transition and options.transition(id) then
            waiting = F.defer(id, function()
                waiting = false
                dispatch(callback, a, b)
            end)
            if waiting then return end
        end
        if id then F.press(id) end
        dispatch(callback, a, b)
    end
    function on_draw()
        F.begin(options.view())
        draw_app()
        F.finish()
        if waiting and not F.busy() then waiting = false end
    end
    function on_update()
        if F.update() then invalidate() end
        if waiting and not F.busy() then waiting = false end
        if update_app then update_app() end
    end
    function on_tap(x, y)
        if waiting then return end
        local id = F.hit(x, y)
        if not id and options.map_tap then id = options.map_tap(x, y) end
        local width, height = punri.get_bounds()
        local metrics = punri.get_metrics()
        if not id and y >= height - math.max(36, metrics.button_hints_height or 40) then return end
        if options.tap then
            activate(id, options.tap, x, y)
        elseif id and id:sub(1, 7) == "footer:" and not options.footer_tap then
            activate(id, button_app, id:sub(8), true)
        elseif tap_app then
            activate(id, tap_app, x, y)
        end
    end
    function on_button(button, pressed)
        if not pressed then return end
        if dispatching then button_app(button, pressed); return end
        if waiting then return end
        local id = options.map_button and options.map_button(button)
        if not id then
            local logical = button == 'page_back' and 'left' or button == 'page_forward' and 'right' or button
            id = 'footer:' .. logical
        end
        activate(id, button_app, button, pressed)
    end
    function on_exit()
        waiting = false
        F.clear()
        if exit_app then exit_app() end
    end
    -- The runtime prefers on_* callbacks; preserve apps' optional aliases too.
    if draw == draw_app then draw = on_draw end
    if update == update_app then update = on_update end
end
