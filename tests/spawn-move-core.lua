-- Run the actual server chat handler with the existing GMod API doubles.
-- Identity checks deliberately do not use Vector's coordinate equality.
return function(gmod, test, eq)
    local newCodec=dofile("tests/spawn-storage-codec.lua")
    local canonical,backup="devonsspawninfo.json","devonsspawninfo.backup.json"
    local kinds={
        {name="enemy", field="enemySpawnPositions", move="!moveEnemySpawn", remove="!removeEnemySpawn"},
        {name="activator", field="activatorSpawnPositions", move="!moveActivatorSpawn", remove="!removeActivatorSpawn"},
    }
    local function setup(kind, keys)
        local env=gmod.new()
        local saves={writes=0, canonicalWrites=0, backupWrites=0, reads=0, decodes=0, encodes=0, files={}}
        local codec=newCodec(env,eq); saves.codec=codec
        env.print=function() end
        env.file.Exists=function(path,realm) eq(realm,"DATA"); return saves.files[path] ~= nil end
        env.file.Read=function(path,realm)
            eq(realm,"DATA"); saves.reads=saves.reads+1; return saves.files[path]
        end
        env.file.Write=function(path,bytes)
            saves.writes=saves.writes+1
            if path == canonical then saves.canonicalWrites=saves.canonicalWrites+1
            else eq(path,backup); saves.backupWrites=saves.backupWrites+1 end
            saves.files[path]=bytes; return true
        end
        env.util.JSONToTable=function(...)
            saves.decodes=saves.decodes+1; return codec.decode(...)
        end
        env.util.TableToJSON=function(value)
            saves.encodes=saves.encodes+1; return codec.encode(value)
        end
        env.fire("Initialize")
        local admin=env.entity("player"); admin.admin=true
        local positions={}
        for _,key in ipairs(keys or {2,9,31}) do positions[key]=env.Vector(key,-key,key/2) end
        env.SpawnPositions[1][kind.field]=positions
        return env,admin,positions,saves
    end
    local function inspect(env,admin,kind,page)
        admin.chats={}
        eq(env.fire("PlayerSay",admin,"!listSpawns " .. kind.name .. (page and " " .. page or "")),"")
        local tokens={}
        for _,line in ipairs(admin.chats) do
            local token=line:match("^Key ([^:]+):")
            if token then tokens[#tokens+1]=token end
            assert(#line <= 255,"private chat lines fit the engine limit")
        end
        assert(#admin.chats <= 10,"eight rows plus header and footer")
        return tokens
    end
    local function snapshot(positions)
        local result={}
        for key,point in pairs(positions) do result[key]={point=point,x=point.x,y=point.y,z=point.z} end
        return result
    end
    local function retained(positions,before)
        for key,saved in pairs(before) do
            assert(rawequal(positions[key],saved.point),"retain point identity at key " .. tostring(key))
            eq(saved.point.x,saved.x); eq(saved.point.y,saved.y); eq(saved.point.z,saved.z)
        end
        for key in pairs(positions) do assert(before[key],"do not invent keys") end
    end
    local function moved(point,destination,old)
        assert(point,"keep the existing key")
        assert(not rawequal(point,old),"replace the original point with a fresh Vector")
        assert(not rawequal(point,destination),"do not retain the player's Vector")
        eq(point.x,destination.x); eq(point.y,destination.y); eq(point.z,destination.z)
    end
    local function rejected(env,admin,positions,saves,command)
        local before=snapshot(positions)
        local writes,encodes,reads,decodes=saves.writes,saves.encodes,saves.reads,saves.decodes
        local ok,result=pcall(env.fire,"PlayerSay",admin,command)
        assert(ok,"rejected move must not throw: " .. tostring(result))
        retained(positions,before)
        eq(saves.writes,writes); eq(saves.encodes,encodes)
        eq(saves.reads,reads); eq(saves.decodes,decodes)
        eq(result,"","recognized move requests are private")
        for _,line in ipairs(admin and admin.chats or {}) do assert(#line <= 255,"bounded response") end
    end

    for _,kind in ipairs(kinds) do
        for _,key in ipairs({2,9,31}) do
            test("move " .. kind.name .. " replaces only sparse key " .. key .. " with a detached Vector",function()
                local env,admin,positions,saves=setup(kind)
                local root,map=env.SpawnPositions,env.SpawnPositions[1]
                local other=kind.name == "enemy" and "activatorSpawnPositions" or "enemySpawnPositions"
                local otherList=map[other]
                local otherMap={map="another_map",enemySpawnPositions={},activatorSpawnPositions={}}
                root[17]=otherMap
                local before=snapshot(positions)
                local destination=env.Vector(100,-200,300.25)
                local reads,copies=0,0
                local constructor=env.Vector
                admin.GetPos=function() reads=reads+1; return destination end
                env.Vector=function(x,y,z) copies=copies+1; return constructor(x,y,z) end
                inspect(env,admin,kind)
                local result=env.fire("PlayerSay",admin,kind.move .. " " .. key)
                moved(positions[key],destination,before[key].point)
                eq(result,"")
                eq(reads,1,"capture the destination exactly once"); eq(copies,1,"construct one copy")
                assert(env.isvector(positions[key])); assert(rawequal(env.SpawnPositions,root))
                assert(rawequal(root[1],map)); assert(rawequal(map[kind.field],positions))
                assert(rawequal(map[other],otherList)); assert(rawequal(root[17],otherMap))
                local count=0
                for existing,point in pairs(positions) do
                    count=count+1
                    if existing ~= key then assert(rawequal(point,before[existing].point)) end
                end
                eq(count,3,"retain sparse cardinality")
                for _,saved in pairs(before) do
                    eq(saved.point.x,saved.x); eq(saved.point.y,saved.y); eq(saved.point.z,saved.z)
                end
                destination.x=999; eq(positions[key].x,100,"later player changes cannot alter the saved point")
                positions[key].y=888; eq(destination.y,-200,"the saved point cannot alter the player")
                local saved=saves.codec.decode(saves.files[canonical])[1][kind.field][key]
                eq(saved.x,100); eq(saved.y,-200); eq(saved.z,300.25)
                assert(env.isvector(saved)); assert(not rawequal(saved,positions[key]),"persisted Vector is detached")
                eq(saves.writes,1); eq(saves.canonicalWrites,1); eq(saves.backupWrites,0); eq(saves.encodes,1)
                assert(admin.chats[#admin.chats]:find("moved",1,true),"confirm the move")
            end)
        end
        test("same-coordinate " .. kind.name .. " move accepts a distinct Vector despite coordinate equality",function()
            local env,admin,positions,saves=setup(kind)
            local old=positions[9]
            local destination=env.Vector(old.x,old.y,old.z)
            local vectorMeta=getmetatable(old)
            vectorMeta.__eq=function(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
            eq(old,destination,"the fixture exercises overloaded Vector equality")
            admin:SetPos(destination)
            local second=env.entity("player"); second.admin=true
            inspect(env,admin,kind); inspect(env,second,kind)
            eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
            moved(positions[9],destination,old); eq(saves.writes,1); eq(saves.encodes,1)
            rejected(env,admin,positions,saves,kind.move .. " 2")
            rejected(env,second,positions,saves,kind.move .. " 2")
        end)
        test("move " .. kind.name .. " can copy the destination when it is already the target object",function()
            local env,admin,positions,saves=setup(kind)
            local old=positions[9]; admin:SetPos(old); inspect(env,admin,kind)
            eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
            moved(positions[9],old,old); eq(saves.writes,1)
        end)
        test("move " .. kind.name .. " footer names both exact-key commands within one bounded line",function()
            local env,admin=setup(kind,{1,2,3,4,5,6,7,8})
            inspect(env,admin,kind)
            eq(#admin.chats,10)
            local footer=admin.chats[#admin.chats]
            assert(footer:find(kind.move .. " <key>",1,true),"show move usage")
            assert(footer:find(kind.remove .. " <key>",1,true),"retain removal usage")
            assert(footer:find("list again",1,true),"explain inspection expiry")
        end)
        for _,suffix in ipairs({""," ","\t"," 9 extra"," 9 31"," \n"}) do
            test("malformed " .. kind.name .. " move gives private usage without legacy fallback: " .. string.format("%q",suffix),function()
                local env,admin,positions,saves=setup(kind); inspect(env,admin,kind); admin.chats={}
                rejected(env,admin,positions,saves,kind.move .. suffix)
                assert(table.concat(admin.chats," "):find("Usage:",1,true),"give usage")
                local old=positions[9]
                eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
                moved(positions[9],admin:GetPos(),old); eq(saves.writes,1,"a malformed request keeps inspection")
            end)
        end
        for _,token in ipairs({"09","9.0","+9","0x9","9e0","900","0","-1","1.5","nan","inf","invalid"}) do
            test("move " .. kind.name .. " requires the literal displayed key: " .. token,function()
                local env,admin,positions,saves=setup(kind); inspect(env,admin,kind)
                rejected(env,admin,positions,saves,kind.move .. " " .. token)
                local old=positions[9]
                eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
                moved(positions[9],admin:GetPos(),old); eq(saves.writes,1)
            end)
        end
        test("move " .. kind.name .. " accepts surrounding argument whitespace",function()
            local env,admin,positions,saves=setup(kind); inspect(env,admin,kind)
            local old=positions[9]
            eq(env.fire("PlayerSay",admin,kind.move .. "\t 9 \t"),"")
            moved(positions[9],admin:GetPos(),old); eq(saves.writes,1)
        end)
        test("move " .. kind.name .. " requires the latest inspected page",function()
            local env,admin,positions,saves=setup(kind,{1,2,3,4,5,6,7,8,9,31})
            inspect(env,admin,kind); inspect(env,admin,kind,2)
            rejected(env,admin,positions,saves,kind.move .. " 2")
            local old=positions[9]
            eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
            moved(positions[9],admin:GetPos(),old); eq(saves.writes,1)
        end)
        test("move " .. kind.name .. " requires this admin's current inspection",function()
            local env,admin,positions,saves=setup(kind)
            rejected(env,admin,positions,saves,kind.move .. " 9")
            local second=env.entity("player"); second.admin=true; inspect(env,second,kind)
            rejected(env,admin,positions,saves,kind.move .. " 9")
            local old=positions[9]
            eq(env.fire("PlayerSay",second,kind.move .. " 9"),"")
            moved(positions[9],second:GetPos(),old); eq(saves.writes,1)
        end)
        for _,reason in ipairs({"other kind","other map","changed shown point","replaced list","replaced map","failed list","disconnect","initialize"}) do
            test("move " .. kind.name .. " rejects stale inspection after " .. reason,function()
                local env,admin,positions,saves=setup(kind); inspect(env,admin,kind)
                if reason == "other kind" then inspect(env,admin,kinds[kind.name == "enemy" and 2 or 1])
                elseif reason == "other map" then env.map="another_map"
                elseif reason == "changed shown point" then positions[2].x=999
                elseif reason == "replaced list" then
                    local replacement={}; for key,point in pairs(positions) do replacement[key]=point end
                    env.SpawnPositions[1][kind.field]=replacement
                elseif reason == "replaced map" then
                    local replacement={}; for key,value in pairs(env.SpawnPositions[1]) do replacement[key]=value end
                    env.SpawnPositions[1]=replacement
                elseif reason == "failed list" then env.fire("PlayerSay",admin,"!listSpawns " .. kind.name .. " 0")
                elseif reason == "disconnect" then env.fire("PlayerDisconnected",admin)
                else env.fire("Initialize") end
                local reads=0; admin.GetPos=function() reads=reads+1; error("must not read stale destination") end
                rejected(env,admin,positions,saves,kind.move .. " 9"); eq(reads,0)
                if reason == "replaced list" then retained(env.SpawnPositions[1][kind.field],snapshot(positions)) end
            end)
        end
        for _,literal in ipairs({"9007199254740992","9223372036854775807","1e100","1.7976931348623157e308"}) do
            test("move " .. kind.name .. " preserves the exact large key " .. literal,function()
                local key=tonumber(literal)
                local env,admin,positions,saves=setup(kind,{key})
                local old=positions[key]
                local token=inspect(env,admin,kind)[1]
                eq(tonumber(token),key)
                eq(env.fire("PlayerSay",admin,kind.move .. " " .. token),"")
                moved(positions[key],admin:GetPos(),old); eq(saves.writes,1)
                local count=0; for current in pairs(positions) do eq(current,key); count=count+1 end
                eq(count,1)
            end)
        end
        test("move " .. kind.name .. " does not round an unlisted adjacent decimal onto a shown key",function()
            local env,admin,positions,saves=setup(kind,{tonumber("9007199254740992")})
            inspect(env,admin,kind)
            rejected(env,admin,positions,saves,kind.move .. " 9007199254740993")
        end)
    end

    local kind=kinds[1]
    local invalidDestinations={
        {"missing GetPos",function(_,admin) admin.GetPos=false end},
        {"throwing GetPos",function(_,admin) admin.GetPos=function() error("fixture GetPos failure") end end},
        {"nil",function(_,admin) admin.GetPos=function() return nil end end},
        {"false",function(_,admin) admin.GetPos=function() return false end end},
        {"string",function(_,admin) admin.GetPos=function() return "1 2 3" end end},
        {"plain coordinates",function(_,admin) admin.GetPos=function() return {x=1,y=2,z=3} end end},
    }
    for _,axis in ipairs({"x","y","z"}) do
        for _,value in ipairs({{name="positive infinity",value=math.huge},{name="negative infinity",value=-math.huge},
            {name="NaN",value=0/0},{name="nonnumeric",value="invalid"}}) do
            invalidDestinations[#invalidDestinations+1]={axis .. " " .. value.name,function(env,admin)
                local destination=env.Vector(1,2,3); destination[axis]=value.value
                admin.GetPos=function() return destination end
            end}
        end
    end
    for _,case in ipairs(invalidDestinations) do
        test("move rejects " .. case[1] .. " destination and preserves inspection",function()
            local env,admin,positions,saves=setup(kind); inspect(env,admin,kind)
            local getPos,constructor=admin.GetPos,env.Vector
            case[2](env,admin)
            local reads,copies=0,0
            if type(admin.GetPos) == "function" then
                local badGetPos=admin.GetPos
                admin.GetPos=function(...) reads=reads+1; return badGetPos(...) end
            end
            env.Vector=function(...) copies=copies+1; return constructor(...) end
            rejected(env,admin,positions,saves,kind.move .. " 9")
            eq(reads,case[1] == "missing GetPos" and 0 or 1); eq(copies,0,"reject before construction")
            admin.GetPos=getPos; env.Vector=constructor
            local old=positions[9]
            eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
            moved(positions[9],admin:GetPos(),old); eq(saves.writes,1)
        end)
    end
    local invalidCopies={
        {"throwing constructor",function() error("fixture Vector failure") end},
        {"nil",function() return nil end},
        {"false",function() return false end},
        {"plain coordinates",function(_,x,y,z) return {x=x,y=y,z=z} end},
    }
    for _,axis in ipairs({"x","y","z"}) do
        for _,value in ipairs({{name="positive infinity",value=math.huge},{name="negative infinity",value=-math.huge},
            {name="NaN",value=0/0},{name="nonnumeric",value="invalid"},{name="mismatch",value=999}}) do
            invalidCopies[#invalidCopies+1]={axis .. " " .. value.name,function(constructor,x,y,z)
                local copy=constructor(x,y,z); copy[axis]=value.value; return copy
            end}
        end
    end
    for _,case in ipairs(invalidCopies) do
        test("move rejects " .. case[1] .. " Vector copy and preserves inspection",function()
            local env,admin,positions,saves=setup(kind); inspect(env,admin,kind)
            local destination=env.Vector(10,20,30); admin:SetPos(destination)
            local constructor=env.Vector; local reads,copies=0,0
            admin.GetPos=function() reads=reads+1; return destination end
            env.Vector=function(x,y,z) copies=copies+1; return case[2](constructor,x,y,z) end
            rejected(env,admin,positions,saves,kind.move .. " 9")
            eq(reads,1); eq(copies,1); eq(destination.x,10); eq(destination.y,20); eq(destination.z,30)
            env.Vector=constructor
            local old=positions[9]
            eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
            moved(positions[9],destination,old); eq(saves.writes,1)
        end)
    end
    for _,alias in ipairs({"destination","existing point"}) do
        test("move rejects an aliased " .. alias .. " Vector copy even with matching coordinates",function()
            local env,admin,positions,saves=setup(kind)
            local old=positions[9]
            local destination=env.Vector(old.x,old.y,old.z); admin:SetPos(destination)
            inspect(env,admin,kind)
            local constructor=env.Vector
            env.Vector=function() return alias == "destination" and destination or old end
            rejected(env,admin,positions,saves,kind.move .. " 9")
            env.Vector=constructor
            eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
            moved(positions[9],destination,old); eq(saves.writes,1)
        end)
    end
    test("move retains finite extreme destination components without truncation",function()
        local env,admin,positions,saves=setup(kind)
        local destination=env.Vector(1.7976931348623157e308,-1.7976931348623157e308,2.2250738585072014e-308)
        admin:SetPos(destination); inspect(env,admin,kind)
        local old=positions[9]
        eq(env.fire("PlayerSay",admin,kind.move .. " 9"),"")
        moved(positions[9],destination,old); eq(saves.writes,1)
    end)
    for _,role in ipairs({"nil sender","invalid player","non-player","non-admin","demoted admin"}) do
        for _,kind in ipairs(kinds) do
            test("move " .. kind.name .. " rejects " .. role .. " before reading the destination",function()
                local env,admin,positions,saves=setup(kind); inspect(env,admin,kind)
                local sender=admin; local reads=0
                admin.GetPos=function() reads=reads+1; error("not allowed") end
                if role == "nil sender" then sender=nil
                elseif role == "invalid player" then admin.valid=false
                elseif role == "non-player" then admin.class="prop_physics"
                elseif role == "non-admin" then sender=env.entity("player"); sender.GetPos=admin.GetPos
                else admin.admin=false end
                rejected(env,sender,positions,saves,kind.move .. " 9")
                eq(reads,0)
            end)
        end
    end
    for _,text in ipairs({"hello","!moveEnemySpawnExtra 9","!moveActivatorSpawnExtra 9","!moveenemyspawn 9","prefix !moveEnemySpawn 9"," !moveEnemySpawn 9"}) do
        test("move routing preserves unrelated chat: " .. text,function()
            local env,admin,positions,saves=setup(kind)
            local before=snapshot(positions)
            eq(env.fire("PlayerSay",admin,text),nil)
            eq(#admin.chats,0); eq(saves.writes,0); eq(saves.encodes,0); retained(positions,before)
        end)
    end
end
