return function(E, Editor, Store, Tools, UI, I)
    local N, D, P = E.number, E.decimal, E.parser
    local App = {ui = UI}
    local TRANSIENT = {back = true, close = true, field = true, answer = true, prev_field = true, next_field = true, history = true,
        history_prev = true, history_next = true, palette = true, trace_left = true, trace_right = true, plot = true,
        zoom_in = true, zoom_out = true, curve = true, standard = true, expand = true, graph_more = true,
        pan_left = true, pan_right = true, pan_up = true, pan_down = true, tool = true, form_field = true,
        run_tool = true, determinant = true, inverse = true, transpose = true, retry = true, retry_exit = true,
        discard_exit = true, refresh = true, about = true, reset = true, reset_confirm = true}
    local function initial()
        return {view = "calculate", orientation = "portrait", locale = "en", angle = "RAD", mode = "decimal", focus = 0,
            editor = Editor.new(""), ans = N.parse("0"), answer = "0", evaluated = "", variables = {}, history = {}, dirty = false,
            functions = {{source = "x^2-4", enabled = true}, {source = "x", enabled = true}, {source = "", enabled = false}, {source = "", enabled = false}},
            graph = {window = {-5, 5, -5, 8}, trace = 1.5, curve = 1, lines = {}, dirty = true, busy = false},
            table = {start = "-2", step = "1", column = 0, selected = 1, rows = {}}}
    end
    function App:context()
        local s = self.state
        local fast_variables = {}
        for name, value in pairs(s.variables) do fast_variables[name] = tonumber(N.format(value)) end
        return {ans = s.ans, fast_ans = tonumber(N.format(s.ans)) or 0, fast_variables = fast_variables, angle = s.angle, variables = s.variables}
    end
    function App:changed(save)
        if save then self.state.dirty, self.state.last_edit = true, punri.millis() end
        self:prepare()
        punri.request_update()
    end
    function App:prepare()
        local w, h = punri.get_bounds()
        UI.prepare(self.state, w, h, punri.get_metrics())
        if self.state.focus == 0 then
            for i, c in ipairs(UI.controls) do if c.id == "key" and c.value == "7" then self.state.focus = i; break end end
        end
    end
    function App:message(message, title)
        self.state.previous_sheet = self.state.sheet
        self.state.sheet = {kind = "message", title = title, message = tostring(message)}
    end
    function App:result(title, rows)
        self.state.previous_sheet = self.state.sheet
        self.state.sheet = {kind = "result", title = title, rows = rows}
    end
    function App:save()
        local s = self.state
        if not s.dirty then return true end
        if s.readonly then s.save_failed = true; return false, "Reset the unrecognized saved session before saving" end
        local ok, problem = Store.save(s, N)
        if ok then s.dirty, s.save_failed = false, false else s.save_failed = true end
        return ok, problem
    end
    function App:init()
        local s = initial()
        local saved, problem = Store.load(N, P)
        if saved then
            for _, field in ipairs({"view", "orientation", "locale", "angle", "mode", "ans", "functions", "history", "variables", "evaluated"}) do s[field] = saved[field] end
            s.editor = Editor.new(saved.input)
            s.answer = N.format(s.ans, s.mode)
        elseif problem then s.readonly, s.save_failed = true, true; s.sheet = {kind = "message", title = "Saved session", message = problem .. ". Reset saved session in Settings to save again."} end
        self.state = s
        if punri.has_feature("orientation") then punri.set_orientation(s.orientation) end
        if s.view == "table" then self:table_rows() end
        self:changed(false)
        local memory = punri.get_memory()
        punri.log(string.format("Calculations ready: Lua=%dKB limit=%dKB", memory.lua_kb, memory.lua_max_kb))
    end
    function App:table_rows()
        local s, rows = self.state, {}
        local start, problem = E.run(s.table.start, self:context())
        local step, problem_step = E.run(s.table.step, self:context())
        if not start or not step then self:message(problem or problem_step); return end
        if D.cmp(N.decimal(step), D.zero) == 0 then self:message("Table step cannot be zero"); return end
        for i = 1, 5 do
            local x = N.add(start, N.mul(step, N.parse(tostring(i - 1))))
            local row = {x = N.format(x), value = x}
            local context = self:context(); context.x = x
            for col = 1, 2 do
                local source = s.functions[s.table.column + col].source
                local value = source ~= "" and E.run(source, context) or nil
                row[col] = value and N.format(value) or "--"
            end
            rows[#rows + 1] = row
        end
        s.table.rows = rows
    end
    function App:trace()
        local s, fn = self.state, self.state.functions[self.state.graph.curve]
        local tree = fn.enabled and P.parse(fn.source) or nil
        s.graph.trace_y = tree and E.fast(tree, s.graph.trace, self:context()) or nil
    end
    function App:start_graph()
        local s, graph = self.state, self.state.graph
        if not s.plot then return end
        graph.context, graph.trees, graph.next, graph.count, graph.lines = self:context(), {}, 0, math.max(16, s.plot.w // 2), {}
        for i, fn in ipairs(s.functions) do graph.trees[i] = fn.enabled and fn.source ~= "" and P.parse(fn.source) or false end
        graph.busy, graph.dirty = true, false
        self:trace()
    end
    local function clipped_segment(x0, y0, x1, y1)
        -- Liang-Barsky clipping in normalized plot coordinates.
        local dx, dy, lo, hi = x1 - x0, y1 - y0, 0, 1
        local p, q = {-dx, dx, -dy, dy}, {x0, 1 - x0, y0, 1 - y0}
        for i = 1, 4 do
            if p[i] == 0 then if q[i] < 0 then return nil end
            else
                local t = q[i] / p[i]
                if p[i] < 0 then lo = math.max(lo, t) else hi = math.min(hi, t) end
                if lo > hi then return nil end
            end
        end
        return {x0 + lo * dx, y0 + lo * dy, x0 + hi * dx, y0 + hi * dy}
    end
    function App:graph_step()
        local graph = self.state.graph
        if not graph.busy then return end
        local w = graph.window
        for _ = 1, 8 do
            local index = graph.next
            if index >= graph.count then
                graph.busy = false; self:trace(); self:changed(false)
                punri.log("Calculations graph complete: " .. #graph.lines .. " segments")
                return
            end
            local x0, x1 = w[1] + (w[2] - w[1]) * index / graph.count, w[1] + (w[2] - w[1]) * (index + 1) / graph.count
            for curve = 1, 4 do
                local tree = graph.trees[curve]
                if tree then
                    local y0, y1 = E.fast(tree, x0, graph.context), E.fast(tree, x1, graph.context)
                    local ym = E.fast(tree, (x0 + x1) / 2, graph.context)
                    local span = w[4] - w[3]
                    if y0 and y1 and ym and math.abs(ym - (y0 + y1) / 2) < span / 8 and math.abs(y1 - y0) < span * 2 then
                        local style = curve == 1 or curve == 2 and index % 6 < 4 or curve == 3 and index % 4 == 0 or curve == 4 and index % 8 < 4
                        if style then
                            local segment = clipped_segment(index / graph.count, (w[4] - y0) / span, (index + 1) / graph.count, (w[4] - y1) / span)
                            if segment then segment[5] = curve; graph.lines[#graph.lines + 1] = segment end
                        end
                    end
                end
            end
            graph.next = index + 1
        end
    end
    function App:open_tool(kind, equation)
        local s = self.state
        s.previous_sheet = nil
        if kind == "settings" then s.sheet = {kind = "settings"}; return end
        local definitions = {
            solve = {title = "Equation solver", help = "Bracket one root; Back cancels", fields = {{label = "Equation", value = equation or "x^2=2", max = 512}, {label = "Lower bound", value = "0", max = 64}, {label = "Upper bound", value = "5", max = 64}}, actions = {{"run_tool", "Solve"}}},
            statistics = {title = "Statistics", help = "Up to 200 comma-separated values", fields = {{label = "Dataset", value = "2,4,4,4,5,5,7,9", max = 4096}}},
            matrix = {title = "Matrices", help = "Up to 4x4; comma columns; semicolon rows", fields = {{label = "Matrix A", value = "2,1,0;0,3,1;0,0,4", max = 1024}}, actions = {{"determinant", "Determinant"}, {"inverse", "Inverse"}, {"transpose", "Transpose"}}},
            complex = {title = "Complex numbers", help = "Rectangular to polar", fields = {{label = "Real, imaginary", value = "3,4", max = 256}}},
            base = {title = "Base converter", help = "Unsigned 32-bit integers", fields = {{label = "Number", value = "FF", max = 32}, {label = "From base", value = "16", max = 2}}},
            units = {title = "Units", help = "Exact offline unit ratios", fields = {{label = "Number", value = "1", max = 256}, {label = "Category", value = "Length", cycle = "category"}, {label = "From", value = "m", cycle = "from"}, {label = "To", value = "cm", cycle = "to"}}, category = 1, from = 1, to = 2},
        }
        s.sheet = definitions[kind]
        s.sheet.kind, s.sheet.tool = "form", kind
    end
    function App:keyboard(target, title, value, maximum)
        if not punri.has_feature("keyboard") then self:message("Text keyboard is not available in this firmware"); return end
        if punri.keyboard(I.t(title), value, maximum, false) then self.keyboard_target = target else self:message("Could not open the text keyboard") end
    end
    function App:keyboard_result(value, cancelled)
        local target = self.keyboard_target
        self.keyboard_target = nil
        if cancelled or not target then self:changed(false); return end
        local s = self.state
        if target.kind == "editor" then local ok, problem = Editor.set(s.editor, value); if not ok then s.error = problem end
        elseif target.kind == "table" then
            local number, problem = E.run(value, self:context())
            if not number or target.field == "step" and D.cmp(N.decimal(number), D.zero) == 0 then self:message(problem or "Table step cannot be zero")
            else s.table[target.field] = value; self:table_rows() end
        elseif target.kind == "form" and s.sheet and s.sheet.kind == "form" then s.sheet.fields[target.index].value = value end
        self:changed(true)
    end
    function App:evaluate()
        local s = self.state
        if s.edited_slot and s.editor.source == "" then
            s.functions[s.edited_slot] = {source = "", enabled = false}
            s.editor, s.edited_slot, s.return_editor, s.view, s.graph.dirty = s.return_editor, nil, nil, "functions", true
            return
        end
        local tree, problem = P.parse(s.editor.source)
        if not tree then s.error, s.editor.p, s.editor.q = problem.message, problem.pos, problem.pos; return end
        if s.editor.source:find("?", 1, true) then
            local pos = s.editor.source:find("?", 1, true)
            s.editor.p, s.editor.q, s.error = pos, pos + 1, "Fill every empty field first"
            return
        end
        if s.edited_slot then
            local valid, validation = E.validate_function(tree, s.variables)
            if not valid then s.error = validation; return end
            local fn = s.functions[s.edited_slot]
            fn.source, fn.enabled = s.editor.source, true
            s.editor, s.edited_slot, s.return_editor, s.view = s.return_editor, nil, nil, "functions"
            s.graph.dirty = true
            return
        end
        if tree.k == "eq" then self:open_tool("solve", s.editor.source); return end
        local value, message, pos = E.run(s.editor.source, self:context())
        if not value then s.error = message; s.editor.p, s.editor.q = pos or 1, pos or 1; return end
        s.ans, s.answer, s.evaluated = value, N.format(value, s.mode), s.editor.source
        s.history[#s.history + 1] = {source = s.editor.source, answer = s.answer, angle = s.angle}
        if #s.history > 50 then table.remove(s.history, 1) end
        s.error, s.graph.dirty = nil, true
    end
    function App:run_tool(operation)
        local s, sheet = self.state, self.state.sheet
        if not sheet or sheet.kind ~= "form" then return end
        local fields, kind = sheet.fields, sheet.tool
        if kind == "solve" then
            s.job = Tools.solver(fields[1].value, fields[2].value, fields[3].value, self:context())
            s.job.started = punri.millis()
            return
        end
        local rows
        if kind == "statistics" then rows = Tools.statistics(fields[1].value)
        elseif kind == "matrix" then rows = Tools.matrix(fields[1].value, operation)
        elseif kind == "complex" then rows = Tools.complex(fields[1].value, s.angle)
        elseif kind == "base" then
            local base = tonumber(fields[2].value)
            if base ~= 2 and base ~= 8 and base ~= 10 and base ~= 16 then error("Choose base 2, 8, 10 or 16", 0) end
            rows = Tools.base(fields[1].value, base)
        elseif kind == "units" then rows = Tools.convert(fields[1].value, sheet.category, sheet.from, sheet.to) end
        self:result(sheet.title, rows)
    end
    function App:back()
        local s = self.state
        if s.job then s.job = nil; return end
        if s.sheet then s.sheet, s.previous_sheet = s.previous_sheet, nil; return end
        if s.expanded then s.expanded = false; return end
        if s.edited_slot then s.editor, s.edited_slot, s.return_editor, s.view = s.return_editor, nil, nil, "functions"; return end
        if s.view ~= "calculate" then s.view, s.graph.busy = "calculate", false; return end
        local ok, problem = self:save()
        if not ok then s.sheet = {kind = "save_error", message = problem}; return end
        punri.exit()
    end
    function App:action(id, value)
        local s = self.state
        s.error = nil
        if id == "action" then return self:action(value) end
        if id == "back" then self:back()
        elseif id == "view" then
            if s.edited_slot then s.editor, s.edited_slot, s.return_editor = s.return_editor, nil, nil end
            s.view, s.sheet, s.previous_sheet, s.expanded = value, nil, nil, false
            if value == "graph" then s.graph.dirty = true elseif value == "table" then self:table_rows() end
        elseif id == "angle" then s.angle = s.angle == "RAD" and "DEG" or "RAD"; s.graph.dirty = true; if s.view == "table" then self:table_rows() end
        elseif id == "rotate" then s.orientation = s.orientation == "portrait" and "landscape" or "portrait"; punri.set_orientation(s.orientation); s.graph.dirty = true
        elseif id == "field" then s.editor.p, s.editor.q = value.p, value.q
        elseif id == "answer" then self:result("Answer", {{"Exact result", N.format(s.ans, "fraction")}, {"Decimal", N.format(s.ans)}})
        elseif id == "key" then
            if value == "=" then self:evaluate()
            else local ok, problem = Editor.key(s.editor, value); if not ok then s.error = problem end end
        elseif id == "template" then
            local ok, problem = Editor.template(s.editor, value)
            if not ok then s.error = problem end
            s.sheet = nil
        elseif id == "prev_field" or id == "next_field" then Editor.move(s.editor, id == "prev_field" and -1 or 1)
        elseif id == "text" then
            s.linear = not s.linear
            if s.linear then self:keyboard({kind = "editor"}, "Edit", s.editor.source, 512) end
        elseif id == "palette" then s.sheet = {kind = "palette"}
        elseif id == "format" then
            s.mode = s.mode == "decimal" and "fraction" or s.mode == "fraction" and "engineering" or "decimal"
            s.answer = N.format(s.ans, s.mode)
        elseif id == "undo" or id == "redo" then Editor.history(s.editor, id == "redo"); s.sheet = nil
        elseif id == "history" then s.sheet = {kind = "history", page = 0}
        elseif id == "history_prev" then s.sheet.page = math.min(s.sheet.page + 1, 49)
        elseif id == "history_next" then s.sheet.page = math.max(0, s.sheet.page - 1)
        elseif id == "reuse" then local row = s.history[value]; Editor.set(s.editor, row.source); s.angle = row.angle; s.sheet, s.view = nil, "calculate"
        elseif id == "insert_answer" then Editor.replace(s.editor, s.history[value].answer)
        elseif id == "toggle_function" then s.functions[value].enabled = not s.functions[value].enabled; s.graph.dirty = true
        elseif id == "edit_function" then
            s.return_editor, s.edited_slot, s.view = s.editor, value, "calculate"
            s.editor = Editor.new(s.functions[value].source)
        elseif id == "expand" then s.expanded = not s.expanded; s.graph.dirty = true
        elseif id == "trace_left" or id == "trace_right" then
            s.graph.trace = s.graph.trace + (id == "trace_left" and -1 or 1) * (s.graph.window[2] - s.graph.window[1]) / 20; self:trace()
        elseif id == "plot" then
            local plot, window = s.plot, s.graph.window
            s.graph.trace = window[1] + math.max(0, math.min(1, (value.x - plot.x) / plot.w)) * (window[2] - window[1]); self:trace()
        elseif id == "zoom_in" or id == "zoom_out" then
            local window, factor = s.graph.window, id == "zoom_in" and 0.5 or 2
            local cx, cy = (window[1] + window[2]) / 2, (window[3] + window[4]) / 2
            local dx, dy = (window[2] - window[1]) * factor / 2, (window[4] - window[3]) * factor / 2
            if dx < 0.00001 or dx > 100000 or dy < 0.00001 or dy > 100000 then self:message("Zoom limit reached")
            else s.graph.window, s.graph.dirty = {cx - dx, cx + dx, cy - dy, cy + dy}, true end
        elseif id == "standard" then s.graph.window, s.graph.dirty, s.sheet = {-5, 5, -5, 8}, true, nil
        elseif id == "curve" then
            for offset = 1, 4 do local index = (s.graph.curve - 1 + offset) % 4 + 1; if s.functions[index].enabled and s.functions[index].source ~= "" then s.graph.curve = index; break end end
            self:trace(); s.sheet = nil
        elseif id:match("^pan_") then
            local window = s.graph.window
            local dx, dy = (window[2] - window[1]) / 4, (window[4] - window[3]) / 4
            if id == "pan_left" then dx, dy = -dx, 0 elseif id == "pan_right" then dy = 0 elseif id == "pan_up" then dx = 0 else dx, dy = 0, -dy end
            if math.abs(window[1] + dx) > 1000000 or math.abs(window[3] + dy) > 1000000 then self:message("Pan limit reached")
            else s.graph.window, s.graph.dirty, s.sheet = {window[1] + dx, window[2] + dx, window[3] + dy, window[4] + dy}, true, nil end
        elseif id == "graph_more" then s.sheet = {kind = "graph_more"}
        elseif id == "graph_root" or id == "graph_intersection" then
            local fn = s.functions[s.graph.curve].source
            local equation = fn .. "=0"
            if id == "graph_intersection" then local other = s.graph.curve == 1 and 2 or 1; equation = "(" .. fn .. ")=(" .. s.functions[other].source .. ")" end
            self:open_tool("solve", equation)
            s.sheet.fields[2].value, s.sheet.fields[3].value = string.format("%.6g", s.graph.window[1]), string.format("%.6g", s.graph.window[2])
        elseif id == "table" then s.view, s.sheet = "table", nil; self:table_rows()
        elseif id == "table_field" then self:keyboard({kind = "table", field = value}, value == "start" and "Start x" or "Step", s.table[value], 64)
        elseif id == "table_prev" or id == "table_next" then
            local start, step = E.run(s.table.start, self:context()), E.run(s.table.step, self:context())
            s.table.start = N.format(N.add(start, N.mul(step, N.parse(id == "table_prev" and "-5" or "5"))))
            self:table_rows()
        elseif id == "table_columns" then s.table.column = s.table.column == 0 and 2 or 0; self:table_rows()
        elseif id == "table_row" then s.table.selected = value; local row = s.table.rows[value]; self:result("x=" .. row.x, {{"Y" .. (s.table.column + 1), row[1]}, {"Y" .. (s.table.column + 2), row[2]}})
        elseif id == "table_graph" then s.graph.trace = tonumber(s.table.rows[s.table.selected].x) or 0; s.view, s.sheet = "graph", nil; self:trace(); s.graph.dirty = true
        elseif id == "tool" then self:open_tool(value)
        elseif id == "run_tool" or id == "determinant" or id == "inverse" or id == "transpose" then self:run_tool(id)
        elseif id == "form_field" then
            local field = s.sheet.fields[value]
            if field.cycle then
                if field.cycle == "category" then s.sheet.category = s.sheet.category % #Tools.units + 1; s.sheet.from, s.sheet.to = 1, 2
                else local which = field.cycle; s.sheet[which] = s.sheet[which] % #Tools.units[s.sheet.category].entries + 1 end
                local category = Tools.units[s.sheet.category]
                s.sheet.fields[2].value, s.sheet.fields[3].value, s.sheet.fields[4].value = category.name, category.entries[s.sheet.from][1], category.entries[s.sheet.to][1]
            else self:keyboard({kind = "form", index = value}, field.label, field.value, field.max or 512) end
        elseif id == "settings" then s.sheet = {kind = "settings"}
        elseif id == "language" then s.locale = s.locale == "en" and "ar" or "en"
        elseif id == "refresh" then punri.full_refresh()
        elseif id == "store" or id == "recall" then s.sheet = {kind = "variables", store = id == "store"}
        elseif id == "variable" then
            if s.sheet.store then s.variables[value] = s.ans
            elseif s.variables[value] then Editor.replace(s.editor, value)
            else self:message("Variable not set: " .. value); return end
            s.sheet, s.view, s.graph.dirty = nil, "calculate", true
        elseif id == "retry" or id == "retry_exit" then
            local ok, problem = self:save()
            if ok then if id == "retry_exit" then punri.exit() else self:message("Saved") end else self:message(problem) end
        elseif id == "discard_exit" then self.discard = true; punri.exit()
        elseif id == "reset" then s.sheet = {kind = "reset"}
        elseif id == "reset_confirm" then self.state = initial(); s = self.state; s.dirty = true; self:save(); punri.set_orientation(s.orientation)
        elseif id == "about" then self:message("Exact fractions: up to 90 digits. Approximate functions: 24-digit software decimal, 12 displayed digits. Graph previews use ~6 digits. Physical-device latency and e-ink behavior still need hardware verification.")
        elseif id == "close" then s.sheet, s.previous_sheet = s.previous_sheet, nil end
    end
    function App:dispatch(id, value)
        local ok, problem = pcall(self.action, self, id, value)
        if not ok then self:message(tostring(problem)); punri.log("Calculations action failed: " .. tostring(problem)) end
        local effective = id == "action" and value or id
        self:changed(not TRANSIENT[effective])
    end
    function App:tap(x, y)
        local c, index = UI.hit(x, y)
        if not c then return end
        self.state.focus = index
        self:dispatch(c.id, c.id == "plot" and {x = x, y = y} or c.value)
    end
    function App:button(button, pressed)
        if not pressed then return end
        local s = self.state
        if button == "back" then self:dispatch("back"); return end
        if button == "confirm" then local c = UI.controls[s.focus]; if c then self:dispatch(c.id, c.id == "plot" and {x = c.x + c.w / 2, y = c.y + c.h / 2} or c.value) end; return end
        local delta = button == "left" and -1 or button == "right" and 1 or nil
        if button == "page_back" then delta = -5 elseif button == "page_forward" then delta = 5 end
        if button == "up" or button == "down" then
            local current, best, score = UI.controls[s.focus], nil, math.huge
            if current then
                local cx, cy = current.x + current.w / 2, current.y + current.h / 2
                for i, c in ipairs(UI.controls) do
                    local dx, dy = c.x + c.w / 2 - cx, c.y + c.h / 2 - cy
                    if (button == "up" and dy < -2 or button == "down" and dy > 2) and math.abs(dy) * 4 + math.abs(dx) < score then best, score = i, math.abs(dy) * 4 + math.abs(dx) end
                end
            end
            if best then s.focus = best end
        elseif delta then s.focus = ((s.focus - 1 + delta) % #UI.controls) + 1 end
        self:changed(false)
    end
    function App:update()
        local s = self.state
        if s.job then
            local ok, problem = pcall(Tools.solve_step, s.job)
            if not ok then s.job = nil; self:message(tostring(problem)); self:changed(false)
            elseif s.job.done then
                local root, residual, iterations = s.job.root, s.job.residual, s.job.iterations
                s.job = nil
                self:result("Equation solver", {{"x", N.format(root)}, {"Residual", N.format(residual)}, {"Iterations", tostring(iterations)}})
                self:changed(false)
            end
        elseif s.view == "graph" and not s.sheet then
            if s.graph.dirty then self:start_graph() end
            self:graph_step()
        end
        if s.dirty and not s.save_failed and not s.readonly and not s.job and punri.millis() - (s.last_edit or 0) >= 2000 then
            local ok = self:save()
            if not ok then self:changed(false) end
        end
    end
    function App:exit()
        self.state.job, self.state.graph.busy = nil, false
        if not self.discard then self:save() end
        local memory = punri.get_memory()
        punri.log(string.format("Calculations exit: Lua=%dKB", memory.lua_kb))
    end
    return App
end
