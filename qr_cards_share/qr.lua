-- QR Code Model 2 encoder for QR Cards Share.
--
-- Adapted for Lua 5.4 from Project Nayuki's QR Code generator library:
-- https://github.com/nayuki/QR-Code-generator (MIT License).
-- Copyright (c) Project Nayuki. The original copyright and permission notice:
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions: The above copyright
-- notice and this permission notice shall be included in all copies or
-- substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
-- WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
--
-- PUNRI adaptation: byte mode only, error correction M only, versions 1..10.
-- The limit is 213 payload bytes (version 10/M), chosen so that the 57-module
-- symbol still has a 7-pixel module plus a four-module quiet zone on 480 px.

local QR = {}

QR.MAX_VERSION = 10
QR.MAX_BYTES = 213

local floor, abs = math.floor, math.abs
local DATA_CODEWORDS = {16, 28, 44, 64, 86, 108, 124, 154, 182, 216}
local ECC_PER_BLOCK = {10, 16, 26, 18, 24, 16, 18, 22, 22, 26}
local BLOCK_COUNT = {1, 1, 1, 2, 2, 4, 4, 4, 5, 5}
local RAW_CODEWORDS = {26, 44, 70, 100, 134, 172, 196, 242, 292, 346}
local ALIGNMENT = {
    {}, {6, 18}, {6, 22}, {6, 26}, {6, 30}, {6, 34},
    {6, 22, 38}, {6, 24, 42}, {6, 26, 46}, {6, 28, 50},
}

local function xor(a, b)
    local out, place = 0, 1
    while a > 0 or b > 0 do
        if (a % 2) ~= (b % 2) then out = out + place end
        a, b, place = floor(a / 2), floor(b / 2), place * 2
    end
    return out
end

local function bit(value, position)
    return floor(value / (2 ^ position)) % 2 ~= 0
end

local function utf8_valid(value)
    local i, length = 1, #value
    while i <= length do
        local first = string.byte(value, i)
        if first <= 0x7F then
            i = i + 1
        else
            local need, minimum
            if first >= 0xC2 and first <= 0xDF then need, minimum = 1, 0x80
            elseif first >= 0xE0 and first <= 0xEF then need, minimum = 2, 0x800
            elseif first >= 0xF0 and first <= 0xF4 then need, minimum = 3, 0x10000
            else return false end
            if i + need > length then return false end
            local code = first % (2 ^ (7 - need))
            for j = 1, need do
                local next_byte = string.byte(value, i + j)
                if next_byte < 0x80 or next_byte > 0xBF then return false end
                code = code * 64 + (next_byte - 0x80)
            end
            if code < minimum or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then return false end
            i = i + need + 1
        end
    end
    return true
end

function QR.capacity(version)
    return DATA_CODEWORDS[version]
        and floor((DATA_CODEWORDS[version] * 8 - 4 - (version < 10 and 8 or 16)) / 8)
        or nil
end

