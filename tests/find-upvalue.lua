-- Test-only closure inspection. A separate found flag preserves nil values.
return function(callback, wanted)
    local seen, visited = {}, 0
    local function visit(fn, depth)
        if seen[fn] or depth > 32 then return nil, false end
        seen[fn], visited = true, visited + 1
        assert(visited <= 256, "upvalue traversal budget exceeded")
        for i = 1, 100 do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            if name == wanted then return value, true end
        end
        for i = 1, 100 do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            if type(value) == "function" then
                local found, exists = visit(value, depth + 1)
                if exists then return found, true end
            end
        end
        return nil, false
    end
    local value, found = visit(callback, 0)
    assert(found, "missing observed upvalue " .. wanted)
    return value
end
