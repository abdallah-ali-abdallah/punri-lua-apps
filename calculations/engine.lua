return function(B, D, N, P)
    local E = {number = N, decimal = D, parser = P}
    local ONE, TWO = N.parse("1"), N.parse("2")
    local function call(name, args, angle)
        local a, b = args[1], args[2]
        local arity = ({root = 2, logbase = 2, gcd = 2, lcm = 2})[name] or 1
        if #args ~= arity then error("Check the function fields", 0) end
        if name == "abs" then return N.abs(a) end
        if name == "gcd" or name == "lcm" then
            if a.approx or b.approx or a.d ~= "1" or b.d ~= "1" then error("gcd/lcm require exact integers", 0) end
            local g = B.gcd(a.n, b.n)
            if name == "gcd" then return N.rational(1, g, "1") end
            if g == "0" then return N.parse("0") end
            return N.rational(1, B.mul(B.div(a.n, g), b.n), "1")
        end
        if name == "sqrt" and not a.approx and a.s >= 0 and #a.n <= 7 and #a.d <= 7 then
            local n, d = tonumber(a.n), tonumber(a.d)
            local rn, rd = math.floor(math.sqrt(n)), math.floor(math.sqrt(d))
            if rn * rn == n and rd * rd == d then return N.rational(a.s, tostring(rn), tostring(rd)) end
        end
        local value = N.decimal(a)
        if name == "sqrt" then return N.approx(D.sqrt(value)) end
        if name == "root" then
            local degree = N.integer(a, 128)
            if not degree or degree == 0 then error("Root degree must be an integer from -128 to 128 except zero", 0) end
            local x = N.decimal(b)
            if x.s < 0 and degree % 2 == 0 then error("Even root needs a non-negative value", 0) end
            if x.s == 0 then if degree < 0 then error("Division by zero", 0) end; return N.parse("0") end
            local answer = D.exp(D.div(D.ln(D.abs(x)), D.integer(degree)))
            return N.approx(x.s < 0 and D.neg(answer) or answer)
        end
        if name == "ln" then return N.approx(D.ln(value)) end
        if name == "log" then return N.approx(D.div(D.ln(value), D.ln(D.integer(10)))) end
        if name == "logbase" then
            if D.cmp(value, D.zero) <= 0 or D.cmp(value, D.one) == 0 then error("Log base must be positive and not one", 0) end
            return N.approx(D.div(D.ln(N.decimal(b)), D.ln(value)))
        end
        if name == "exp" then return N.approx(D.exp(value)) end
        if name == "sin" or name == "cos" or name == "tan" then
            if angle == "DEG" then value = D.div(D.mul(value, D.pi), D.integer(180)) end
            local sine, cosine = D.sincos(value)
            if name == "sin" then return N.approx(sine) end
            if name == "cos" then return N.approx(cosine) end
            if D.cmp(D.abs(cosine), D.parse("1e-20")) < 0 then error("Tangent is undefined at this angle", 0) end
            return N.approx(D.div(sine, cosine))
        end
        if name == "asin" or name == "acos" or name == "atan" then
            local result = D[name](value)
            if angle == "DEG" then result = D.div(D.mul(result, D.integer(180)), D.pi) end
            return N.approx(result)
        end
        if name == "sinh" or name == "cosh" or name == "tanh" then
            if name == "tanh" and D.cmp(D.abs(value), D.integer(30)) > 0 then return N.approx(D.integer(value.s)) end
            local sine, cosine = D.sinhcosh(value)
            return N.approx(name == "sinh" and sine or name == "cosh" and cosine or D.div(sine, cosine))
        end
        error("Unknown function: " .. name, 0)
    end
    E.call = call
    local names = {sqrt = true, root = true, abs = true, gcd = true, lcm = true, logbase = true, ln = true, log = true,
        exp = true, sin = true, cos = true, tan = true, asin = true, acos = true, atan = true, sinh = true, cosh = true, tanh = true}
    function E.validate_function(tree, variables)
        if tree.k == "slot" or tree.k == "eq" then return false, "Fill a function expression without an equation" end
        if tree.k == "call" then
            if not names[tree.name] then return false, "Unknown function: " .. tree.name end
            if #tree.args ~= (({root = 2, logbase = 2, gcd = 2, lcm = 2})[tree.name] or 1) then return false, "Check the function fields" end
            for _, arg in ipairs(tree.args) do local ok, problem = E.validate_function(arg, variables); if not ok then return ok, problem end end
        elseif tree.k == "var" then
            if tree.text ~= "x" and tree.text ~= "pi" and tree.text ~= "e" and tree.text ~= "Ans" and not variables[tree.text] then return false, "Variable not set: " .. tree.text end
        elseif tree.left then
            local ok, problem = E.validate_function(tree.left, variables)
            if not ok then return ok, problem end
            return E.validate_function(tree.right, variables)
        elseif tree.body then return E.validate_function(tree.body, variables) end
        return true
    end
    local function evaluate(node, context)
        if node.k == "num" then return N.parse(node.text) end
        if node.k == "slot" then error("Fill every empty field first", 0) end
        if node.k == "var" then
            if node.text == "pi" then return N.approx(D.pi) end
            if node.text == "e" then return N.approx(D.exp(D.one)) end
            if node.text == "Ans" then return context.ans or N.parse("0") end
            if node.text == "x" and context.x then return context.x end
            local saved = context.variables and context.variables[node.text]
            if saved then return saved end
            error("Variable not set: " .. node.text, 0)
        end
        if node.k == "group" then return evaluate(node.body, context) end
        if node.k == "unary" then local a = evaluate(node.body, context); return node.op == "-" and N.neg(a) or a end
        if node.k == "factorial" then
            local integer = N.integer(evaluate(node.body, context), 50)
            if not integer or integer < 0 then error("Factorial supports integers from 0 to 50", 0) end
            local product = ONE
            for i = 2, integer do product = N.mul(product, N.parse(tostring(i))) end
            return product
        end
        if node.k == "call" then
            local args = {}
            for i, arg in ipairs(node.args) do args[i] = evaluate(arg, context) end
            return call(node.name, args, context.angle)
        end
        if node.k == "eq" then error("Use the equation solver", 0) end
        local a, b = evaluate(node.left, context), evaluate(node.right, context)
        if node.op == "+" then return N.add(a, b) elseif node.op == "-" then return N.sub(a, b)
        elseif node.op == "*" then return N.mul(a, b) elseif node.op == "/" then return N.div(a, b)
        elseif node.op == "^" then return N.pow(a, b) end
        error("Unknown operator", 0)
    end
    E.evaluate = evaluate
    function E.run(source, context)
        local tree, problem = P.parse(source)
        if not tree then return nil, problem.message, problem.pos end
        local ok, value = pcall(evaluate, tree, context or {})
        if ok then return value end
        return nil, tostring(value), tree.p
    end
    -- Graph pixels use the native float path deliberately. Its approximate
    -- values are labeled separately from the 12-digit calculator backend.
    local function fast(node, x, context)
        if node.k == "num" then return tonumber(node.text) end
        if node.k == "var" then
            if node.text == "x" then return x elseif node.text == "pi" then return math.pi
            elseif node.text == "e" then return math.exp(1) elseif node.text == "Ans" then return context.fast_ans or 0 end
            local variable = context.fast_variables and context.fast_variables[node.text]
            if variable then return variable end
            return nil
        end
        if node.body then
            local a = fast(node.body, x, context)
            if not a then return nil end
            if node.k == "unary" then return node.op == "-" and -a or a end
            if node.k == "factorial" then
                if a < 0 or a > 30 or a ~= math.floor(a) then return nil end
                local product = 1.0
                for i = 2, a do product = product * i end
                return product
            end
            return a
        end
        if node.k == "call" then
            local a = fast(node.args[1], x, context)
            if not a then return nil end
            local b = node.args[2] and fast(node.args[2], x, context)
            local name = node.name
            if name == "sin" or name == "cos" or name == "tan" then
                if context.angle == "DEG" then a = a * math.pi / 180 end
                if name == "tan" and math.abs(math.cos(a)) < 1e-6 then return nil end
                return math[name](a)
            end
            if name == "asin" or name == "acos" or name == "atan" then
                local value = math[name](a)
                return context.angle == "DEG" and value * 180 / math.pi or value
            end
            if name == "sqrt" then return a >= 0 and math.sqrt(a) or nil end
            if name == "ln" then return a > 0 and math.log(a) or nil end
            if name == "log" then return a > 0 and math.log(a, 10) or nil end
            if name == "logbase" then return b and b > 0 and a > 0 and a ~= 1 and math.log(b, a) or nil end
            if name == "root" then return b and a ~= 0 and a == math.floor(a) and math.abs(a) <= 128 and (b >= 0 and b ^ (1 / a) or a % 2 ~= 0 and -((-b) ^ (1 / a))) or nil end
            if name == "exp" then return math.exp(a) end
            if name == "abs" then return math.abs(a) end
            if name == "sinh" then return (math.exp(a) - math.exp(-a)) / 2 end
            if name == "cosh" then return (math.exp(a) + math.exp(-a)) / 2 end
            if name == "tanh" then return (math.exp(a) - math.exp(-a)) / (math.exp(a) + math.exp(-a)) end
            return nil
        end
        if node.k ~= "op" then return nil end
        local a, b = fast(node.left, x, context), fast(node.right, x, context)
        if not a or not b then return nil end
        if node.op == "+" then return a + b elseif node.op == "-" then return a - b
        elseif node.op == "*" then return a * b elseif node.op == "/" then return b ~= 0 and a / b or nil
        elseif node.op == "^" then return a ^ b end
    end
    function E.fast(tree, x, context)
        local value = fast(tree, x, context)
        if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    return E
end