function QR.validate_payload(payload)
    if type(payload) ~= "string" then return false, "QR content must be text" end
    if not utf8_valid(payload) then return false, "Text is not valid UTF-8" end
    for i = 1, #payload do
        local byte = payload:byte(i)
        if byte == 0 or byte == 127 or (byte < 32 and byte ~= 10 and byte ~= 13) then
            return false, "QR content contains unsupported control characters"
        end
    end
    if #payload > QR.MAX_BYTES then
        return false, string.format("QR content is %d bytes; the QR Cards limit is %d bytes", #payload, QR.MAX_BYTES)
    end
    return true
end

local function choose_version(length)
    for version = 1, QR.MAX_VERSION do
        if length <= QR.capacity(version) then return version end
    end
    return nil
end

local function append_bits(writer, value, count)
    for shift = count - 1, 0, -1 do writer(bit(value, shift) and 1 or 0) end
end

local function make_data_codewords(payload, version)
    local result, current, used = {}, 0, 0
    local function write(one)
        current = current * 2 + one
        used = used + 1
        if used == 8 then
            result[#result + 1] = current
            current, used = 0, 0
        end
    end
    append_bits(write, 0x4, 4) -- Byte mode
    append_bits(write, #payload, version < 10 and 8 or 16)
    for i = 1, #payload do append_bits(write, string.byte(payload, i), 8) end
    local target_bits = DATA_CODEWORDS[version] * 8
    local data_bits = 4 + (version < 10 and 8 or 16) + #payload * 8
    append_bits(write, 0, math.min(4, target_bits - data_bits))
    if used ~= 0 then append_bits(write, 0, 8 - used) end
    local pad = true
    while #result < DATA_CODEWORDS[version] do
        result[#result + 1] = pad and 0xEC or 0x11
        pad = not pad
    end
    return result
end

local function gf_multiply(x, y)
    local result = 0
    for i = 7, 0, -1 do
        local high = result >= 128
        result = (result * 2) % 256
        if high then result = xor(result, 0x1D) end
        if bit(y, i) then result = xor(result, x) end
    end
    return result
end

local function rs_divisor(degree)
    local result, root = {}, 1
    for i = 1, degree - 1 do result[i] = 0 end
    result[degree] = 1
    for _ = 1, degree do
        for j = 1, degree do
            result[j] = gf_multiply(result[j], root)
            if j < degree then result[j] = xor(result[j], result[j + 1]) end
        end
        root = gf_multiply(root, 2)
    end
    return result
end

local function rs_remainder(data, divisor)
    local degree, result = #divisor, {}
    for i = 1, degree do result[i] = 0 end
    for i = 1, #data do
        local factor = xor(data[i], result[1])
        for j = 1, degree - 1 do result[j] = result[j + 1] end
        result[degree] = 0
        for j = 1, degree do result[j] = xor(result[j], gf_multiply(divisor[j], factor)) end
    end
    return result
end

local function add_ecc_and_interleave(data, version)
    local blocks, offset = {}, 1
    local count, ecc_length = BLOCK_COUNT[version], ECC_PER_BLOCK[version]
    local short_blocks = count - (RAW_CODEWORDS[version] % count)
    local short_total = floor(RAW_CODEWORDS[version] / count)
    local short_data = short_total - ecc_length
    local divisor = rs_divisor(ecc_length)
    for i = 1, count do
        local data_length = short_data + (i <= short_blocks and 0 or 1)
        local block = {data = {}, ecc = {}}
        for j = 1, data_length do block.data[j] = data[offset + j - 1] end
        offset = offset + data_length
        block.ecc = rs_remainder(block.data, divisor)
        blocks[i] = block
    end
    local result, max_data = {}, short_data + (short_blocks < count and 1 or 0)
    for j = 1, max_data do
        for i = 1, count do
            if blocks[i].data[j] then result[#result + 1] = blocks[i].data[j] end
        end
    end
    for j = 1, ecc_length do
        for i = 1, count do result[#result + 1] = blocks[i].ecc[j] end
    end
    return result
end

local function new_grid(size)
    local rows = {}
    for y = 1, size do rows[y] = {} end
    return rows
end

local function set_function(matrix, functions, x, y, value)
    matrix[y + 1][x + 1] = value
    functions[y + 1][x + 1] = true
end

local function draw_finder(matrix, functions, size, x, y)
    for dy = -4, 4 do
        for dx = -4, 4 do
            local xx, yy = x + dx, y + dy
            if xx >= 0 and xx < size and yy >= 0 and yy < size then
                local distance = math.max(abs(dx), abs(dy))
                set_function(matrix, functions, xx, yy, distance ~= 2 and distance ~= 4)
            end
        end
    end
end

local function draw_alignment(matrix, functions, x, y)
    for dy = -2, 2 do
        for dx = -2, 2 do
            set_function(matrix, functions, x + dx, y + dy, math.max(abs(dx), abs(dy)) ~= 1)
        end
    end
end

local function draw_format(matrix, functions, size, mask)
    -- M has format bits 00. BCH divisor 0x537 and fixed XOR 0x5412 are ISO/IEC 18004.
    local data, remainder = mask, mask
    for _ = 1, 10 do remainder = xor(remainder * 2, floor(remainder / 512) * 0x537) end
    local bits = xor(data * 1024 + remainder, 0x5412)
    for i = 0, 5 do set_function(matrix, functions, 8, i, bit(bits, i)) end
    set_function(matrix, functions, 8, 7, bit(bits, 6))
    set_function(matrix, functions, 8, 8, bit(bits, 7))
    set_function(matrix, functions, 7, 8, bit(bits, 8))
    for i = 9, 14 do set_function(matrix, functions, 14 - i, 8, bit(bits, i)) end
    for i = 0, 7 do set_function(matrix, functions, size - 1 - i, 8, bit(bits, i)) end
    for i = 8, 14 do set_function(matrix, functions, 8, size - 15 + i, bit(bits, i)) end
    set_function(matrix, functions, 8, size - 8, true)
end

local function draw_version(matrix, functions, size, version)
    if version < 7 then return end
    local remainder = version
    for _ = 1, 12 do remainder = xor(remainder * 2, floor(remainder / 2048) * 0x1F25) end
    local bits = version * 4096 + remainder
    for i = 0, 17 do
        local a, b = size - 11 + (i % 3), floor(i / 3)
        set_function(matrix, functions, a, b, bit(bits, i))
        set_function(matrix, functions, b, a, bit(bits, i))
    end
end

local function draw_functions(matrix, functions, size, version)
    for i = 0, size - 1 do
        set_function(matrix, functions, 6, i, i % 2 == 0)
        set_function(matrix, functions, i, 6, i % 2 == 0)
    end
    draw_finder(matrix, functions, size, 3, 3)
    draw_finder(matrix, functions, size, size - 4, 3)
    draw_finder(matrix, functions, size, 3, size - 4)
    local centers, last = ALIGNMENT[version], #ALIGNMENT[version]
    for i = 1, last do
        for j = 1, last do
            if not ((i == 1 and j == 1) or (i == 1 and j == last) or (i == last and j == 1)) then
                draw_alignment(matrix, functions, centers[i], centers[j])
            end
        end
    end
    draw_format(matrix, functions, size, 0)
    draw_version(matrix, functions, size, version)
end

local function fill_codewords(matrix, functions, size, codewords)
    local index = 0
    for right = size - 1, 1, -2 do
        local column = right <= 6 and right - 1 or right
        for vertical = 0, size - 1 do
            local upward = (floor((column + 1) / 2) % 2) == 0
            local y = upward and size - 1 - vertical or vertical
            for j = 0, 1 do
                local x = column - j
                if not functions[y + 1][x + 1] and index < #codewords * 8 then
                    matrix[y + 1][x + 1] = bit(codewords[floor(index / 8) + 1], 7 - (index % 8))
                    index = index + 1
                end
            end
        end
    end
    for y = 1, size do
        for x = 1, size do if matrix[y][x] == nil then matrix[y][x] = false end end
    end
end

local function mask_at(mask, x, y)
    local product = x * y
    if mask == 0 then return (x + y) % 2 == 0 end
    if mask == 1 then return y % 2 == 0 end
    if mask == 2 then return x % 3 == 0 end
    if mask == 3 then return (x + y) % 3 == 0 end
    if mask == 4 then return (floor(x / 3) + floor(y / 2)) % 2 == 0 end
    if mask == 5 then return product % 2 + product % 3 == 0 end
    if mask == 6 then return (product % 2 + product % 3) % 2 == 0 end
    return ((x + y) % 2 + product % 3) % 2 == 0
end

local function apply_mask(matrix, functions, size, mask)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            if not functions[y + 1][x + 1] and mask_at(mask, x, y) then
                matrix[y + 1][x + 1] = not matrix[y + 1][x + 1]
            end
        end
    end
end

local function add_history(history, current)
    for i = 7, 2, -1 do history[i] = history[i - 1] end
    history[1] = current
end

local function finder_patterns(history)
    local n = history[2]
    local core = n > 0 and history[3] == n and history[5] == n and history[6] == n and history[4] == n * 3
    local count = 0
    if core and history[1] >= n * 4 and history[7] >= n then count = count + 1 end
    if core and history[7] >= n * 4 and history[1] >= n then count = count + 1 end
    return count
end

local function finish_run(history, color, length, padding, size)
    if color then
        add_history(history, length + padding)
        length, padding = 0, 0
    end
    add_history(history, length + padding + size)
    return finder_patterns(history)
end

local function penalty(matrix, size)
    local result = 0
    for axis = 0, 1 do
        for line = 0, size - 1 do
            local color, run, padding, history = false, 0, size, {0, 0, 0, 0, 0, 0, 0}
            for point = 0, size - 1 do
                local cell
                if axis == 0 then cell = matrix[line + 1][point + 1]
                else cell = matrix[point + 1][line + 1] end
                if cell == color then
                    run = run + 1
                    if run == 5 then result = result + 3 elseif run > 5 then result = result + 1 end
                else
                    add_history(history, run + padding)
                    padding = 0
                    if not color then result = result + finder_patterns(history) * 40 end
                    color, run = cell, 1
                end
            end
            result = result + finish_run(history, color, run, padding, size) * 40
        end
    end
    for y = 1, size - 1 do
        for x = 1, size - 1 do
            if matrix[y][x] == matrix[y][x + 1] and matrix[y][x] == matrix[y + 1][x] and matrix[y][x] == matrix[y + 1][x + 1] then
                result = result + 3
            end
        end
    end
    local dark = 0
    for y = 1, size do for x = 1, size do if matrix[y][x] then dark = dark + 1 end end end
    local total = size * size
    local balance = floor((abs(dark * 20 - total * 10) + total - 1) / total) - 1
    return result + balance * 10
end

local function compact_matrix(matrix, size)
    local rows = {}
    for y = 1, size do
        local bytes = {}
        for x = 1, size do bytes[x] = matrix[y][x] and 1 or 0 end
        rows[y] = string.char(table.unpack(bytes))
    end
    return rows
end

function QR.encode(payload, forced_mask)
    local valid, message = QR.validate_payload(payload)
    if not valid then return nil, message end
    if forced_mask ~= nil and (type(forced_mask) ~= "number" or forced_mask < 0 or forced_mask > 7 or forced_mask % 1 ~= 0) then
        return nil, "Invalid QR mask"
    end
    local version = choose_version(#payload)
    if not version then return nil, "Content does not fit QR Cards' version 10/M limit" end
    local size = version * 4 + 17
    local matrix, functions = new_grid(size), new_grid(size)
    draw_functions(matrix, functions, size, version)
    fill_codewords(matrix, functions, size, add_ecc_and_interleave(make_data_codewords(payload, version), version))
    local selected, lowest = forced_mask, nil
    if selected == nil then
        for mask = 0, 7 do
            apply_mask(matrix, functions, size, mask)
            draw_format(matrix, functions, size, mask)
            local score = penalty(matrix, size)
            apply_mask(matrix, functions, size, mask)
            if lowest == nil or score < lowest then selected, lowest = mask, score end
        end
    end
    apply_mask(matrix, functions, size, selected)
    draw_format(matrix, functions, size, selected)
    if lowest == nil then lowest = penalty(matrix, size) end
    local rows = compact_matrix(matrix, size)
    functions, matrix = nil, nil
    collectgarbage("collect")
    return {rows = rows, size = size, version = version, mask = selected, bytes = #payload}
end

function QR.is_dark(code, x, y)
    return code and x >= 0 and y >= 0 and x < code.size and y < code.size
        and string.byte(code.rows[y + 1], x + 1) == 1
end

function QR.bits_row(code, row)
    local data = code and code.rows[row]
    if not data then return nil end
    local result = {}
    for i = 1, #data do result[i] = string.byte(data, i) == 1 and "1" or "0" end
    return table.concat(result)
end

return QR
