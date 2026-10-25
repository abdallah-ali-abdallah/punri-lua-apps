-- Bounded, length-prefixed storage. Existing corrupt data is never overwritten automatically.

local Storage = {}
local FILE = "cards_v1.dat"
local HEADER = "PUNRI_QR_CARDS_1\n"
local MAX_FILE_BYTES = 8192

local function append_field(parts, value)
    parts[#parts + 1] = tostring(#value)
    parts[#parts + 1] = "\n"
    parts[#parts + 1] = value
    parts[#parts + 1] = "\n"
end

local function read_line(data, position)
    local end_at = data:find("\n", position, true)
    if not end_at then return nil end
    return data:sub(position, end_at - 1), end_at + 1
end

local function read_field(data, position, maximum)
    local text
    text, position = read_line(data, position)
    if not text or not text:match("^%d+$") then return nil end
    local length = tonumber(text)
    if not length or length > maximum or position + length - 1 > #data then return nil end
    local value = data:sub(position, position + length - 1)
    position = position + length
    if data:sub(position, position) ~= "\n" then return nil end
    return value, position + 1
end

function Storage.save(cards)
    if #cards > Cards.MAX_CARDS then return false, "Card limit reached" end
    local parts = {HEADER, tostring(#cards), "\n"}
    for _, card in ipairs(cards) do
        local ok, message = Cards.validate(card, QR)
        if not ok then return false, message end
        append_field(parts, card.type)
        append_field(parts, card.modified or "Clock unavailable")
        for _, field in ipairs(Cards.field_names(card.type)) do append_field(parts, card.fields[field]) end
    end
    local payload = table.concat(parts)
    if #payload > MAX_FILE_BYTES then return false, "Saved card data is too large" end
    if not punri.write_file(FILE, payload) then return false, "Save failed. The last saved cards are still intact." end
    return true
end

function Storage.load()
    local data = punri.read_file(FILE, MAX_FILE_BYTES + 1)
    if data == nil or data == "" then return {}, nil end
    if #data > MAX_FILE_BYTES or data:sub(1, #HEADER) ~= HEADER then return nil, "Saved cards are corrupt; they were left unchanged." end
    local position = #HEADER + 1
    local count
    count, position = read_line(data, position)
    count = count and tonumber(count)
    if not count or count < 0 or count > Cards.MAX_CARDS or count % 1 ~= 0 then return nil, "Saved cards are corrupt; they were left unchanged." end
    local cards = {}
    for _ = 1, count do
        local type, modified
        type, position = read_field(data, position, 12)
        if type == nil or position == nil then return nil, "Saved cards are corrupt; they were left unchanged." end
        modified, position = read_field(data, position, 32)
        local item = type and Cards.type_for(type)
        if not item or not modified or position == nil or not Cards.valid_field("title", modified) then
            return nil, "Saved cards are corrupt; they were left unchanged."
        end
        local card = Cards.new(type)
        card.modified = modified
        for _, field in ipairs(item.fields) do
            local value
            value, position = read_field(data, position, 256)
            if value == nil then return nil, "Saved cards are corrupt; they were left unchanged." end
            card.fields[field] = value
        end
        local ok = Cards.validate(card, QR)
        if not ok then return nil, "Saved cards are corrupt; they were left unchanged." end
        cards[#cards + 1] = card
    end
    if position <= #data then return nil, "Saved cards are corrupt; they were left unchanged." end
    return cards, nil
end

function Storage.file_name() return FILE end

return Storage
