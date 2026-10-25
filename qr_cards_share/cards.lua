-- Structured card validation and QR payload construction. No card payload is logged.

local Cards = {}

Cards.MAX_CARDS = 12
Cards.types = {
    {id = "link", label = "Link / Text", fields = {"title", "content"}},
    {id = "contact", label = "Contact (vCard)", fields = {"title", "name", "phone", "email", "address", "note"}},
    {id = "wifi", label = "Wi-Fi", fields = {"title", "ssid", "password", "security", "hidden"}},
    {id = "emergency", label = "Emergency / Return", fields = {"title", "message", "contact"}},
}

local TYPE_INDEX = {}
for _, item in ipairs(Cards.types) do TYPE_INDEX[item.id] = item end

local LIMITS = {
    title = 48, content = 213, name = 64, phone = 40, email = 96,
    address = 90, note = 90, ssid = 64, password = 63, security = 6,
    hidden = 5, message = 180, contact = 213,
}

local function valid_utf8(value)
    local i = 1
    while i <= #value do
        local first = string.byte(value, i)
        if first <= 0x7F then
            i = i + 1
        else
            local need, minimum
            if first >= 0xC2 and first <= 0xDF then need, minimum = 1, 0x80
            elseif first >= 0xE0 and first <= 0xEF then need, minimum = 2, 0x800
            elseif first >= 0xF0 and first <= 0xF4 then need, minimum = 3, 0x10000
            else return false end
            if i + need > #value then return false end
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

function Cards.valid_field(field, value)
    if type(value) ~= "string" or #value > (LIMITS[field] or 0) then return false end
    if not valid_utf8(value) then return false end
    for i = 1, #value do
        local byte = string.byte(value, i)
        if byte == 0 or byte == 0x7F or (byte < 0x20) then return false end
    end
    return true
end

function Cards.type_for(id) return TYPE_INDEX[id] end

function Cards.label_for(id)
    local item = TYPE_INDEX[id]
    return item and item.label or "Unknown"
end

function Cards.new(id)
    local item = TYPE_INDEX[id]
    if not item then return nil end
    local fields = {}
    for _, field in ipairs(item.fields) do fields[field] = "" end
    if id == "wifi" then fields.security = "WPA"; fields.hidden = "false" end
    return {type = id, modified = "Not saved", fields = fields}
end

function Cards.copy(card)
    local clone = {type = card.type, modified = card.modified, fields = {}}
    for key, value in pairs(card.fields or {}) do clone.fields[key] = value end
    return clone
end

function Cards.field_names(id)
    local item = TYPE_INDEX[id]
    return item and item.fields or {}
end

function Cards.field_limit(field) return LIMITS[field] or 0 end

function Cards.display_field(field)
    local labels = {
        title = "Title", content = "Link or text", name = "Name", phone = "Phone", email = "Email",
        address = "Address", note = "Note", ssid = "Network name", password = "Password",
        security = "Security (WPA/WEP/Open)", hidden = "Hidden (true/false)", message = "Large message",
        contact = "QR contact (optional)",
    }
    return labels[field] or field
end

local function escaped(value, extra)
    return (value:gsub("[\\;,:\"]", function(character)
        return extra[character] and "\\" .. character or character
    end))
end

local function vcard_escape(value)
    value = value:gsub("\\", "\\\\"):gsub(";", "\\;"):gsub(",", "\\,")
    return value:gsub("\r\n", "\\n"):gsub("\n", "\\n"):gsub("\r", "\\n")
end

function Cards.payload(card)
    if not card or not TYPE_INDEX[card.type] then return nil, "Unknown card type" end
    local field = card.fields
    if card.type == "link" then return field.content end
    if card.type == "contact" then
        local lines = {"BEGIN:VCARD", "VERSION:3.0", "FN:" .. vcard_escape(field.name)}
        if field.phone ~= "" then lines[#lines + 1] = "TEL:" .. vcard_escape(field.phone) end
        if field.email ~= "" then lines[#lines + 1] = "EMAIL:" .. vcard_escape(field.email) end
        if field.address ~= "" then lines[#lines + 1] = "ADR:;;" .. vcard_escape(field.address) end
        if field.note ~= "" then lines[#lines + 1] = "NOTE:" .. vcard_escape(field.note) end
        lines[#lines + 1] = "END:VCARD"
        return table.concat(lines, "\r\n")
    end
    if card.type == "wifi" then
        local security = field.security == "Open" and "nopass" or field.security
        local content = "WIFI:T:" .. security .. ";S:" .. escaped(field.ssid, {['\\'] = true, [';'] = true, [','] = true, [':'] = true, ['"'] = true}) .. ";"
        if security ~= "nopass" then content = content .. "P:" .. escaped(field.password, {['\\'] = true, [';'] = true, [','] = true, [':'] = true, ['"'] = true}) .. ";" end
        if field.hidden == "true" then content = content .. "H:true;" end
        return content .. ";"
    end
    return field.contact ~= "" and field.contact or nil
end

function Cards.validate(card, qr)
    local item = card and TYPE_INDEX[card.type]
    if not item or type(card.fields) ~= "table" then return false, "Invalid card" end
    for _, field in ipairs(item.fields) do
        if not Cards.valid_field(field, card.fields[field] or "") then return false, "Invalid " .. Cards.display_field(field) end
    end
    if card.fields.title == "" then return false, "A title is required" end
    if card.type == "link" and card.fields.content == "" then return false, "Link or text is required" end
    if card.type == "contact" and card.fields.name == "" then return false, "A contact name is required" end
    if card.type == "wifi" then
        if card.fields.ssid == "" then return false, "A network name is required" end
        if card.fields.security ~= "WPA" and card.fields.security ~= "WEP" and card.fields.security ~= "Open" then
            return false, "Security must be WPA, WEP, or Open"
        end
        if card.fields.hidden ~= "true" and card.fields.hidden ~= "false" then return false, "Hidden must be true or false" end
        if card.fields.security ~= "Open" and card.fields.password == "" then return false, "A password is required" end
    end
    if card.type == "emergency" and card.fields.message == "" then return false, "A large message is required" end
    local payload = Cards.payload(card)
    if payload then
        local ok, message = qr.validate_payload(payload)
        if not ok then return false, message end
    end
    return true, nil, payload
end

function Cards.modified_now()
    local date = punri.get_date and punri.get_date() or nil
    if type(date) == "table" and type(date.year) == "number" and type(date.month) == "number" and type(date.day) == "number"
        and date.month >= 1 and date.month <= 12 and date.day >= 1 and date.day <= 31 then
        return string.format("%04d-%02d-%02d %02d:%02d", date.year, date.month, date.day, date.hour or 0, date.min or 0)
    end
    return "Clock unavailable"
end

return Cards
