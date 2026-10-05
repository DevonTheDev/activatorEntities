-- Exercise the real admin chat handler and subsequent spawn/start callbacks.
-- These diagnostics describe inputs, not native engine validity or timer state.
return function(gmod, test, eq)
    local function setup()
        local env=gmod.new()
        env.SpawnPositions={{map=env.map, activatorSpawnPositions={[8]=env.Vector(1,2,3)},
            enemySpawnPositions={[12]=env.Vector(4,5,6)}}}
        env.NPCEdits[7]={name="Ambush", information={activatorModel="models/alyx.mdl",
            npcPath="npc_combine_s", maxNPCs=2, dialogue="An ambush awaits."}}
        local admin=env.entity("player"); admin.admin=true
        return env, admin
    end
    local function contains(text, expected)
        assert(text:find(expected,1,true), "expected '" .. expected .. "' in '" .. text .. "'")
    end
    local function excludes(text, unexpected)
        assert(not text:find(unexpected,1,true), "unexpected '" .. unexpected .. "' in '" .. text .. "'")
    end
    local function status(env, admin)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,"!eventStatus"), "")
        local lines={}
        for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        assert(#lines <= 16, "bounded complete status")
        local diagnostics={}
        for _, line in ipairs(lines) do
            assert(#line <= 255, "ChatPrint byte limit")
            assert(not line:find("[%c]"), "no control characters in status")
            if line:match("^Automatic spawn") or line:match("^Spawn inputs:")
                or line:match("^Encounter start enemy positions:") then
                diagnostics[#diagnostics+1]=line
            end
        end
        eq(#diagnostics,3,"three fixed diagnostic lines")
        local detail=table.concat(diagnostics,"\n")
        contains(detail,"next normal attempt")
        excludes(detail,"ready"); excludes(detail,"countdown"); excludes(detail,"timer")
        return detail, table.concat(lines,"\n"), lines
    end
    local function queue(env, admin, name)
        eq(env.fire("PlayerSay",admin,"!nextEvent " .. name), "")
    end
    local function actor(env, name)
        local ent=env.entity("activatorent"); ent.EventIdentifier=name or "Raid"; ent:Spawn()
        return ent
    end
    local function begin(env, admin, ent)
        admin:SetPos(ent:GetPos()); ent:AcceptInput("Use",admin,admin)
        env.receive("SendNPCInformation",admin,ent.EventIdentifier)
    end

    test("spawn status distinguishes idle inputs and sparse positions without promising creation",function()
        local env,admin=setup(); local detail=status(env,admin)
        contains(detail,"no active encounter")
        contains(detail,"players 1/min 0 (met)")
        contains(detail,"activators 0/cap 3 (space)")
        contains(detail,"random: pool present; event unchosen; engine unchecked")
        contains(detail,"activator positions: 1 available")
        contains(detail,"Encounter start enemy positions: 1 available (required on use)")
        env.fireTimer("activatorSpawner"); eq(#env.ents.FindByClass("activatorent"),3)
    end)
    test("spawn status reports active encounter independently of future selection",function()
        local env,admin=setup(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        begin(env,admin,env.ents.FindByClass("activatorent")[1]); queue(env,admin,"Raid")
        contains(status(env,admin),"active encounter (blocked)")
        eq(env.totalEnemies,2)
    end)
    for _, case in ipairs({{0,"met"},{1,"met"},{2,"below minimum"},{1.5,"below minimum"},{-1,"met"}}) do
        test("spawn player threshold snapshot at minimum " .. case[1],function()
            local env,admin=setup(); env.minNumberOfPlayers=case[1]
            contains(status(env,admin),"players 1/min " .. case[1] .. " (" .. case[2] .. ")")
            env.fireTimer("activatorSpawner")
            eq(#env.ents.FindByClass("activatorent"),case[2] == "met" and 3 or 0)
        end)
    end
    for _, case in ipairs({{"nil",nil},{"false",false},{"string","2"},{"table",{}},
        {"infinity",math.huge},{"negative infinity",-math.huge},{"NaN",0/0}}) do
        test("spawn status diagnoses malformed player minimum " .. case[1],function()
            local env,admin=setup(); env.minNumberOfPlayers=case[2]
            contains(status(env,admin),"players 1/min unavailable (invalid minimum)")
        end)
    end
    for _, case in ipairs({{0,"no capacity",0},{-2,"negative; no capacity",0},
        {1.5,"fractional; unassessed",1},{3,"space",3}}) do
        test("spawn status preserves configured capacity semantics " .. case[1],function()
            local env,admin=setup(); env.maxActivators=case[1]
            contains(status(env,admin),"activators 0/cap " .. case[1] .. " (" .. case[2] .. ")")
            env.fireTimer("activatorSpawner"); eq(#env.ents.FindByClass("activatorent"),case[3])
            if case[1] == 1.5 then eq(env.timers.activatorSpawner.stopped,false) end
        end)
    end
    for _, case in ipairs({{"multiple disabled",false,99},{"nil maximum",true,nil},{"false maximum",true,false}}) do
        test("spawn status uses runtime one-actor fallback for " .. case[1],function()
            local env,admin=setup(); env.multipleEntities=case[2]; env.maxActivators=case[3]
            contains(status(env,admin),"activators 0/cap 1 (space)")
            env.fireTimer("activatorSpawner"); eq(#env.ents.FindByClass("activatorent"),1)
            contains(status(env,admin),"activators 1/cap 1 (capacity reached)")
        end)
    end
    for _, case in ipairs({{"string","3"},{"table",{}},{"true",true},
        {"infinity",math.huge},{"negative infinity",-math.huge},{"NaN",0/0}}) do
        test("spawn status diagnoses malformed capacity " .. case[1],function()
            local env,admin=setup(); env.maxActivators=case[2]
            contains(status(env,admin),"activators 0/cap unavailable (invalid capacity)")
        end)
    end
    test("spawn status counts usable manual and mixed actors instead of stale global count",function()
        local env,admin=setup(); local first=actor(env,"Raid"); actor(env,"Ambush")
        local third=actor(env,"Raid"); actor(env,"Ambush").valid=false
        env.deferRemoval=true; third:Remove(); env.activatorCount=987
        contains(status(env,admin),"activators 2/cap 3 (space)")
        env.maxActivators=2; contains(status(env,admin),"activators 2/cap 2 (capacity reached)")
        env.maxActivators=1; contains(status(env,admin),"activators 2/cap 1 (capacity reached)")
        eq(first.valid,true); eq(env.activatorCount,987)
    end)
    test("player minimum does not prevent starting an existing actor",function()
        local env,admin=setup(); local ent=actor(env,"Ambush"); env.minNumberOfPlayers=10
        contains(status(env,admin),"players 1/min 10 (below minimum)")
        begin(env,admin,ent); eq(env.totalEnemies,2)
    end)
    test("empty enemy positions are an encounter-start requirement only",function()
        local env,admin=setup(); env.SpawnPositions[1].enemySpawnPositions={}
        local detail=status(env,admin)
        contains(detail,"activator positions: 1 available")
        contains(detail,"Encounter start enemy positions: empty list (required on use)")
        env.fireTimer("activatorSpawner"); local ent=env.ents.FindByClass("activatorent")[1]
        eq(#env.ents.FindByClass("activatorent"),3); begin(env,admin,ent); eq(env.totalEnemies,0)
        env.SpawnPositions[1].enemySpawnPositions={[99]=env.Vector(4,5,6)}
        status(env,admin); begin(env,admin,ent); assert(env.totalEnemies > 0)
    end)
    for _, case in ipairs({"absent map","empty maps","nil maps","false maps","string maps",
        "bad record","bad map name","bad map index","duplicate map"}) do
        test("spawn status distinguishes current map data: " .. case,function()
            local env,admin=setup(); local expected
            if case == "absent map" then env.SpawnPositions[1].map="elsewhere"; expected="missing map record"
            elseif case == "empty maps" then env.SpawnPositions={}; expected="missing map record"
            elseif case == "nil maps" then env.SpawnPositions=nil; expected="malformed map data"
            elseif case == "false maps" then env.SpawnPositions=false; expected="malformed map data"
            elseif case == "string maps" then env.SpawnPositions="bad"; expected="malformed map data"
            elseif case == "bad record" then env.SpawnPositions[2]=false; expected="malformed map data"
            elseif case == "bad map name" then env.SpawnPositions[1].map={}; expected="malformed map data"
            elseif case == "bad map index" then env.SpawnPositions.extra=env.SpawnPositions[1]; env.SpawnPositions[1]=nil; expected="malformed map data"
            else
                env.SpawnPositions[9]={map=env.map, activatorSpawnPositions={},enemySpawnPositions={}}
                expected="ambiguous map records (2)"
            end
            local detail=status(env,admin)
            contains(detail,"activator positions: " .. expected)
            contains(detail,"Encounter start enemy positions: " .. expected)
        end)
    end
    for _, field in ipairs({"activatorSpawnPositions","enemySpawnPositions"}) do
        for _, case in ipairs({"missing","empty","false","string","plain coordinates","nonfinite vector",
            "NaN vector","string index","zero index","fractional index","mixed values","sparse"}) do
            test("spawn status validates " .. field .. ": " .. case,function()
                local env,admin=setup(); local point=env.Vector(1,2,3); local positions,expected
                if case == "missing" then expected="missing list"
                elseif case == "empty" then positions={}; expected="empty list"
                elseif case == "false" then positions=false
                elseif case == "string" then positions="bad"
                elseif case == "plain coordinates" then positions={{x=1,y=2,z=3}}
                elseif case == "nonfinite vector" then positions={env.Vector(1,math.huge,3)}
                elseif case == "NaN vector" then positions={env.Vector(0/0,2,3)}
                elseif case == "string index" then positions={point=point}
                elseif case == "zero index" then positions={[0]=point}
                elseif case == "fractional index" then positions={[1.5]=point}
                elseif case == "mixed values" then positions={[2]=point,[50]=false}
                else positions={[8]=point,[90]=env.Vector(-2,0,3)}; expected="2 available" end
                env.SpawnPositions[1][field]=positions
                local prefix=field == "activatorSpawnPositions" and "activator positions: " or "Encounter start enemy positions: "
                contains(status(env,admin),prefix .. (expected or "malformed list"))
            end)
        end
    end
    test("spawn status locates sparse map records without pooling other maps",function()
        local env,admin=setup(); local current=env.SpawnPositions[1]
        env.SpawnPositions={[20]=current,[7]={map="other_map",activatorSpawnPositions=false,enemySpawnPositions=false}}
        local detail=status(env,admin)
        contains(detail,"activator positions: 1 available")
        contains(detail,"Encounter start enemy positions: 1 available")
    end)

    for _, mode in ipairs({"pending selection","selected batch"}) do
        for _, missing in ipairs({"removed","duplicate","missing information","malformed information","missing definitions"}) do
            test("spawn status explains applicable " .. mode .. ": " .. missing,function()
                local env,admin=setup(); queue(env,admin,"Ambush")
                if mode == "selected batch" then env.fireTimer("activatorSpawner"); queue(env,admin,"Raid") end
                local reason
                if missing == "removed" then env.NPCEdits[7]=nil; reason="unknown configured name"
                elseif missing == "duplicate" then env.NPCEdits[18]=env.NPCEdits[7]; reason="duplicate configured name"
                elseif missing == "missing information" then env.NPCEdits[7].information=nil; reason="missing event information"
                elseif missing == "malformed information" then env.NPCEdits[7].information=false; reason="missing event information"
                else env.NPCEdits=false; reason="unknown configured name" end
                contains(status(env,admin),mode .. ": " .. reason)
            end)
        end
    end
    test("surviving selected batch takes precedence over an unavailable pending selection",function()
        local env,admin=setup(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        queue(env,admin,"Raid"); env.NPCEdits[1]=nil
        contains(status(env,admin),"selected batch: information present; engine unchecked")
    end)
    test("pending applies only after the last usable actor including manual actors is gone",function()
        local env,admin=setup(); queue(env,admin,"Ambush"); local ent=actor(env,"Raid"); env.NPCEdits[7]=nil
        contains(status(env,admin),"random: pool present; event unchosen; engine unchecked")
        env.deferRemoval=true; ent:Remove()
        contains(status(env,admin),"pending selection: unknown configured name")
    end)
    test("status ignores a departing selected batch without refreshing its ownership",function()
        local env,admin=setup(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner"); queue(env,admin,"Raid")
        env.deferRemoval=true
        for _, ent in ipairs(env.ents.FindByClass("activatorent")) do ent:Remove() end
        contains(status(env,admin),"pending selection: information present; engine unchecked")
        local manual=actor(env,"Raid")
        contains(status(env,admin),"random: pool present; event unchosen; engine unchecked")
        manual:Remove(); env.timers.activatorSpawner.callback()
        for _, ent in ipairs(env.ents.FindByClass("activatorent")) do
            if not ent:IsMarkedForDeletion() then eq(ent.EventIdentifier,"Raid") end
        end
    end)
    for _, case in ipairs({"empty","absent","false","string","bad entry","missing name","duplicate name","missing information","empty information"}) do
        test("spawn status assesses random pool without choosing: " .. case,function()
            local env,admin=setup(); local expected="random: unassessable pool"
            if case == "empty" then env.NPCEdits={}; expected="random: no configured pool"
            elseif case == "absent" then env.NPCEdits=nil; expected="random: no configured pool"
            elseif case == "false" then env.NPCEdits=false
            elseif case == "string" then env.NPCEdits="bad"
            elseif case == "bad entry" then env.NPCEdits[12]=false
            elseif case == "missing name" then env.NPCEdits[7].name=nil
            elseif case == "duplicate name" then env.NPCEdits[12]=env.NPCEdits[7]
            elseif case == "missing information" then env.NPCEdits[7].information=nil
            else env.NPCEdits[7].information={}; expected="random: pool present; event unchosen; engine unchecked" end
            contains(status(env,admin),expected)
        end)
    end

    -- Read-only is checked against actual private closure state as well as host
    -- calls. This catches pruning an apparently stale selected batch on reads.
    local function privateState(env)
        local values, visited={},{}
        local names={interactions=true,pendingSelection=true,selectedBatchName=true,
            selectedBatchEntities=true,activeEnemies=true,eventActive=true,eventInterrupted=true,
            activeEventName=true,initialEnemies=true,statusRequestAfter=true}
        local function inspect(callback)
            if visited[callback] then return end
            visited[callback]=true
            for i=1,100 do
                local name,value=debug.getupvalue(callback,i)
                if not name then break end
                if names[name] then values[name]=value end
                if type(value) == "function" then inspect(value) end
            end
        end
        for _, hooks in pairs(env.hooks) do for _, callback in pairs(hooks) do inspect(callback) end end
        for _, timer in pairs(env.timers) do inspect(timer.callback) end
        for _, callback in pairs(env.receivers) do inspect(callback) end
        return values
    end
    local function snapshot(value, seen)
        if type(value) ~= "table" then return value end
        seen=seen or {}
        if seen[value] then return seen[value] end
        local copy={original=value,entries={}}; seen[value]=copy
        for key,child in pairs(value) do
            if key ~= "chats" then copy.entries[key]=snapshot(child,seen) end
        end
        return copy
    end
    local function unchanged(before, value, checked)
        if type(before) ~= "table" then eq(value,before,"unchanged scalar/reference"); return end
        eq(value,before.original,"unchanged table identity")
        checked=checked or {}; if checked[before] then return end; checked[before]=true
        local oldCount,newCount=0,0
        for key,child in pairs(before.entries) do oldCount=oldCount+1; unchanged(child,value[key],checked) end
        for key in pairs(value) do if key ~= "chats" then newCount=newCount+1 end end
        eq(newCount,oldCount,"unchanged table entries")
    end
    local function readOnly(env,admin)
        local restored={}
        local function forbid(owner,key)
            restored[#restored+1]={owner,key,owner[key]}
            owner[key]=function() error("status called forbidden " .. key) end
        end
        env.math=setmetatable({},{__index=math})
        forbid(env.math,"random"); forbid(env.math,"randomseed")
        for _, key in ipairs({"determineRandomEvent","returnNPCInformation","returnActivatorSpawns","returnSpawnPositions","destroyActivators","saveSpawnPositions"}) do forbid(env,key) end
        for _, owner in ipairs({env.timer,env.file,env.net}) do
            local keys={}; for key,value in pairs(owner) do if type(value) == "function" then keys[#keys+1]=key end end
            for _, key in ipairs(keys) do forbid(owner,key) end
        end
        forbid(env.ents,"Create")
        for _, ent in ipairs(env.entities) do
            for _, key in ipairs({"Remove","FinishRemoval","Spawn","SetPos","SetModel","SetMoveType","StopMoving"}) do forbid(ent,key) end
        end
        local private=privateState(env)
        assert(type(private.interactions) == "table" and type(private.selectedBatchEntities) == "table",
            "inspect the actual interaction and batch state")
        local states={env.NPCEdits,env.SpawnPositions,env.entities,env.timers,env.messages,private}
        local snapshots={}; for i,value in ipairs(states) do snapshots[i]=snapshot(value) end
        local globalCount,total=env.activatorCount,env.totalEnemies
        local ok,err=pcall(function()
            local first=status(env,admin)
            for i=1,3 do eq(status(env,admin),first,"repeatable snapshot") end
            local current={env.NPCEdits,env.SpawnPositions,env.entities,env.timers,env.messages}
            for i=1,5 do unchanged(snapshots[i],current[i]) end
            local after=privateState(env)
            -- The temporary holder is new; all actual private values must retain identity.
            for key,child in pairs(snapshots[6].entries) do unchanged(child,after[key]) end
            local beforeCount,afterCount=0,0
            for _ in pairs(private) do beforeCount=beforeCount+1 end
            for _ in pairs(after) do afterCount=afterCount+1 end
            eq(beforeCount,afterCount); eq(env.activatorCount,globalCount); eq(env.totalEnemies,total)
        end)
        for _, entry in ipairs(restored) do entry[1][entry[2]]=entry[3] end
        assert(ok,err)
    end
    test("repeated status preserves pending, selected refills, open interaction and active encounter",function()
        local env,admin=setup(); queue(env,admin,"Ambush"); readOnly(env,admin)
        env.fireTimer("activatorSpawner"); local actors=env.ents.FindByClass("activatorent")
        eq(#actors,3); for _, ent in ipairs(actors) do eq(ent.EventIdentifier,"Ambush") end
        queue(env,admin,"Raid"); actors[3]:Remove()
        admin:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",admin,admin)
        readOnly(env,admin); env.fireTimer("activatorSpawner")
        eq(#env.ents.FindByClass("activatorent"),3)
        env.receive("SendNPCInformation",admin,"Ambush"); eq(env.totalEnemies,2)
        readOnly(env,admin)
        for _, enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do env.fire("OnNPCKilled",enemy,admin) end
        env.fireTimer("activatorSpawner")
        for _, ent in ipairs(env.ents.FindByClass("activatorent")) do eq(ent.EventIdentifier,"Raid") end
    end)
    test("repeated status cannot prune deferred selected ownership or repair missing spawn inputs",function()
        local env,admin=setup(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        queue(env,admin,"Raid"); env.deferRemoval=true
        for _, ent in ipairs(env.ents.FindByClass("activatorent")) do ent:Remove() end
        env.SpawnPositions[1].activatorSpawnPositions={}; readOnly(env,admin)
        env.SpawnPositions[1].activatorSpawnPositions={[80]=env.Vector(1,2,3)}
        env.timers.activatorSpawner.callback()
        local live=0
        for _, ent in ipairs(env.ents.FindByClass("activatorent")) do
            if not ent:IsMarkedForDeletion() then live=live+1; eq(ent.EventIdentifier,"Raid") end
        end
        eq(live,3)
    end)
    test("non-admin and unrelated chat cannot disclose spawn diagnostics",function()
        local env,admin=setup(); local stranger=env.entity("player")
        eq(env.fire("PlayerSay",stranger,"!eventStatus"),"")
        eq(#stranger.chats,1); contains(stranger.chats[1],"Only admins")
        eq(env.fire("PlayerSay",admin,"ordinary conversation"),nil); eq(#admin.chats,0)
        eq(env.fire("PlayerSay",admin,"!eventStatus extra"),""); eq(#admin.chats,1)
        contains(admin.chats[1],"Usage:")
    end)
    test("full status bounds UTF-8 and control names while preserving all three diagnostic lines",function()
        local env,admin=setup(); local name=string.rep("火🚀é\n\t",100)
        env.NPCEdits[8]={name=name,information=env.NPCEdits[7].information}
        queue(env,admin,name); env.fireTimer("activatorSpawner")
        for i=1,12 do
            local custom=name .. i; env.NPCEdits[20+i]={name=custom,information=env.NPCEdits[7].information}
            actor(env,custom)
        end
        queue(env,admin,"Raid"); local detail,all,lines=status(env,admin)
        eq(#lines,16,"maximum status lines")
        contains(detail,"selected batch: information present; engine unchecked")
        contains(all,'Selected ready batch: "'); contains(all,'Pending next batch: "Raid"')
        for _, line in ipairs(lines) do
            local remainder=line:gsub("火",""):gsub("🚀",""):gsub("é","")
            assert(not remainder:find("[\128-\255]"),"valid UTF-8 truncation")
        end
    end)
end
