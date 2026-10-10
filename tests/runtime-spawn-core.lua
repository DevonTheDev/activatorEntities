-- Runtime must reject the same unsafe target input that status already diagnoses.
-- These tests call actual addon functions; RNG/creation spies expose early effects.
return function(gmod,test,eq)
    local H=dofile("tests/runtime-spawn-fixtures.lua")(gmod,eq)
    local function rejectLookup(env,ioState,kind)
        local before=H.dataState(env,ioState)
        local observed=H.watch(env)
        eq(H.call(kind.name .. " lookup",function() return env[kind.lookup](env.map) end),nil)
        eq(#observed.draws,0,"unavailable lookup does not sample or filter the list")
        eq(#observed.creates,0); H.sameData(env,ioState,before)
    end
    local function rejectTimer(env,ioState)
        local admin=env.entity("player"); admin.admin=true
        local before=H.dataState(env,ioState)
        local timer=H.snapshot(env.timers.activatorSpawner)
        local messages,entities,errors=#env.messages,#env.entities,#env.errors
        local observed=H.watch(env)
        H.call("timer attempt",function() env.fireTimer("activatorSpawner") end)
        eq(#observed.creates,0,"invalid initial input creates no partial batch")
        eq(#observed.placements,0); eq(#observed.draws,0,"preflight precedes event and position RNG")
        eq(#env.entities,entities); eq(#env.messages,messages); eq(#env.errors,errors)
        eq(#env.ents.FindByClass("activatorent"),0); eq(env.totalEnemies,0)
        eq(#admin.chats,0); H.same(env.timers.activatorSpawner,timer)
        H.sameData(env,ioState,before)
    end
    local function loadedDuplicates(reverse)
        return H.setup(function(env)
            return {[2]=H.record(env,nil,reverse and 100 or 0),
                [8]=H.record(env,nil,reverse and 0 or 100)}
        end)
    end
    -- Accepted storage is the primary regression, in both distinct-record orders.
    for _,reverse in ipairs({false,true}) do
        for _,kind in ipairs(H.kinds) do
            test("runtime " .. kind.name .. " rejects loaded duplicate maps, reverse=" .. tostring(reverse),function()
                local env,ioState=loadedDuplicates(reverse)
                assert(not rawequal(env.SpawnPositions[2],env.SpawnPositions[8]))
                assert(not rawequal(env.SpawnPositions[2][kind.field],env.SpawnPositions[8][kind.field]))
                rejectLookup(env,ioState,kind)
            end)
        end
        test("timer rejects loaded duplicate maps before RNG, reverse=" .. tostring(reverse),function()
            local env,ioState=loadedDuplicates(reverse)
            rejectTimer(env,ioState)
        end)
    end
    for _,case in ipairs(H.invalid) do
        for _,kind in ipairs(H.kinds) do
            test("runtime " .. kind.name .. " returns nil for " .. case[1],function()
                local env,ioState=H.setup(); case[2](env,kind)
                rejectLookup(env,ioState,kind)
            end)
        end
        test("timer rejects " .. case[1] .. " before random selection or creation",function()
            local env,ioState=H.setup(); case[2](env,H.kinds[1])
            rejectTimer(env,ioState)
        end)
    end

    -- An implementation that validates the entire storage document would fail
    -- these controls: only target positions and all record identities are gates.
    for _,kind in ipairs(H.kinds) do
        for _,damage in ipairs({"other kind","other map","duplicate other maps"}) do
            test("runtime " .. kind.name .. " preserves sparse target despite " .. damage,function()
                local env,ioState=H.setup()
                env.NPCEdits[1].information.maxNPCs=2
                local ply,actor
                if kind.name == "enemy" then ply,actor=env.ready() else ply=env.entity("player") end
                local current=env.SpawnPositions[1]
                env.SpawnPositions={[20]=current}
                if damage == "other kind" then current[kind.other]=false
                else
                    env.SpawnPositions[7]={map="other_map",activatorSpawnPositions=false,enemySpawnPositions=false}
                    if damage == "duplicate other maps" then
                        env.SpawnPositions[90]={map="other_map",activatorSpawnPositions="bad",enemySpawnPositions="bad"}
                    end
                end
                local point=env.Vector(101,202,303)
                current[kind.field]={[400]=point}
                local before=H.dataState(env,ioState)
                local observed=H.watch(env)
                eq(env[kind.lookup](env.map),point)
                if kind.name == "activator" then
                    env.fireTimer("activatorSpawner")
                    local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
                    for _,ent in ipairs(actors) do eq(ent:GetPos(),point) end
                    eq(#observed.creates,3)
                else
                    actor:AcceptInput("Use",ply,ply); env.receive("SendNPCInformation",ply,"Raid")
                    eq(env.totalEnemies,2); eq(#observed.creates,2)
                    for i,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do
                        eq(enemy:GetPos().x,point.x+30*i); eq(enemy:GetPos().y,point.y+30*i)
                        eq(enemy:GetPos().z,point.z)
                    end
                end
                H.sameData(env,ioState,before)
            end)
        end
        test("runtime " .. kind.name .. " lookup validates the requested map rather than the current map",function()
            local env,ioState=H.setup()
            local point=env.Vector(4,5,6)
            env.SpawnPositions[8]=H.record(env,"requested_map")
            env.SpawnPositions[8][kind.field]={[99]=point}
            env.SpawnPositions[9]=H.record(env)
            local before=H.dataState(env,ioState); local observed=H.watch(env)
            eq(env[kind.lookup]("requested_map"),point)
            eq(#observed.draws,1); eq(observed.draws[1][2],1)
            H.sameData(env,ioState,before)
        end)
    end
    test("valid sparse timer and Start preserve event-first RNG, candidate order and enemy offsets",function()
        local env,ioState=H.setup()
        env.NPCEdits={}
        for _,key in ipairs({3,14,29}) do
            env.NPCEdits[key]={name="Encounter " .. key,information={activatorModel="models/alyx.mdl",
                npcPath="npc_combine_s",maxNPCs=2,dialogue="Ready?"}}
        end
        local current=env.SpawnPositions[1]
        current.activatorSpawnPositions={[11]=env.Vector(10,20,30),[70]=env.Vector(40,50,60)}
        current.enemySpawnPositions={[2]=env.Vector(100,200,300),[8]=env.Vector(400,500,600),
            [34]=env.Vector(700,800,900),[90]=env.Vector(1000,1100,1200)}
        env.SpawnPositions={[27]=current,[6]=H.record(env,"other_map")}
        local function enumeration(values)
            local result={}; for _,value in pairs(values) do result[#result+1]=value end; return result
        end
        local events=enumeration(env.NPCEdits)
        local positions=enumeration(current.activatorSpawnPositions)
        local enemies=enumeration(current.enemySpawnPositions)
        local before=H.dataState(env,ioState)
        local observed=H.watch(env,{2,2,1,2,1,3})
        local ply=env.entity("player"); env.fireTimer("activatorSpawner")
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
        eq(#observed.draws,5,"retain event draw and the existing trailing position sample")
        for i,choice in ipairs({2,1,2}) do
            eq(actors[i].EventIdentifier,events[2].name)
            eq(actors[i]:GetPos(),positions[choice],"preserve pairs enumeration without sorting/compaction")
        end
        ply:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",ply,ply)
        env.receive("SendNPCInformation",ply,events[2].name)
        eq(#observed.draws,6); eq(#observed.creates,5); eq(env.totalEnemies,2)
        for i,size in ipairs({3,2,2,2,2,4}) do
            eq(observed.draws[i][1],1); eq(observed.draws[i][2],size,"unchanged draw order and pool size")
        end
        for i,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do
            eq(enemy:GetPos().x,enemies[3].x+30*i)
            eq(enemy:GetPos().y,enemies[3].y+30*i); eq(enemy:GetPos().z,enemies[3].z)
        end
        H.sameData(env,ioState,before)
    end)
end
