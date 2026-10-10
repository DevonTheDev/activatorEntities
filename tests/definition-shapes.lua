-- Exercise actual addon timer/Initialize paths; field and native model validity
-- are separate contracts. Every environment retains the real lookup helpers.
return function(gmod, test, eq)
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result={}
        for key,child in pairs(value) do result[key]=copy(child) end
        return result
    end
    local function same(actual,expected)
        eq(type(actual),type(expected),"configuration type")
        if type(expected) ~= "table" then eq(actual,expected); return end
        for key,value in pairs(expected) do same(actual[key],value) end
        for key in pairs(actual) do assert(expected[key] ~= nil,"configuration gained an entry") end
    end
    local function setup()
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local calls={random={},creates=0,starts=0,stops=0,files=0,network=0}
        env.math=setmetatable({random=function(low,high)
            calls.random[#calls.random+1]={low,high}; return low
        end},{__index=math})
        local create,start,stop,network=env.ents.Create,env.timer.Start,env.timer.Stop,env.net.Start
        env.ents.Create=function(class) calls.creates=calls.creates+1; return create(class) end
        env.timer.Start=function(...) calls.starts=calls.starts+1; return start(...) end
        env.timer.Stop=function(...) calls.stops=calls.stops+1; return stop(...) end
        env.net.Start=function(...) calls.network=calls.network+1; return network(...) end
        for _,key in ipairs({"Read","Write"}) do
            local original=env.file[key]
            env.file[key]=function(...) calls.files=calls.files+1; return original(...) end
        end
        return env,admin,calls
    end
    local function idle(env,calls,expectedStarts)
        eq(env.totalEnemies,0,"no encounter started")
        eq(#env.ents.FindByName("devonsSpawnedEntity"),0,"no enemies")
        eq(calls.starts,expectedStarts or 0,"only existing removal timer Start")
        eq(calls.files,0,"no persistence I/O")
        eq(calls.network,0,"no network start")
        eq(#env.messages,0,"no network messages")
        eq(#env.errors,0,"no new diagnostic errors")
    end
    local function actors(env,expected,name)
        local result=env.ents.FindByClass("activatorent")
        eq(#result,expected,"usable activators")
        for _,ent in ipairs(result) do
            eq(ent.EventIdentifier,name or "Raid"); eq(ent.model,ent.NPCInfo.activatorModel)
        end
        return result
    end
    local function rejectTimer(make,randomCalls)
        local env,_,calls=setup(); local repaired=env.NPCEdits
        env.NPCEdits=make(); local malformed=env.NPCEdits; local before=copy(malformed)
        local timer=env.timers.activatorSpawner; local callback,delay=timer.callback,timer.delay
        env.fireTimer("activatorSpawner")
        actors(env,0); eq(calls.creates,0,"rejection creates no entity")
        eq(#env.entities,1,"only the existing player")
        eq(#calls.random,randomCalls,"selection is not retried")
        eq(calls.stops,0); eq(timer.stopped,false)
        eq(env.timers.activatorSpawner,timer); eq(timer.callback,callback); eq(timer.delay,delay); eq(timer.repetitions,0)
        eq(env.NPCEdits,malformed); same(env.NPCEdits,before); idle(env,calls)
        env.NPCEdits=repaired
        env.fireTimer("activatorSpawner")
        actors(env,3); eq(calls.creates,3); eq(#env.entities,4)
        eq(#calls.random,randomCalls+5,"one event draw and existing four position draws")
        eq(timer.stopped,true); eq(calls.stops,1); idle(env,calls)
    end
    local function rejectManual(make,explicit,randomCalls)
        local env,_,calls=setup(); local repaired=env.NPCEdits
        env.NPCEdits=make(); local malformed=env.NPCEdits; local before=copy(malformed)
        local ent=env.ents.Create("activatorent")
        if explicit then ent.EventIdentifier="Raid" end
        ent:Spawn()
        eq(ent.valid,false,"existing Initialize removal path"); eq(ent.markedForDeletion,true)
        actors(env,0); eq(calls.creates,1); eq(#env.entities,2)
        eq(#calls.random,randomCalls); eq(calls.stops,0); eq(env.timers.activatorSpawner.stopped,false)
        eq(env.NPCEdits,malformed); same(env.NPCEdits,before); idle(env,calls,1)
        env.NPCEdits=repaired
        local fresh=env.ents.Create("activatorent"); fresh.EventIdentifier="Raid"; fresh:Spawn()
        eq(fresh.valid,true); actors(env,1); eq(calls.creates,2); eq(#env.entities,3)
        eq(#calls.random,randomCalls,"explicit recovery does not sample")
        eq(calls.stops,0); eq(env.timers.activatorSpawner.stopped,false); idle(env,calls,1)
    end

    -- The first four cases are the deterministic source-derived failures.
    test("definition shapes: timer rejects a string pool and recovers",function()
        rejectTimer(function() return "bad" end,0)
    end)
    test("definition shapes: timer rejects a singleton boolean record and recovers",function()
        rejectTimer(function() return {true} end,1)
    end)
    test("definition shapes: timer rejects matched boolean information and recovers",function()
        rejectTimer(function() return {{name="Raid",information=true}} end,1)
    end)
    test("definition shapes: manual lookup ignores a boolean record and recovers",function()
        rejectManual(function() return {true} end,true,0)
    end)

    local scalars={
        {"missing",function() return nil end}, {"false",function() return false end},
        {"true",function() return true end}, {"number",function() return 17 end},
        {"function",function() return function() end end}
    }
    for _,shape in ipairs(scalars) do
        test("definition shapes: timer rejects " .. shape[1] .. " pool",function() rejectTimer(shape[2],0) end)
        test("definition shapes: explicit manual rejects " .. shape[1] .. " pool",function() rejectManual(shape[2],true,0) end)
    end
    test("definition shapes: explicit manual rejects a string pool",function()
        rejectManual(function() return "bad" end,true,0)
    end)
    for _,shape in ipairs({{"false",false},{"string","bad"},{"number",17},{"function",function() end}}) do
        test("definition shapes: timer rejects sampled " .. shape[1] .. " record",function()
            rejectTimer(function() return {shape[2]} end,1)
        end)
    end
    for _,shape in ipairs({scalars[1],scalars[2],scalars[4],scalars[5],{"string",function() return "bad" end}}) do
        test("definition shapes: timer rejects " .. shape[1] .. " information",function()
            rejectTimer(function() return {{name="Raid",information=shape[2]()}} end,1)
        end)
    end
    test("definition shapes: an unnamed record is unavailable",function()
        rejectTimer(function() return {{}} end,1)
    end)
    test("definition shapes: manual random boolean record is removed",function()
        rejectManual(function() return {true} end,false,1)
    end)
    test("definition shapes: explicit manual boolean information is removed",function()
        rejectManual(function() return {{name="Raid",information=true}} end,true,0)
    end)

    test("definition shapes: sparse mixed pool retains every slot and exactly one draw",function()
        local env,_,calls=setup(); local info=env.NPCEdits[1].information
        local pool={[3]={name="Custom: Alpha!",information=info},[17]=true,[42]={name="Raid",information=info}}
        env.NPCEdits=pool; local before=copy(pool); local ordered={}
        for _,value in pairs(pool) do ordered[#ordered+1]=value end
        local draw=0
        env.math.random=function(low,high)
            eq(low,1); eq(high,3,"malformed record remains in sample population"); draw=draw+1; return draw
        end
        for index,record in ipairs(ordered) do
            eq(env.determineRandomEvent(),type(record) == "table" and record.name or nil)
            eq(draw,index,"one draw per event selection")
        end
        eq(calls.creates,0); same(pool,before); idle(env,calls)
    end)
    test("definition shapes: invalid random pick never falls back to a valid neighbor",function()
        local env,_,calls=setup(); local info=env.NPCEdits[1].information
        env.NPCEdits={[7]=true,[31]={name="Raid",information=info}}
        local invalidIndex,index=nil,0
        for _,record in pairs(env.NPCEdits) do index=index+1; if record == true then invalidIndex=index end end
        env.math.random=function(low,high)
            calls.random[#calls.random+1]={low,high}; eq(low,1); eq(high,2); return invalidIndex
        end
        env.fireTimer("activatorSpawner")
        actors(env,0); eq(calls.creates,0); eq(#calls.random,1); eq(calls.stops,0); idle(env,calls)
    end)
    test("definition shapes: queued valid custom name survives unrelated malformed records",function()
        local env,admin,calls=setup(); local info=env.NPCEdits[1].information
        -- Put the requested record last in the actual pairs order so lookup
        -- must visit the non-table neighbor, without assuming key ordering.
        local pool={[4]=true,[19]=true,[60]=true}; local last
        for key in pairs(pool) do last=key end
        pool[last]={name="Custom: Alpha!",information=info}; env.NPCEdits=pool
        local before=copy(pool)
        eq(env.fire("PlayerSay",admin,"!nextEvent Custom: Alpha!"),"")
        env.fireTimer("activatorSpawner")
        actors(env,3,"Custom: Alpha!"); eq(calls.creates,3); eq(#calls.random,4,"only existing position draws")
        same(pool,before); idle(env,calls)
    end)
    for _,badFirst in ipairs({false,true}) do
        test("definition shapes: duplicate lookup preserves first match with " .. (badFirst and "invalid" or "valid") .. " information",function()
            local env,_,calls=setup(); local info=env.NPCEdits[1].information
            local other=copy(info); other.activatorModel="models/alyx.mdl"
            local pool={[5]={name="Raid",information=info},[21]={name="Raid",information=other}}
            local first=next(pool); if badFirst then pool[first].information=true end
            env.NPCEdits=pool; local before=copy(pool)
            local expected=not badFirst and pool[first].information or nil
            eq(env.returnNPCInformation("Raid"),expected,"first matching definition wins or is unavailable")
            local ent=env.ents.Create("activatorent"); ent.EventIdentifier="Raid"; ent:Spawn()
            eq(ent.valid,not badFirst); eq(ent.NPCInfo,expected); eq(#calls.random,0)
            eq(calls.creates,1); same(pool,before); idle(env,calls,badFirst and 1 or 0)
        end)
    end
    test("definition shapes: malformed manual removal preserves paused spawning",function()
        local env,admin,calls=setup(); local repaired=env.NPCEdits
        eq(env.fire("PlayerSay",admin,"!pauseActivatorSpawns"),"")
        env.NPCEdits={true}; local ent=env.ents.Create("activatorent"); ent.EventIdentifier="Raid"; ent:Spawn()
        eq(ent.valid,false); eq(calls.creates,1); eq(calls.starts,0); eq(calls.stops,1)
        eq(env.timers.activatorSpawner.stopped,true); idle(env,calls)
        env.NPCEdits=repaired
        local fresh=env.ents.Create("activatorent"); fresh.EventIdentifier="Raid"; fresh:Spawn()
        actors(env,1); eq(calls.creates,2); eq(calls.starts,0); eq(calls.stops,1)
        eq(env.timers.activatorSpawner.stopped,true); idle(env,calls)
    end)
    test("definition shapes: table information remains a shape-only contract",function()
        local env=setup(); local empty={}; env.NPCEdits={{name="Incomplete",information=empty}}
        eq(env.returnNPCInformation("Incomplete"),empty,"no new field or model validation")
    end)
end
