return function(B, D)
    local N = {}
    local function rational(sign, numerator, denominator)
        if denominator == "0" then error("Division by zero", 0) end
        if numerator == "0" then return {s = 0, n = "0", d = "1"} end
        local gcd = B.gcd(numerator, denominator)
        numerator, denominator = B.div(numerator, gcd), B.div(denominator, gcd)
        if #numerator > 90 or #denominator > 90 then error("Exact fraction exceeds 90 digits", 0) end
        return {s = sign, n = numerator, d = denominator}
    end
    N.rational = rational
    function N.parse(text)
        if #text > 96 then error("Numeric literal is too long", 0) end
        local sign, whole, fraction, exponent = text:match("^([+-]?)(%d*)%.?(%d*)[eE]?([+-]?%d*)$")
        if not whole or whole .. fraction == "" then error("Invalid number", 0) end
        local power = exponent == "" and 0 or tonumber(exponent)
        if not power or math.abs(power) > 80 then error("Literal exponent must be -80 through 80", 0) end
        local numerator, denominator = B.check(whole .. fraction), "1"
        power = power - #fraction
        if power >= 0 then numerator = B.shift(numerator, power) else denominator = B.shift(denominator, -power) end
        return rational(sign == "-" and -1 or 1, numerator, denominator)
    end
    function N.decimal(a)
        if a.approx then return a.value end
        return D.div(D.make(a.s, a.n, 0), D.make(1, a.d, 0))
    end
    function N.approx(value) return {approx = true, value = value} end
    function N.neg(a)
        if a.approx then return N.approx(D.neg(a.value)) end
        return {s = -a.s, n = a.n, d = a.d}
    end
    function N.abs(a)
        if a.approx then return N.approx(D.abs(a.value)) end
        return {s = math.abs(a.s), n = a.n, d = a.d}
    end
    function N.add(a, b)
        if a.approx or b.approx then return N.approx(D.add(N.decimal(a), N.decimal(b))) end
        local gcd = B.gcd(a.d, b.d)
        local ad, bd = B.div(a.d, gcd), B.div(b.d, gcd)
        local am, bm, sign, m = B.mul(a.n, bd), B.mul(b.n, ad), a.s, nil
        if a.s == b.s then m = B.add(am, bm)
        elseif B.cmp(am, bm) >= 0 then m = B.sub(am, bm)
        else m, sign = B.sub(bm, am), b.s end
        return rational(sign, m, B.mul(ad, b.d))
    end
    function N.sub(a, b) return N.add(a, N.neg(b)) end
    function N.mul(a, b)
        if a.approx or b.approx then return N.approx(D.mul(N.decimal(a), N.decimal(b))) end
        local g1, g2 = B.gcd(a.n, b.d), B.gcd(b.n, a.d)
        return rational(a.s * b.s, B.mul(B.div(a.n, g1), B.div(b.n, g2)), B.mul(B.div(a.d, g2), B.div(b.d, g1)))
    end
    function N.div(a, b)
        if a.approx or b.approx then return N.approx(D.div(N.decimal(a), N.decimal(b))) end
        if b.s == 0 then error("Division by zero", 0) end
        return N.mul(a, {s = b.s, n = b.d, d = b.n})
    end
    function N.integer(a, limit)
        if not a.approx and a.d == "1" and #a.n <= 6 then
            local n = a.s * tonumber(a.n)
            if math.abs(n) <= (limit or 10000) then return n end
        end
        return nil
    end
    function N.pow(a, b)
        local exponent = N.integer(b, 128)
        if exponent then
            if exponent < 0 then return N.div(N.parse("1"), N.pow(a, N.parse(tostring(-exponent)))) end
            local result = N.parse("1")
            while exponent > 0 do
                if exponent % 2 == 1 then result = N.mul(result, a) end
                exponent = exponent // 2
                if exponent > 0 then a = N.mul(a, a) end
            end
            return result
        end
        if D.cmp(N.decimal(a), D.zero) <= 0 then error("Non-integer power needs a positive base", 0) end
        return N.approx(D.exp(D.mul(N.decimal(b), D.ln(N.decimal(a)))))
    end
    function N.format(a, mode)
        if mode == "fraction" and not a.approx then
            local sign = a.s < 0 and "-" or ""
            return sign .. a.n .. (a.d ~= "1" and "/" .. a.d or "")
        end
        return D.format(N.decimal(a), 12, mode == "engineering")
    end
    function N.serialize(a)
        if a.approx then return "~" .. D.format(a.value, 24) end
        return (a.s < 0 and "-" or "") .. a.n .. "/" .. a.d
    end
    function N.restore(text)
        if text:sub(1, 1) == "~" then return N.approx(D.parse(text:sub(2))) end
        local sign, n, d = text:match("^([+-]?)(%d+)/(%d+)$")
        if not n then return N.parse(text) end
        return rational(sign == "-" and -1 or 1, B.check(n), B.check(d))
    end
    return N
end
