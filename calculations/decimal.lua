-- Software decimal floats: 24 significant digits, 12 displayed significant
-- digits. No mantissa or decimal literal passes through native Lua floats.
return function(B)
    local D = { PREC = 24 }
    local function make(sign, m, e, precision)
        precision = precision or D.PREC
        m = B.check(m)
        if m == "0" then return {s = 0, m = "0", e = 0} end
        if #m > precision then
            local cut = #m - precision
            local tail, head = m:sub(precision + 1), m:sub(1, precision)
            local first = tail:byte(1) - 48
            if first > 5 or (first == 5 and (tail:sub(2):find("[1-9]") or (head:byte(-1) - 48) % 2 == 1)) then
                head = B.add(head, "1")
            end
            m, e = head, e + cut
        end
        local zeros = #(m:match("0*$"))
        if zeros > 0 then m, e = m:sub(1, #m - zeros), e + zeros end
        local order = #m + e - 1
        if order > 96 then error("Overflow: maximum magnitude is below 1e97", 0) end
        if order < -96 then error("Underflow: minimum magnitude is 1e-96", 0) end
        return {s = sign, m = m, e = e}
    end
    D.make = make
    function D.parse(source)
        local s, whole, fraction, exponent = source:match("^([+-]?)(%d*)%.?(%d*)[eE]?([+-]?%d*)$")
        if not whole or whole .. fraction == "" then error("Invalid decimal", 0) end
        local e = exponent == "" and 0 or tonumber(exponent)
        if not e or math.abs(e) > 120 then error("Exponent must be between -120 and 120", 0) end
        return make(s == "-" and -1 or 1, whole .. fraction, e - #fraction)
    end
    local ZERO, ONE, TWO = D.parse("0"), D.parse("1"), D.parse("2")
    D.zero, D.one = ZERO, ONE
    function D.neg(a) return {s = -a.s, m = a.m, e = a.e} end
    function D.abs(a) return {s = math.abs(a.s), m = a.m, e = a.e} end
    function D.cmp(a, b)
        if a.s ~= b.s then return a.s < b.s and -1 or 1 end
        if a.s == 0 then return 0 end
        local oa, ob = #a.m + a.e, #b.m + b.e
        if oa ~= ob then return (oa < ob and -1 or 1) * a.s end
        local length = math.max(#a.m, #b.m)
        return B.cmp(B.shift(a.m, length - #a.m), B.shift(b.m, length - #b.m)) * a.s
    end
    function D.add(a, b)
        if a.s == 0 then return b elseif b.s == 0 then return a end
        if math.abs((#a.m + a.e) - (#b.m + b.e)) > D.PREC + 2 then
            return #a.m + a.e > #b.m + b.e and a or b
        end
        local e = math.min(a.e, b.e)
        local am, bm = B.shift(a.m, a.e - e), B.shift(b.m, b.e - e)
        if a.s == b.s then return make(a.s, B.add(am, bm), e) end
        if B.cmp(am, bm) >= 0 then return make(a.s, B.sub(am, bm), e) end
        return make(b.s, B.sub(bm, am), e)
    end
    function D.sub(a, b) return D.add(a, D.neg(b)) end
    function D.mul(a, b) return make(a.s * b.s, B.mul(a.m, b.m), a.e + b.e) end
    function D.div(a, b)
        if b.s == 0 then error("Division by zero", 0) end
        local shift = D.PREC + 3 + #b.m - #a.m
        local numerator, denominator = a.m, b.m
        if shift >= 0 then numerator = B.shift(numerator, shift) else denominator = B.shift(denominator, -shift) end
        local quotient = B.div(numerator, denominator)
        return make(a.s * b.s, quotient, a.e - b.e - shift)
    end
    function D.integer(n) return D.parse(tostring(n)) end
    local function same(a, b) return a.s == b.s and a.m == b.m and a.e == b.e end
    function D.sqrt(a)
        if a.s < 0 then error("Square root needs a non-negative value", 0) end
        if a.s == 0 then return ZERO end
        local guess = make(1, "1", (#a.m + a.e) // 2)
        for _ = 1, 48 do
            local next_value = D.div(D.add(guess, D.div(a, guess)), TWO)
            if same(next_value, guess) then return next_value end
            guess = next_value
        end
        return guess
    end
    local PI = D.parse("3.141592653589793238462643383279502884")
    local HALF_PI, TAU = D.div(PI, TWO), D.mul(PI, TWO)
    local LN2, LN10 = D.parse("0.693147180559945309417232121458"), D.parse("2.302585092994045684017991454684")
    D.pi = PI
    function D.exp(a)
        if D.cmp(D.abs(a), D.integer(200)) > 0 then error("exp supports -200 through 200", 0) end
        local x, squares = a, 0
        while D.cmp(D.abs(x), D.parse("0.125")) > 0 do x, squares = D.div(x, TWO), squares + 1 end
        local sum, term = ONE, ONE
        for i = 1, 40 do
            term = D.div(D.mul(term, x), D.integer(i))
            local next_sum = D.add(sum, term)
            if same(sum, next_sum) then break end
            sum = next_sum
        end
        for _ = 1, squares do sum = D.mul(sum, sum) end
        return sum
    end
    function D.ln(a)
        if a.s <= 0 then error("Logarithm needs a positive value", 0) end
        local order, twos = #a.m + a.e - 1, 0
        local x = make(1, a.m, 1 - #a.m)
        while D.cmp(x, D.parse("1.5")) > 0 do x, twos = D.div(x, TWO), twos + 1 end
        local t = D.div(D.sub(x, ONE), D.add(x, ONE))
        local t2, term, sum = D.mul(t, t), t, t
        for i = 1, 48 do
            term = D.mul(term, t2)
            local next_sum = D.add(sum, D.div(term, D.integer(2 * i + 1)))
            if same(next_sum, sum) then break end
            sum = next_sum
        end
        return D.add(D.mul(TWO, sum), D.add(D.mul(D.integer(twos), LN2), D.mul(D.integer(order), LN10)))
    end
    function D.sincos(a)
        if D.cmp(D.abs(a), D.integer(1000000)) > 0 then error("Trig input exceeds 1000000 radians", 0) end
        if D.cmp(D.abs(a), D.parse("1e-12")) < 0 then return a, ONE end
        -- Native float supplies only a coarse integer quotient; decimal
        -- comparison below corrects it before all subsequent arithmetic.
        local rough = tonumber(D.format(a, 7)) or 0
        local turns = math.floor(rough / 6.283185307)
        local x = D.sub(a, D.mul(D.integer(turns), TAU))
        for _ = 1, 3 do
            if D.cmp(x, PI) > 0 then x = D.sub(x, TAU)
            elseif D.cmp(x, D.neg(PI)) < 0 then x = D.add(x, TAU) end
        end
        local x2, sine, cosine, st, ct = D.mul(x, x), x, ONE, x, ONE
        for i = 1, 40 do
            st = D.neg(D.div(D.mul(st, x2), D.integer((2 * i) * (2 * i + 1))))
            ct = D.neg(D.div(D.mul(ct, x2), D.integer((2 * i - 1) * (2 * i))))
            local ns, nc = D.add(sine, st), D.add(cosine, ct)
            if same(ns, sine) and same(nc, cosine) then break end
            sine, cosine = ns, nc
        end
        return sine, cosine
    end
    function D.atan(a)
        if D.cmp(D.abs(a), D.parse("1e-12")) < 0 then return a end
        local negative, x = a.s < 0, D.abs(a)
        local inverse = D.cmp(x, ONE) > 0
        if inverse then x = D.div(ONE, x) end
        local shift = D.cmp(x, D.parse("0.5")) > 0
        if shift then x = D.div(D.sub(x, ONE), D.add(x, ONE)) end
        local x2, term, sum = D.mul(x, x), x, x
        for i = 1, 72 do
            term = D.neg(D.mul(term, x2))
            local ns = D.add(sum, D.div(term, D.integer(2 * i + 1)))
            if same(ns, sum) then break end
            sum = ns
        end
        if shift then sum = D.add(D.div(PI, D.integer(4)), sum) end
        if inverse then sum = D.sub(HALF_PI, sum) end
        return negative and D.neg(sum) or sum
    end
    function D.asin(a)
        if D.cmp(D.abs(a), ONE) > 0 then error("asin needs a value from -1 to 1", 0) end
        if D.cmp(D.abs(a), ONE) == 0 then return a.s < 0 and D.neg(HALF_PI) or HALF_PI end
        return D.atan(D.div(a, D.sqrt(D.sub(ONE, D.mul(a, a)))))
    end
    function D.acos(a) return D.sub(HALF_PI, D.asin(a)) end
    function D.sinhcosh(a)
        if D.cmp(D.abs(a), D.parse("1e-12")) < 0 then return a, ONE end
        if D.cmp(D.abs(a), ONE) <= 0 then
            local x2, st, ct, sine, cosine = D.mul(a, a), a, ONE, a, ONE
            for i = 1, 24 do
                st = D.div(D.mul(st, x2), D.integer((2 * i) * (2 * i + 1)))
                ct = D.div(D.mul(ct, x2), D.integer((2 * i - 1) * (2 * i)))
                local ns, nc = D.add(sine, st), D.add(cosine, ct)
                if same(ns, sine) and same(nc, cosine) then break end
                sine, cosine = ns, nc
            end
            return sine, cosine
        end
        local positive, negative = D.exp(a), D.exp(D.neg(a))
        return D.div(D.sub(positive, negative), TWO), D.div(D.add(positive, negative), TWO)
    end
    function D.format(a, digits, engineering)
        if a.s == 0 then return "0" end
        digits = digits or 12
        local rounded = make(a.s, a.m, a.e, digits)
        local m, e = rounded.m, rounded.e
        local order = #m + e - 1
        local sign = a.s < 0 and "-" or ""
        if order >= digits or order < -5 or engineering then
            local exponent = engineering and (order // 3) * 3 or order
            local head = order - exponent + 1
            if #m < head then m = m .. string.rep("0", head - #m) end
            local tail = m:sub(head + 1)
            return sign .. m:sub(1, head) .. (tail ~= "" and "." .. tail or "") .. "e" .. tostring(exponent)
        end
        local point = #m + e
        if point <= 0 then return sign .. "0." .. string.rep("0", -point) .. m end
        if point >= #m then return sign .. m .. string.rep("0", point - #m) end
        return sign .. m:sub(1, point) .. "." .. m:sub(point + 1)
    end
    return D
end
