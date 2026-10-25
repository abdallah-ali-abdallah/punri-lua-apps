-- Conversion and validation deliberately stay independent from drawing and SD I/O.
return function(Units)
    local M = {}

    -- Lua is compiled with 32-bit floats on PUNRI.  The source-unit limit is
    -- derived from this base cap, so a valid small-unit result remains editable
    -- after Swap (for example 1 GiB -> 1,073,741,824 bytes).
    M.MAX_BASE = 1100000000000000.0
    M.ABSOLUTE_ZERO_C = -273.15
    local ABSOLUTE_ZERO_EPSILON = 0.0002

    local function finite(value)
        return value == value and value <= M.MAX_BASE and value >= -M.MAX_BASE
    end

    local function linear_to_base(value, item)
        -- The 0.0 coercions prevent 32-bit Lua integer multiplication from
        -- wrapping before the division is applied (notably GiB -> bytes).
        return ((value + 0.0) * (item.num + 0.0)) / (item.den + 0.0)
    end

    local function linear_from_base(value, item)
        -- Divide first to keep the intermediate bounded for US volume ratios.
        return ((value + 0.0) / (item.num + 0.0)) * (item.den + 0.0)
    end

    function M.input_limit(category, item)
        if category.affine then return M.MAX_BASE end
        return (M.MAX_BASE / (item.num + 0.0)) * (item.den + 0.0)
    end

    function M.to_base(value, category, item)
        if category.affine then
            if item.id == "C" then return value + 0.0 end
            if item.id == "F" then return ((value + 0.0) - 32.0) * 5.0 / 9.0 end
            if item.id == "K" then return (value + 0.0) - 273.15 end
            return nil, "Unknown temperature unit."
        end
        return linear_to_base(value, item)
    end

    function M.from_base(value, category, item)
        if category.affine then
            if item.id == "C" then return value + 0.0 end
            if item.id == "F" then return ((value + 0.0) * 9.0 / 5.0) + 32.0 end
            if item.id == "K" then return (value + 0.0) + 273.15 end
            return nil, "Unknown temperature unit."
        end
        return linear_from_base(value, item)
    end

    function M.convert(value, category, from, to)
        if value == nil or value ~= value then return nil, "Enter a valid number." end
        value = value + 0.0
        local limit = M.input_limit(category, from)
        if value > limit or value < -limit then
            return nil, "Input is outside this unit's safe range."
        end
        if category.nonnegative and value < 0.0 then
            return nil, "Data values cannot be negative."
        end

        local base, error = M.to_base(value, category, from)
        if not base or not finite(base) then return nil, error or "Conversion is outside the safe range." end
        if category.affine and base < M.ABSOLUTE_ZERO_C - ABSOLUTE_ZERO_EPSILON then
            return nil, "Temperature is below absolute zero."
        end

        local result
        result, error = M.from_base(base, category, to)
        if not result or not finite(result) then return nil, error or "Conversion is outside the safe range." end
        if category.nonnegative and result < 0.0 then return nil, "Conversion produced an invalid data value." end
        return result
    end

    return M
end
