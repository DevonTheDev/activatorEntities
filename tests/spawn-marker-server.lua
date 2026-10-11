-- Actual PlayerSay admission and packet fields. Engine methods remain doubles.
return function(gmod, test, eq)
    local channel="ActivatorSpawnMarker"
    local function setup(kind)
        local env=gmod.new()
        local admin=env.entity("player"); admin.admin=true
        env.SpawnPositions={{map=env.map, enemySpawnPositions={
            [2]=env.Vector(20000.125,-30000.5,0.03125),[9]=env.Vector(9,8,7)},
            activatorSpawnPositions={[2]=env.Vector(-24000.25,45000.5,2.125),[9]=env.Vector(5,6,7)}}}
        env.randomCalls=0
        env.math=setmetatable({random=function() env.randomCalls=env.randomCalls+1; error("marker sampled RNG") end},{__index=math})
        env.file.Write=function() error("marker saved data") end
        if kind then eq(env.fire("PlayerSay",admin,"!listSpawns "..kind),"") end
        return env,admin
    end
    local function say(env,admin,text) return env.fire("PlayerSay",admin,text) end
    local function mark(env,admin,kind,token)
        eq(say(env,admin,"!markSpawn "..kind.." "..(token or "2")),"","marker command is private")
    end
    local function packet(env,admin,kind,token)
        eq(#env.messages,1); local out=env.messages[1]
        eq(out.name,channel); eq(out.player,admin); eq(out.broadcast,nil); eq(out.unreliable,false)
        eq(out.values[1],true); eq(out.values[2],env.map); eq(out.values[3],kind); eq(out.values[4],token or "2")
        local expected={"bool","string","string","string","double","double","double","double"}
        for i,field in ipairs(expected) do eq(out.fields[i].kind,field) end
        eq(#out.fields,8); eq(out.values[8],env.now+15)
        eq(env.receivers[channel],nil,"no client request receiver")
        eq(env.networkStrings[channel],true)
        eq(env.randomCalls,0)
        return out
    end
    for _,kind in ipairs({"enemy","activator"}) do
        test("spawn marker sends private exact "..kind.." base",function()
            local env,admin=setup(kind); local field=kind.."SpawnPositions"
            local positions=env.SpawnPositions[1][field]; local point=positions[2]
            local entities=#env.entities; local timer=env.timers.activatorSpawner
            mark(env,admin,kind); local out=packet(env,admin,kind)
            eq(out.values[5],point.x); eq(out.values[6],point.y); eq(out.values[7],point.z)
            eq(env.SpawnPositions[1][field],positions); eq(positions[2],point)
            eq(#env.entities,entities); eq(env.timers.activatorSpawner,timer); eq(timer.stopped,false)
            assert(admin.chats[#admin.chats]:find("sent",1,true)); assert(admin.chats[#admin.chats]:find("snapshot",1,true))
            local remove=kind == "enemy" and "!removeEnemySpawn 2" or "!removeActivatorSpawn 2"
            eq(say(env,admin,remove),""); eq(positions[2],nil,"marker retains edit inspection")
        end)
        for _,literal in ipairs({"9223372036854775807","1e100","1.7976931348623157e308"}) do
            test("spawn marker preserves "..kind.." large exact key "..literal,function()
                local env,admin=setup(); local key=tonumber(literal)
                env.SpawnPositions[1][kind.."SpawnPositions"]={[key]=env.Vector(1.25,2.5,3.75)}
                say(env,admin,"!listSpawns "..kind)
                local token
                for _,line in ipairs(admin.chats) do token=token or line:match("^Key ([^:]+):") end
                assert(token); mark(env,admin,kind,token); packet(env,admin,kind,token)
            end)
        end
        local cases={"absent page","wrong kind","unknown token","off page","rounded alias","relist","bad relist",
            "map changed","list replaced","record replaced","changed target","changed other row","malformed list",
            "missing key","other admin page","disconnect","initialize","same-coordinate edit","failed-save edit","reused key"}
        for _,case in ipairs(cases) do
            test("spawn marker rejects "..kind.." "..case,function()
                local env,admin=setup(case ~= "absent page" and kind or nil)
                local info=env.SpawnPositions[1]; local field=kind.."SpawnPositions"; local positions=info[field]
                local token="2"; local remove=kind == "enemy" and "!removeEnemySpawn" or "!removeActivatorSpawn"
                if case == "wrong kind" then say(env,admin,"!listSpawns "..(kind == "enemy" and "activator" or "enemy"))
                elseif case == "unknown token" then token="99"
                elseif case == "off page" then
                    for i=10,20 do positions[i]=env.Vector(i,i,i) end
                    say(env,admin,"!listSpawns "..kind.." 2")
                elseif case == "rounded alias" then token="02"
                elseif case == "relist" then say(env,admin,"!listSpawns "..kind); positions[9].z=0
                elseif case == "bad relist" then say(env,admin,"!listSpawns bad")
                elseif case == "map changed" then env.map="gm_flatgrass"
                elseif case == "list replaced" then
                    local equal={__eq=function() return true end}; setmetatable(positions,equal)
                    info[field]=setmetatable({[2]=positions[2],[9]=positions[9]},equal)
                elseif case == "record replaced" then
                    local equal={__eq=function() return true end}; setmetatable(info,equal)
                    env.SpawnPositions[1]=setmetatable({map=env.map,enemySpawnPositions=info.enemySpawnPositions,
                        activatorSpawnPositions=info.activatorSpawnPositions},equal)
                elseif case == "changed target" then positions[2].x=0
                elseif case == "changed other row" then positions[9].x=0
                elseif case == "malformed list" then positions.bad=env.Vector(1,2,3)
                elseif case == "missing key" then positions[2]=nil
                elseif case == "other admin page" then local second=env.entity("player"); second.admin=true; admin=second
                elseif case == "disconnect" then env.fire("PlayerDisconnected",admin)
                elseif case == "initialize" then env.file.Exists=function() return false end; env.fire("Initialize")
                elseif case == "same-coordinate edit" then
                    local other=env.entity("player"); other.admin=true; other.pos=positions[2]
                    say(env,other,"!listSpawns "..kind)
                    say(env,other,(kind == "enemy" and "!moveEnemySpawn 2" or "!moveActivatorSpawn 2"))
                elseif case == "failed-save edit" then
                    local other=env.entity("player"); other.admin=true
                    say(env,other,"!listSpawns "..kind); say(env,other,remove.." 9")
                elseif case == "reused key" then
                    say(env,admin,remove.." 2"); positions[2]=env.Vector(20000.125,-30000.5,0.03125)
                end
                mark(env,admin,kind,token); eq(#env.messages,0)
            end)
        end
    end
    for _,text in ipairs({"!markSpawn","!markSpawn bad 2","!markSpawn enemy","!markSpawn enemy 2 extra",
        "!markSpawn enemy 02","!markSpawn enemy 2.0","!markSpawn enemy +2","!markSpawn enemy 0x2",
        "!markSpawn enemy 1e999","!clearSpawnMarker extra"}) do
        test("spawn marker keeps malformed command private: "..text,function()
            local env,admin=setup("enemy"); eq(say(env,admin,text),""); eq(#env.messages,0)
            assert(#admin.chats[#admin.chats] <= 255)
        end)
    end
    for _,case in ipairs({"invalid","not player","not admin","dead"}) do
        test("spawn marker requires current living admin: "..case,function()
            local env,admin=setup("enemy")
            if case == "invalid" then admin.valid=false elseif case == "not player" then admin.class="worldspawn"
            elseif case == "not admin" then admin.admin=false else admin.alive=false end
            mark(env,admin,"enemy"); eq(#env.messages,0)
        end)
    end
    for _,now in ipairs({0/0,math.huge,-math.huge,1e308}) do
        test("spawn marker rejects unusable server deadline "..tostring(now),function()
            local env,admin=setup("enemy"); env.now=now; mark(env,admin,"enemy"); eq(#env.messages,0)
        end)
    end
    for _,map in ipairs({string.rep("a",129),"bad\nmap","bad\0map"}) do
        test("spawn marker rejects unsafe map label "..#map,function()
            local env,admin=setup(); env.map=map; env.SpawnPositions[1].map=map
            say(env,admin,"!listSpawns enemy"); mark(env,admin,"enemy"); eq(#env.messages,0)
        end)
    end
    test("spawn marker exact command recognition leaves unrelated chat alone",function()
        local env,admin=setup("enemy")
        for _,text in ipairs({"!markSpawnSuffix enemy 2","!clearSpawnMarkers","hello !markSpawn enemy 2"}) do eq(say(env,admin,text),nil) end
        eq(#env.messages,0)
    end)
    test("spawn marker explicit clear is private and idempotent",function()
        local env,admin=setup("enemy")
        for i=1,2 do
            eq(say(env,admin,"!clearSpawnMarker"),"")
            local out=env.messages[i]; assert(out); eq(out.name,channel); eq(out.player,admin)
            eq(#out.fields,1); eq(out.fields[1].kind,"bool"); eq(out.values[1],false)
        end
        eq(#env.messages,2)
    end)
    for _,read in ipairs({"IsPlayer","IsAdmin","Alive","GetMap","CurTime"}) do
        for _,inner in ipairs({"relist","clear","mark","disconnect","initialize"}) do
            test("spawn marker nested "..inner.." during "..read.." supersedes outer",function()
                local env,admin=setup("enemy")
                local object=read == "GetMap" and env.game or read == "CurTime" and env or admin
                local original=object[read]
                object[read]=function(...)
                    object[read]=original
                    if inner == "relist" then say(env,admin,"!listSpawns enemy")
                    elseif inner == "clear" then say(env,admin,"!clearSpawnMarker")
                    elseif inner == "mark" then mark(env,admin,"enemy","9")
                    elseif inner == "disconnect" then env.fire("PlayerDisconnected",admin)
                    else env.file.Exists=function() return false end; env.fire("Initialize") end
                    return original(...)
                end
                mark(env,admin,"enemy")
                eq(#env.messages,(inner == "clear" or inner == "mark") and 1 or 0)
                if inner == "mark" then eq(env.messages[1].values[4],"9") end
                if inner == "clear" then eq(env.messages[1].values[1],false) end
                say(env,admin,"!listSpawns enemy"); mark(env,admin,"enemy")
                eq(env.messages[#env.messages].values[4],"2","request ownership released")
            end)
        end
    end
    test("spawn marker sends before success ChatPrint callback",function()
        local env,admin=setup("enemy"); local original=admin.ChatPrint
        admin.ChatPrint=function(self,text)
            original(self,text)
            if text:find("sent",1,true) then admin.ChatPrint=original; say(env,admin,"!clearSpawnMarker") end
        end
        mark(env,admin,"enemy"); eq(#env.messages,2)
        eq(env.messages[1].values[1],true); eq(env.messages[2].values[1],false)
    end)
    test("spawn marker admin operations are isolated",function()
        local env,admin=setup("enemy"); local second=env.entity("player"); second.admin=true
        say(env,second,"!listSpawns activator"); mark(env,admin,"enemy"); mark(env,second,"activator")
        eq(#env.messages,2); eq(env.messages[1].player,admin); eq(env.messages[2].player,second)
    end)
    test("spawn marker missing inspection gives bounded relist guidance",function()
        local env,admin=setup(); mark(env,admin,"enemy")
        eq(#env.messages,0); eq(#admin.chats,1)
        assert(admin.chats[1]:find("!listSpawns",1,true)); assert(#admin.chats[1] <= 255)
    end)
    for _,change in ipairs({"demotion","death","invalidation","map change"}) do
        test("spawn marker rechecks current state after time read: "..change,function()
            local env,admin=setup("enemy")
            env.CurTime=function()
                if change == "demotion" then admin.admin=false elseif change == "death" then admin.alive=false
                elseif change == "invalidation" then admin.valid=false else env.map="gm_flatgrass" end
                return env.now
            end
            mark(env,admin,"enemy"); eq(#env.messages,0)
        end)
    end

end
