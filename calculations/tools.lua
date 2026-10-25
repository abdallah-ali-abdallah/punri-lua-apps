return function(B, D, N, E, P)
    local T = {}
    local function list(source, maximum)
        local values = {}
        for part in (source .. ","):gmatch("(.-),") do
            if #values >= maximum or part:match("^%s*$") then error("Check the bounded comma-separated list", 0) end
            local value, problem = E.run(part, {})
            if not value then error(problem, 0) end
            values[#values + 1] = value
        end
        return values
    end
    function T.statistics(source)
        local values = list(source, 200)
        if #values < 2 then error("Enter at least two values", 0) end
        local sum, n = N.parse("0"), N.parse(tostring(#values))
        for _, value in ipairs(values) do sum = N.add(sum, value) end
        local mean = N.div(sum, n)
        local squares = N.parse("0")
        for _, value in ipairs(values) do local delta = N.sub(value, mean); squares = N.add(squares, N.mul(delta, delta)) end
        table.sort(values, function(a, b) return D.cmp(N.decimal(a), N.decimal(b)) < 0 end)
        local middle = (#values + 1) // 2
        local median = #values % 2 == 1 and values[middle] or N.div(N.add(values[middle], values[middle + 1]), N.parse("2"))
        return {{"Count", tostring(#values)}, {"Mean", N.format(mean)}, {"Median", N.format(median)},
            {"Population SD", N.format(E.call("sqrt", {N.div(squares, n)}))},
            {"Sample s", N.format(E.call("sqrt", {N.div(squares, N.parse(tostring(#values - 1)))}))},
            {"Range", N.format(N.sub(values[#values], values[1]))}}
    end
    function T.matrix(source, operation)
        local rows, width = {}, nil
        for line in (source .. ";"):gmatch("(.-);") do
            if #rows >= 4 then error("Matrices support at most four rows", 0) end
            local row = list(line, 4)
            width = width or #row
            if #row ~= width then error("Matrix rows must have equal lengths", 0) end
            rows[#rows + 1] = row
        end
        if operation == "transpose" then
            local result = {}
            for col = 1, width do
                local values = {}
                for row = 1, #rows do values[#values + 1] = N.format(rows[row][col]) end
                result[#result + 1] = {tostring(col), table.concat(values, ", ")}
            end
            return result
        end
        if #rows ~= width then error("This operation needs a square matrix", 0) end
        local n, determinant, sign = #rows, N.parse("1"), 1
        for i = 1, n do for j = 1, n do rows[i][n + j] = N.parse(i == j and "1" or "0") end end
        for col = 1, n do
            local pivot = col
            for row = col + 1, n do
                if D.cmp(D.abs(N.decimal(rows[row][col])), D.abs(N.decimal(rows[pivot][col]))) > 0 then pivot = row end
            end
            if D.cmp(N.decimal(rows[pivot][col]), D.zero) == 0 then
                if operation == "determinant" then return {{"Determinant", "0"}} end
                error("Singular matrix has no inverse", 0)
            end
            if pivot ~= col then rows[col], rows[pivot], sign = rows[pivot], rows[col], -sign end
            local divisor = rows[col][col]
            determinant = N.mul(determinant, divisor)
            for j = col, 2 * n do rows[col][j] = N.div(rows[col][j], divisor) end
            for row = 1, n do
                if row ~= col then
                    local factor = rows[row][col]
                    for j = col, 2 * n do rows[row][j] = N.sub(rows[row][j], N.mul(factor, rows[col][j])) end
                end
            end
        end
        if operation == "determinant" then return {{"Determinant", N.format(sign < 0 and N.neg(determinant) or determinant)}} end
        local result = {}
        for i = 1, n do
            local values = {}
            for j = 1, n do values[j] = N.format(rows[i][n + j]) end
            result[#result + 1] = {tostring(i), table.concat(values, ", ")}
        end
        return result
    end
    function T.complex(source, angle)
        local values = list(source, 2)
        if #values ~= 2 then error("Enter real,imaginary", 0) end
        local a, b = values[1], values[2]
        local magnitude = E.call("sqrt", {N.add(N.mul(a, a), N.mul(b, b))})
        local ad, bd = N.decimal(a), N.decimal(b)
        if ad.s == 0 and bd.s == 0 then return {{"Magnitude", "0"}, {"Phase", "Undefined"}} end
        local phase
        if ad.s == 0 then phase = D.div(D.pi, D.integer(bd.s > 0 and 2 or -2))
        else
            phase = D.atan(D.div(bd, ad))
            if ad.s < 0 then phase = D.add(phase, bd.s >= 0 and D.pi or D.neg(D.pi)) end
        end
        if angle == "DEG" then phase = D.div(D.mul(phase, D.integer(180)), D.pi) end
        return {{"Real", N.format(a)}, {"Imaginary", N.format(b)}, {"Magnitude", N.format(magnitude)}, {"Phase", D.format(phase) .. " " .. angle}}
    end
    function T.base(source, base)
        source = source:gsub("%s", ""):upper()
        if #source == 0 or #source > 32 then error("Enter a bounded unsigned 32-bit value", 0) end
        local digits, value = "0123456789ABCDEF", "0"
        for i = 1, #source do
            local d = digits:find(source:sub(i, i), 1, true)
            if not d or d > base then error("Digit is not valid in this base", 0) end
            value = B.add(B.small(value, base), tostring(d - 1))
            if B.cmp(value, "4294967295") > 0 then error("Unsigned 32-bit range exceeded", 0) end
        end
        local result = {}
        for _, radix in ipairs({2, 8, 10, 16}) do
            local v, reversed = value, {}
            repeat
                local quotient, rem = B.div(v, tostring(radix))
                local d = tonumber(rem) + 1
                reversed[#reversed + 1], v = digits:sub(d, d), quotient
            until v == "0"
            result[#result + 1] = {"Base " .. radix, table.concat(reversed):reverse()}
        end
        return result
    end
    T.units = {
        {name = "Length", entries = {{"m", "1"}, {"cm", "0.01"}, {"mm", "0.001"}, {"km", "1000"}, {"inch", "0.0254"}, {"foot", "0.3048"}, {"mile", "1609.344"}}},
        {name = "Mass", entries = {{"kg", "1"}, {"g", "0.001"}, {"mg", "0.000001"}, {"lb", "0.45359237"}, {"oz", "0.028349523125"}}},
        {name = "Temperature", entries = {{"C", "1"}, {"F", "1"}, {"K", "1"}}},
    }
    function T.convert(source, category, from, to)
        local value, problem = E.run(source, {})
        if not value then error(problem, 0) end
        if category == 3 then
            if from == 2 then value = N.div(N.mul(N.sub(value, N.parse("32")), N.parse("5")), N.parse("9")) end
            if from == 3 then value = N.sub(value, N.parse("273.15")) end
            if D.cmp(N.decimal(value), D.parse("-273.15")) < 0 then error("Temperature is below absolute zero", 0) end
            if to == 2 then value = N.add(N.div(N.mul(value, N.parse("9")), N.parse("5")), N.parse("32")) end
            if to == 3 then value = N.add(value, N.parse("273.15")) end
        else
            local units = T.units[category].entries
            value = N.div(N.mul(value, N.parse(units[from][2])), N.parse(units[to][2]))
        end
        return {{"Result", N.format(value) .. " " .. T.units[category].entries[to][1]}}
    end
    -- A bracketed, cancellable solve job. Stopping uses both width and residual
    -- checks, so a sign change at a pole cannot be reported as a root.
    function T.solver(source, lower, upper, context)
        local tree, problem = P.parse(source)
        if not tree then error(problem.message, 0) end
        if tree.k == "eq" then tree = {k = "op", op = "-", left = tree.left, right = tree.right} end
        local a, err = E.run(lower, context)
        local b, errb = E.run(upper, context)
        if not a or not b then error(err or errb, 0) end
        if D.cmp(N.decimal(a), N.decimal(b)) >= 0 then error("Lower bound must be below upper bound", 0) end
        local function at(x)
            context.x = x
            return E.evaluate(tree, context)
        end
        local fa, fb = at(a), at(b)
        local sa, sb = N.decimal(fa).s, N.decimal(fb).s
        if sa ~= 0 and sb ~= 0 and sa == sb then error("Choose an interval that brackets one root", 0) end
        return {a = a, b = b, fa = fa, fb = fb, at = at, iterations = 0, done = false, initial = D.abs(N.decimal(N.sub(b, a)))}
    end
    function T.solve_step(job)
        if job.done then return end
        for _ = 1, 2 do
            local a, b = job.a, job.b
            local mid = N.div(N.add(a, b), N.parse("2"))
            local value = job.at(mid)
            local residual = D.abs(N.decimal(value))
            job.iterations = job.iterations + 1
            if N.decimal(job.fa).s == 0 then mid, value, residual = a, job.fa, D.zero end
            if N.decimal(job.fb).s == 0 then mid, value, residual = b, job.fb, D.zero end
            local width = D.abs(N.decimal(N.sub(b, a)))
            local scale = D.add(D.one, D.abs(N.decimal(mid)))
            if D.cmp(residual, D.parse("1e-12")) <= 0
                and (residual.s == 0 or D.cmp(width, D.mul(scale, D.parse("1e-11"))) <= 0) then
                job.done, job.root, job.residual = true, mid, value
                return
            end
            if job.iterations >= 100 then error("Solver did not converge; check the interval and discontinuities", 0) end
            if N.decimal(value).s == N.decimal(job.fa).s then job.a, job.fa = mid, value else job.b, job.fb = mid, value end
        end
    end
    return T
end
