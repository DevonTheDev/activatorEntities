-- Load the actual addon with API doubles. Every malformed-capacity callback
-- has a deliberate fourth-attempt sentinel, so even an unguarded +inf is safe.
return function(gmod, test, eq)
    local sentinel = "CAPACITY_BASELINE_ATTEMPT_4"
    local function setup(maximum)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        env.NPCEdits[7]={name="Ambush",information={activatorModel="models/alyx.mdl",
            npcPath="npc_combine_s",maxNPCs=2,dialogue="An ambush awaits."}}
        env.maxActivators=maximum
        return env,admin
    end
    local function boundedCallback(env)
        local create=env.ents.Create; local attempts=0
        env.ents.Create=function(class)
            if class ~= "activatorent" then return create(class) end
            attempts=attempts+1
            if attempts == 4 then error(sentinel,0) end
            return {valid=false}
        end
        local ok,err=pcall(env.timers.activatorSpawner.callback)
        env.ents.Create=create
        return ok,err,attempts
    end
    local function private(callback,wanted)
        for i=1,100 do
            local name,value=debug.getupvalue(callback,i)
            if not name then break end
            if name == wanted then return value end
        end
        error("missing observed upvalue " .. wanted)
    end
    local function state(env,name) return private(env.timers.activatorSpawner.callback,name) end
    local function queue(env,admin,name)
        eq(env.fire("PlayerSay",admin,"!nextEvent " .. name),"")
        return state(env,"pendingSelection")
    end
    local function actors(env,name,count)
        local found=env.ents.FindByClass("activatorent"); eq(#found,count)
        for _,actor in ipairs(found) do
            eq(actor.EventIdentifier,name); eq(actor:IsMarkedForDeletion(),false)
        end
        return found
    end
    local function watch(env)
        local calls={trace={},draws=0,timers=0,files=0,network=0,cleanup=0}
        for _,entry in ipairs({{"determineRandomEvent","event"},{"returnNPCInformation","information"},
            {"returnActivatorSpawns","position"},{"returnMaxActivators","maximum"}}) do
            local original=env[entry[1]]; local label=entry[2]
            env[entry[1]]=function(...)
                calls.trace[#calls.trace+1]=label; return original(...)
            end
        end
        env.math=setmetatable({random=function(low,high)
            calls.draws=calls.draws+1; return low
        end},{__index=math})
        local function record(owner,key,field)
            local original=owner[key]
            owner[key]=function(...) calls[field]=calls[field]+1; return original(...) end
        end
        for _,key in ipairs({"Start","Stop","Create","Simple"}) do record(env.timer,key,"timers") end
        for _,key in ipairs({"Read","Write"}) do record(env.file,key,"files") end
        record(env.net,"Start","network")
        record(env,"destroyActivators","cleanup"); record(env,"stopActivatorEvent","cleanup")
        return calls
    end
    local function quiet(calls)
        eq(calls.timers,0,"no timer change"); eq(calls.files,0,"no persistence I/O")
        eq(calls.network,0,"no network output"); eq(calls.cleanup,0,"no encounter or actor cleanup")
    end
    local function rejected(env)
        local ok,err,attempts=boundedCallback(env)
        assert(ok,"invalid capacity raised: " .. tostring(err))
        eq(attempts,0,"invalid capacity never reaches ents.Create")
    end

    test("capacity infinity returns before the bounded fourth-attempt sentinel",function()
        local env=setup(math.huge)
        local ok,err,attempts=boundedCallback(env)
        if not ok then
            eq(err,sentinel,"baseline must hit the deliberate sentinel")
            eq(attempts,4,"baseline sentinel bounds actual creation attempts")
        end
        assert(ok,"expected normal return; observed " .. tostring(err) .. " after " .. attempts .. " attempts")
        eq(attempts,0,"invalid capacity never reaches ents.Create")
    end)

    for _,bad in ipairs({{"string","3"},{"table",{}},{"true",true},
        {"positive infinity",math.huge},{"negative infinity",-math.huge},{"NaN",0/0}}) do
        test("capacity rejects " .. bad[1] .. " and retains pending until a repaired normal attempt",function()
            local env,admin=setup(bad[2]); local choice=queue(env,admin,"Ambush")
            local timer=env.timers.activatorSpawner; local callback,delay=timer.callback,timer.delay
            local definitions,positions=env.NPCEdits,env.SpawnPositions
            local chats=#admin.chats; local calls=watch(env)
            rejected(env)
            eq(table.concat(calls.trace,","),"information,position,maximum","preserve pre-capacity lookup order")
            eq(calls.draws,1,"selected attempt retains its initial position sample")
            quiet(calls); eq(#admin.chats,chats); eq(#env.errors,0); eq(#env.messages,0)
            eq(state(env,"pendingSelection"),choice,"same pending object")
            eq(state(env,"selectedBatchName"),nil); actors(env,nil,0); eq(env.totalEnemies,0)
            eq(env.NPCEdits,definitions); eq(env.SpawnPositions,positions)
            if bad[1] == "NaN" then assert(env.maxActivators ~= env.maxActivators)
            else eq(env.maxActivators,bad[2],"no configuration repair") end
            eq(env.timers.activatorSpawner,timer); eq(timer.callback,callback)
            eq(timer.delay,delay); eq(timer.repetitions,0); eq(timer.stopped,false)

            -- Controlled fixture repair; this is not a live hot-reload promise.
            env.maxActivators=3; env.fireTimer("activatorSpawner")
            actors(env,"Ambush",3); eq(state(env,"pendingSelection"),nil)
            eq(state(env,"selectedBatchName"),"Ambush"); eq(timer.stopped,true)
            eq(env.timers.activatorSpawner,timer); eq(timer.callback,callback); eq(timer.delay,delay)
        end)
    end

    test("capacity rejection preserves random event then initial position sampling",function()
        local env=setup(math.huge); local calls=watch(env)
        rejected(env)
        eq(table.concat(calls.trace,","),"event,information,position,maximum")
        eq(calls.draws,2,"one real event draw and one real position draw")
        quiet(calls); actors(env,nil,0)
    end)

    local controls={
        {name="nil fallback",count=1,stop=true},
        {name="false fallback",maximum=false,count=1,stop=true},
        {name="negative",maximum=-2,count=0,stop=false},
        {name="zero",maximum=0,count=0,stop=false},
        {name="fraction below one",maximum=0.5,count=0,stop=false},
        {name="fraction above one",maximum=1.5,count=1,stop=false},
        {name="three",maximum=3,count=3,stop=true},
    }
    for _,multiple in ipairs({{name="false",value=false},{name="nil"},{name="string",value="true"},
        {name="number",value=1},{name="table",value={}}}) do
        controls[#controls+1]={name="multipleEntities " .. multiple.name,maximum="ignored",
            multiple=multiple,count=1,stop=true}
    end
    for _,case in ipairs(controls) do
        for _,existing in ipairs({0,4}) do
            test("capacity preserves " .. case.name .. " with " .. existing .. " existing actors",function()
                local env,admin=setup(case.maximum)
                if case.multiple then env.multipleEntities=case.multiple.value end
                local originals={}
                for i=1,existing do
                    local actor=env.entity("activatorent"); actor.EventIdentifier="Raid"; actor:Spawn()
                    originals[i]=actor
                end
                local choice=queue(env,admin,"Ambush"); local calls=watch(env)
                local attempts=0; local create=env.ents.Create
                env.ents.Create=function(class)
                    if class == "activatorent" then attempts=attempts+1 end
                    return create(class)
                end
                env.fireTimer("activatorSpawner")
                local expected=existing == 0 and case.count or existing
                eq(#env.ents.FindByClass("activatorent"),expected)
                eq(attempts,existing == 0 and case.count or 0,"unchanged finite iteration count")
                eq(env.timers.activatorSpawner.stopped,existing > 0 or case.stop)
                eq(calls.timers,(existing > 0 or case.stop) and 1 or 0,"only existing capacity Stop")
                eq(calls.files,0); eq(calls.network,0); eq(calls.cleanup,0)
                for _,actor in ipairs(originals) do
                    eq(actor.valid,true); eq(actor:IsMarkedForDeletion(),false)
                end
                if existing == 0 and case.count > 0 then
                    eq(state(env,"pendingSelection"),nil)
                    actors(env,"Ambush",case.count); eq(state(env,"selectedBatchName"),"Ambush")
                else
                    eq(state(env,"pendingSelection"),choice); eq(state(env,"selectedBatchName"),nil)
                end
                eq(env.maxActivators,case.maximum,"finite/fallback configuration remains unchanged")
            end)
        end
    end

    for _,mode in ipairs({"selected","manual"}) do
        for _,stopped in ipairs({false,true}) do
            test("capacity rejection preserves " .. mode .. " actor and Use grant, stopped=" .. tostring(stopped),function()
                local env,admin=setup(1); local name=mode == "selected" and "Ambush" or "Raid"
                local actor
                if mode == "selected" then
                    queue(env,admin,name); env.fireTimer("activatorSpawner"); actor=actors(env,name,1)[1]
                else
                    actor=env.entity("activatorent"); actor.EventIdentifier=name; actor:Spawn()
                end
                local choice=queue(env,admin,mode == "selected" and "Raid" or "Ambush")
                if stopped then env.timer.Stop("activatorSpawner") else env.timer.Start("activatorSpawner") end
                admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
                local grants=private(env.receivers.SendNPCInformation,"interactions"); local grant=grants[admin]
                assert(grant,"real Use issued a grant")
                local owners=state(env,"selectedBatchEntities"); local timer=env.timers.activatorSpawner
                local messages,chats=#env.messages,#admin.chats; local calls=watch(env)
                env.maxActivators=math.huge; rejected(env)
                quiet(calls); eq(env.timers.activatorSpawner,timer); eq(timer.stopped,stopped)
                eq(#env.messages,messages); eq(#admin.chats,chats); eq(#env.errors,0)
                eq(state(env,"pendingSelection"),choice); eq(grants[admin],grant)
                eq(actor.valid,true); eq(actor:IsMarkedForDeletion(),false); actors(env,name,1)
                if mode == "selected" then
                    eq(state(env,"selectedBatchName"),name); eq(state(env,"selectedBatchEntities"),owners)
                    eq(owners[actor],true)
                else eq(state(env,"selectedBatchName"),nil) end
                env.receive("SendNPCInformation",admin,name)
                eq(env.totalEnemies,mode == "selected" and 2 or 5,"old Use grant still starts the encounter")
                eq(state(env,"pendingSelection"),choice); eq(actor.valid,false)
                for _,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do env.fire("OnNPCKilled",enemy,admin) end
                eq(env.messageCount("roundFinished"),1); eq(env.totalEnemies,0)
                eq(timer.stopped,false,"normal encounter retirement restarts enabled schedule")
                env.maxActivators=3; env.fireTimer("activatorSpawner")
                actors(env,choice.name,3); eq(state(env,"pendingSelection"),nil)
            end)
        end
    end

    for _,gate in ipairs({"paused","active encounter"}) do
        test("capacity is not sampled by an already due " .. gate .. " callback",function()
            local env,admin=setup(1); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
            local actor=actors(env,"Ambush",1)[1]; local choice=queue(env,admin,"Raid")
            if gate == "paused" then eq(env.fire("PlayerSay",admin,"!pauseActivatorSpawns"),"")
            else
                admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
                env.receive("SendNPCInformation",admin,"Ambush")
            end
            local enemies=env.ents.FindByName("devonsSpawnedEntity")
            local active=private(env.receivers.SendNPCInformation,"activeEnemies")
            local messages,chats=#env.messages,#admin.chats; local timer=env.timers.activatorSpawner
            local calls=watch(env); env.maxActivators=math.huge
            rejected(env)
            eq(#calls.trace,0,"pause/active gate precedes all config lookup and sampling")
            eq(calls.draws,0); quiet(calls); eq(timer.stopped,true); eq(env.timers.activatorSpawner,timer)
            eq(#env.messages,messages); eq(#admin.chats,chats); eq(#env.errors,0)
            eq(state(env,"pendingSelection"),choice)
            if gate == "paused" then
                eq(actor.valid,true); eq(actor:IsMarkedForDeletion(),false); eq(env.totalEnemies,0)
                eq(state(env,"selectedBatchName"),"Ambush")
            else
                eq(env.totalEnemies,2); eq(private(env.receivers.SendNPCInformation,"activeEnemies"),active)
                for _,enemy in ipairs(enemies) do
                    eq(enemy.valid,true); eq(enemy:IsMarkedForDeletion(),false); eq(active[enemy],true)
                end
            end
        end)
    end

    test("capacity-stopped direct callback keeps existing finite refill semantics",function()
        local env,admin=setup(1); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        local original=actors(env,"Ambush",1)[1]; eq(env.timers.activatorSpawner.stopped,true)
        env.maxActivators=3; env.timers.activatorSpawner.callback()
        actors(env,"Ambush",3); eq(original.valid,true); eq(env.timers.activatorSpawner.stopped,true)
    end)
end
