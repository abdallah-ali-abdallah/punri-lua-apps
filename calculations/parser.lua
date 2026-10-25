local P = { MAX_BYTES = 512, MAX_TOKENS = 256, MAX_DEPTH = 20 }
local function fail(message, pos) error({message = message, pos = pos}, 0) end
function P.parse(source)
    local function parse()
        if #source > P.MAX_BYTES then fail("Expression is too long", P.MAX_BYTES) end
        local tokens, position = {}, 1
        while position <= #source do
            local rest, text = source:sub(position), nil
            if rest:match("^%s") then position = position + 1
            else
                text = rest:match("^%d+%.?%d*[eE][+-]?%d+") or rest:match("^%.%d+[eE][+-]?%d+")
                    or rest:match("^%d+%.?%d*") or rest:match("^%.%d+") or rest:match("^[A-Za-z]+")
                    or rest:match("^[+%-%*/%^%(%)=,%?!]")
                if not text then fail("Unknown character", position) end
                tokens[#tokens + 1] = {text = text, p = position, q = position + #text}
                if #tokens > P.MAX_TOKENS then fail("Too many expression tokens", position) end
                position = position + #text
            end
        end
        if #tokens == 0 then fail("Enter an expression", 1) end
        local cursor, equalities = 1, 0
        local function read(minimum, depth)
            if depth > P.MAX_DEPTH then fail("Expression is too deep", tokens[cursor] and tokens[cursor].p or #source) end
            local token = tokens[cursor]
            if not token then fail("Fill the missing value", #source + 1) end
            cursor = cursor + 1
            local text, node = token.text, nil
            if text == "+" or text == "-" then
                local body = read(3, depth + 1)
                node = {k = "unary", op = text, body = body, p = token.p, q = body.q}
            elseif text == "(" then
                local body = read(0, depth + 1)
                local close = tokens[cursor]
                if not close or close.text ~= ")" then fail("Close the bracket", token.p) end
                cursor = cursor + 1
                node = {k = "group", body = body, p = token.p, q = close.q}
            elseif text:match("^[A-Za-z]") and tokens[cursor] and tokens[cursor].text == "(" then
                cursor = cursor + 1
                local args = {read(0, depth + 1)}
                while tokens[cursor] and tokens[cursor].text == "," do
                    if #args >= 2 then fail("At most two function fields", token.p) end
                    cursor = cursor + 1
                    args[#args + 1] = read(0, depth + 1)
                end
                local close = tokens[cursor]
                if not close or close.text ~= ")" then fail("Close the function bracket", token.p) end
                cursor = cursor + 1
                node = {k = "call", name = text, args = args, p = token.p, q = close.q}
            elseif text == "?" or text:match("^[%d%.]") or text:match("^[A-Za-z]") then
                node = {k = text == "?" and "slot" or text:match("^[%d%.]") and "num" or "var", text = text, p = token.p, q = token.q}
            else fail("Fill the missing value", token.p) end
            while tokens[cursor] do
                local operator = tokens[cursor].text
                if operator == "!" then
                    local last = tokens[cursor]
                    cursor = cursor + 1
                    node = {k = "factorial", body = node, p = node.p, q = last.q}
                else
                    local precedence = ({["="] = 0, ["+"] = 1, ["-"] = 1, ["*"] = 2, ["/"] = 2, ["^"] = 4})[operator]
                    if not precedence or precedence < minimum then break end
                    if operator == "=" then
                        equalities = equalities + 1
                        if equalities > 1 or depth ~= 0 then fail("Use one equation at the outer level", tokens[cursor].p) end
                    end
                    cursor = cursor + 1
                    local right = read(precedence + (operator == "^" and 0 or 1), depth + 1)
                    node = {k = operator == "=" and "eq" or "op", op = operator, left = node, right = right, p = node.p, q = right.q}
                end
            end
            return node
        end
        local tree = read(0, 0)
        if cursor <= #tokens then fail("Add an operator between values", tokens[cursor].p) end
        return tree
    end
    local ok, result = pcall(parse)
    if ok then return result end
    return nil, type(result) == "table" and result or {message = tostring(result), pos = 1}
end
function P.fields(tree, output)
    if not tree then return output end
    if tree.k == "num" or tree.k == "var" or tree.k == "slot" then output[#output + 1] = tree
    elseif tree.left then P.fields(tree.left, output); P.fields(tree.right, output)
    elseif tree.args then for _, arg in ipairs(tree.args) do P.fields(arg, output) end
    elseif tree.body then P.fields(tree.body, output) end
    return output
end
return P
