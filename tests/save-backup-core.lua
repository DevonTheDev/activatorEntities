-- Exercise actual addon hooks with detached sparse-Vector snapshots associated
-- with exact byte tokens. This models codec/file boundaries, not native JSON,
-- disk durability, case-sensitive DATA storage, or GMod engine lifetime.
return function(gmod, test, eq)
    local canonical = "devonsspawninfo.json"
    local backup = "devonsspawninfo.backup.json"
    local legacy = "DevonsSpawnInfo.json"
    local A, B = '{"fixture":"saved A"}', '{"fixture":"saved B"}'

    local function storage(env)
        local state = {files={}, snapshots={}, encodings={}, operations={}, prints={},
            writeFault={}, readFault={}, readbackFault={}, writeCounts={}, encodedCount=0}
        local function clone(value)
            if env.isvector(value) then return env.Vector(value.x, value.y, value.z) end
            if type(value) ~= "table" then return value end
            local copy = {}
            for key, child in pairs(value) do copy[key] = clone(child) end
            return copy
        end
        local function signature(value)
            if env.isvector(value) then
                return "Vector(" .. tostring(value.x) .. "," .. tostring(value.y) .. "," .. tostring(value.z) .. ")"
            end
            if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
            local keys, parts = {}, {}
            for key in pairs(value) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
            for _, key in ipairs(keys) do parts[#parts + 1] = signature(key) .. "=" .. signature(value[key]) end
            return "{" .. table.concat(parts, ";") .. "}"
        end
        function state.register(bytes, value, encodeAs)
            state.snapshots[bytes] = clone(value)
            if encodeAs ~= false then state.encodings[signature(value)] = bytes end
            return bytes
        end
        function state.seed(path, bytes, value, encodeAs)
            state.files[path] = state.register(bytes, value, encodeAs)
        end
        function state.writes(path)
            local count = 0
            for _, operation in ipairs(state.operations) do
                if operation.kind == "write" and (not path or operation.path == path) then count = count + 1 end
            end
            return count
        end
        function state.successes()
            local count = 0
            for _, message in ipairs(state.prints) do
                if message:find("successfully saved", 1, true) then count = count + 1 end
            end
            return count
        end
        function state.clear()
            state.operations, state.prints, env.errors = {}, {}, {}
        end
        env.print = function(message) state.prints[#state.prints + 1] = message end
        env.file.Exists = function(path, realm)
            eq(realm, "DATA"); return state.files[path] ~= nil
        end
        env.file.Read = function(path, realm)
            eq(realm, "DATA")
            state.operations[#state.operations + 1] = {kind="read", path=path}
            local fault = state.readFault[path]
            if state.writeCounts[path] and state.readbackFault[path] then fault = state.readbackFault[path] end
            if fault == "throw" then error("injected read failure") end
            if fault == "nil" then return nil end
            if fault == "wrong" then return "unrelated read bytes" end
            return state.files[path]
        end
        env.file.Write = function(path, bytes)
            eq(path, path:lower(), "all writes use lowercase DATA names")
            assert(type(bytes) == "string")
            state.operations[#state.operations + 1] = {kind="write", path=path, bytes=bytes}
            state.writeCounts[path] = (state.writeCounts[path] or 0) + 1
            local fault = state.writeFault[path]
            -- Even false/nil/throw faults damage the old file, like a write that
            -- opened/truncated before failing. This is not a failed-open double.
            state.files[path] = fault and "partial bytes" or bytes
            if fault == "wrong" then state.files[path] = "wrong complete bytes" end
            if fault and fault:sub(1, 5) == "full-" then state.files[path] = bytes end
            if fault == "throw" or fault == "full-throw" then error("injected destructive write failure") end
            if fault == "false" or fault == "full-false" then return false end
            if fault == "nil" or fault == "full-nil" then return nil end
            return true
        end
        env.util.TableToJSON = function(value)
            state.encodedCount = state.encodedCount + 1
            if state.encodeFault == "throw" then error("injected encode failure") end
            if state.encodeFault == "nil" then return nil end
            if state.encodeFault == "empty" then return "" end
            if state.encodeFault == "number" then return 4 end
            local key = signature(value)
            local bytes = state.encodings[key]
            if not bytes then
                bytes = '{"fixture":"candidate ' .. state.encodedCount .. '"}'
                state.register(bytes, value)
            end
            state.lastEncoded = bytes
            return bytes
        end
        env.util.JSONToTable = function(bytes, ignoreLimits, ignoreConversions)
            eq(ignoreLimits, nil, "retain default JSON limits")
            eq(ignoreConversions, nil, "retain default numeric-key conversion")
            if state.decodeFault == "throw" then error("injected decode failure") end
            if state.decodeFault == "nil" then return nil end
            if state.decodeFault == "schema" then return {{map="gm_construct", enemySpawnPositions={}}} end
            return clone(state.snapshots[bytes])
        end
        return state
    end
    local function valid(env, x)
        return {[4]={map="gm_construct", enemySpawnPositions={[10]=env.Vector(x or 1,2,3)},
            activatorSpawnPositions={[20]=env.Vector(4,5,6)}}}
    end
    local function loaded(path)
        local env = gmod.new(); local state = storage(env)
        state.seed(path or canonical, A, valid(env))
        env.fire("Initialize"); state.clear()
        return env, state
    end
    local function add(env, kind)
        local player = env.entity("player"); player.admin = true; player:SetPos(env.Vector(30,40,50))
        env.fire("PlayerSay", player, kind == "activator" and "!setActivatorSpawn" or "!setEnemySpawn")
        return player
    end
    local function warn(player)
        local message = player.chats[#player.chats]
        assert(message:find("remains in memory", 1, true), "accepted edit reports retained in-memory state privately")
        assert(message:find("could not be verified", 1, true), "warning allows an uncertain on-disk result")
        assert(not message:find("in memory only", 1, true), "uncertain disk contents must not be claimed absent")
        assert(#message <= 255, "private warning remains within ChatPrint's byte limit")
    end
    local function untouched(state, original)
        eq(state.writes(), 0, "failure must precede every file write")
        eq(state.files[canonical], original)
        eq(state.successes(), 0)
    end
    local function hasError(env, text)
        for _, message in ipairs(env.errors) do if message:find(text, 1, true) then return end end
        error("missing diagnostic: " .. text)
    end

    test("changed save verifies exact loaded predecessor before replacing canonical bytes", function()
        local env, state = loaded(); add(env)
        eq(state.files[backup], A, "backup is immutable pre-edit bytes")
        eq(state.files[canonical], state.lastEncoded)
        eq(state.writes(backup), 1); eq(state.writes(canonical), 1)
        local expected = {{"read",backup},{"write",backup},{"read",backup},{"write",canonical},{"read",canonical}}
        eq(#state.operations, #expected)
        for index, operation in ipairs(expected) do
            eq(state.operations[index].kind, operation[1]); eq(state.operations[index].path, operation[2])
        end
        eq(state.snapshots[A][4].enemySpawnPositions[11], nil, "codec snapshot cannot alias mutable memory")
        eq(env.SpawnPositions[4].enemySpawnPositions[11].x, 30)
        eq(env.isvector(env.SpawnPositions[4].enemySpawnPositions[10]), true)
        eq(state.successes(), 1)
    end)

    test("first verified save preserves an orphan backup and writes canonical only", function()
        local env = gmod.new(); local state = storage(env); state.files[backup] = "orphan recovery bytes"
        env.fire("Initialize"); state.clear(); eq(env.fire("ShutDown"), nil)
        eq(state.writes(canonical), 1); eq(state.writes(backup), 0)
        eq(state.files[canonical], state.lastEncoded); eq(state.files[backup], "orphan recovery bytes")
        eq(#state.operations, 2); eq(state.operations[2].kind, "read"); eq(state.operations[2].path, canonical)
        eq(state.successes(), 1)
    end)

    test("a byte-identical acknowledged save verifies canonical without rotating its predecessor", function()
        local env, state = loaded(); state.files[backup] = "older predecessor"; eq(env.fire("ShutDown"), nil)
        eq(state.writes(), 0); eq(state.files[backup], "older predecessor")
        eq(#state.operations, 1); eq(state.operations[1].kind, "read"); eq(state.operations[1].path, canonical)
        eq(#env.errors, 0)
    end)

    test("an already matching backup is reused and read before canonical write", function()
        local env, state = loaded(); state.files[backup] = A; add(env)
        eq(state.writes(backup), 0); eq(state.writes(canonical), 1)
        eq(state.operations[1].path, backup); eq(state.operations[1].kind, "read")
        eq(state.files[backup], A)
    end)

    test("legacy migration backs up exact legacy bytes and leaves legacy intact", function()
        local env, state = loaded(legacy); eq(env.fire("ShutDown"), nil)
        eq(state.files[backup], A); eq(state.files[canonical], A); eq(state.files[legacy], A)
        eq(state.writes(backup), 1); eq(state.writes(canonical), 1); eq(state.writes(legacy), 0)
    end)

    test("canonical precedence selects the acknowledged predecessor over legacy and backup", function()
        local env = gmod.new(); local state = storage(env)
        state.seed(canonical, A, valid(env)); state.seed(legacy, B, valid(env, 9))
        state.files[backup] = "unrelated older bytes"
        env.fire("Initialize"); state.clear(); add(env)
        eq(state.files[backup], A); eq(state.files[legacy], B)
    end)

    for _, fault in ipairs({"false", "nil", "throw", "truncated", "wrong", "full-false", "full-nil", "full-throw"}) do
        test("backup " .. fault .. " failure leaves canonical unchanged and edit in memory", function()
            local env, state = loaded(); state.writeFault[backup] = fault; local player = add(env)
            eq(state.writes(backup), 1); eq(state.writes(canonical), 0); eq(state.files[canonical], A)
            if fault:sub(1, 5) == "full-" then eq(state.files[backup], A, "full-byte backup fault actually writes the entire predecessor") end
            eq(env.SpawnPositions[4].enemySpawnPositions[11].x, 30); warn(player)
            eq(state.successes(), 0); hasError(env, backup)
        end)
    end
    for _, fault in ipairs({"nil", "throw", "wrong"}) do
        test("backup readback " .. fault .. " blocks canonical before it is touched", function()
            local env, state = loaded(); state.readbackFault[backup] = fault; local player = add(env)
            eq(state.writes(backup), 1); eq(state.writes(canonical), 0); eq(state.files[canonical], A)
            warn(player); eq(state.successes(), 0); hasError(env, backup)
        end)
    end

    for _, fault in ipairs({"false", "nil", "throw", "truncated", "wrong", "full-false", "full-nil", "full-throw"}) do
        test("canonical " .. fault .. " failure keeps predecessor and retries without rewriting backup", function()
            local env, state = loaded(); state.writeFault[canonical] = fault; local player = add(env)
            eq(state.files[backup], A); eq(state.writes(backup), 1); eq(state.writes(canonical), 1)
            if fault:sub(1, 5) == "full-" then eq(state.files[canonical], state.lastEncoded, "full-byte canonical fault actually writes the entire candidate") end
            warn(player); eq(state.successes(), 0); hasError(env, canonical)
            local uncertain = state.lastEncoded
            state.writeFault[canonical] = nil; state.clear(); eq(env.fire("ShutDown"), nil)
            eq(state.writes(backup), 0); eq(state.writes(canonical), 1, "uncertain candidate must not qualify as acknowledged no-op")
            eq(state.files[backup], A); eq(state.files[canonical], uncertain); eq(state.successes(), 1)
        end)
    end
    for _, fault in ipairs({"nil", "throw", "wrong"}) do
        test("canonical readback " .. fault .. " is not acknowledged even after true write", function()
            local env, state = loaded(); state.readbackFault[canonical] = fault; local player = add(env)
            eq(state.files[backup], A); eq(state.files[canonical], state.lastEncoded)
            warn(player); eq(state.successes(), 0); hasError(env, canonical)
            state.readbackFault[canonical] = nil; state.clear(); env.fire("ShutDown")
            eq(state.writes(backup), 0); eq(state.writes(canonical), 1); eq(state.successes(), 1)
        end)
    end

    for _, fault in ipairs({"tampered", "nil", "throw"}) do
        test("prepared backup " .. fault .. " stops retries until exact predecessor is readable again", function()
            local env, state = loaded(); state.writeFault[canonical] = "false"; add(env)
            eq(state.files[backup], A)
            state.writeFault[canonical] = nil
            if fault == "tampered" then state.files[backup] = "tampered backup" else state.readFault[backup] = fault end
            local oldCanonical, oldBackup = state.files[canonical], state.files[backup]
            state.clear(); local player = add(env, "activator"); warn(player)
            eq(env.SpawnPositions[4].activatorSpawnPositions[21].x, 30)
            eq(state.writes(), 0); eq(state.files[canonical], oldCanonical); eq(state.files[backup], oldBackup)
            eq(state.successes(), 0); hasError(env, backup)
            eq(env.fire("ShutDown"), nil); eq(state.writes(), 0, "shutdown cannot rewrite a prepared sole recovery copy")
            state.files[backup] = A; state.readFault[backup] = nil; state.clear(); env.fire("ShutDown")
            eq(state.writes(backup), 0); eq(state.writes(canonical), 1); eq(state.files[backup], A)
            local recovered = state.files[canonical]; state.clear(); add(env)
            eq(state.files[backup], recovered, "next changed save backs up newly acknowledged predecessor")
            eq(state.writes(backup), 1); eq(state.writes(canonical), 1)
            state.clear(); env.fire("ShutDown"); eq(state.writes(), 0, "identical shutdown leaves prior backup intact")
            eq(state.files[backup], recovered)
        end)
    end

    test("matching preexisting backup becomes protected after a destructive canonical failure", function()
        local env, state = loaded(); state.files[backup] = A; state.writeFault[canonical] = "false"; add(env)
        eq(state.writes(backup), 0); state.files[backup] = "external damage"; state.writeFault[canonical] = nil
        state.clear(); env.fire("ShutDown")
        eq(state.writes(), 0); eq(state.files[backup], "external damage"); hasError(env, backup)
    end)

    test("unacknowledged partial canonical bytes never become the next backup after another edit", function()
        local env, state = loaded(); state.writeFault[canonical] = "truncated"; add(env)
        state.clear(); add(env, "activator")
        eq(state.files[backup], A); eq(state.writes(backup), 0); eq(state.writes(canonical), 1)
        eq(state.successes(), 0)
        state.writeFault[canonical] = nil; state.clear(); env.fire("ShutDown")
        eq(state.files[backup], A); eq(state.writes(backup), 0); eq(state.writes(canonical), 1)
    end)

    for _, fault in ipairs({"throw", "nil", "empty", "number"}) do
        test("candidate encode " .. fault .. " fails before any backup or canonical write", function()
            local env, state = loaded(); state.encodeFault = fault; warn(add(env)); untouched(state, A)
        end)
    end
    for _, fault in ipairs({"throw", "nil", "schema"}) do
        test("candidate decode " .. fault .. " fails before any backup or canonical write", function()
            local env, state = loaded(); state.decodeFault = fault; warn(add(env)); untouched(state, A)
        end)
    end
    test("invalid current memory fails before encoding or writing a backup", function()
        local env, state = loaded(); env.SpawnPositions[4].enemySpawnPositions[10] = {x=1,y=2,z=3}
        env.fire("ShutDown"); eq(state.encodedCount, 0); untouched(state, A)
    end)

    for _, failure in ipairs({"corrupt", "nil", "throw"}) do
        test("canonical load " .. failure .. " locks out saves despite valid legacy and backup", function()
            local env = gmod.new(); local state = storage(env); local defaults = env.SpawnPositions
            state.files[canonical] = "corrupt canonical"
            state.seed(legacy, A, valid(env)); state.seed(backup, B, valid(env, 9))
            if failure ~= "corrupt" then state.readFault[canonical] = failure end
            env.fire("Initialize"); eq(env.SpawnPositions, defaults); state.clear(); warn(add(env)); env.fire("ShutDown")
            eq(state.encodedCount, 0); untouched(state, "corrupt canonical")
            eq(state.files[backup], B); eq(state.files[legacy], A); eq(#state.operations, 0)
        end)
    end

    for _, shape in ipairs({"empty table", "empty lists"}) do
        test(shape .. " is a valid acknowledged predecessor", function()
            local env = gmod.new(); local state = storage(env)
            local data = shape == "empty table" and {} or {[7]={map="gm_construct",enemySpawnPositions={},activatorSpawnPositions={}}}
            state.seed(canonical, A, data); env.fire("Initialize"); state.clear(); add(env)
            eq(state.files[backup], A); eq(state.writes(canonical), 1)
            if shape == "empty table" then eq(next(state.snapshots[A]), nil) else eq(next(state.snapshots[A]), 7) end
        end)
    end

    test("first-save destructive failure preserves orphan backup through retry", function()
        local env = gmod.new(); local state = storage(env); state.files[backup] = "orphan"
        env.fire("Initialize"); state.writeFault[canonical] = "false"; warn(add(env))
        eq(state.files[backup], "orphan"); eq(state.writes(backup), 0)
        state.writeFault[canonical] = nil; state.clear(); env.fire("ShutDown")
        eq(state.files[backup], "orphan"); eq(state.writes(backup), 0); eq(state.writes(canonical), 1)
    end)

    test("reinitialization discards an old prepared marker and acknowledges newly loaded bytes", function()
        local env, state = loaded(); state.writeFault[canonical] = "false"; add(env)
        state.seed(canonical, B, valid(env, 8)); state.files[backup] = "old damaged backup"
        state.writeFault[canonical] = nil; env.fire("Initialize"); state.clear(); add(env)
        eq(state.files[backup], B); eq(state.writes(backup), 1); eq(state.writes(canonical), 1)
    end)

    test("same-memory canonical mismatch is rewritten from acknowledged bytes without promoting external bytes", function()
        local env, state = loaded(); state.files[canonical] = "external change"; env.fire("ShutDown")
        eq(state.files[backup], A); eq(state.files[canonical], A)
        eq(state.writes(backup), 1); eq(state.writes(canonical), 1)
    end)

    test("different encoding of equal data is a changed save rather than a semantic no-op", function()
        local env, state = loaded(); state.register(B, env.SpawnPositions)
        env.fire("ShutDown")
        eq(state.files[backup], A); eq(state.files[canonical], B)
        eq(state.writes(backup), 1); eq(state.writes(canonical), 1)
    end)

    test("unverified failed backup preparation can be retried while canonical remains acknowledged", function()
        local env, state = loaded(); state.writeFault[backup] = "truncated"; warn(add(env))
        eq(state.files[canonical], A); eq(state.writes(canonical), 0)
        state.writeFault[backup] = nil; state.clear(); env.fire("ShutDown")
        eq(state.files[backup], A); eq(state.writes(backup), 1); eq(state.writes(canonical), 1)
        eq(state.files[canonical], state.lastEncoded); eq(state.successes(), 1)
    end)

    test("a same-byte no-op cannot bypass candidate decode validation", function()
        local env, state = loaded(); state.decodeFault = "nil"; env.fire("ShutDown")
        untouched(state, A); eq(#state.operations, 0); assert(#env.errors > 0)
    end)
end
