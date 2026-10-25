-- Unsigned, bounded decimal integers. Every intermediate is below 1000,
-- including on PUNRI's signed 32-bit integer / binary32 Lua build.
local B = { MAX = 192 }
local function trim(s)
    s = s:gsub("^0+", "")
    return s == "" and "0" or s
end
function B.check(s)
    if #s > B.MAX then error("Number exceeds the 192-digit working limit", 0) end
    return trim(s)
end
function B.cmp(a, b)
    if #a ~= #b then return #a < #b and -1 or 1 end
    if a == b then return 0 end
    return a < b and -1 or 1
end
function B.add(a, b)
    local out, carry, i, j = {}, 0, #a, #b
    while i > 0 or j > 0 or carry > 0 do
        local v = (i > 0 and a:byte(i) - 48 or 0) + (j > 0 and b:byte(j) - 48 or 0) + carry
        out[#out + 1], carry = string.char(48 + v % 10), v // 10
        i, j = i - 1, j - 1
    end
    return B.check(table.concat(out):reverse())
end
function B.sub(a, b)
    assert(B.cmp(a, b) >= 0)
    local out, borrow, j = {}, 0, #b
    for i = #a, 1, -1 do
        local v = a:byte(i) - 48 - borrow - (j > 0 and b:byte(j) - 48 or 0)
        borrow = v < 0 and 1 or 0
        out[#out + 1] = string.char(48 + (v + 10) % 10)
        j = j - 1
    end
    return trim(table.concat(out):reverse())
end
function B.small(a, n)
    local out, carry = {}, 0
    for i = #a, 1, -1 do
        local v = (a:byte(i) - 48) * n + carry
        out[#out + 1], carry = string.char(48 + v % 10), v // 10
    end
    while carry > 0 do out[#out + 1], carry = string.char(48 + carry % 10), carry // 10 end
    return B.check(table.concat(out):reverse())
end
function B.mul(a, b)
    if a == "0" or b == "0" then return "0" end
    if #a + #b > B.MAX + 1 then error("Number exceeds the working limit", 0) end
    local out = {}
    for i = 1, #a + #b do out[i] = 0 end
    for i = #a, 1, -1 do
        local carry = 0
        for j = #b, 1, -1 do
            local k = i + j
            local v = (a:byte(i) - 48) * (b:byte(j) - 48) + out[k] + carry
            out[k], carry = v % 10, v // 10
        end
        out[i] = carry
    end
    for i = 1, #out do out[i] = string.char(48 + out[i]) end
    return B.check(table.concat(out))
end
function B.shift(a, n)
    if a == "0" then return a end
    if n < 0 or #a + n > B.MAX then error("Exponent exceeds the working limit", 0) end
    return a .. string.rep("0", n)
end
function B.div(a, b)
    if b == "0" then error("Division by zero", 0) end
    if B.cmp(a, b) < 0 then return "0", a end
    local out, remainder = {}, "0"
    for i = 1, #a do
        remainder = trim((remainder == "0" and "" or remainder) .. a:sub(i, i))
        local low, high = 0, 9
        while low < high do
            local mid = (low + high + 1) // 2
            if B.cmp(B.small(b, mid), remainder) <= 0 then low = mid else high = mid - 1 end
        end
        out[i] = string.char(48 + low)
        if low > 0 then remainder = B.sub(remainder, B.small(b, low)) end
    end
    return trim(table.concat(out)), remainder
end
function B.gcd(a, b)
    for _ = 1, 512 do
        if b == "0" then return a end
        local _, r = B.div(a, b)
        a, b = b, r
    end
    error("Fraction reduction limit reached", 0)
end
return B
