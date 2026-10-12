-- Trusted-configuration policy tests through real timer, Use and Start handlers.
-- The general Create double is permissive: no native non-string failure is
-- invented. Empty/unknown strings explicitly model Create returning invalid.
return function(gmod, test, eq)
    local correction="This encounter has an invalid enemy class. Ask an admin to correct the configuration and restart the server."
    local expired="This interaction expired. Use the activator again."
    local missing="No enemy spawn position is available. Ask an admin to fix it, then use the activator again."
    local badCount="This encounter has an invalid enemy count. Ask an admin to correct the configuration and restart the server."
    local empty="No enemies could be spawned for your encounter. Ask an admin to check the server console."
    local function status(env, admin)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,"!eventStatus"),"")
        local lines={}
        for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        return table.concat(lines,"\n")
    end
    local function contains(text, expected) assert(text:find(expected,1,true),"missing status: " .. expected) end
    local function setup(class, schedule)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local ply=env.entity("player"); local observer=env.entity("player")
        local info={activatorModel=env.NPCEdits[1].information.activatorModel,
            npcPath=class,maxNPCs=2.75,dialogue="An ambush awaits."}
        env.NPCEdits[7]={name="Ambush",information=info}
        eq(env.fire("PlayerSay",admin,"!nextEvent Ambush"),"")
        local create=env.ents.Create; local attempts=0
        if schedule == "running" then
            env.ents.Create=function(value)
                if value == "activatorent" then
                    attempts=attempts+1
                    if attempts == 3 then return {valid=false} end
                end
                return create(value)
            end
        end
        env.fireTimer("activatorSpawner"); env.ents.Create=create
        local actors=env.ents.FindByClass("activatorent")
        eq(#actors,schedule == "running" and 2 or 3)
        eq(env.fire("PlayerSay",admin,"!nextEvent Raid"),"")
        if schedule == "paused" then eq(env.fire("PlayerSay",admin,"!pauseActivatorSpawns"),"") end
        eq(env.timers.activatorSpawner.stopped,schedule ~= "running")
        ply:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",ply,ply)
        return env,ply,info,actors,admin,observer
    end
    local function watch(env, actors)
        local calls={creates=0,removes=0,health=0,setHealth=0,timers=0,reads=0,writes=0,random=0}
        local create=env.ents.Create
        env.ents.Create=function(value)
            calls.creates=calls.creates+1
            local ent=create(value)
            if env.IsValid(ent) then
                local setter=ent.SetHealth
                ent.SetHealth=function(self,...) calls.setHealth=calls.setHealth+1; return setter(self,...) end
            end
            return ent
        end
        for _,ent in ipairs(actors) do
            local remove=ent.Remove
            ent.Remove=function(self,...) calls.removes=calls.removes+1; return remove(self,...) end
        end
        local health=env.returnEnemyHealth
        env.returnEnemyHealth=function(...) calls.health=calls.health+1; return health(...) end
        for _,key in ipairs({"Start","Stop","Create","Simple"}) do
            local original=env.timer[key]
            env.timer[key]=function(...) calls.timers=calls.timers+1; return original(...) end
        end
        for _,key in ipairs({"Read","Write"}) do
            local original=env.file[key]; local field=key == "Read" and "reads" or "writes"
            env.file[key]=function(...) calls[field]=calls[field]+1; return original(...) end
        end
        env.math=setmetatable({}, {__index=math})
        env.math.random=function(...) calls.random=calls.random+1; return math.random(...) end
        return calls
    end
    local function snapshot(env,admin,actors)
        local text=status(env,admin)
        contains(text,'Selected ready batch: "Ambush"'); contains(text,'Pending next batch: "Raid"')
        contains(text,"Active event: none")
        local timer=env.timers.activatorSpawner
        local state={text=text,timer=timer,stopped=timer.stopped,delay=timer.delay,repetitions=timer.repetitions,
            callback=timer.callback,messages=#env.messages,errors=#env.errors,count=env.activatorCount,
            definitions=env.NPCEdits,positions=env.SpawnPositions,chats={},actors={}}
        for _,player in ipairs(env.player.GetAll()) do state.chats[player]=#player.chats end
        for _,actor in ipairs(actors) do
            state.actors[actor]={info=actor.NPCInfo,identifier=actor.EventIdentifier,model=actor:GetModel(),pos=actor:GetPos()}
        end
        return state
    end
    local function retained(env,ply,info,actors,admin,calls,state,notice,draws,diagnostics)
        for player,count in pairs(state.chats) do
            eq(#player.chats,count+(player == ply and notice and 1 or 0),"private once-only feedback")
        end
        if notice then eq(ply.chats[#ply.chats],notice) end
        eq(status(env,admin),state.text,"ready selection and queued choice retained")
        eq(env.NPCEdits,state.definitions); eq(env.SpawnPositions,state.positions)
        eq(env.activatorCount,state.count); eq(env.totalEnemies,0)
        eq(#env.ents.FindByName("devonsSpawnedEntity"),0)
        eq(#env.ents.FindByClass("activatorent"),#actors)
        for actor,old in pairs(state.actors) do
            eq(env.IsValid(actor),true); eq(actor:IsMarkedForDeletion(),false)
            eq(actor.NPCInfo,old.info); eq(actor.NPCInfo,info)
            eq(actor.EventIdentifier,old.identifier); eq(actor:GetModel(),old.model); eq(actor:GetPos(),old.pos)
        end
        eq(env.timers.activatorSpawner,state.timer); eq(state.timer.stopped,state.stopped)
        eq(state.timer.delay,state.delay); eq(state.timer.repetitions,state.repetitions); eq(state.timer.callback,state.callback)
        eq(#env.messages,state.messages); eq(#env.errors,state.errors+(diagnostics or 0))
        eq(calls.creates,0); eq(calls.removes,0); eq(calls.health,0); eq(calls.setHealth,0)
        eq(calls.timers,0); eq(calls.reads,0); eq(calls.writes,0); eq(calls.random,draws)
    end
    local function rejection(value,schedule)
        local env,ply,info,actors,admin=setup(value,schedule)
        local state=snapshot(env,admin,actors); local calls=watch(env,actors)
        env.receive("SendNPCInformation",ply,"Ambush")
        retained(env,ply,info,actors,admin,calls,state,correction,1)
        assert(info.npcPath == value,"class must remain unchanged without serialization")
        eq(info.maxNPCs,2.75)
        -- A controlled fixture repair is not support for live configuration reload.
        info.npcPath="npc_combine_s"
        local chats=#ply.chats
        env.receive("SendNPCInformation",ply,"Ambush")
        eq(#ply.chats,chats); eq(calls.creates,0); eq(calls.random,1)
        eq(status(env,admin),state.text,"consumed replay cannot activate repaired configuration")
        actors[1]:AcceptInput("Use",ply,ply)
        env.receive("SendNPCInformation",ply,"Ambush")
        local enemies=env.ents.FindByName("devonsSpawnedEntity")
        eq(#enemies,2); eq(env.totalEnemies,2); eq(calls.creates,2); eq(calls.random,2)
        eq(#env.ents.FindByClass("activatorent"),0); eq(calls.health,2); eq(calls.setHealth,2)
        contains(status(env,admin),'Pending next batch: "Raid"')
        for _,enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,ply) end
        eq(env.messageCount("roundFinished"),1)
        eq(env.timers.activatorSpawner.stopped,schedule == "paused")
        if schedule == "paused" then
            env.fireTimer("activatorSpawner"); eq(#env.ents.FindByClass("activatorent"),0)
            env.fire("PlayerSay",admin,"!resumeActivatorSpawns")
        end
        env.fireTimer("activatorSpawner")
        eq(#env.ents.FindByClass("activatorent"),3)
        for _,actor in ipairs(env.ents.FindByClass("activatorent")) do eq(actor.EventIdentifier,"Raid") end
    end
    for _,case in ipairs({
        {"missing",nil},{"boolean",false},{"number",17},
        {"hostile table",setmetatable({}, {__tostring=function() error("must not serialize class") end})},
        {"function",function() error("must not call class") end},
        {"thread",coroutine.create(function() error("must not resume class") end)}
    }) do
        test("non-string class retains readiness and permits fresh Use: " .. case[1],function()
            rejection(case[2],"capacity")
        end)
    end
    for _,schedule in ipairs({"running","paused"}) do
        test("class rejection preserves schedule and future selection: " .. schedule,function()
            rejection(false,schedule)
        end)
    end
    for _,action in ipairs({"Start","Cancel"}) do
        test("class rejection preserves another player's existing " .. action .. " grant",function()
            local env,ply,info,actors,admin,other=setup(false,"capacity")
            other:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",other,other)
            env.receive("SendNPCInformation",ply,"Ambush")
            eq(ply.chats[#ply.chats],correction); eq(#other.chats,0)
            info.npcPath="npc_combine_s"
            if action == "Cancel" then
                local before=actors[1].moveChanges or 0
                env.receive("CloseInteractionMenu",other,actors[1])
                eq(actors[1].moveChanges,before+1,"other grant still authorizes Cancel")
            end
            env.receive("SendNPCInformation",other,"Ambush")
            eq(env.totalEnemies,action == "Start" and 2 or 0)
            if action == "Cancel" then eq(#other.chats,0); eq(#env.ents.FindByClass("activatorent"),3) end
        end)
    end
    for _,gate in ipairs({"expiry","spawn position","count"}) do
        test("existing Start validation precedes class admission: " .. gate,function()
            local env,ply,info,actors,admin=setup(false,"capacity")
            local reads=0
            info.npcPath=nil
            setmetatable(info,{__index=function(_,key) if key == "npcPath" then reads=reads+1; return false end end})
            info.maxNPCs="2"
            if gate == "expiry" then env.now=61 end
            if gate ~= "count" then env.SpawnPositions[1].enemySpawnPositions={} end
            local state=snapshot(env,admin,actors); local calls=watch(env,actors)
            env.receive("SendNPCInformation",ply,"Ambush")
            retained(env,ply,info,actors,admin,calls,state,
                gate == "expiry" and expired or gate == "spawn position" and missing or badCount,
                gate == "count" and 1 or 0,gate == "spawn position" and 1 or 0)
            eq(reads,0,"earlier rejection must not read class")
        end)
    end
    for _,reason in ipairs({"unissued","mismatched","cancelled","dead","distant"}) do
        test("unauthorized Start stays silent before class admission: " .. reason,function()
            local env,ply,info,actors,admin,other=setup(false,"capacity")
            local identifier="Ambush"
            if reason == "unissued" then ply=other
            elseif reason == "mismatched" then identifier="Raid"
            elseif reason == "cancelled" then env.receive("CloseInteractionMenu",ply,actors[1])
            elseif reason == "dead" then ply.alive=false
            elseif reason == "distant" then ply:SetPos(env.Vector(100000,0,0)) end
            local state=snapshot(env,admin,actors); local calls=watch(env,actors)
            env.receive("SendNPCInformation",ply,identifier)
            retained(env,ply,info,actors,admin,calls,state,nil,0)
        end)
    end
    test("inherited class and fractional count remain valid without rewriting configuration",function()
        local env,ply,info,actors=setup("npc_combine_s","capacity")
        local inherited={npcPath=info.npcPath,maxNPCs=info.maxNPCs}
        info.npcPath=nil; info.maxNPCs=nil; setmetatable(info,{__index=inherited})
        local calls=watch(env,actors)
        env.receive("SendNPCInformation",ply,"Ambush")
        eq(env.totalEnemies,2); eq(calls.creates,2)
        eq(rawget(info,"npcPath"),nil); eq(rawget(info,"maxNPCs"),nil)
        for _,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do eq(enemy:GetClass(),inherited.npcPath) end
    end)
    test("numeric string class reaches Create unchanged",function()
        local env,ply,info,actors=setup("123","capacity")
        local create=env.ents.Create; local attempts=0
        env.ents.Create=function(value) attempts=attempts+1; eq(value,"123"); return create(value) end
        env.receive("SendNPCInformation",ply,"Ambush")
        eq(attempts,2); eq(env.totalEnemies,2); eq(info.npcPath,"123")
    end)
    for _,case in ipairs({{"empty",""},{"unknown","npc_nonexistent_fixture"}}) do
        test("string class retains modeled Create failure lifecycle: " .. case[1],function()
            local env,ply,info,actors,admin,observer=setup(case[2],"capacity")
            local attempts,health=0,0
            env.ents.Create=function(value) attempts=attempts+1; eq(value,case[2]); return {valid=false} end
            env.returnEnemyHealth=function() health=health+1; return 100 end
            env.receive("SendNPCInformation",ply,"Ambush")
            eq(attempts,2); eq(health,0); eq(env.totalEnemies,0)
            eq(#env.ents.FindByClass("activatorent"),0); eq(#ply.chats,1); eq(ply.chats[1],empty)
            eq(#observer.chats,0); eq(env.timers.activatorSpawner.stopped,false)
            eq(env.messageCount("roundFinished"),0); eq(#env.errors,1)
            contains(status(env,admin),'Selected ready batch: none'); contains(status(env,admin),'Pending next batch: "Raid"')
            env.receive("SendNPCInformation",ply,"Ambush"); eq(attempts,2); eq(#ply.chats,1)
        end)
    end
    test("valid class mutation remains visible to each creation attempt",function()
        local env,ply,info=setup("npc_combine_s","capacity")
        local create=env.ents.Create; local classes={}
        env.ents.Create=function(value)
            classes[#classes+1]=value
            local enemy=create(value); local spawn=enemy.Spawn
            enemy.Spawn=function(self,...) info.npcPath="npc_zombie"; return spawn(self,...) end
            return enemy
        end
        env.receive("SendNPCInformation",ply,"Ambush")
        eq(#classes,2); eq(classes[1],"npc_combine_s"); eq(classes[2],"npc_zombie"); eq(env.totalEnemies,2)
    end)
    test("class admission adds one uncached inherited getter read before construction",function()
        local env,ply,info,actors=setup("npc_combine_s","capacity")
        local reads,creates=0,0; local create=env.ents.Create
        info.npcPath=nil
        setmetatable(info,{__index=function(_,key)
            if key == "npcPath" then
                reads=reads+1
                if reads == 1 then
                    eq(#env.ents.FindByClass("activatorent"),3,"admission reads before ready removal")
                    eq(env.totalEnemies,0); return "npc_admission_only"
                end
                return reads == 2 and "npc_combine_s" or "npc_zombie"
            end
        end})
        env.ents.Create=function(value)
            creates=creates+1
            eq(value,creates == 1 and "npc_combine_s" or "npc_zombie")
            return create(value)
        end
        env.receive("SendNPCInformation",ply,"Ambush")
        eq(reads,3); eq(creates,2); eq(env.totalEnemies,2)
    end)
end
