-- The bounded command list is rebuilt on a state change, never per draw tick.
-- Native drawing and touch hit tests consume the very same rectangles.
local F = punri.dofile("press_feedback.lua")
return function(I, P, N, D)
    local U = {feedback = F, commands = {}, controls = {}, width = 0, height = 0, MAX_COMMANDS = 2400}
    local fonts = {"ui12", "ui10", "small"}
    local function command(kind, a, b, c, d, e, f, g)
        if #U.commands >= U.MAX_COMMANDS then return end
        U.commands[#U.commands + 1] = {kind, a, b, c, d, e, f, g}
    end
    function U.text(x, y, value, font, style, align, color)
        command("text", x, y, tostring(value), font or "ui10", style or "regular", align or "left", color ~= false)
    end
    function U.line(x1, y1, x2, y2, thickness) command("line", x1, y1, x2, y2, thickness or 1) end
    function U.rect(x, y, w, h, filled, thickness) command("rect", x, y, w, h, filled or false, thickness or 1) end
    local function width(text, font, style) return punri.text_width(text, font or "ui10", style or "regular") end
    local function height(font) return punri.line_height(font or "ui10") end
    local function fit(text, maximum, font, style)
        text = tostring(text)
        if width(text, font, style) <= maximum then return text end
        local lines = punri.wrapped_text(text, maximum, font or "ui10", style or "regular", 1)
        return lines[1] or ""
    end
    local function centered(x, y, w, h, text, font, style, color)
        local visible = fit(text, w - 10, font, style)
        U.text(x + w // 2, y + math.max(0, (h - height(font)) // 2), visible, font, style, "center", color)
    end
    function U.button(id, value, label, x, y, w, h, active, icon)
        local index = #U.controls + 1
        local selected = index == U.state.focus
        U.controls[index] = {id = id, value = value, label = label, x = x, y = y, w = w, h = h, dark = active == true}
        U.rect(x, y, w, h, active, selected and 3 or 1)
        command("feedback", index)
        if icon then
            local cx, cy = x + w // 2, y + h // 2
            if icon == "fraction" then
                U.rect(cx - 4, cy - 16, 8, 9); U.line(cx - 12, cy - 2, cx + 12, cy - 2, 2); U.rect(cx - 4, cy + 3, 8, 9)
            elseif icon == "root" then
                U.line(cx - 18, cy, cx - 12, cy + 8, 2); U.line(cx - 12, cy + 8, cx - 5, cy - 12, 2)
                U.line(cx - 5, cy - 12, cx + 18, cy - 12, 2); U.rect(cx + 1, cy - 6, 12, 14)
            elseif icon == "power" then
                U.text(cx - 16, cy - height("ui12") // 2, "x", "ui12", "bold"); U.rect(cx + 4, cy - 17, 10, 10)
            elseif icon == "equation" then
                U.rect(cx - 25, cy - 8, 12, 16); U.line(cx - 6, cy - 3, cx + 6, cy - 3, 2)
                U.line(cx - 6, cy + 3, cx + 6, cy + 3, 2); U.rect(cx + 13, cy - 8, 12, 16)
            elseif icon == "pi" then
                U.line(cx - 12, cy - 10, cx + 12, cy - 10, 2)
                U.line(cx - 7, cy - 10, cx - 8, cy + 11, 2)
                U.line(cx + 6, cy - 10, cx + 6, cy + 9, 2); U.line(cx + 6, cy + 9, cx + 12, cy + 9, 2)
            end
        else
            local text = I.t(label)
            local font = width(text, "ui10") <= w - 10 and height("ui10") <= h - 4 and "ui10" or "small"
            centered(x, y, w, h, text, font, active and "bold" or "regular", not active)
        end
        command("feedback_end")
        return index
    end
    local function grid(items, x, y, w, h, columns, id)
        local rows, gap = math.ceil(#items / columns), 6
        local cw, ch = (w - gap * (columns - 1)) // columns, (h - gap * (rows - 1)) // rows
        for i, item in ipairs(items) do
            local label = type(item) == "table" and item[2] or item
            local value = type(item) == "table" and item[1] or item
            U.button(id, value, label, x + ((i - 1) % columns) * (cw + gap), y + ((i - 1) // columns) * (ch + gap), cw, ch,
                value == "=" or value == "solve", type(item) == "table" and item.icon or nil)
        end
    end
    local function wrap(text, x, y, w, font, max_lines)
        local lines = punri.wrapped_text(I.t(text), w, font or "ui10", "regular", max_lines or 3)
        for _, line in ipairs(lines) do U.text(x, y, line, font); y = y + height(font) end
        return y
    end
    local function model(node, level)
        local font = fonts[math.min(level, #fonts)]
        if node.k == "num" or node.k == "var" or node.k == "slot" then
            local text = node.k == "slot" and "" or node.text
            local w, h = math.max(node.k == "slot" and 20 or 8, width(text, font) + 6), height(font) + 4
            return {k = "leaf", node = node, font = font, text = text, w = w, h = h}
        end
        if node.k == "group" then return {k = "row", items = {model({k = "var", text = "(", p = 0, q = 0}, level), model(node.body, level), model({k = "var", text = ")", p = 0, q = 0}, level)}} end
        if node.k == "unary" then return {k = "row", items = {model({k = "var", text = node.op, p = 0, q = 0}, level), model(node.body, level)}} end
        if node.k == "factorial" then return {k = "row", items = {model(node.body, level), model({k = "var", text = "!", p = 0, q = 0}, level)}} end
        local function ungroup(value) return value.k == "group" and value.body or value end
        if node.k == "op" and node.op == "/" then return {k = "fraction", a = model(ungroup(node.left), level + 1), b = model(ungroup(node.right), level + 1)} end
        if node.k == "op" and node.op == "^" then return {k = "power", a = model(node.left.k == "group" and node.left.body.k ~= "op" and node.left.body or node.left, level), b = model(ungroup(node.right), level + 1)} end
        if node.left then return {k = "row", items = {model(node.left, level), model({k = "var", text = node.op == "*" and "x" or node.op, p = 0, q = 0}, level), model(node.right, level)}} end
        if node.k == "call" and ((node.name == "sqrt" and #node.args == 1) or (node.name == "root" and #node.args == 2)) then
            return {k = "root", a = model(node.args[node.name == "root" and 2 or 1], level), degree = node.name == "root" and model(node.args[1], level + 1) or nil}
        end
        local items = {model({k = "var", text = node.name .. "(", p = 0, q = 0}, level)}
        for i, arg in ipairs(node.args) do
            if i > 1 then items[#items + 1] = model({k = "var", text = ",", p = 0, q = 0}, level) end
            items[#items + 1] = model(arg, level)
        end
        items[#items + 1] = model({k = "var", text = ")", p = 0, q = 0}, level)
        return {k = "row", items = items}
    end
    local function measure(box)
        if box.k == "leaf" then return end
        if box.items then
            box.w, box.h = 0, 0
            for _, item in ipairs(box.items) do measure(item); box.w = box.w + item.w + 2; box.h = math.max(box.h, item.h) end
        else
            measure(box.a)
            if box.b then measure(box.b) end
            if box.degree then measure(box.degree) end
            if box.k == "fraction" then box.w, box.h = math.max(box.a.w, box.b.w) + 8, box.a.h + box.b.h + 8
            elseif box.k == "power" then box.w, box.h = box.a.w + box.b.w + 2, math.max(box.a.h + 8, box.b.h + 12)
            else box.w, box.h = box.a.w + 20 + (box.degree and box.degree.w or 0), math.max(box.a.h + 6, box.degree and box.degree.h + 10 or 0) end
        end
    end
    local function leaves(box, x, y, output)
        if box.k == "leaf" then
            output[#output + 1] = {box = box, x = x, y = y}; return
        end
        if box.items then
            for _, item in ipairs(box.items) do leaves(item, x, y + (box.h - item.h) // 2, output); x = x + item.w + 2 end
        elseif box.k == "fraction" then
            leaves(box.a, x + (box.w - box.a.w) // 2, y, output); leaves(box.b, x + (box.w - box.b.w) // 2, y + box.a.h + 8, output)
        elseif box.k == "power" then
            leaves(box.a, x, y + box.h - box.a.h, output); leaves(box.b, x + box.a.w + 2, y, output)
        else
            local degree_w = box.degree and box.degree.w or 0
            if box.degree then leaves(box.degree, x, y, output) end
            leaves(box.a, x + degree_w + 20, y + 6, output)
        end
    end
    local function within(x, y, w, h, clip) return x >= clip.x and y >= clip.y and x + w <= clip.x + clip.w and y + h <= clip.y + clip.h end
    local function draw_model(box, x, y, clip, editor)
        if box.k == "leaf" then
            if not within(x, y, box.w, box.h, clip) then return end
            local node, selected = box.node, false
            if node.p > 0 then
                selected = (editor.p == node.p and editor.q == node.q) or (editor.p == editor.q and editor.p > node.p and editor.p <= node.q)
                U.controls[#U.controls + 1] = {id = "field", value = {p = node.p, q = node.q}, label = box.text, x = x, y = y, w = box.w, h = box.h}
            end
            if node.k == "slot" or selected then U.rect(x, y, box.w, box.h, false, selected and 2 or 1) end
            if node.p > 0 then command("feedback", #U.controls) end
            -- A math atom is measured with six pixels of padding. Ordinary
            -- buttons reserve ten; using that wrapper here ellipsizes digits.
            if box.text ~= "" then U.text(x + 3, y + (box.h - height(box.font)) // 2, box.text, box.font) end
            if node.p > 0 then command("feedback_end") end
        elseif box.items then
            for _, item in ipairs(box.items) do draw_model(item, x, y + (box.h - item.h) // 2, clip, editor); x = x + item.w + 2 end
        elseif box.k == "fraction" then
            draw_model(box.a, x + (box.w - box.a.w) // 2, y, clip, editor)
            if within(x, y + box.a.h + 3, box.w, 2, clip) then U.line(x, y + box.a.h + 3, x + box.w, y + box.a.h + 3, 2) end
            draw_model(box.b, x + (box.w - box.b.w) // 2, y + box.a.h + 8, clip, editor)
        elseif box.k == "power" then
            draw_model(box.a, x, y + box.h - box.a.h, clip, editor); draw_model(box.b, x + box.a.w + 2, y, clip, editor)
        else
            local degree_w = box.degree and box.degree.w or 0
            if box.degree then draw_model(box.degree, x, y, clip, editor) end
            local rx = x + degree_w
            if within(rx, y, box.w - degree_w, box.h, clip) then
                U.line(rx, y + box.h // 2, rx + 5, y + box.h - 2, 2)
                U.line(rx + 5, y + box.h - 2, rx + 14, y + 2, 2)
                U.line(rx + 14, y + 2, x + box.w, y + 2, 2)
            end
            draw_model(box.a, rx + 20, y + 6, clip, editor)
        end
    end
    local function expression(editor, x, y, w, h)
        local tree = P.parse(editor.source)
        if not tree or U.state.linear then
            local source = editor.source == "" and I.t("Enter an expression") or editor.source
            local cursor = math.min(editor.p, #source + 1)
            local start = 1
            while start < cursor and width(source:sub(start, cursor - 1), "ui10") > w - 28 do start = start + 1 end
            local visible = fit(source:sub(start), w - 8, "ui10")
            U.text(x + 4, y + (h - height("ui10")) // 2, visible, "ui10")
            local cx = x + 4 + width(source:sub(start, cursor - 1), "ui10")
            if cx < x + w - 4 then U.line(cx, y + h // 2 - 12, cx, y + h // 2 + 12, 2) end
            return
        end
        local box = model(tree, 1)
        measure(box)
        local parts, offsetx, offsety = {}, 0, 0
        leaves(box, 0, 0, parts)
        for _, part in ipairs(parts) do
            local node = part.box.node
            if node.p > 0 and ((editor.p == node.p and editor.q == node.q) or (editor.p == editor.q and editor.p > node.p and editor.p <= node.q)) then
                offsetx = math.max(0, part.x + part.box.w - w + 8)
                offsety = math.max(0, part.y + part.box.h - h + 3)
                break
            end
        end
        if editor.p == editor.q and editor.p == #editor.source + 1 then offsetx = math.max(0, box.w - w + 12) end
        draw_model(box, x + 4 - offsetx, y + math.max(0, (h - box.h) // 2) - offsety, {x = x, y = y, w = w, h = h}, editor)
        if editor.p == editor.q and editor.p == #editor.source + 1 then
            local cx = x + 6 + box.w - offsetx
            if cx < x + w then U.line(cx, y + h // 2 - 10, cx, y + h // 2 + 10, 2) end
        end
        if box.w > w then U.text(x + w - 10, y + h - height("small"), ">", "small", "bold") end
    end
    local KEYS = {{"7", "7"}, {"8", "8"}, {"9", "9"}, {"/", "÷"}, {"Del", "Del"},
        {"4", "4"}, {"5", "5"}, {"6", "6"}, {"*", "×"}, {"(", "("}, {"1", "1"}, {"2", "2"}, {"3", "3"}, {"-", "−"}, {")", ")"},
        {"0", "0"}, {".", "."}, {"+/-", "+/-"}, {"+", "+"}, {"^", "^"}, {"Ans", "Ans"}, {"pi", "pi", icon = "pi"}, {"x", "x"}, {"Clear", "Clear"}, {"=", "="}}
    local TEMPLATES = {{"fraction", "", icon = "fraction"}, {"root", "", icon = "root"}, {"power", "", icon = "power"}, {"equation", "", icon = "equation"}, {"text", "Text"}}
    local function calculate(s, r)
        local gap, keyx, keyw, keyh, keyy = 6, r.x, r.w, 56, 0
        local leftw = r.w
        if U.landscape then
            leftw = (r.w - 12) // 2; keyx, keyw = r.x + leftw + 12, r.w - leftw - 12
            keyh = (r.h - 24) // 5; keyy = r.y
        else keyy = r.y + r.h - (keyh * 5 + 24) end
        grid(KEYS, keyx, keyy, keyw, keyh * 5 + 24, 5, "key")
        local action_y = U.landscape and r.y + r.h - 48 or keyy - 54
        local template_y = action_y - 54
        local entry_h = U.landscape and 128 or 120
        local entry_y = template_y - 6 - entry_h
        U.button("history", nil, "History", r.x + leftw - 94, r.y, 94, 40)
        U.text(r.x, r.y + 4, s.edited_slot and "Y" .. s.edited_slot .. " · " .. I.t("Edit") or I.t("Working tape"), "small")
        local row = s.history[#s.history]
        if row and not s.edited_slot and entry_y - r.y >= 72 then
            local answer_w = math.min(leftw // 3, math.max(60, width(row.answer, "ui10") + 12))
            U.button("reuse", #s.history, row.source, r.x, r.y + 40, leftw - answer_w - 6, 32)
            U.button("insert_answer", #s.history, row.answer, r.x + leftw - answer_w, r.y + 40, answer_w, 32)
        end
        U.rect(r.x, entry_y, leftw, entry_h, false, 2)
        expression(s.editor, r.x + 8, entry_y + 6, leftw - 16, entry_h - 48)
        local label = s.error and "Edit" or s.editor.source ~= s.evaluated and "Last answer" or s.ans.approx and "Approximate" or "Answer"
        U.controls[#U.controls + 1] = {id = "answer", label = s.answer, x = r.x + 6, y = entry_y + entry_h - 44, w = leftw - 12, h = 38}
        command("feedback", #U.controls)
        U.text(r.x + 8, entry_y + entry_h - height("small") - 8, I.t(label), "small")
        local result = s.error and I.t(s.error) or s.answer
        local result_font = width(result, "ui12", "bold") <= leftw - 116 and "ui12" or "small"
        if s.error then
            centered(r.x + 8, entry_y + entry_h - 42, leftw - 16, 38, result, "small", "bold")
        else U.text(r.x + leftw - 10, entry_y + entry_h - height(result_font) - 7, fit(result, leftw - 110, result_font, "bold"), result_font, "bold", "right") end
        command("feedback_end")
        for i, template in ipairs(TEMPLATES) do
            local cw = (leftw - 24) // 5
            U.button(template[1] == "text" and "text" or "template", template[1], template[1] == "text" and (s.linear and "Natural" or "Text") or template[2],
                r.x + (i - 1) * (cw + gap), template_y, cw, 48, false, template.icon)
        end
        grid({{"palette", "f(x)"}, {"format", "a/b <-> ."}, {"prev_field", "Prev field"}, {"next_field", "Next field"}}, r.x, action_y, leftw, 48, 4, "action")
    end
    local function page_title(title, subtitle, r)
        U.text(r.x, r.y, I.t(title), "ui12", "bold")
        if subtitle then U.text(r.x, r.y + height("ui12") + 7, fit(I.t(subtitle), r.w, "small"), "small") end
        return r.y + height("ui12") + (subtitle and height("small") + 20 or 12)
    end
    local function functions(s, r)
        local y = page_title("Functions", "Shared by Graph and Table", r)
        local columns, rows = U.landscape and 2 or 1, U.landscape and 2 or 4
        local gap, cw, ch = 12, (r.w - (columns - 1) * 12) // columns, math.min(108, (r.y + r.h - y - 62 - (rows - 1) * 12) // rows)
        for i, fn in ipairs(s.functions) do
            local x, yy = r.x + ((i - 1) % columns) * (cw + gap), y + ((i - 1) // columns) * (ch + gap)
            U.button("toggle_function", i, "Y" .. i, x, yy, 52, ch, fn.enabled)
            U.button("edit_function", i, fn.source == "" and "Empty" or fn.source, x + 58, yy, cw - 58, ch - 24)
            U.text(x + 60, yy + ch - height("small"), I.t(fn.enabled and "Enabled" or "Disabled") .. " · " .. ({"solid", "dash", "dot", "dash-dot"})[i], "small")
        end
        U.button("view", "graph", "Draw", r.x, r.y + r.h - 48, r.w, 48, true)
    end
    local function graph(s, r)
        local title_h, sidebar, controls_h = 44, U.landscape and 204 or 0, U.landscape and 0 or 172
        local selected = s.functions[s.graph.curve]
        U.text(r.x, r.y + 10, fit("Y" .. s.graph.curve .. " = " .. selected.source, r.w - 112, "ui10"), "ui10", "bold")
        U.button("expand", nil, s.expanded and "Collapse" or "Expand", r.x + r.w - 104, r.y, 104, 42)
        local plot = {x = r.x + 34, y = r.y + title_h + 12, w = r.w - sidebar - 44, h = r.h - title_h - controls_h - 36}
        s.plot = plot
        U.rect(r.x, r.y + title_h, r.w - sidebar - (sidebar > 0 and 10 or 0), plot.h + 36)
        local window = s.graph.window
        local function px(x) return plot.x + (x - window[1]) / (window[2] - window[1]) * plot.w end
        local function py(y) return plot.y + (window[4] - y) / (window[4] - window[3]) * plot.h end
        for i = 0, 4 do
            local x = window[1] + (window[2] - window[1]) * i / 4
            local y = window[3] + (window[4] - window[3]) * i / 4
            U.text(px(x), plot.y + plot.h + 5, string.format("%.3g", x), "small", "regular", i == 0 and "left" or i == 4 and "right" or "center")
            U.text(plot.x - 5, py(y) - height("small") // 2, string.format("%.3g", y), "small", "regular", "right")
        end
        if window[1] <= 0 and window[2] >= 0 then U.line(px(0), plot.y, px(0), plot.y + plot.h) end
        if window[3] <= 0 and window[4] >= 0 then U.line(plot.x, py(0), plot.x + plot.w, py(0)) end
        for _, segment in ipairs(s.graph.lines) do U.line(plot.x + segment[1] * plot.w, plot.y + segment[2] * plot.h, plot.x + segment[3] * plot.w, plot.y + segment[4] * plot.h, segment[5] == 1 and 2 or 1) end
        local trace_y = s.graph.trace_y
        if trace_y and s.graph.trace >= window[1] and s.graph.trace <= window[2] and trace_y >= window[3] and trace_y <= window[4] then
            local x, y = px(s.graph.trace), py(trace_y)
            U.line(x - 5, y, x + 5, y, 2); U.line(x, y - 5, x, y + 5, 2)
        end
        U.controls[#U.controls + 1] = {id = "plot", x = plot.x, y = plot.y, w = plot.w, h = plot.h, label = "Trace"}
        local x, y, w = sidebar > 0 and r.x + r.w - sidebar or r.x, sidebar > 0 and r.y + 54 or plot.y + plot.h + 34, sidebar > 0 and sidebar or r.w
        U.text(x, y, I.t(s.graph.busy and "Computing" or "Trace") .. " · ~6 digits", "small")
        U.text(x, y + height("small") + 5, "x=" .. string.format("%.6g", s.graph.trace), "ui10", "bold")
        U.text(sidebar > 0 and x or x + w // 2, y + height("small") + 5 + (sidebar > 0 and height("ui10") + 5 or 0), "y=" .. (trace_y and string.format("%.6g", trace_y) or "--"), "ui10", "bold")
        local buttons_y = sidebar > 0 and r.y + r.h - 164 or r.y + r.h - 104
        grid({{"trace_left", "< Trace"}, {"trace_right", "Trace >"}, {"zoom_in", "Zoom in"}, {"zoom_out", "Zoom out"}}, x, buttons_y, w, sidebar > 0 and 104 or 48, sidebar > 0 and 2 or 4, "action")
        if sidebar > 0 then U.button("sheet", "graph_more", "More", x, r.y + r.h - 48, w, 48)
        else grid({{"curve", "Curve"}, {"standard", "Standard"}, {"table", "Table"}, {"graph_more", "More"}}, x, r.y + r.h - 48, w, 48, 4, "action") end
    end
    local function table_view(s, r)
        local y = page_title("Table", "Select x to inspect full values", r)
        local top = y + 54
        U.button("table_field", "start", "x: " .. s.table.start, r.x, y, r.w // 2 - 3, 46)
        U.button("table_field", "step", "Step: " .. s.table.step, r.x + r.w // 2 + 3, y, r.w // 2 - 3, 46)
        local row_h = math.min(60, (r.y + r.h - top - 110) // 6)
        local cw = r.w // 3
        for col, label in ipairs({"x", "Y" .. (s.table.column + 1), "Y" .. (s.table.column + 2)}) do centered(r.x + (col - 1) * cw, top, cw, row_h, label, "ui10", "bold") end
        U.line(r.x, top + row_h, r.x + r.w, top + row_h, 2)
        for i, row in ipairs(s.table.rows) do
            local yy = top + i * row_h
            U.button("table_row", i, row.x, r.x, yy, cw - 4, row_h - 2, s.table.selected == i)
            centered(r.x + cw, yy, cw, row_h, row[1], "small")
            centered(r.x + 2 * cw, yy, cw, row_h, row[2], "small")
            U.line(r.x + cw, yy + row_h - 2, r.x + r.w, yy + row_h - 2)
        end
        grid({{"table_prev", "Previous"}, {"table_next", "Next"}, {"table_columns", "Y1-Y4"}, {"table_graph", "Graph"}}, r.x, r.y + r.h - 48, r.w, 48, 4, "action")
    end
    local tool_items = {{"solve", "Equation solver"}, {"statistics", "Statistics"}, {"matrix", "Matrices"}, {"complex", "Complex numbers"}, {"base", "Base converter"}, {"units", "Units"}, {"settings", "Settings"}}
    local function tools(s, r)
        local y = page_title("Tools", "Precision: 12 digits; graph: ~6", r)
        local columns = U.landscape and 2 or 1
        grid(tool_items, r.x, y, r.w, r.y + r.h - y, columns, "tool")
    end
    local function menu(title, items, r, id)
        local y = page_title(title, nil, r)
        grid(items, r.x, y, r.w, r.y + r.h - y, U.landscape and 2 or 1, id)
    end
    function U.prepare(s, w, h, metrics)
        U.state, U.width, U.height, U.landscape = s, w, h, w > h
        U.commands, U.controls = {}, {}
        I.locale = s.locale
        local header_h, top = math.max(52, math.min(metrics.header_height or 60, height("ui12") + 24)), metrics.top_padding or 0
        local footer_h = math.max(40, metrics.button_hints_height or 0)
        local nav_h = s.expanded and s.view == "graph" and not s.sheet and 0 or 50
        local r = {x = metrics.content_side_padding or 12, y = top + header_h + nav_h + 8}
        r.w, r.h = w - 2 * r.x, h - footer_h - 8 - r.y
        U.button("back", nil, "<", r.x, top + 2, 46, header_h - 4)
        local title_w = w - 2 * r.x - 46 - 126
        centered(r.x + 50, top, title_w, header_h, I.t("Calculations"), "ui12", "bold")
        U.button("angle", nil, s.angle, w - r.x - 118, top + 2, 52, header_h - 4)
        U.button("rotate", nil, "Rotate", w - r.x - 60, top + 2, 60, header_h - 4)
        if nav_h > 0 then
            local labels = {{"calculate", "Calculate"}, {"functions", "Functions"}, {"graph", "Graph"}, {"table", "Table"}, {"tools", "Tools"}}
            local cw = (w - 2 * r.x) // 5
            for i, item in ipairs(labels) do U.button("view", item[1], item[2], r.x + (i - 1) * cw, top + header_h + 2, cw, nav_h - 4, s.view == item[1]) end
        end
        U.content = r
        if s.sheet then
            local sheet = s.sheet
            if sheet.kind == "palette" then
                local y = page_title("Scientific keys", "Templates keep editable fields", r)
                grid({{"fraction", "a/b"}, {"root", "sqrt"}, {"power", "x^n"}, {"square", "x^2"}, {"nthroot", "nth root"}, {"logbase", "log base"},
                    {"sin", "sin"}, {"cos", "cos"}, {"tan", "tan"}, {"asin", "asin"}, {"acos", "acos"}, {"atan", "atan"}, {"ln", "ln"}, {"log", "log"}, {"exp", "exp"},
                    {"abs", "abs"}, {"brackets", "( )"}, {"scientific", "x10^n"}, {"sinh", "sinh"}, {"cosh", "cosh"}, {"tanh", "tanh"}, {"gcd", "gcd"}, {"lcm", "lcm"}, {"factorial", "n!"}},
                    r.x, y, r.w, r.y + r.h - y - 54, U.landscape and 6 or 3, "template")
                grid({{"undo", "Undo"}, {"redo", "Redo"}, {"store", "Store answer"}, {"recall", "Recall variable"}}, r.x, r.y + r.h - 48, r.w, 48, 4, "action")
            elseif sheet.kind == "graph_more" then
                menu("Graph", {{"curve", "Curve"}, {"standard", "Standard"}, {"pan_left", "Pan left"}, {"pan_right", "Pan right"}, {"pan_up", "Pan up"}, {"pan_down", "Pan down"}, {"graph_root", "Root"}, {"graph_intersection", "Intersection"}}, r, "action")
            elseif sheet.kind == "settings" then
                menu("Settings", {{"language", "Language"}, {"format", "Number format"}, {"retry", "Retry save"}, {"refresh", "Refresh"}, {"reset", "Reset saved session"}, {"about", "Precision: 12 digits; graph: ~6"}}, r, "action")
            elseif sheet.kind == "variables" then
                local y = page_title(sheet.store and "Store answer" or "Recall variable", nil, r)
                local items = {}
                for byte = 65, 90 do local name = string.char(byte); items[#items + 1] = {name, name .. (s.variables[name] and " *" or "")} end
                grid(items, r.x, y, r.w, r.y + r.h - y, U.landscape and 7 or 4, "variable")
            elseif sheet.kind == "history" then
                local y = page_title("History", nil, r)
                local count = math.max(1, math.min(7, (r.y + r.h - y - 54) // 68))
                for offset = 0, count - 1 do
                    local index = #s.history - sheet.page * count - offset
                    local row = s.history[index]
                    if row then U.button("reuse", index, row.source .. " = " .. row.answer .. " " .. row.angle, r.x, y + offset * 68, r.w, 62) end
                end
                grid({{"history_prev", "Previous"}, {"history_next", "Next"}, {"close", "Close"}}, r.x, r.y + r.h - 48, r.w, 48, 3, "action")
            elseif sheet.kind == "result" then
                local y = page_title(sheet.title or "Result", nil, r)
                local cols = U.landscape and 2 or 1
                local cw = (r.w - (cols - 1) * 16) // cols
                local rh = (r.y + r.h - y - 54) // math.ceil(#sheet.rows / cols)
                for i, row in ipairs(sheet.rows) do
                    local xx, yy = r.x + ((i - 1) % cols) * (cw + 16), y + ((i - 1) // cols) * rh
                    U.text(xx, yy, I.t(row[1]), "small")
                    local value_font = width(row[2], "ui10") > cw * 2 and "small" or "ui10"
                    wrap(row[2], xx, yy + height("small") + 4, cw, value_font, math.max(1, (rh - height("small") - 8) // height(value_font)))
                end
                U.button("close", nil, "Close", r.x, r.y + r.h - 48, r.w, 48)
            elseif sheet.kind == "message" then
                local y = page_title(sheet.title or "Calculations", nil, r)
                wrap(sheet.message, r.x, y, r.w, "ui10", U.landscape and 5 or 12)
                U.button("close", nil, "Close", r.x, r.y + r.h - 48, r.w, 48)
            elseif sheet.kind == "save_error" then
                local y = page_title("Save failed", nil, r)
                wrap(sheet.message, r.x, y, r.w, "ui10", 4)
                grid({{"retry_exit", "Retry save"}, {"discard_exit", "Exit without saving"}, {"close", "Cancel"}}, r.x, r.y + r.h - 164, r.w, 164, 1, "action")
            elseif sheet.kind == "reset" then
                local y = page_title("Confirm reset", nil, r)
                wrap("Discard this app's saved session and start again?", r.x, y, r.w, "ui10", 4)
                grid({{"reset_confirm", "Reset"}, {"close", "Cancel"}}, r.x, r.y + r.h - 104, r.w, 104, 1, "action")
            elseif sheet.kind == "form" then
                local y = page_title(sheet.title, sheet.help, r)
                local columns, gap = U.landscape and 2 or 1, 10
                local fw = (r.w - (columns - 1) * gap) // columns
                for i, field in ipairs(sheet.fields) do
                    local x, yy = r.x + ((i - 1) % columns) * (fw + gap), y + ((i - 1) // columns) * 74
                    U.text(x, yy, I.t(field.label), "small")
                    U.button("form_field", i, field.value, x, yy + height("small") + 3, fw, 48)
                end
                grid(sheet.actions or {{"run_tool", "Calculate"}}, r.x, r.y + r.h - 48, r.w, 48, #(sheet.actions or {1}), "action")
                if s.job then U.text(r.x, r.y + r.h - 78, I.t("Computing") .. " · " .. I.t("Back") .. ": " .. I.t("Cancel"), "small", "bold") end
            end
        elseif s.view == "calculate" then calculate(s, r)
        elseif s.view == "functions" then functions(s, r)
        elseif s.view == "graph" then graph(s, r)
        elseif s.view == "table" then table_view(s, r)
        else tools(s, r) end
        U.line(0, h - footer_h, w, h - footer_h)
        if s.focus > #U.controls then s.focus = #U.controls end
    end
    function U.feedback_id(control)
        local value = type(control.value) == "string" or type(control.value) == "number"
        return control.id .. ":" .. (value and tostring(control.value) or "") .. ":" .. control.x .. ":" .. control.y
    end
    function U.draw()
        local s = U.state
        F.begin(s.view .. "/" .. (s.sheet and s.sheet.kind or ""))
        for _, c in ipairs(U.controls) do
            if c.id ~= "plot" then F.target(U.feedback_id(c), c.x, c.y, c.w, c.h, true, "rect", 0, c.dark) end
        end
        punri.clear()
        local ink
        for _, c in ipairs(U.commands) do
            if c[1] == "feedback" then ink = F.paint(U.feedback_id(U.controls[c[2]]))
            elseif c[1] == "feedback_end" then ink = nil
            elseif c[1] == "text" then
                local color = c[8]
                if ink ~= nil then color = ink end
                punri.text(c[2], c[3], c[4], c[5], c[6], c[7], color)
            elseif c[1] == "line" then punri.line(c[2], c[3], c[4], c[5], c[6], ink ~= false)
            elseif ink ~= nil then
                if c[6] then punri.rect(c[2], c[3], c[4], c[5], true, ink)
                else punri.rect(c[2], c[3], c[4], c[5], false, c[7], ink) end
            else punri.rect(c[2], c[3], c[4], c[5], c[6], c[7]) end
        end
        F.footer({I.t("Back"), I.t("Select"), "<", ">"}, {"footer_back", "footer_confirm", "footer_left", "footer_right"})
        F.finish()
    end
    function U.hit(x, y)
        for i = #U.controls, 1, -1 do local c = U.controls[i]; if x >= c.x and x < c.x + c.w and y >= c.y and y < c.y + c.h then return c, i end end
    end
    return U
end
