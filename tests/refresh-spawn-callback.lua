-- Exercise the actual refresh command from real automatic Spawn callbacks.
-- Doubles prove retirement/order and timer API calls, not native elapsed delay.
return function(gmod, test, eq)
    local upvalue = dofile("tests/find-upvalue.lua")
    local function private(env, wanted)
        return upvalue(env.timers.activatorSpawner.callback, wanted)
    end
    local function say(env, admin, command)
        eq(env.fire("PlayerSay",admin,command),"","command handled privately")
    end
    local function live(env, name)
        local result={}
        for _,ent in ipairs(env.entities) do
            if ent.class == "activatorent" and ent.valid and not ent:IsMarkedForDeletion() then
                if name then eq(ent.EventIdentifier,name) end
                result[#result+1]=ent
            end
        end
        return result
    end
    local function state(env, pending, selected)
        local choice=private(env,"pendingSelection")
        eq(choice and choice.name,pending,"pending choice")
        eq(private(env,"selectedBatchName"),selected,"selected ownership")
        if not selected then eq(next(private(env,"selectedBatchEntities")),nil,"no retired ownership") end
    end
    local function setup(maximum, deferred)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        env.maxActivators=maximum; env.deferRemoval=deferred
        env.NPCEdits[7]={name="Ambush",information={activatorModel="models/barney.mdl",
            npcPath="npc_combine_s",maxNPCs=2,dialogue="Another encounter"}}
        env.SpawnPositions[1].activatorSpawnPositions={env.Vector(100,200,300)}
        local calls={samples=0,creates=0,scans=0,starts=0,stops=0,random=0}
        env.determineRandomEvent=function() calls.random=calls.random+1; return "Raid" end
        for _,entry in ipairs({{env,"returnActivatorSpawns","samples"},
                {env.ents,"Create","creates"},{env.ents,"FindByClass","scans"},
                {env.timer,"Start","starts"},{env.timer,"Stop","stops"}}) do
            local owner,key,field=entry[1],entry[2],entry[3]; local original=owner[key]
            owner[key]=function(...) calls[field]=calls[field]+1; return original(...) end
        end
        return env,admin,calls
    end
    local function snapshot(calls)
        local result={}; for key,value in pairs(calls) do result[key]=value end
        return result
    end
    local function unchanged(calls, before)
        for key,value in pairs(before) do eq(calls[key],value,"abandoned attempt must not change " .. key) end
    end
    local function onceInsideSpawn(env, callback)
        local create=env.ents.Create; local fired=false
        env.ents.Create=function(class)
            local ent=create(class); local spawn=ent.Spawn
            ent.Spawn=function(self)
                spawn(self)
                if not fired then fired=true; callback(self) end
            end
            return ent
        end
        return function() eq(fired,true,"real Spawn callback reached") end
    end

    for _,deferred in ipairs({false,true}) do
        for _,maximum in ipairs({1,3}) do
            for _,mode in ipairs({"pending","replacement","random"}) do
                test("refresh inside Spawn retires " .. mode .. " attempt, cap=" .. maximum .. ", deferred=" .. tostring(deferred),function()
                    local env,admin,calls=setup(maximum,deferred)
                    if mode ~= "random" then say(env,admin,"!nextEvent Ambush") end
                    local wanted=mode == "pending" and "Ambush" or (mode == "replacement" and "Raid" or nil)
                    local afterRefresh,retired,choice
                    local timer=env.timers.activatorSpawner; local callback=timer.callback
                    local fired=onceInsideSpawn(env,function(actor)
                        retired=actor
                        if mode == "replacement" then say(env,admin,"!nextEvent Raid") end
                        choice=private(env,"pendingSelection")
                        say(env,admin,"!refreshActivators")
                        eq(#live(env),0); state(env,wanted,nil)
                        afterRefresh=snapshot(calls)
                    end)
                    env.fireTimer("activatorSpawner"); fired()
                    eq(#live(env),0,"no replacement before next normal attempt")
                    unchanged(calls,afterRefresh)
                    eq(calls.samples,1); eq(calls.creates,1)
                    eq(private(env,"pendingSelection"),choice,"retain pending slot identity")
                    state(env,wanted,nil)
                    eq(env.timers.activatorSpawner,timer); eq(timer.callback,callback)
                    eq(timer.delay,env.returnDelayBetweenEvents()); eq(timer.repetitions,0)
                    eq(timer.stopped,false,"refresh-owned timer remains enabled")
                    assert(retired:IsMarkedForDeletion()); env.flushRemovals()
                    eq(retired.valid,false); state(env,wanted,nil)
                    -- Existing EntityRemoved callbacks may restart the timer;
                    -- assert only the abandoned outer attempt adds no operations.
                    env.fireTimer("activatorSpawner")
                    eq(#live(env,wanted or "Raid"),maximum,"next ordinary attempt fills capacity")
                    state(env,nil,wanted); eq(timer.stopped,true)
                end)
            end
        end
        test("refresh inside refill removes manual and in-flight actors, deferred=" .. tostring(deferred),function()
            local env,admin,calls=setup(3,deferred)
            local manual=env.entity("activatorent"); manual.EventIdentifier="Raid"; manual:Spawn()
            say(env,admin,"!nextEvent Ambush")
            local afterRefresh
            local fired=onceInsideSpawn(env,function()
                say(env,admin,"!refreshActivators"); afterRefresh=snapshot(calls)
            end)
            env.fireTimer("activatorSpawner"); fired(); unchanged(calls,afterRefresh)
            eq(#live(env),0); assert(manual:IsMarkedForDeletion())
            eq(env.maxActivators,3); eq(env.activatorCount,0); state(env,"Ambush",nil)
            env.flushRemovals(); eq(manual.valid,false); state(env,"Ambush",nil)
            -- A newly added manual actor occupies one live slot. Pending stays
            -- queued until an empty-batch admission can own it.
            local replacement=env.entity("activatorent"); replacement.EventIdentifier="Raid"; replacement:Spawn()
            env.fireTimer("activatorSpawner"); eq(#live(env,"Raid"),3)
            eq(env.activatorCount,3); eq(env.maxActivators,3); state(env,"Ambush",nil)
            say(env,admin,"!refreshActivators"); env.flushRemovals()
            env.fireTimer("activatorSpawner"); eq(#live(env,"Ambush"),3); state(env,nil,"Ambush")
        end)
    end

    test("refresh invalidates its attempt before synchronous removal callbacks",function()
        local env,admin=setup(1,false); say(env,admin,"!nextEvent Ambush")
        local before=private(env,"spawnScheduleGeneration"); local checked=false
        onceInsideSpawn(env,function(actor)
            local remove=actor.Remove
            actor.Remove=function(self)
                assert(private(env,"spawnScheduleGeneration") ~= before,"retire schedule before removal callbacks")
                checked=true; return remove(self)
            end
            say(env,admin,"!refreshActivators")
        end)
        env.fireTimer("activatorSpawner"); eq(checked,true); state(env,"Ambush",nil)
    end)

    test("abandoned final iteration cannot recount and stop the refreshed timer",function()
        local env,admin,calls=setup(1,false); say(env,admin,"!nextEvent Ambush")
        local afterRefresh
        onceInsideSpawn(env,function()
            say(env,admin,"!refreshActivators")
            -- Other addon work can add a manual actor after refresh returns.
            -- The next normal attempt, not this abandoned one, owns its count.
            local manual=env.entity("activatorent"); manual.EventIdentifier="Raid"; manual:Spawn()
            afterRefresh=snapshot(calls)
        end)
        env.fireTimer("activatorSpawner"); unchanged(calls,afterRefresh)
        eq(#live(env,"Raid"),1); eq(env.activatorCount,0)
        eq(env.timers.activatorSpawner.stopped,false); state(env,"Ambush",nil)
        env.fireTimer("activatorSpawner"); eq(env.activatorCount,1)
        eq(env.timers.activatorSpawner.stopped,true); state(env,"Ambush",nil)
    end)

    for _,gate in ipairs({"players","positions","capacity"}) do
        test("fresh attempt after callback refresh still honors " .. gate .. " and edited positions",function()
            local env,admin=setup(3,true); say(env,admin,"!nextEvent Ambush")
            onceInsideSpawn(env,function() say(env,admin,"!refreshActivators") end)
            env.fireTimer("activatorSpawner"); eq(#live(env),0); env.flushRemovals()
            local point=env.Vector(700,800,900); admin:SetPos(point)
            say(env,admin,"!listSpawns activator"); say(env,admin,"!moveActivatorSpawn 1")
            local positions=env.SpawnPositions[1].activatorSpawnPositions
            if gate == "players" then env.minNumberOfPlayers=2
            elseif gate == "positions" then env.SpawnPositions[1].activatorSpawnPositions={}
            else env.maxActivators=0 end
            env.fireTimer("activatorSpawner"); eq(#live(env),0); state(env,"Ambush",nil)
            env.minNumberOfPlayers=0; env.maxActivators=3
            env.SpawnPositions[1].activatorSpawnPositions=positions
            env.fireTimer("activatorSpawner"); local batch=live(env,"Ambush"); eq(#batch,3)
            for _,actor in ipairs(batch) do
                eq(actor:GetPos().x,point.x); eq(actor:GetPos().y,point.y); eq(actor:GetPos().z,point.z)
            end
            state(env,nil,"Ambush")
        end)
    end
    for _,kind in ipairs({"nonadmin","malformed"}) do
        test("refused callback refresh leaves the existing automatic attempt intact: " .. kind,function()
            local env,admin=setup(3,false); say(env,admin,"!nextEvent Ambush")
            local before=private(env,"spawnScheduleGeneration")
            onceInsideSpawn(env,function()
                if kind == "nonadmin" then admin.admin=false end
                say(env,admin,kind == "malformed" and "!refreshActivators extra" or "!refreshActivators")
            end)
            env.fireTimer("activatorSpawner"); eq(#live(env,"Ambush"),3)
            eq(private(env,"spawnScheduleGeneration"),before)
            eq(env.timers.activatorSpawner.stopped,true); state(env,nil,"Ambush")
        end)
    end
end
