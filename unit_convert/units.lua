-- Static unit catalogue.  Ratios convert to the category base unit as
-- (value * numerator) / denominator; every integer is within signed 32-bit
-- Lua range.  The tables are built once when this module is loaded.
local M = {}

local function unit(id, symbol, label, numerator, denominator)
    return {id = id, symbol = symbol, label = label, num = numerator, den = denominator}
end

M.categories = {
    {
        id = "length", short = "Length", base = "mm", defaults = {"m", "foot"},
        units = {
            unit("mm", "mm", "Millimetre", 1, 1),
            unit("cm", "cm", "Centimetre", 10, 1),
            unit("m", "m", "Metre", 1000, 1),
            unit("km", "km", "Kilometre", 1000000, 1),
            unit("inch", "in", "Inch", 127, 5),
            unit("foot", "ft", "Foot", 1524, 5),
            unit("yard", "yd", "Yard", 4572, 5),
            unit("mile", "mi", "Mile", 1609344, 1),
        },
    },
    {
        id = "mass", short = "Mass", base = "mg", defaults = {"g", "lb"},
        units = {
            unit("mg", "mg", "Milligram", 1, 1),
            unit("g", "g", "Gram", 1000, 1),
            unit("kg", "kg", "Kilogram", 1000000, 1),
            unit("tonne", "t", "Metric tonne", 1000000000, 1),
            unit("ounce", "oz", "Ounce", 226796185, 8000),
            unit("lb", "lb", "Pound", 45359237, 100),
        },
    },
    {
        id = "temperature", short = "Temp", base = "C", defaults = {"C", "F"}, affine = true,
        units = {
            unit("C", "C", "Celsius", 1, 1),
            unit("F", "F", "Fahrenheit", 1, 1),
            unit("K", "K", "Kelvin", 1, 1),
        },
    },
    {
        id = "volume", short = "Volume", base = "ml", defaults = {"L", "US_cup"},
        units = {
            unit("ml", "ml", "Millilitre", 1, 1),
            unit("L", "L", "Litre", 1000, 1),
            -- US customary measures, derived from the exact 231 cubic-inch US gallon.
            unit("US_tsp", "US tsp", "US teaspoon", 473176473, 96000000),
            unit("US_tbsp", "US tbsp", "US tablespoon", 473176473, 32000000),
            unit("US_floz", "US fl oz", "US fluid ounce", 473176473, 16000000),
            unit("US_cup", "US cup", "US cup", 473176473, 2000000),
            unit("US_pint", "US pt", "US pint", 473176473, 1000000),
            unit("US_quart", "US qt", "US quart", 473176473, 500000),
            unit("US_gallon", "US gal", "US gallon", 473176473, 125000),
        },
    },
    {
        id = "speed", short = "Speed", base = "mps", defaults = {"kmh", "mph"},
        units = {
            unit("mps", "m/s", "Metres per second", 1, 1),
            unit("kmh", "km/h", "Kilometres per hour", 5, 18),
            unit("mph", "mph", "Miles per hour", 1397, 3125),
            unit("knot", "kn", "Knot", 463, 900),
        },
    },
    {
        id = "data", short = "Data", base = "byte", defaults = {"MiB", "MB"}, nonnegative = true,
        units = {
            unit("byte", "B", "Byte", 1, 1),
            unit("KiB", "KiB", "Kibibyte (1024 bytes)", 1024, 1),
            unit("MiB", "MiB", "Mebibyte (1024 KiB)", 1048576, 1),
            unit("GiB", "GiB", "Gibibyte (1024 MiB)", 1073741824, 1),
            unit("kB", "kB", "Kilobyte (1000 bytes)", 1000, 1),
            unit("MB", "MB", "Megabyte (1000 kB)", 1000000, 1),
            unit("GB", "GB", "Gigabyte (1000 MB)", 1000000000, 1),
        },
    },
}

M.by_id = {}
for _, category in ipairs(M.categories) do
    M.by_id[category.id] = category
    category.by_id = {}
    for index, item in ipairs(category.units) do
        item.index = index
        category.by_id[item.id] = item
    end
end

function M.category(id)
    return M.by_id[id]
end

function M.unit(category, id)
    if not category then return nil end
    return category.by_id[id]
end

function M.next_unit(category, id, delta)
    local current = M.unit(category, id)
    if not current then return category.units[1] end
    local index = ((current.index - 1 + delta) % #category.units) + 1
    return category.units[index]
end

return M
