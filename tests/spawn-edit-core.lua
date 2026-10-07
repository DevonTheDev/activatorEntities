-- Exercise the real chat handler. File/codec doubles only count persistence;
-- native ChatPrint rendering and Vector JSON still need a GMod smoke test.
return function(gmod, test, eq)
    local kinds = {
        {name="enemy", field="enemySpawnPositions", remove="!removeEnemySpawn"},
        {name="activator", field="activatorSpawnPositions", remove="!removeActivatorSpawn"},
    }
    local function setup(kind, keys)
        local env=gmod.new()
        local saves={writes=0, serializations=0}
        env.print=function() end
        env.file.Exists=function() return false end
        env.file.Write=function() saves.writes=saves.writes+1; return true end
        env.util.TableToJSON=function() saves.serializations=saves.serializations+1; return "fixture" end
        env.fire("Initialize")
        local admin=env.entity("player"); admin.admin=true
        local positions={}
        for _, key in ipairs(keys or {2, 9, 31}) do positions[key]=env.Vector(key, -key, key/2) end
        env.SpawnPositions[1][kind.field]=positions
        return env, admin, positions, saves
    end
    local function inspect(env, admin, kind, page)
        admin.chats={}
        local result=env.fire("PlayerSay", admin, "!listSpawns " .. kind.name .. (page and " " .. page or ""))
        eq(result, "", "list command is private")
        return admin.chats
    end
    local function rowTokens(chats)
        local tokens={}
        for _, line in ipairs(chats) do
            local token=line:match("^Key ([^:]+):")
            if token then tokens[#tokens+1]=token end
        end
        return tokens
    end
    local function bounded(chats)
        assert(#chats <= 10, "at most eight points and two framing lines")
        for _, line in ipairs(chats) do assert(#line <= 255, "ChatPrint byte ceiling") end
    end
    local function unchanged(env, admin, kind, positions, saves, command)
        local expected={}; for key, value in pairs(positions) do expected[key]=value end
        local writes, serializations=saves.writes, saves.serializations
        eq(env.fire("PlayerSay", admin, command), "", "recognized indexed request is private")
        for key, value in pairs(expected) do eq(positions[key], value, "retain key " .. tostring(key)) end
        for key, value in pairs(positions) do eq(expected[key], value, "no invented key") end
        eq(saves.writes, writes); eq(saves.serializations, serializations)
        bounded(admin.chats)
    end

    for _, kind in ipairs(kinds) do
        for _, target in ipairs({2, 9, 31}) do
            test("indexed " .. kind.name .. " deletion removes only sparse key " .. target, function()
                local env, admin, positions, saves=setup(kind)
                local map=env.SpawnPositions[1]
                local otherField=kind.name == "enemy" and "activatorSpawnPositions" or "enemySpawnPositions"
                local other=map[otherField]
                local original={}; for key, value in pairs(positions) do original[key]=value end
                local chats=inspect(env, admin, kind)
                local tokens=rowTokens(chats); eq(#tokens, 3)
                for i, key in ipairs({2, 9, 31}) do eq(tonumber(tokens[i]), key) end
                assert(chats[#chats]:find(kind.remove .. " <key>", 1, true), "show exact-key command")
                bounded(chats); eq(saves.writes, 0); eq(saves.serializations, 0)
                eq(env.fire("PlayerSay", admin, kind.remove .. " " .. target), "")
                eq(env.SpawnPositions[1], map); eq(map[kind.field], positions); eq(map[otherField], other)
                for key, value in pairs(original) do eq(positions[key], key ~= target and value or nil) end
                eq(saves.writes, 1); eq(saves.serializations, 1)
                assert(admin.chats[#admin.chats]:find("removed", 1, true))
            end)
        end
        test("paged " .. kind.name .. " inspection shows eight sorted sparse keys", function()
            local keys={1, 3, 5, 8, 12, 18, 25, 40, 55, 100, 901}
            local env, admin, positions, saves=setup(kind, keys)
            local chats=inspect(env, admin, kind)
            local tokens=rowTokens(chats); eq(#tokens, 8); bounded(chats)
            assert(chats[1]:find("page 1/2", 1, true))
            for i=1,8 do eq(tonumber(tokens[i]), keys[i]) end
            chats=inspect(env, admin, kind, 2); tokens=rowTokens(chats); eq(#tokens, 3); bounded(chats)
            assert(chats[1]:find("page 2/2", 1, true))
            for i=1,3 do eq(tonumber(tokens[i]), keys[i+8]) end
            admin.chats={}
            unchanged(env, admin, kind, positions, saves, kind.remove .. " 1")
            eq(env.fire("PlayerSay", admin, kind.remove .. " 55"), ""); eq(positions[55], nil)
            eq(saves.writes, 1)
        end)
        test("empty " .. kind.name .. " inspection is explicit and cannot remove", function()
            local env, admin, positions, saves=setup(kind, {})
            local chats=inspect(env, admin, kind); eq(#rowTokens(chats), 0)
            assert(table.concat(chats, " "):lower():find("empty", 1, true))
            admin.chats={}; unchanged(env, admin, kind, positions, saves, kind.remove .. " 1")
        end)
        test("indexed " .. kind.name .. " deletion requires an inspection", function()
            local env, admin, positions, saves=setup(kind)
            unchanged(env, admin, kind, positions, saves, kind.remove .. " 9")
            assert(table.concat(admin.chats, " "):find("!listSpawns", 1, true))
        end)
        for _, suffix in ipairs({" ", " invalid", " 0", " -1", " 1.5", " inf", " nan", " 1e999", " 9 extra", " 09", " 9.0", " 0x9", " +9", " 1e1"}) do
            test("malformed indexed " .. kind.name .. " argument cannot fall through: " .. suffix, function()
                local env, admin, positions, saves=setup(kind)
                inspect(env, admin, kind); admin.chats={}
                unchanged(env, admin, kind, positions, saves, kind.remove .. suffix)
            end)
        end
        test("bare " .. kind.name .. " removal keeps last-key semantics and visibility", function()
            local env, admin, positions, saves=setup(kind)
            eq(env.fire("PlayerSay", admin, kind.remove), nil)
            eq(positions[31], nil); assert(positions[2]); assert(positions[9]); eq(saves.writes, 1)
        end)
        test("indexed " .. kind.name .. " deletion leaves max-key allocation intact", function()
            local env, admin, positions, saves=setup(kind)
            inspect(env, admin, kind); env.fire("PlayerSay", admin, kind.remove .. " 9")
            local add=kind.name == "enemy" and "!setEnemySpawn" or "!setActivatorSpawn"
            eq(env.fire("PlayerSay", admin, add), nil)
            eq(positions[32], admin:GetPos()); eq(positions[9], nil); eq(saves.writes, 2)
        end)
        for _, literal in ipairs({"9223372036854775807", "1e100", "1.7976931348623157e308"}) do
            test("append " .. kind.name .. " rejects an unrepresentable successor without losing inspection: " .. literal, function()
                local maximum=tonumber(literal)
                local env, admin, positions, saves=setup(kind, {2, maximum})
                local last=positions[maximum]
                inspect(env, admin, kind); admin.chats={}
                local add=kind.name == "enemy" and "!setEnemySpawn" or "!setActivatorSpawn"
                local result=env.fire("PlayerSay", admin, add)
                eq(positions[maximum], last, "never overwrite the previous maximum")
                local count=0; for _ in pairs(positions) do count=count+1 end
                eq(count, 2, "never create a wrapped or invalid successor")
                eq(saves.writes, 0); eq(saves.serializations, 0)
                eq(result, "", "the allocation failure is private"); bounded(admin.chats)
                assert(table.concat(admin.chats, " "):find("key", 1, true), "explain the allocation boundary")
                -- A rejected append is not an edit and must not revoke the page.
                eq(env.fire("PlayerSay", admin, kind.remove .. " 2"), "")
                eq(positions[2], nil); eq(positions[maximum], last); eq(saves.writes, 1)
            end)
        end
    end

    local enemy=kinds[1]
    for _, command in ipairs({"!listSpawns", "!listSpawns ", "!listSpawns wrong", "!listSpawns Enemy", "!listSpawns enemy 0", "!listSpawns enemy -1", "!listSpawns enemy 1.5", "!listSpawns enemy 2", "!listSpawns enemy 1 extra", "!listSpawns enemy nan", "!listSpawns enemy 1e999"}) do
        test("invalid list syntax is private and read-only: " .. command, function()
            local env, admin, positions, saves=setup(enemy)
            unchanged(env, admin, enemy, positions, saves, command)
            assert(#admin.chats > 0, "give private bounded guidance")
            eq(#rowTokens(admin.chats), 0)
        end)
    end
    for _, command in ipairs({"!listSpawnsExtra enemy", "!removeEnemySpawnExtra 9", "!removeActivatorSpawnExtra 9", "prefix !listSpawns enemy", "hello"}) do
        test("unrelated chat preserves hook behavior: " .. command, function()
            local env, admin, positions, saves=setup(enemy)
            eq(env.fire("PlayerSay", admin, command), nil)
            eq(#admin.chats, 0); eq(saves.writes, 0); assert(positions[31])
        end)
    end
    for _, actor in ipairs({"nil", "invalid", "nonplayer", "nonadmin", "demoted"}) do
        test("spawn inspection and targeted editing require a current player/admin: " .. actor, function()
            local env, admin, positions, saves=setup(enemy)
            inspect(env, admin, enemy)
            local sender=admin
            if actor == "nil" then sender=nil
            elseif actor == "invalid" then sender.valid=false
            elseif actor == "nonplayer" then sender=env.entity("worldspawn"); sender.admin=true
            elseif actor == "nonadmin" then sender=env.entity("player")
            else sender.admin=false end
            env.fire("PlayerSay", sender, "!listSpawns enemy")
            env.fire("PlayerSay", sender, "!removeEnemySpawn 9")
            assert(positions[9]); eq(saves.writes, 0); eq(saves.serializations, 0)
        end)
    end
    local malformed={
        {"missing map", function(env) env.SpawnPositions={} end, "missing"},
        {"non-table root", function(env) env.SpawnPositions=false end, "malformed"},
        {"non-table record", function(env) env.SpawnPositions[2]=false end, "malformed"},
        {"invalid map key", function(env) env.SpawnPositions.bad=env.SpawnPositions[1] end, "malformed"},
        {"invalid map name", function(env) env.SpawnPositions[2]={map=false} end, "malformed"},
        {"duplicate current map", function(env) env.SpawnPositions[2]=env.SpawnPositions[1] end, "ambiguous"},
        {"missing list", function(env) env.SpawnPositions[1].enemySpawnPositions=nil end, "missing"},
        {"non-table list", function(env) env.SpawnPositions[1].enemySpawnPositions=false end, "malformed"},
        {"string key", function(env) env.SpawnPositions[1].enemySpawnPositions.bad=env.Vector(0,0,0) end, "malformed"},
        {"zero key", function(env) env.SpawnPositions[1].enemySpawnPositions[0]=env.Vector(0,0,0) end, "malformed"},
        {"fractional key", function(env) env.SpawnPositions[1].enemySpawnPositions[2.5]=env.Vector(0,0,0) end, "malformed"},
        {"plain coordinate table", function(env) env.SpawnPositions[1].enemySpawnPositions[9]={x=1,y=2,z=3} end, "malformed"},
        {"non-finite coordinate", function(env) env.SpawnPositions[1].enemySpawnPositions[9].x=math.huge end, "malformed"},
        {"NaN coordinate", function(env) env.SpawnPositions[1].enemySpawnPositions[9].y=0/0 end, "malformed"},
    }
    for _, case in ipairs(malformed) do
        test("inspection and indexed edit fail closed for " .. case[1], function()
            local env, admin, positions, saves=setup(enemy)
            inspect(env, admin, enemy); case[2](env)
            admin.chats={}; unchanged(env, admin, enemy, positions, saves, "!removeEnemySpawn 31")
            local chats=inspect(env, admin, enemy)
            eq(#rowTokens(chats), 0); assert(table.concat(chats, " "):lower():find(case[3], 1, true))
            eq(saves.writes, 0); eq(saves.serializations, 0); bounded(chats)
        end)
    end
    test("other admins cannot reuse a shown page", function()
        local env, admin, positions, saves=setup(enemy)
        inspect(env, admin, enemy)
        local other=env.entity("player"); other.admin=true
        unchanged(env, other, enemy, positions, saves, "!removeEnemySpawn 9")
        eq(#admin.chats, 5, "only the requesting player received the inspection")
    end)
    for _, target in ipairs({"map record", "position list"}) do
        test("inspection requires raw " .. target .. " identity even with custom table equality", function()
            local env, admin, positions, saves=setup(enemy)
            local original=target == "map record" and env.SpawnPositions[1] or positions
            local equality={__eq=function() return true end}
            setmetatable(original, equality)
            inspect(env, admin, enemy)
            local replacement={}; for key, value in pairs(original) do replacement[key]=value end
            setmetatable(replacement, equality)
            if target == "map record" then env.SpawnPositions[1]=replacement
            else env.SpawnPositions[1].enemySpawnPositions=replacement end
            local current=env.SpawnPositions[1].enemySpawnPositions
            local before=current[9]
            env.fire("PlayerSay", admin, "!removeEnemySpawn 9")
            eq(current[9], before, "an equal but replaced table is stale")
            eq(saves.writes, 0); eq(saves.serializations, 0)
        end)
    end
    test("coordinates and large keys remain exact and bounded", function()
        local keys={tonumber("9007199254740992"), tonumber("9007199254740993"), tonumber("9223372036854775807"), tonumber("1e100"), tonumber("1.7976931348623157e308")}
        local env, admin, positions, saves=setup(enemy, keys)
        for _, value in pairs(positions) do value.x=1.2345678901234567; value.y=-1.7976931348623157e308; value.z=2.2250738585072014e-308 end
        local chats=inspect(env, admin, enemy); bounded(chats)
        local tokens=rowTokens(chats)
        local count=0; for _ in pairs(positions) do count=count+1 end
        eq(#tokens, count)
        local previous=0
        for _, token in ipairs(tokens) do
            local key=tonumber(token); assert(positions[key], "listed token round trips to the actual key")
            assert(key > previous); previous=key
        end
        for _, line in ipairs(chats) do
            if line:match("^Key ") then
                local x,y,z=line:match(": x=([^,]+), y=([^,]+), z=(.+)$")
                assert(x and y and z, "all coordinates are shown without truncation")
                eq(tonumber(x), 1.2345678901234567); eq(tonumber(y), -1.7976931348623157e308); eq(tonumber(z), 2.2250738585072014e-308)
            end
        end
        local selected=tokens[#tokens]
        eq(env.fire("PlayerSay", admin, "!removeEnemySpawn " .. selected), "")
        eq(positions[tonumber(selected)], nil); eq(saves.writes, 1)
    end)
    test("rounded decimal input cannot retarget a large adjacent key", function()
        local env, admin, positions, saves=setup(enemy, {tonumber("9007199254740992")})
        inspect(env, admin, enemy); admin.chats={}
        unchanged(env, admin, enemy, positions, saves, "!removeEnemySpawn 9007199254740993")
    end)
    test("Lua 5.3 integer keys use exact decimal tokens rather than rounded floating formatting", function()
        local key=tonumber("9223372036854775807")
        local env, admin, positions, saves=setup(enemy, {key})
        local token=rowTokens(inspect(env, admin, enemy))[1]
        eq(tonumber(token), key)
        if math.type and math.type(key) == "integer" then eq(token, "9223372036854775807") end
        env.fire("PlayerSay", admin, "!removeEnemySpawn " .. token)
        eq(positions[key], nil); eq(saves.writes, 1)
    end)
end
