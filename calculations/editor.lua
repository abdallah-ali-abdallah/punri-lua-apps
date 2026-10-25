return function(P)
    local Editor = {}
    function Editor.new(source) return {source = source or "", p = #(source or "") + 1, q = #(source or "") + 1, undo = {}, redo = {}} end
    local function remember(e)
        e.undo[#e.undo + 1] = {source = e.source, p = e.p, q = e.q}
        if #e.undo > 20 then table.remove(e.undo, 1) end
        e.redo = {}
    end
    function Editor.replace(e, value, offset)
        local candidate = e.source:sub(1, e.p - 1) .. value .. e.source:sub(e.q)
        if #candidate > P.MAX_BYTES then return false, "Expression is too long" end
        remember(e)
        e.source, e.p = candidate, e.p + (offset or #value)
        e.q = e.p + (offset and 1 or 0)
        return true
    end
    function Editor.set(e, value)
        value = value:gsub("%s+", " ")
        if value:find("[^A-Za-z0-9%s%.%+%-%*/%^%(%)%=,%?!]") then return false, "Use calculator symbols and ASCII variables" end
        if #value > P.MAX_BYTES then return false, "Expression is too long" end
        remember(e)
        e.source, e.p, e.q = value, #value + 1, #value + 1
        return true
    end
    function Editor.move(e, direction)
        local tree = P.parse(e.source)
        local fields = P.fields(tree, {})
        if #fields == 0 then e.p = math.max(1, math.min(#e.source + 1, e.p + direction)); e.q = e.p; return end
        local current = nil
        for i, field in ipairs(fields) do
            if (e.p == field.p and e.q == field.q) or (e.p > field.p and e.p <= field.q) then current = i; break end
        end
        if current == #fields and direction > 0 then e.p, e.q = #e.source + 1, #e.source + 1; return end
        local next_index = current and math.max(1, math.min(#fields, current + direction)) or (direction > 0 and 1 or #fields)
        e.p, e.q = fields[next_index].p, fields[next_index].q
    end
    function Editor.template(e, kind)
        local p, q, seed = e.p, e.q, e.source:sub(e.p, e.q - 1)
        if seed == "?" then seed = "" end
        if kind == "equation" and e.source:find("=", 1, true) then return false, "This expression already has an equation" end
        if p == q and kind ~= "equation" then
            local prefix = e.source:sub(1, p - 1)
            local operand
            local function find(node)
                if not node then return end
                if node.q == e.p and (node.k == "num" or node.k == "var" or node.k == "call" or node.k == "group" or node.k == "factorial" or node.k == "op" and (node.op == "/" or node.op == "^")) then
                    if not operand or node.p < operand.p then operand = node end
                end
                if node.left then find(node.left); find(node.right) elseif node.body then find(node.body) elseif node.args then for _, arg in ipairs(node.args) do find(arg) end end
            end
            find(P.parse(e.source))
            if operand then p, seed = operand.p, e.source:sub(operand.p, operand.q - 1)
            elseif prefix:sub(-1) == ")" then
                local start, depth = #prefix, 0
                repeat
                    local c = prefix:sub(start, start)
                    if c == ")" then depth = depth + 1 elseif c == "(" then depth = depth - 1 end
                    start = start - 1
                until start == 0 or depth == 0
                if depth == 0 then
                    local name = prefix:sub(1, start):match("[A-Za-z]+$") or ""
                    p, seed = start + 1 - #name, prefix:sub(start + 1 - #name)
                end
            else
                local atom = prefix:match("[%d%.]+[eE][+-]?%d+$") or prefix:match("[%d%.]+$") or prefix:match("[A-Za-z]+$")
                if atom then p, seed = p - #atom, atom end
            end
        end
        if kind == "equation" and p == q then p, q, seed = 1, #e.source + 1, e.source end
        local base = seed ~= "" and seed or "?"
        local templates = {fraction = "(" .. base .. ")/(?)", root = "sqrt(" .. base .. ")", power = "(" .. base .. ")^(?)",
            square = "(" .. base .. ")^2", nthroot = "root(?," .. base .. ")", logbase = "logbase(?," .. base .. ")",
            brackets = "(" .. base .. ")", scientific = "(" .. base .. ")*10^(?)", equation = base .. "=?",
            factorial = "(" .. base .. ")!", gcd = "gcd(" .. base .. ",?)", lcm = "lcm(" .. base .. ",?)"}
        local value = templates[kind] or (kind .. "(" .. base .. ")")
        local offset = value:find("?", 1, true)
        local oldp, oldq = e.p, e.q
        e.p, e.q = p, q
        local ok, message = Editor.replace(e, value, offset and offset - 1 or nil)
        if not ok then e.p, e.q = oldp, oldq end
        return ok, message
    end
    function Editor.key(e, key)
        if key == "Clear" then return Editor.set(e, "") end
        if key == "Del" then
            if e.p ~= e.q then return Editor.replace(e, "?", 0) end
            if e.p == 1 then return true end
            e.p = e.p - 1
            return Editor.replace(e, "")
        end
        if key == "(" then return Editor.template(e, "brackets") end
        if key == "^" then return Editor.template(e, "power") end
        if key == ")" then
            if e.source:sub(e.p, e.p) == ")" then e.p, e.q = e.p + 1, e.p + 1; return true end
            return false, "Use Next field to leave this field"
        end
        if key == "+/-" then
            if e.source == "" or e.source:sub(e.p, e.q - 1) == "?" then return Editor.replace(e, "-?", 1) end
            return Editor.set(e, "-(" .. e.source .. ")")
        end
        if key == "+" or key == "-" or key == "*" or key == "/" then
            if e.source == "" or e.source:sub(e.p, e.q - 1) == "?" then
                if key == "+" or key == "-" then return Editor.replace(e, key .. "?", 1) end
                return false, "Enter a value before the operator"
            end
            e.p = e.q
            return Editor.replace(e, key .. "?", 1)
        end
        return Editor.replace(e, key)
    end
    function Editor.history(e, redo)
        local from, to = redo and e.redo or e.undo, redo and e.undo or e.redo
        local saved = table.remove(from)
        if not saved then return false end
        to[#to + 1] = {source = e.source, p = e.p, q = e.q}
        e.source, e.p, e.q = saved.source, saved.p, saved.q
        return true
    end
    return Editor
end
