-- One bounded snapshot; punri.write_file already provides sync/close/backup
-- replacement and recovery. Never append to, or overwrite, an unknown schema.
local Store = { FILE = "session_v1.txt", MAX_BYTES = 65536 }
local function checksum(text)
    local a, b = 1, 0
    for i = 1, #text do a = (a + text:byte(i)) % 65521; b = (b + a) % 65521 end
    return string.format("%04x%04x", b, a)
end
local function safe(text, limit)
    return type(text) == "string" and #text <= limit and not text:find("[\r\n|%z]")
end
function Store.encode(state, N)
    local editor = state.return_editor or state.editor
    local lines = {"PUNRI_CALCULATIONS_1", "angle|" .. state.angle, "mode|" .. state.mode,
        "locale|" .. state.locale, "orientation|" .. state.orientation, "view|" .. (state.edited_slot and "functions" or state.view),
        "input|" .. editor.source, "answer|" .. N.serialize(state.ans), "evaluated|" .. state.evaluated}
    for i, fn in ipairs(state.functions) do lines[#lines + 1] = "function|" .. i .. "|" .. (fn.enabled and "1" or "0") .. "|" .. fn.source end
    for byte = 65, 90 do
        local name = string.char(byte)
        if state.variables[name] then lines[#lines + 1] = "variable|" .. name .. "|" .. N.serialize(state.variables[name]) end
    end
    for _, row in ipairs(state.history) do lines[#lines + 1] = "history|" .. row.source .. "|" .. row.answer .. "|" .. row.angle end
    local body = table.concat(lines, "\n") .. "\n"
    if #body > Store.MAX_BYTES - 40 then return nil, "Session exceeds the storage limit" end
    return body .. "checksum|" .. checksum(body) .. "\n"
end
function Store.decode(raw, N, P)
    if not raw or raw == "" then return nil end
    if #raw > Store.MAX_BYTES or raw:sub(1, 21) ~= "PUNRI_CALCULATIONS_1\n" then return nil, "Saved session has an unknown format" end
    local body, expected = raw:match("^(.*\n)checksum|([a-f0-9]+)\n$")
    if not body or #expected ~= 8 or checksum(body) ~= expected then return nil, "Saved session is damaged" end
    local data = {functions = {}, history = {}, variables = {}}
    local seen = {}
    for line in body:gmatch("[^\n]+") do
        if line ~= "PUNRI_CALCULATIONS_1" then
            local parts = {}
            for field in (line .. "|"):gmatch("(.-)|") do parts[#parts + 1] = field end
            local tag = parts[1]
            if tag == "function" then
                local index = tonumber(parts[2])
                if #parts ~= 4 or not index or index < 1 or index > 4 or data.functions[index] or not safe(parts[4], P.MAX_BYTES)
                    or (parts[3] ~= "0" and parts[3] ~= "1") then return nil, "Saved functions are damaged" end
                data.functions[index] = {source = parts[4], enabled = parts[3] == "1"}
            elseif tag == "history" then
                if #parts ~= 4 or #data.history >= 50 or not safe(parts[2], P.MAX_BYTES) or not safe(parts[3], 192)
                    or (parts[4] ~= "RAD" and parts[4] ~= "DEG") or not P.parse(parts[2]) then return nil, "Saved history is damaged" end
                data.history[#data.history + 1] = {source = parts[2], answer = parts[3], angle = parts[4]}
            elseif tag == "variable" then
                if #parts ~= 3 or not parts[2]:match("^[A-Z]$") or data.variables[parts[2]] then return nil, "Saved variables are damaged" end
                data.variables[parts[2]] = N.restore(parts[3])
            else
                if #parts ~= 2 or seen[tag] then return nil, "Saved session is damaged" end
                seen[tag], data[tag] = true, parts[2]
            end
        end
    end
    if data.angle ~= "RAD" and data.angle ~= "DEG" then return nil, "Saved angle mode is damaged" end
    if data.mode ~= "decimal" and data.mode ~= "fraction" and data.mode ~= "engineering" then return nil, "Saved number mode is damaged" end
    if data.locale ~= "en" and data.locale ~= "ar" then return nil, "Saved language is damaged" end
    if data.orientation ~= "portrait" and data.orientation ~= "landscape" then return nil, "Saved orientation is damaged" end
    if not ({calculate = true, functions = true, graph = true, table = true, tools = true})[data.view] then return nil, "Saved view is damaged" end
    if not safe(data.input, P.MAX_BYTES) or not safe(data.evaluated, P.MAX_BYTES) or not safe(data.answer, 192) then return nil, "Saved expression is damaged" end
    for i = 1, 4 do if not data.functions[i] then return nil, "Saved functions are missing" end end
    data.ans = N.restore(data.answer)
    return data
end
function Store.load(N, P)
    -- Read one extra byte so an oversized valid prefix cannot be accepted.
    local raw = punri.read_file(Store.FILE, Store.MAX_BYTES + 1)
    local ok, data, problem = pcall(Store.decode, raw, N, P)
    if not ok then return nil, "Saved session is damaged" end
    return data, problem
end
function Store.save(state, N)
    local ok, raw, problem = pcall(Store.encode, state, N)
    if not ok then return false, tostring(raw) end
    if not raw then return false, problem end
    if not punri.write_file(Store.FILE, raw) then
        punri.log("Calculations: session write failed; prior snapshot retained")
        return false, "Save failed. Retry or exit without saving."
    end
    return true
end
return Store
