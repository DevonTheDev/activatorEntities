-- These doubles exercise the addon at the file/codec boundary, not GMod's JSON
-- parser. Real Vector JSON round-trips still require an in-engine smoke test.
return function(gmod, test, eq)
    local canonical, legacy = "devonsspawninfo.json", "DevonsSpawnInfo.json"
    local function storage(env, files, decoded)
        local state = {files=files or {}, reads={}, writes={}, decoded=decoded, prints={}}
        env.print = function(text) state.prints[#state.prints + 1] = text end
        env.file.Exists = function(path, realm)
            eq(realm, "DATA"); return state.files[path] ~= nil
        end
        env.file.Read = function(path, realm)
            eq(realm, "DATA"); state.reads[#state.reads + 1] = path
            if state.readError then error("read failed") end
            if state.unreadable then return nil end
            return state.files[path]
        end
        env.file.Write = function(path, content)
            assert(type(content) == "string", "file.Write requires a string")
            state.writes[#state.writes + 1] = {path=path, content=content}
            if state.writeError then error("write failed") end
            if state.writeFails then return false end
            state.files[path:lower()] = content
            return true
        end
        env.util.JSONToTable = function(json, ignoreLimits, ignoreConversions)
            state.decodeInput = json
            eq(ignoreLimits == true, false, "keep GMod JSON limits enabled")
            eq(ignoreConversions == true, false, "preserve numeric-key conversion")
            if state.decodeError then error("decode failed") end
            return state.decoded
        end
        env.util.TableToJSON = function(value)
            state.encoded = value
            if state.encodeError then error("encode failed") end
            if state.encodeFails then return nil end
            if state.encodeEmpty then return "" end
            return '{"fixture":"serialized spawn positions"}'
        end
        return state
    end
    local function valid(env)
        return {[4]={map="gm_construct", enemySpawnPositions={[10]=env.Vector(1,2,3)},
            activatorSpawnPositions={[20]=env.Vector(4,5,6)}}}
    end
    local function rejected(env, state, defaults)
        env.fire("Initialize")
        eq(env.SpawnPositions, defaults, "retain the complete default table")
        assert(#env.errors > 0, "report why saved data was rejected")
        -- Both lookup/spawning and admin edits must remain safe after rejection.
        local ply, enemies = env.start(); eq(#enemies, 5)
        ply.admin=true; env.fire("PlayerSay", ply, "!setEnemySpawn")
        env.fire("ShutDown")
        eq(#state.writes, 0, "do not replace recoverable data even after session edits")
        eq(state.encoded, nil, "skip serialization after rejected load")
    end

    test("missing saved file retains defaults and permits a lowercase shutdown save", function()
        local env=gmod.new(); local defaults=env.SpawnPositions; local state=storage(env)
        env.fire("Initialize"); eq(env.SpawnPositions, defaults)
        env.fire("ShutDown")
        eq(#state.writes, 1); eq(state.writes[1].path, canonical)
        eq(state.encoded, defaults); eq(#env.errors, 0)
        eq(env.converted, nil, "serialized state must not leak into a global")
    end)
    test("shutdown before initialization leaves saved data untouched", function()
        local env=gmod.new(); local state=storage(env, {[canonical]="recoverable"})
        env.fire("ShutDown"); eq(#state.writes, 0); eq(state.files[canonical], "recoverable")
    end)
    test("canonical saved sparse maps and Vector positions load unchanged", function()
        local env=gmod.new(); local data=valid(env)
        local state=storage(env, {[canonical]='{"4":{"map":"gm_construct","enemySpawnPositions":{"10":"[1 2 3]"},"activatorSpawnPositions":{"20":"[4 5 6]"}}}'}, data)
        env.fire("Initialize"); eq(env.SpawnPositions, data)
        eq(state.reads[1], canonical); eq(#state.reads, 1)
        eq(env.returnSpawnPositions("gm_construct"), data[4].enemySpawnPositions[10])
        eq(env.returnActivatorSpawns("gm_construct"), data[4].activatorSpawnPositions[20])
        local ply, enemies=env.start(); eq(#enemies, 5)
        ply.admin=true; env.fire("PlayerSay", ply, "!setEnemySpawn")
        eq(data[4].enemySpawnPositions[11], ply:GetPos())
        env.fire("PlayerSay", ply, "!removeEnemySpawn")
        eq(data[4].enemySpawnPositions[11], nil)
        eq(data[4].enemySpawnPositions[10].x, 1)
        env.fire("ShutDown"); eq(state.encoded, data); eq(#state.writes, 1)
    end)
    test("historical mixed-case file loads only when canonical file is absent", function()
        local env=gmod.new(); local data=valid(env); local state=storage(env, {[legacy]="legacy bytes"}, data)
        env.fire("Initialize"); eq(env.SpawnPositions, data); eq(state.reads[1], legacy)
        env.fire("ShutDown"); eq(state.writes[1].path, canonical)
        eq(state.files[legacy], "legacy bytes", "legacy source is not modified or removed")
    end)
    test("canonical file takes precedence when both filenames exist", function()
        local env=gmod.new(); local data=valid(env)
        local state=storage(env, {[canonical]="current bytes", [legacy]="old bytes"}, data)
        env.fire("Initialize"); eq(env.SpawnPositions, data)
        eq(state.decodeInput, "current bytes"); eq(#state.reads, 1)
    end)
    test("invalid canonical file cannot fall back to a stale mixed-case copy", function()
        local env=gmod.new(); local defaults=env.SpawnPositions
        local state=storage(env, {[canonical]="corrupt", [legacy]="old bytes"})
        rejected(env, state, defaults); eq(state.decodeInput, "corrupt")
        eq(#state.reads, 1); eq(state.files[canonical], "corrupt")
    end)
    test("invalid legacy file is preserved without creating a canonical replacement", function()
        local env=gmod.new(); local defaults=env.SpawnPositions
        local state=storage(env, {[legacy]="corrupt"})
        rejected(env, state, defaults); eq(state.files[legacy], "corrupt")
        eq(state.files[canonical], nil)
    end)
    for _, failure in ipairs({"unreadable", "readError", "decodeError"}) do
        test("saved data survives " .. failure .. " without crashing initialization", function()
            local env=gmod.new(); local defaults=env.SpawnPositions
            local state=storage(env, {[canonical]="recoverable", [legacy]="stale"})
            state[failure]=true; rejected(env, state, defaults)
            eq(state.files[canonical], "recoverable"); eq(#state.reads, 1)
        end)
    end
    local malformed = {
        {"invalid JSON", function() return nil end},
        {"boolean root", function() return false end},
        {"string root", function() return "wrong" end},
        {"number root", function() return 123 end},
        {"non-table map entry", function() return {false} end},
        {"missing map name", function() return {{enemySpawnPositions={}, activatorSpawnPositions={}}} end},
        {"blank map name", function() return {{map="", enemySpawnPositions={}, activatorSpawnPositions={}}} end},
        {"non-string map name", function() return {{map=123, enemySpawnPositions={}, activatorSpawnPositions={}}} end},
        {"missing enemy list", function() return {{map="gm_construct", activatorSpawnPositions={}}} end},
        {"missing activator list", function() return {{map="gm_construct", enemySpawnPositions={}}} end},
        {"non-table enemy list", function() return {{map="gm_construct", enemySpawnPositions="wrong", activatorSpawnPositions={}}} end},
        {"non-table activator list", function() return {{map="gm_construct", enemySpawnPositions={}, activatorSpawnPositions=false}} end},
        {"plain coordinate table", function(env) local data=valid(env); data[4].enemySpawnPositions[10]={x=1,y=2,z=3}; return data end},
        {"unconverted vector string", function(env) local data=valid(env); data[4].enemySpawnPositions[10]="[1 2 3]"; return data end},
        {"invalid activator position", function(env) local data=valid(env); data[4].activatorSpawnPositions[20]=false; return data end},
        {"non-finite vector", function(env) local data=valid(env); data[4].enemySpawnPositions[10]=env.Vector(math.huge,0,0); return data end},
        {"NaN vector", function(env) local data=valid(env); data[4].enemySpawnPositions[10]=env.Vector(0,0/0,0); return data end},
        {"string map index", function(env) local data=valid(env); return {first=data[4]} end},
        {"fractional map index", function(env) local data=valid(env); return {[1.5]=data[4]} end},
        {"nonpositive position index", function(env) local data=valid(env); data[4].enemySpawnPositions[0]=env.Vector(0,0,0); return data end},
        {"string position index", function(env) local data=valid(env); data[4].enemySpawnPositions.bad=env.Vector(0,0,0); return data end},
        {"valid map followed by invalid map", function(env) local data=valid(env); data[8]={map="broken"}; return data end},
    }
    for _, case in ipairs(malformed) do
        test("reject " .. case[1] .. " while preserving defaults and saved bytes", function()
            local env=gmod.new(); local defaults=env.SpawnPositions
            local state=storage(env, {[canonical]="invalid saved bytes", [legacy]="invalid saved bytes"}, case[2](env))
            rejected(env, state, defaults)
            eq(state.files[canonical], "invalid saved bytes")
            eq(state.files[legacy], "invalid saved bytes")
        end)
    end
    for _, emptyRoot in ipairs({true, false}) do
        test("accept deliberately empty " .. (emptyRoot and "map configuration" or "spawn lists"), function()
            local env=gmod.new(); local data=emptyRoot and {} or {{map="gm_construct", enemySpawnPositions={}, activatorSpawnPositions={}}}
            local state=storage(env, {[canonical]="empty configuration"}, data)
            env.fire("Initialize"); eq(env.SpawnPositions, data)
            eq(env.returnSpawnPositions("gm_construct"), nil); eq(env.returnActivatorSpawns("gm_construct"), nil)
            env.fireTimer("activatorSpawner"); eq(#env.ents.FindByClass("activatorent"), 0)
            env.fire("ShutDown"); eq(state.encoded, data); eq(#state.writes, 1)
        end)
    end
    test("invalid runtime spawn edits never replace a previously valid save", function()
        local env=gmod.new(); local state=storage(env, {[canonical]="original"}, valid(env))
        env.fire("Initialize"); env.SpawnPositions[4].enemySpawnPositions[10]="broken"
        env.fire("ShutDown"); eq(#state.writes, 0); eq(state.files[canonical], "original")
        assert(#env.errors > 0)
    end)
    for _, failure in ipairs({"encodeError", "encodeFails", "encodeEmpty"}) do
        test("serialization " .. failure .. " leaves the saved file untouched", function()
            local env=gmod.new(); local state=storage(env, {[canonical]="original"}, valid(env))
            env.fire("Initialize"); state[failure]=true
            env.fire("ShutDown"); eq(#state.writes, 0); eq(state.files[canonical], "original")
            assert(#env.errors > 0)
        end)
    end
    for _, failure in ipairs({"writeFails", "writeError"}) do
        test("report " .. failure .. " instead of claiming a successful save", function()
            local env=gmod.new(); local state=storage(env); env.fire("Initialize"); state[failure]=true
            env.fire("ShutDown"); eq(#state.writes, 1); eq(#state.prints, 0)
            assert(#env.errors > 0)
        end)
    end
end
