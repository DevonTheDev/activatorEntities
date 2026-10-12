-- Actual command/timer handlers with bounded callbacks. These establish Lua
-- admission, ownership and API order, not native Spawn success or timer timing.
return function(gmod, test, eq)
    local upvalue = dofile("tests/find-upvalue.lua")
    local command = "!spawnActivatorsNow"
    local function setup(maximum)
        local env = gmod.new(); local admin = env.entity("player"); admin.admin = true
        env.NPCEdits[7] = {name="Ambush", information={activatorModel="models/alyx.mdl",
            npcPath="npc_combine_s", maxNPCs=2, dialogue="An ambush awaits."}}
        env.maxActivators = maximum == nil and 3 or maximum
        env.math = setmetatable({random=function(low) return low end}, {__index=math})
        return env, admin
    end
    local function state(env, name) return upvalue(env.timers.activatorSpawner.callback, name) end
    local function say(env, admin, text) return env.fire("PlayerSay", admin, text or command) end
    local function queue(env, admin, name)
        eq(say(env, admin, "!nextEvent " .. (name or "Ambush")), "")
        return state(env, "pendingSelection")
    end
    local function ready(env)
        local result = {}
        for _, actor in ipairs(env.entities) do
            if actor.class == "activatorent" and actor.valid and not actor:IsMarkedForDeletion() then
                result[#result+1] = actor
            end
        end
        return result
    end
    local function reply(admin, fragment)
        local line = assert(admin.chats[#admin.chats], "private reply missing")
        assert(#line <= 255 and not line:find("%c"), "bounded private line")
        assert(line:find(fragment, 1, true), "expected " .. fragment .. ", got " .. line)
    end
    local function watch(env)
        local calls = {trace={}, timers=0, draws=0, creates=0, scans=0}
        local function wrap(owner, key, label, count)
            local original = owner[key]
            owner[key] = function(...)
                if label then calls.trace[#calls.trace+1] = label end
                if count then calls[count] = calls[count]+1 end
                return original(...)
            end
        end
        wrap(env, "determineRandomEvent", "event")
        wrap(env, "returnNPCInformation", "information")
        wrap(env, "returnActivatorSpawns", "position")
        wrap(env, "returnMaxActivators", "maximum")
        wrap(env.math, "random", nil, "draws")
        wrap(env.ents, "Create", "create", "creates")
        wrap(env.ents, "FindByClass", nil, "scans")
        for _, key in ipairs({"Start", "Stop", "Create", "Simple"}) do wrap(env.timer, key, nil, "timers") end
        return calls
    end
    local function onceSpawn(env, callback)
        local create, entered = env.ents.Create, false
        env.ents.Create = function(class)
            local actor = create(class)
            if class == "activatorent" and env.IsValid(actor) then
                local spawn = actor.Spawn
                actor.Spawn = function(self)
                    spawn(self)
                    if not entered then entered = true; callback(self) end
                end
            end
            return actor
        end
        return function() assert(entered, "Spawn callback must execute") end
    end

    test("immediate exact command makes one private random ready batch without starting combat", function()
        local env, admin = setup(); local observer = env.entity("player"); local calls = watch(env)
        local timer, callback = env.timers.activatorSpawner, env.timers.activatorSpawner.callback
        eq(say(env, admin), ""); eq(#ready(env), 3); eq(#admin.chats, 1); eq(#observer.chats, 0)
        reply(admin, "Ready activators: 3 / 3"); eq(env.totalEnemies, 0); eq(#env.messages, 0)
        eq(calls.timers, 1); eq(timer.stopped, true); eq(env.timers.activatorSpawner, timer); eq(timer.callback, callback)
        eq(state(env, "spawnAttemptDepth"), 0)
    end)
    for _, text in ipairs({command .. " extra", command .. " ", command .. "\t", command .. "\n", command .. " " .. string.rep("x", 2000)}) do
        test("immediate arguments give bounded usage: " .. #text, function()
            local env, admin = setup(); local choice = queue(env, admin); local calls = watch(env)
            eq(say(env, admin, text), ""); reply(admin, "Usage: " .. command)
            eq(#ready(env), 0); eq(#calls.trace, 0); eq(calls.draws, 0); eq(calls.timers, 0)
            eq(state(env, "pendingSelection"), choice)
        end)
    end
    for _, text in ipairs({"!spawnactivatorsnow", "!SpawnActivatorsNow", " " .. command, command .. "More", "hello " .. command}) do
        test("immediate unrelated spelling remains unhandled: " .. text, function()
            local env, admin = setup(); eq(say(env, admin, text), nil); eq(#admin.chats, 0); eq(#ready(env), 0)
        end)
    end
    for _, role in ipairs({"invalid", "nonplayer", "nonadmin", "dead admin"}) do
        test("immediate caller eligibility: " .. role, function()
            local env, admin = setup(); local observer = env.entity("player")
            if role == "invalid" then admin.valid = false
            elseif role == "nonplayer" then admin.class = "prop_physics"
            elseif role == "nonadmin" then admin.admin = false
            else admin.alive = false end
            local result = say(env, admin)
            if role == "invalid" or role == "nonplayer" then eq(result, nil) else eq(result, "") end
            eq(#observer.chats, 0)
            if role == "nonadmin" then reply(admin, "Only admins")
            elseif role == "dead admin" then eq(#ready(env), 3)
            else eq(#admin.chats, 0) end
        end)
    end
    for _, gate in ipairs({"paused", "active", "manual", "selected"}) do
        test("immediate refuses " .. gate .. " without pruning selection or touching schedule/RNG", function()
            local env, admin = setup(); local choice = queue(env, admin)
            if gate == "paused" then say(env, admin, "!pauseActivatorSpawns")
            elseif gate == "manual" then local actor=env.entity("activatorent"); actor.EventIdentifier="Raid"; actor:Spawn()
            elseif gate == "selected" then
                env.fireTimer("activatorSpawner"); choice=queue(env, admin, "Raid")
                -- Simulate a stale ownership member without calling lifecycle hooks.
                ready(env)[1].valid=false
            else
                env.fireTimer("activatorSpawner"); local actor=ready(env)[1]
                admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
                env.receive("SendNPCInformation",admin,"Ambush"); choice=queue(env,admin,"Raid")
            end
            local owners=state(env,"selectedBatchEntities"); local name=state(env,"selectedBatchName")
            local members=0; for _ in pairs(owners) do members=members+1 end
            local count=#ready(env); local timer=env.timers.activatorSpawner; local stopped=timer.stopped
            local calls=watch(env); eq(say(env,admin),""); reply(admin,"refused")
            eq(state(env,"pendingSelection"),choice); eq(state(env,"selectedBatchEntities"),owners)
            eq(state(env,"selectedBatchName"),name); local after=0; for _ in pairs(owners) do after=after+1 end
            eq(after,members); eq(#ready(env),count); eq(#calls.trace,0); eq(calls.draws,0); eq(calls.timers,0)
            eq(env.timers.activatorSpawner,timer); eq(timer.stopped,stopped); eq(state(env,"spawnAttemptDepth"),0)
        end)
    end
    test("immediate ignores invalid and deleting manual actors",function()
        local env,admin=setup(1); env.deferRemoval=true
        local deleted=env.entity("activatorent"); deleted:Remove()
        local invalid=env.entity("activatorent"); invalid.valid=false
        eq(say(env,admin),""); eq(#ready(env),1); eq(deleted.markedForDeletion,true)
        reply(admin,"Ready activators: 1 / 1")
    end)
    local gates={
        {name="players",apply=function(e) e.minNumberOfPlayers=9 end,fragment="not enough players",trace="",draws=0},
        {name="positions",apply=function(e) e.SpawnPositions={} end,fragment="no activator positions",trace="",draws=0},
        {name="selected unavailable",apply=function(e) e.NPCEdits[7]=nil end,fragment="selected event is unavailable",trace="",draws=0},
        {name="event absent",random=true,apply=function(e) e.determineRandomEvent=function() return nil end end,fragment="event information is unavailable",trace="event",draws=0},
        {name="event malformed",random=true,apply=function(e) e.determineRandomEvent=function() return {} end end,fragment="event information is unavailable",trace="event,information",draws=0},
        {name="sample absent",apply=function(e) e.returnActivatorSpawns=function() return nil end end,fragment="no position was sampled",trace="information,position",draws=0},
    }
    for _, gate in ipairs(gates) do for _, stopped in ipairs({false,true}) do
        test("immediate ordinary admission " .. gate.name .. " preserves stopped=" .. tostring(stopped),function()
            local env,admin=setup(); local choice
            if not gate.random then choice=queue(env,admin) end
            gate.apply(env); local timer=env.timers.activatorSpawner; timer.stopped=stopped
            local calls=watch(env); eq(say(env,admin),""); reply(admin,gate.fragment)
            eq(table.concat(calls.trace,","),gate.trace); eq(calls.draws,gate.draws); eq(calls.timers,0)
            eq(state(env,"pendingSelection"),choice); eq(#ready(env),0); eq(timer.stopped,stopped)
        end)
    end end
    for _, case in ipairs({{name="nil",count=1,stop=true}, {name="false",value=false,count=1,stop=true},
        {name="negative",value=-2,count=0}, {name="zero",value=0,count=0},
        {name="fraction low",value=.5,count=0}, {name="fraction high",value=1.5,count=1},
        {name="three",value=3,count=3,stop=true}, {name="string",value="3",count=0,bad=true},
        {name="table",value={},count=0,bad=true}, {name="true",value=true,count=0,bad=true},
        {name="inf",value=math.huge,count=0,bad=true}, {name="negative inf",value=-math.huge,count=0,bad=true},
        {name="NaN",value=0/0,count=0,bad=true}}) do
        for _, stopped in ipairs({false,true}) do
            test("immediate capacity " .. case.name .. " with stopped=" .. tostring(stopped),function()
                local env,admin=setup(); env.maxActivators=case.value; local choice=queue(env,admin)
                local timer=env.timers.activatorSpawner; timer.stopped=stopped
                local calls=watch(env); local create=env.ents.Create; local attempts=0
                env.ents.Create=function(class)
                    attempts=attempts+1; assert(attempts<=3,"bounded creation sentinel")
                    return create(class)
                end
                eq(say(env,admin),""); eq(#ready(env),case.count); eq(attempts,case.count)
                eq(calls.timers,case.stop and 1 or 0); eq(timer.stopped,stopped or case.stop == true)
                if case.count>0 then eq(state(env,"pendingSelection"),nil); eq(state(env,"selectedBatchName"),"Ambush")
                else eq(state(env,"pendingSelection"),choice) end
                if case.bad then
                    reply(admin,"capacity is invalid")
                    eq(table.concat(calls.trace,","),"information,position,maximum"); eq(calls.draws,1)
                else reply(admin,"Ready activators: " .. case.count .. " / ") end
            end)
        end
    end
    for _, value in ipairs({false,"true",1,{}}) do
        test("immediate non-true multipleEntities retains one-actor fallback: " .. type(value),function()
            local env,admin=setup(); env.multipleEntities=value; env.maxActivators="ignored"
            say(env,admin); eq(#ready(env),1); reply(admin,"Ready activators: 1 / 1")
        end)
    end
    test("immediate nil multipleEntities retains one-actor fallback",function()
        local env,admin=setup(); env.multipleEntities=nil; say(env,admin); eq(#ready(env),1)
    end)
    for _, mode in ipairs({"full", "partial", "invalid Create"}) do
        for _, path in ipairs({"timer", "command"}) do
            test("immediate extraction preserves exact " .. mode .. " API/RNG order via " .. path,function()
                local env,admin=setup(); local trace={}; local samples,creates=0,0
                local function mark(value) trace[#trace+1]=value end
                local function wrap(owner,key,label)
                    local original=owner[key]; owner[key]=function(...) mark(label); return original(...) end
                end
                wrap(env,"determineRandomEvent","event"); wrap(env,"returnNPCInformation","info")
                wrap(env,"returnMaxActivators","cap"); wrap(env.math,"random","rng")
                local sample=env.returnActivatorSpawns
                env.returnActivatorSpawns=function(...)
                    samples=samples+1; mark("position")
                    if mode=="partial" and samples==2 then return nil end
                    return sample(...)
                end
                local create=env.ents.Create
                env.ents.Create=function(class)
                    creates=creates+1; mark("create"); assert(creates<=3,"bounded finite attempts")
                    if mode=="invalid Create" and creates<=2 then return {valid=false} end
                    local actor=create(class); local set,spawn=actor.SetPos,actor.Spawn
                    actor.SetPos=function(self,pos) mark("set"); return set(self,pos) end
                    actor.Spawn=function(self) mark("spawn"); return spawn(self) end
                    return actor
                end
                wrap(env.timer,"Stop","stop")
                if path=="timer" then env.fireTimer("activatorSpawner") else eq(say(env,admin),"") end
                local prefix="event,rng,info,position,rng,cap,"
                local expected=mode=="full" and ("create,set,spawn,info,position,rng,create,set,spawn,info,position,rng,create,set,spawn,info,position,rng,stop")
                    or mode=="partial" and "create,set,spawn,info,position"
                    or "create,create,create,set,spawn,info,position,rng"
                eq(table.concat(trace,","),prefix .. expected)
                eq(#ready(env),mode=="full" and 3 or 1)
            end)
        end
    end
    for _, path in ipairs({"timer","command"}) do for _, boundary in ipairs({"ready scan","event lookup","Create","Spawn"}) do
        if path=="command" or boundary~="ready scan" then
            test("immediate nested request during " .. path .. " " .. boundary .. " is refused",function()
                local env,admin=setup(); local nested=env.entity("player"); nested.admin=true
                local injected=false
                local function request()
                    if injected then return end; injected=true
                    eq(say(env,nested),""); reply(nested,"another spawn attempt is in flight")
                end
                if boundary=="Spawn" then onceSpawn(env,request)
                else
                    local owner,key=env,"determineRandomEvent"
                    if boundary=="ready scan" then owner,key=env.ents,"FindByClass"
                    elseif boundary=="Create" then owner,key=env.ents,"Create" end
                    local original=owner[key]; owner[key]=function(...) request(); return original(...) end
                end
                if path=="timer" then env.fireTimer("activatorSpawner") else say(env,admin) end
                eq(injected,true); eq(#ready(env),3); eq(#nested.chats,1); eq(state(env,"spawnAttemptDepth"),0)
            end)
        end
    end end
    test("immediate guard preserves ordinary timer reentry",function()
        local env,admin=setup(1); local entered=false; local random=env.determineRandomEvent
        env.determineRandomEvent=function()
            if not entered then entered=true; env.timers.activatorSpawner.callback() end
            return random()
        end
        say(env,admin); eq(entered,true); eq(#ready(env),1); eq(state(env,"spawnAttemptDepth"),0)
    end)
    for _, action in ipairs({"replace","clear","same name","self remove","false return"}) do
        test("immediate exact pending table ownership through Spawn " .. action,function()
            local env,admin=setup(1); local choice=queue(env,admin); local replacement
            local check=onceSpawn(env,function(actor)
                if action=="replace" then replacement=queue(env,admin,"Raid")
                elseif action=="same name" then replacement=queue(env,admin,"Ambush")
                elseif action=="clear" then say(env,admin,"!clearNextEvent")
                elseif action=="self remove" then actor:Remove() end
            end)
            if action=="false return" then
                local create=env.ents.Create; env.ents.Create=function(class)
                    local actor=create(class); local spawn=actor.Spawn
                    actor.Spawn=function(self) spawn(self); return false end; return actor
                end
            end
            say(env,admin); check()
            if action=="self remove" then eq(state(env,"pendingSelection"),choice); eq(state(env,"selectedBatchName"),nil); eq(#ready(env),0)
            else
                eq(state(env,"pendingSelection"),replacement); eq(state(env,"selectedBatchName"),"Ambush")
                eq(ready(env)[1].EventIdentifier,"Ambush")
                if replacement then assert(replacement~=choice,"replacement table identity") end
            end
        end)
    end
    for _, cap in ipairs({1,3}) do for _, action in ipairs({"pause","pause resume","refresh"}) do
        test("immediate Spawn " .. action .. " retires at cap " .. cap .. " without stale work",function()
            local env,admin=setup(cap); queue(env,admin); local calls=watch(env); local snapshot
            local check=onceSpawn(env,function()
                if action=="refresh" then say(env,admin,"!refreshActivators")
                else say(env,admin,"!pauseActivatorSpawns"); if action=="pause resume" then say(env,admin,"!resumeActivatorSpawns") end end
                snapshot={draws=calls.draws,timers=calls.timers,creates=calls.creates,scans=calls.scans}
            end)
            say(env,admin); check(); reply(admin,"interrupted")
            for key,value in pairs(snapshot) do eq(calls[key],value,"no stale " .. key) end
            eq(#ready(env),action=="refresh" and 0 or 1)
            if action=="refresh" then eq(state(env,"selectedBatchName"),nil) else eq(state(env,"selectedBatchName"),"Ambush") end
            if action=="refresh" then assert(state(env,"pendingSelection")) else eq(state(env,"pendingSelection"),nil) end
            eq(env.timers.activatorSpawner.stopped,action=="pause")
        end)
    end end
    for _, cap in ipairs({1,3}) do
        test("immediate actual encounter Start in Spawn retires later work at cap " .. cap,function()
            local env,admin=setup(cap); queue(env,admin); local calls=watch(env); local snapshot
            local check=onceSpawn(env,function(actor)
                admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
                env.receive("SendNPCInformation",admin,"Ambush")
                eq(env.totalEnemies,2); snapshot={draws=calls.draws,timers=calls.timers,creates=calls.creates,scans=calls.scans}
            end)
            say(env,admin); check(); reply(admin,"interrupted")
            for key,value in pairs(snapshot) do eq(calls[key],value,"no work after Start: " .. key) end
            eq(#ready(env),0); eq(env.totalEnemies,2); eq(env.timers.activatorSpawner.stopped,true)
            assert(state(env,"pendingSelection"),"removed actor does not consume pending")
        end)
    end
    for _, stage in ipairs({"Create","SetPos","Spawn","after survivor"}) do for _, path in ipairs({"command","timer"}) do
        test("immediate " .. path .. " preserves errors and releases guard at " .. stage,function()
            local env,admin=setup(); local choice=queue(env,admin); local errorObject=setmetatable({}, {__tostring=function() error("must not serialize error") end})
            local create=env.ents.Create; local attempts=0
            env.ents.Create=function(class)
                attempts=attempts+1
                if stage=="Create" or (stage=="after survivor" and attempts==2) then error(errorObject,0) end
                local actor=create(class)
                if stage=="SetPos" then actor.SetPos=function() error(errorObject,0) end
                elseif stage=="Spawn" then actor.Spawn=function() error(errorObject,0) end end
                return actor
            end
            local timer=env.timers.activatorSpawner; local callback=timer.callback
            if path=="command" then eq(say(env,admin),""); reply(admin,"error"); reply(admin,"actors may remain")
            else local ok,err=pcall(callback); eq(ok,false); assert(rawequal(err,errorObject),"original error identity") end
            eq(state(env,"spawnAttemptDepth"),0); eq(env.timers.activatorSpawner,timer); eq(timer.callback,callback); eq(timer.stopped,false)
            if stage=="after survivor" then eq(state(env,"pendingSelection"),nil); eq(state(env,"selectedBatchName"),"Ambush")
            else eq(state(env,"pendingSelection"),choice) end
            env.ents.Create=create
            eq(say(env,admin),"")
            if stage=="Create" then eq(#ready(env),3); reply(admin,"Ready activators: 3 / 3")
            else eq(#ready(env),1); reply(admin,"ready activator already exists") end
        end)
    end end
    for _, action in ipairs({"throw","disconnect","reenter"}) do
        test("immediate reply " .. action .. " cannot leave a guard or perform late writes",function()
            local env,admin=setup(0); local nested=env.entity("player"); nested.admin=true
            local original=admin.ChatPrint; local entered=false; local resulting
            admin.ChatPrint=function(self,text)
                if entered then return original(self,text) end
                entered=true; eq(state(env,"spawnAttemptDepth"),0,"released before native feedback")
                if action=="throw" then error({secret="not printable"},0)
                elseif action=="disconnect" then self.valid=false; env.fire("PlayerDisconnected",self)
                else
                    env.maxActivators=1; eq(say(env,nested),""); reply(nested,"Ready activators: 1 / 1")
                    resulting=queue(env,nested,"Raid"); say(env,nested,"!pauseActivatorSpawns")
                end
            end
            eq(say(env,admin),""); eq(entered,true); eq(state(env,"spawnAttemptDepth"),0)
            if action=="reenter" then eq(state(env,"pendingSelection"),resulting); eq(#ready(env),1); eq(env.timers.activatorSpawner.stopped,true)
            else env.maxActivators=1; eq(say(env,nested),""); eq(#ready(env),1) end
        end)
    end
    test("immediate disconnected caller after Spawn receives no private delivery attempt",function()
        local env,admin=setup(1); onceSpawn(env,function() admin.valid=false; env.fire("PlayerDisconnected",admin) end)
        eq(say(env,admin),""); eq(#admin.chats,0); eq(#ready(env),1); eq(state(env,"spawnAttemptDepth"),0)
    end)
    test("test accessor finds nested nil and terminates closure cycles",function()
        local wanted; local a,b
        a=function() return b,wanted end; b=function() return a end
        eq(upvalue(b,"wanted"),nil)
        local ok,err=pcall(upvalue,a,"absent"); eq(ok,false); assert(err:find("missing observed upvalue absent",1,true))
    end)
    for _, shape in ipairs({"missing pool","scalar pool","empty pool","wrong map","duplicate map","malformed record",
        "missing list","scalar list","empty list","bad key","nonvector","NaN coordinate","infinite coordinate"}) do
        test("immediate position admission preserves unavailable " .. shape,function()
            local env,admin=setup(); local choice=queue(env,admin); local record=env.SpawnPositions[1]
            if shape=="missing pool" then env.SpawnPositions=nil
            elseif shape=="scalar pool" then env.SpawnPositions=true
            elseif shape=="empty pool" then env.SpawnPositions={}
            elseif shape=="wrong map" then env.map="no_current_map"
            elseif shape=="duplicate map" then env.SpawnPositions[2]={map=env.map,activatorSpawnPositions={env.Vector(1,2,3)}}
            elseif shape=="malformed record" then env.SpawnPositions={false}
            elseif shape=="missing list" then record.activatorSpawnPositions=nil
            elseif shape=="scalar list" then record.activatorSpawnPositions=12
            elseif shape=="empty list" then record.activatorSpawnPositions={}
            elseif shape=="bad key" then record.activatorSpawnPositions={key=env.Vector(1,2,3)}
            elseif shape=="nonvector" then record.activatorSpawnPositions={{x=1,y=2,z=3}}
            elseif shape=="NaN coordinate" then record.activatorSpawnPositions={env.Vector(0/0,2,3)}
            else record.activatorSpawnPositions={env.Vector(math.huge,2,3)} end
            local positions=env.SpawnPositions; local calls=watch(env)
            eq(say(env,admin),""); reply(admin,"no activator positions")
            eq(env.SpawnPositions,positions); eq(state(env,"pendingSelection"),choice)
            eq(#calls.trace,0); eq(calls.draws,0); eq(calls.timers,0); eq(#ready(env),0)
        end)
    end
    test("immediate sparse position list samples only existing positions including the final extra draw",function()
        local env,admin=setup(); local first,second=env.Vector(1,2,3),env.Vector(4,5,6)
        env.SpawnPositions[1].activatorSpawnPositions={[3]=first,[91]=second}
        queue(env,admin); local calls=watch(env); eq(say(env,admin),"")
        eq(calls.draws,4,"initial plus one sample after every valid Create/Spawn")
        for _,actor in ipairs(ready(env)) do assert(actor.pos==first or actor.pos==second) end
        eq(#ready(env),3)
    end)
    for _, stopped in ipairs({false,true}) do
        test("immediate all invalid Create attempts retain position/queue/schedule stopped=" .. tostring(stopped),function()
            local env,admin=setup(); local choice=queue(env,admin); env.failClass="activatorent"
            env.timers.activatorSpawner.stopped=stopped; local calls=watch(env)
            eq(say(env,admin),""); reply(admin,"Ready activators: 0 / 3")
            eq(calls.creates,3); eq(calls.draws,1); eq(calls.timers,0); eq(#ready(env),0)
            eq(table.concat(calls.trace,","),"information,position,maximum,create,create,create")
            eq(state(env,"pendingSelection"),choice); eq(env.timers.activatorSpawner.stopped,stopped)
        end)
        test("immediate partial position exhaustion preserves stopped=" .. tostring(stopped),function()
            local env,admin=setup(); queue(env,admin); env.timers.activatorSpawner.stopped=stopped
            local original=env.returnActivatorSpawns; local samples=0
            env.returnActivatorSpawns=function(...) samples=samples+1; if samples==1 then return original(...) end end
            local calls=watch(env); say(env,admin); reply(admin,"Ready activators: 1 / 3")
            eq(samples,2); eq(calls.creates,1); eq(calls.timers,0); eq(env.timers.activatorSpawner.stopped,stopped)
            eq(state(env,"pendingSelection"),nil)
        end)
    end
    for _, cap in ipairs({1,3}) do
        test("immediate deferred refresh never restores retired ownership at cap " .. cap,function()
            local env,admin=setup(cap); env.deferRemoval=true; local original=queue(env,admin); local actor
            onceSpawn(env,function(current) actor=current; say(env,admin,"!refreshActivators") end)
            say(env,admin); reply(admin,"interrupted"); eq(#ready(env),0)
            eq(actor.valid,true); eq(actor.markedForDeletion,true); eq(state(env,"pendingSelection"),original)
            eq(state(env,"selectedBatchName"),nil); eq(next(state(env,"selectedBatchEntities")),nil)
            eq(env.timers.activatorSpawner.stopped,false)
        end)
    end
    for _, path in ipairs({"command","timer"}) do
        test("immediate " .. path .. " error leaves an already stopped schedule stopped",function()
            local env,admin=setup(); env.timers.activatorSpawner.stopped=true
            local sentinel={}; env.ents.Create=function() error(sentinel,0) end
            local calls=watch(env)
            if path=="command" then eq(say(env,admin),""); reply(admin,"error")
            else local ok,err=pcall(env.timers.activatorSpawner.callback); eq(ok,false); assert(rawequal(err,sentinel)) end
            eq(calls.timers,0); eq(env.timers.activatorSpawner.stopped,true); eq(state(env,"spawnAttemptDepth"),0)
        end)
    end
end
