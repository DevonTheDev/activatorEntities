-- Exercise the actual chat hook and lifecycle through API doubles. These tests
-- establish Lua ordering, not native timer delay or entity replication timing.
return function(gmod, test, eq)
    local success="Ready activator removal requested (including manual activators). Normal spawn delay restarted; the next attempt still requires ordinary spawn conditions."
    local refusal="Cannot refresh activators during an active encounter. Finish it or use !stopEvent first."
    local function configured()
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local raid=env.NPCEdits[1].information
        env.NPCEdits[7]={name="Ambush",information={activatorModel=raid.activatorModel,
            npcPath="npc_combine_s",maxNPCs=2,dialogue="An ambush awaits."}}
        env.determineRandomEvent=function() return "Raid" end
        return env,admin
    end
    local function say(env,ply,text) return env.fire("PlayerSay",ply,text) end
    local function queue(env,admin,name) eq(say(env,admin,"!nextEvent " .. name),"") end
    local function selected(env,admin)
        queue(env,admin,"Raid"); env.fireTimer("activatorSpawner")
        return env.ents.FindByClass("activatorent")
    end
    local function private(callback,wanted)
        for i=1,100 do
            local name,value=debug.getupvalue(callback,i)
            if not name then break end
            if name == wanted then return value end
        end
        error("missing private state: " .. wanted)
    end
    local function pending(env) return private(env.timers.activatorSpawner.callback,"pendingSelection") end
    local function pinned(env) return private(env.timers.activatorSpawner.callback,"selectedBatchName") end
    local function open(env,ply,ent)
        ply:SetPos(ent:GetPos()); ent:AcceptInput("Use",ply,ply)
    end
    local function count(env,name)
        local total=0
        for _,ent in ipairs(env.ents.FindByClass("activatorent")) do
            if not ent:IsMarkedForDeletion() then
                if name then eq(ent.EventIdentifier,name) end
                total=total+1
            end
        end
        return total
    end
    local function snapshot(value,seen)
        if type(value) ~= "table" then return value end
        seen=seen or {}; if seen[value] then return seen[value] end
        local result={original=value,entries={}}; seen[value]=result
        for key,child in pairs(value) do result.entries[key]=snapshot(child,seen) end
        return result
    end
    local function retained(before,value,seen)
        if type(before) ~= "table" then eq(value,before); return end
        eq(value,before.original,"retain table identity")
        seen=seen or {}; if seen[before] then return end; seen[before]=true
        local oldCount,newCount=0,0
        for key,child in pairs(before.entries) do oldCount=oldCount+1; retained(child,value[key],seen) end
        for _ in pairs(value) do newCount=newCount+1 end
        eq(newCount,oldCount,"retain table entries")
    end
    -- Refresh may retire actors and restart the named timer, but must not run
    -- spawn, persistence, RNG, enemy cleanup or progress/victory operations.
    local function bounded(env,mutationAllowed,callback)
        local restore={}
        local function forbid(owner,key)
            restore[#restore+1]={owner,key,owner[key]}
            owner[key]=function() error("unexpected command operation: " .. key) end
        end
        env.math=setmetatable({}, {__index=math})
        forbid(env.math,"random")
        for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnActivatorSpawns","returnSpawnPositions","stopActivatorEvent"}) do forbid(env,key) end
        for _,key in ipairs({"Read","Write"}) do forbid(env.file,key) end
        for _,key in ipairs({"TableToJSON","JSONToTable"}) do forbid(env.util,key) end
        for _,key in ipairs({"Start","Send","Broadcast"}) do forbid(env.net,key) end
        for _,key in ipairs({"Create","Stop","Simple"}) do forbid(env.timer,key) end
        forbid(env.ents,"Create")
        if not mutationAllowed then forbid(env.timer,"Start"); forbid(env,"destroyActivators") end
        for _,ent in ipairs(env.entities) do
            forbid(ent,"Spawn")
            if not mutationAllowed or ent:GetClass() ~= "activatorent" then forbid(ent,"Remove") end
        end
        local positions,definitions=snapshot(env.SpawnPositions),snapshot(env.NPCEdits)
        local ok,err=pcall(callback)
        for _,entry in ipairs(restore) do entry[1][entry[2]]=entry[3] end
        assert(ok,err)
        retained(positions,env.SpawnPositions); retained(definitions,env.NPCEdits)
    end
    local function reply(ply,before,expected)
        eq(#ply.chats,before+1,"one private response")
        eq(ply.chats[#ply.chats],expected,"literal command feedback")
        assert(#expected <= 255,"ChatPrint bound")
    end

    test("admin refresh retires the ready actors and restarts the ordinary timer", function()
        local env=gmod.new(); local admin=env.ready(); admin.admin=true
        local timer=env.timers.activatorSpawner
        eq(timer.stopped,true)
        eq(env.fire("PlayerSay",admin,"!refreshActivators"),"","refresh is handled privately")
        eq(#env.ents.FindByClass("activatorent"),0)
        eq(env.timers.activatorSpawner,timer,"keep the ordinary timer")
        eq(timer.stopped,false)
        eq(env.totalEnemies,0)
    end)

    for _,mode in ipairs({"random and manual","selected and manual","manual only"}) do
        test("refresh retires all addon actors from " .. mode .. " without other work",function()
            local env,admin=configured()
            if mode == "selected and manual" then selected(env,admin)
            elseif mode ~= "manual only" then env.fireTimer("activatorSpawner") end
            local manual=env.entity("activatorent"); manual.EventIdentifier="Ambush"; manual:Spawn()
            local other=env.entity("npc_citizen"); other:SetName("devonsSpawnedEntity")
            local observer=env.entity("player")
            queue(env,admin,"Ambush"); local choice=pending(env)
            local before=#admin.chats
            bounded(env,true,function() eq(say(env,admin,"!refreshActivators"),"") end)
            eq(count(env),0); eq(manual.valid,false); eq(other.valid,true)
            eq(pending(env),choice,"exact pending slot survives")
            eq(pinned(env),nil); eq(env.activatorCount,0); eq(env.totalEnemies,0)
            eq(#observer.chats,0); eq(#env.messages,0)
            reply(admin,before,success)
        end)
    end

    test("empty refresh restarts the same configured timer and preserves pending identity",function()
        local env,admin=configured(); queue(env,admin,"Ambush")
        local choice=pending(env); local timer=env.timers.activatorSpawner
        local callback,delay,repetitions=timer.callback,timer.delay,timer.repetitions
        local original=env.timer.Start; local starts=0
        env.timer.Start=function(name) eq(name,"activatorSpawner"); starts=starts+1; original(name) end
        for _,stopped in ipairs({true,false}) do
            timer.stopped=stopped; local before=#admin.chats
            bounded(env,true,function() eq(say(env,admin,"!refreshActivators"),"") end)
            reply(admin,before,success)
            eq(timer.stopped,false); eq(pending(env),choice); eq(count(env),0)
            eq(env.timers.activatorSpawner,timer); eq(timer.callback,callback)
            eq(timer.delay,delay); eq(timer.delay,env.returnDelayBetweenEvents()); eq(timer.repetitions,repetitions)
        end
        eq(starts,2,"each empty request restarts the ordinary delay")
    end)

    for _,suffix in ipairs({" extra"," 1"," ","\t","\nRaid"}) do
        test("refresh rejects extra input " .. string.format("%q",suffix),function()
            local env,admin=configured(); local actors=selected(env,admin)
            queue(env,admin,"Ambush"); local choice=pending(env); open(env,admin,actors[1])
            local before=#admin.chats
            bounded(env,false,function() eq(say(env,admin,"!refreshActivators" .. suffix),"") end)
            reply(admin,before,"Usage: !refreshActivators")
            eq(pending(env),choice); eq(pinned(env),"Raid"); eq(count(env),3)
            eq(env.timers.activatorSpawner.stopped,true)
            env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,5,"refusal retains Use authority")
        end)
    end

    for _,text in ipairs({"!refreshActivatorsNow","!refreshactivators","!RefreshActivators"," !refreshActivators","hello !refreshActivators"}) do
        test("refresh leaves nonmatching chat unchanged: " .. text,function()
            local env,admin=configured(); selected(env,admin); local before=#admin.chats
            bounded(env,false,function() eq(say(env,admin,text),nil) end)
            eq(#admin.chats,before); eq(count(env),3); eq(pinned(env),"Raid")
        end)
    end

    for _,role in ipairs({"nonadmin","nil","invalid","nonplayer"}) do
        test("refresh rejects " .. role .. " callers without lifecycle mutation",function()
            local env,admin=configured(); local actors=selected(env,admin)
            queue(env,admin,"Ambush"); local choice=pending(env); open(env,admin,actors[1])
            local caller
            if role == "nonadmin" then caller=env.entity("player")
            elseif role == "invalid" then caller={valid=false}
            elseif role == "nonplayer" then caller=env.entity("worldspawn"); caller.admin=true end
            bounded(env,false,function()
                eq(say(env,caller,"!refreshActivators"),role == "nonadmin" and "" or nil)
            end)
            if role == "nonadmin" then reply(caller,0,"Only admins can refresh activators.") end
            eq(pending(env),choice); eq(pinned(env),"Raid"); eq(count(env),3)
            eq(env.timers.activatorSpawner.stopped,true)
            env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,5)
        end)
    end

    test("refresh refuses an active encounter without changing progress or pending choice",function()
        local env,admin=configured(); local actors=selected(env,admin)
        open(env,admin,actors[1]); env.receive("SendNPCInformation",admin,"Raid")
        local enemies=env.ents.FindByName("devonsSpawnedEntity")
        env.fire("OnNPCKilled",enemies[1],admin); queue(env,admin,"Ambush")
        local choice=pending(env); local before=#admin.chats; local messages=#env.messages
        bounded(env,false,function() eq(say(env,admin,"!refreshActivators"),"") end)
        reply(admin,before,refusal); eq(pending(env),choice); eq(env.totalEnemies,4)
        eq(#env.messages,messages); eq(env.timers.activatorSpawner.stopped,true)
        for i=2,#enemies do env.fire("OnNPCKilled",enemies[i],admin) end
        eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),1)
        env.fireTimer("activatorSpawner"); eq(count(env,"Ambush"),3)
    end)

    for _,boundary in ipairs({"activator removal","enemy creation","enemy Spawn"}) do
        test("refresh refuses during encounter construction at " .. boundary,function()
            local env,admin=configured(); local actors=selected(env,admin); queue(env,admin,"Ambush")
            local choice=pending(env); local checked=false
            local function attempt()
                if checked then return end; checked=true
                local before=#admin.chats; local enemies=env.totalEnemies
                bounded(env,false,function() eq(say(env,admin,"!refreshActivators"),"") end)
                reply(admin,before,refusal); eq(env.totalEnemies,enemies)
                eq(pending(env),choice); eq(env.timers.activatorSpawner.stopped,true)
            end
            if boundary == "activator removal" then
                for _,ent in ipairs(actors) do
                    local remove=ent.Remove
                    ent.Remove=function(self) attempt(); remove(self) end
                end
            else
                local create=env.ents.Create
                env.ents.Create=function(class)
                    local ent=create(class)
                    if class == "npc_stalker" then
                        if boundary == "enemy creation" then attempt()
                        else local spawn=ent.Spawn; ent.Spawn=function(self) attempt(); spawn(self) end end
                    end
                    return ent
                end
            end
            open(env,admin,actors[1]); env.receive("SendNPCInformation",admin,"Raid")
            eq(checked,true); eq(env.totalEnemies,5); eq(env.messageCount("roundFinished"),0)
            eq(#env.ents.FindByName("devonsSpawnedEntity"),5)
            for _,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do env.fire("OnNPCKilled",enemy,admin) end
            eq(env.messageCount("roundFinished"),1)
        end)
    end

    for _,deferred in ipairs({false,true}) do
        test("refresh clears every old Start and Cancel before first Remove with deferred " .. tostring(deferred),function()
            local env,admin=configured(); local actors=selected(env,admin); env.deferRemoval=deferred
            local people={admin,env.entity("player"),env.entity("player")}
            for i,ply in ipairs(people) do open(env,ply,actors[i]) end
            queue(env,admin,"Ambush"); local checked=false; local replacementChoice
            for _,ent in ipairs(actors) do
                local remove=ent.Remove
                ent.Remove=function(self)
                    if not checked then
                        checked=true; eq(self:IsMarkedForDeletion(),false,"before native removal marking")
                        eq(pinned(env),nil,"old selected authority already retired")
                        for i,ply in ipairs(people) do
                            if i ~= 2 then env.receive("SendNPCInformation",ply,"Raid") end
                            env.receive("CloseInteractionMenu",ply,actors[i])
                            eq(actors[i].moveChanges,nil,"old Cancel has no movement authority")
                            if i == 2 then env.receive("SendNPCInformation",ply,"Raid") end
                        end
                        eq(env.totalEnemies,0,"no old Start can construct enemies")
                        queue(env,admin,"Raid") -- Reentrant newer choice must survive the outer command.
                        replacementChoice=pending(env)
                    end
                    remove(self)
                end
            end
            eq(say(env,admin,"!refreshActivators"),""); eq(checked,true)
            eq(pending(env),replacementChoice); eq(pending(env).name,"Raid"); eq(env.totalEnemies,0); eq(count(env),0)
            eq(env.timers.activatorSpawner.stopped,false)
            for _,ent in ipairs(actors) do eq(ent.valid,deferred); eq(ent:IsMarkedForDeletion(),true) end
            env.fireTimer("activatorSpawner"); eq(count(env,"Raid"),3); eq(pinned(env),"Raid")
            env.flushRemovals(); eq(count(env,"Raid"),3); eq(pinned(env),"Raid","late old removal retains new selected batch")
            eq(pending(env),nil)
        end)
    end

    test("repeated refresh from different admins retires only each current ready batch",function()
        local env,admin=configured(); selected(env,admin); env.deferRemoval=true
        local other=env.entity("player"); other.admin=true; queue(env,admin,"Ambush")
        local choice=pending(env)
        for _,ply in ipairs({admin,other,admin}) do
            eq(say(env,ply,"!refreshActivators"),""); eq(pending(env),choice); eq(count(env),0)
        end
        env.fireTimer("activatorSpawner"); eq(count(env,"Ambush"),3)
        eq(say(env,other,"!refreshActivators"),""); eq(count(env),0)
        env.fireTimer("activatorSpawner"); eq(count(env,"Raid"),3); eq(pinned(env),nil)
        env.flushRemovals(); eq(count(env,"Raid"),3)
    end)

    test("refresh without pending selection releases the selected name for normal random spawning",function()
        local env,admin=configured(); selected(env,admin); local randomCalls=0
        env.determineRandomEvent=function() randomCalls=randomCalls+1; return "Ambush" end
        eq(say(env,admin,"!refreshActivators"),""); eq(randomCalls,0); eq(pinned(env),nil)
        env.fireTimer("activatorSpawner"); eq(count(env,"Ambush"),3); eq(randomCalls,1)
        eq(pinned(env),nil); eq(pending(env),nil)
    end)

    for _,blocked in ipairs({"minimum players","missing map","missing positions","zero capacity","invalid definition","failed creation","self removal"}) do
        test("refresh preserves ordinary retry after " .. blocked,function()
            local env,admin=configured(); selected(env,admin); queue(env,admin,"Ambush")
            local choice=pending(env); local positions=env.SpawnPositions[1].activatorSpawnPositions
            local information=env.NPCEdits[7].information; local create=env.ents.Create
            if blocked == "minimum players" then env.minNumberOfPlayers=2
            elseif blocked == "missing map" then env.map="missing"
            elseif blocked == "missing positions" then env.SpawnPositions[1].activatorSpawnPositions={}
            elseif blocked == "zero capacity" then env.maxActivators=0
            elseif blocked == "invalid definition" then env.NPCEdits[7].information=nil
            elseif blocked == "failed creation" then env.failClass="activatorent"
            else
                env.deferRemoval=true
                env.ents.Create=function(class)
                    local ent=create(class)
                    if class == "activatorent" then ent.Spawn=function(self) self:Remove() end end
                    return ent
                end
            end
            eq(say(env,admin,"!refreshActivators"),""); eq(pending(env),choice); eq(count(env),0)
            env.fireTimer("activatorSpawner"); eq(count(env),0); eq(pending(env),choice); eq(pinned(env),nil)
            eq(env.timers.activatorSpawner.stopped,false)
            env.minNumberOfPlayers=0; env.map="gm_construct"; env.maxActivators=3; env.failClass=nil
            env.SpawnPositions[1].activatorSpawnPositions=positions; env.NPCEdits[7].information=information
            env.ents.Create=create
            env.fireTimer("activatorSpawner"); eq(count(env,"Ambush"),3); eq(pending(env),nil)
        end)
    end
end
