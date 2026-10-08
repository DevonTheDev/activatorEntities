-- Test-only byte tokens model JSON round-trips; they do not parse native JSON.
-- Every token owns a detached snapshot, including sparse keys and Vector type.
return function(env, eq)
    local constructor, isvector = env.Vector, env.isvector
    local snapshots, bytesByValue, nextToken = {}, {}, 0
    local codec = {}
    function codec.copy(value)
        if isvector(value) then return constructor(value.x, value.y, value.z) end
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = codec.copy(child) end
        return result
    end
    local function signature(value)
        local kind = type(value)
        if kind == "number" then
            return "n:" .. ((math.type and math.type(value) == "integer") and tostring(value) or string.format("%.17g", value))
        end
        if kind ~= "table" then return kind .. ":" .. string.format("%q", tostring(value)) end
        local entries = {}
        for key, child in pairs(value) do entries[#entries + 1] = signature(key) .. "=" .. signature(child) end
        table.sort(entries)
        return (isvector(value) and "vector{" or "table{") .. table.concat(entries, ";") .. "}"
    end
    function codec.remember(bytes, value)
        assert(type(bytes) == "string")
        assert(snapshots[bytes] == nil, "a byte token has only one immutable snapshot")
        snapshots[bytes] = {value=codec.copy(value)}
        bytesByValue[signature(value)] = bytes
        return bytes
    end
    function codec.encode(value)
        local key = signature(value)
        local bytes = bytesByValue[key]
        if not bytes then
            repeat
                nextToken = nextToken + 1
                bytes = '{"spawnSnapshot":' .. nextToken .. '}'
            until snapshots[bytes] == nil
            codec.remember(bytes, value)
        end
        return bytes
    end
    function codec.decode(bytes, ignoreLimits, ignoreConversions)
        eq(ignoreLimits == true, false, "keep GMod JSON limits enabled")
        eq(ignoreConversions == true, false, "preserve numeric-key conversion")
        local saved = snapshots[bytes]
        return saved and codec.copy(saved.value)
    end
    function codec.same(actual, expected)
        eq(type(actual), type(expected), "snapshot value type")
        eq(isvector(actual), isvector(expected), "snapshot Vector type")
        if type(expected) ~= "table" then
            if type(expected) == "number" and expected ~= expected then assert(actual ~= actual)
            else eq(actual, expected) end
            return
        end
        for key, child in pairs(expected) do codec.same(actual[key], child) end
        for key in pairs(actual) do assert(expected[key] ~= nil, "unexpected snapshot key " .. tostring(key)) end
    end
    return codec
end
