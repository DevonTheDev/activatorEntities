-- Actual Start receiver with controlled callback/API doubles. SetHealth's
-- documented argument is a number; its native response to other types, NaN,
-- infinities, fractions or out-of-range numbers is not established here.
return function(gmod, test, eq)
    local correction = "Your encounter start was cancelled because the configured enemy health is not a number. Ask an admin to correct the configuration and restart the server."
    local empty = "No enemies could be spawned for your encounter. Ask an admin to check the server console."
    local function upvalue(callback, wanted)
        for i=1,100 do
            local name, value=debug.getupvalue(callback,i)
            if not name then break end
            if name == wanted then return value end
        end
        error("missing observed upvalue " .. wanted)
    end
    local function state(env, name) return upvalue(env.receivers.SendNPCInformation,name) end
    local function notices(ply, text)
        local count=0
        for _, line in ipairs(ply.chats) do if line == text then count=count+1 end end
        return count
    end
    local function successNotices(ply)
        local count=0
        for _, line in ipairs(ply.chats) do
            if line:find("enemies have been spawned",1,true) then count=count+1 end
        end
        return count
    end
    local function lastStatus(env)
        for i=#env.messages,1,-1 do
            if env.messages[i].name == "ActivatorEventStatus" then return env.messages[i].values end
        end
        error("missing status")
    end
    local function prepare(valueFor, deferred, paused)
        local env=gmod.new(); local ply, actor=env.ready(); ply.admin=true
        if paused then env.fire("PlayerSay",ply,"!pauseActivatorSpawns") end
        actor:AcceptInput("Use",ply,ply)
        env.deferRemoval=deferred
        local f={env=env,ply=ply,actor=actor,observer=env.entity("player"),enemies={},trace={},
            attempts=0,samples=0,setters=0,invalidSetters=0,stops=0,timerChanges={}}
        local function trace(stage) f.trace[#f.trace+1]=f.attempts .. ":" .. stage end
        local create=env.ents.Create
        env.ents.Create=function(class)
            if class ~= "npc_stalker" then return create(class) end
            f.attempts=f.attempts+1; trace("Create")
            if f.failedAttempt == f.attempts then return {valid=false} end
            local enemy=create(class); f.enemies[f.attempts]=enemy; f.current=enemy
            for _, name in ipairs({"SetPos","SetName","Spawn"}) do
                local original=enemy[name]
                enemy[name]=function(self,...)
                    trace(name); original(self,...)
                    if name == "Spawn" and f.selfRemoveAttempt == f.attempts then self:Remove() end
                end
            end
            function enemy:SetHealth(value)
                f.setters=f.setters+1; trace("SetHealth")
                if type(value) ~= "number" then
                    f.invalidSetters=f.invalidSetters+1
                    -- Deliberate mock error, not a claim about native SetHealth.
                    error("controlled mock SetHealth received a non-number")
                end
                self.health=value
            end
            local remove=enemy.Remove
            function enemy:Remove()
                self.removeCalls=(self.removeCalls or 0)+1
                if f.onRemoveRequest then f.onRemoveRequest(self) end
                return remove(self)
            end
            if f.onCreate then f.onCreate(enemy,f.attempts) end
            return enemy
        end
        env.returnEnemyHealth=function()
            f.samples=f.samples+1; trace("lookup")
            f.owner=f.owner or state(env,"activeEnemies")
            return valueFor(f.samples,f)
        end
        local stop=env.stopActivatorEvent
        env.stopActivatorEvent=function() f.stops=f.stops+1; return stop() end
        for _, name in ipairs({"Start","Stop","Create","Simple"}) do
            local original=env.timer[name]
            env.timer[name]=function(...)
                f.timerChanges[#f.timerChanges+1]=name
                return original(...)
            end
        end
        function f.start() env.receive("SendNPCInformation",ply,"Raid") end
        return f
    end
    local function inactive(f, paused)
        local env=f.env
        eq(state(env,"eventActive"),false); eq(state(env,"constructingEnemies"),nil)
        eq(state(env,"initialEnemies"),0); eq(state(env,"activeEventName"),nil)
        eq(next(state(env,"activeEnemies")),nil); eq(env.totalEnemies,0)
        eq(env.timers.activatorSpawner.stopped,paused)
        eq(#lastStatus(env),1); eq(lastStatus(env)[1],false)
    end
    local function noOldResult(f)
        eq(f.env.messageCount("roundFinished"),0)
        eq(notices(f.ply,empty),0); eq(#f.env.errors,0)
        eq(f.invalidSetters,0,"non-number must never reach SetHealth")
    end
    local function removed(f)
        for _, enemy in pairs(f.enemies) do
            eq(enemy:IsMarkedForDeletion(),true,"every old candidate has removal requested")
        end
        f.env.flushRemovals()
        for _, enemy in pairs(f.enemies) do eq(enemy.valid,false,"no old survivor") end
    end
    local function retirementTimers(paused, deferred)
        if paused then return "Stop" end
        -- The existing EntityRemoved handler restarts the enabled timer once
        -- for each of the three ready actors flushed while no event is active.
        return deferred and "Stop,Start,Start,Start,Start" or "Stop,Start"
    end
    local function cancelled(f, ordinal, paused, noticeCount)
        eq(f.attempts,ordinal,"no later Create after bad sample")
        eq(f.samples,ordinal,"one sample per eligible candidate, no later sample")
        eq(f.setters,ordinal-1,"only earlier numeric samples reach setter")
        eq(f.stops,1,"retire partial encounter exactly once")
        inactive(f,paused); noOldResult(f)
        eq(successNotices(f.ply),0); eq(notices(f.ply,correction),noticeCount or 1)
        eq(#f.observer.chats,0,"correction is private")
        eq(f.env.messageCount("ActivatorEventStatus"),1,"only inactive status")
        eq(upvalue(f.env.timers.activatorSpawner.callback,"selectedBatchName"),nil,"ready batch consumed")
        removed(f); inactive(f,paused)
        eq(#f.env.ents.FindByClass("activatorent"),0,"ready actors already retired")
        local messages=#f.env.messages; local chats=#f.ply.chats
        f.start()
        eq(f.attempts,ordinal); eq(f.samples,ordinal)
        eq(#f.env.messages,messages); eq(#f.ply.chats,chats,"replay stays silent")
    end
    local function replace(f)
        local env=f.env
        env.NPCEdits[#env.NPCEdits+1]={name="Replacement",information={
            activatorModel="models/alyx.mdl",npcPath="npc_zombie",maxNPCs=2,dialogue="Replacement"}}
        local actor=env.entity("activatorent"); actor.EventIdentifier="Replacement"; actor:Spawn()
        local ply=env.entity("player"); ply:SetPos(actor:GetPos())
        local getter=env.returnEnemyHealth; env.returnEnemyHealth=function() return 100 end
        actor:AcceptInput("Use",ply,ply); env.receive("SendNPCInformation",ply,"Replacement")
        env.returnEnemyHealth=getter
        f.replacement={player=ply,enemies=env.ents.FindByClass("npc_zombie"),owner=state(env,"activeEnemies")}
    end
    local function replacementIntact(f)
        local env=f.env; local replacement=assert(f.replacement,"replacement started")
        eq(state(env,"eventActive"),true); eq(state(env,"activeEventName"),"Replacement")
        eq(state(env,"activeEnemies"),replacement.owner)
        eq(state(env,"constructingEnemies"),nil); eq(state(env,"initialEnemies"),2); eq(env.totalEnemies,2)
        eq(env.timers.activatorSpawner.stopped,true)
        for _, enemy in ipairs(replacement.enemies) do
            eq(enemy.valid,true); eq(enemy:IsMarkedForDeletion(),false)
            eq(replacement.owner[enemy],true)
        end
        local status=lastStatus(env)
        eq(#status,5); eq(status[1],true); eq(status[2],"Replacement")
        eq(status[3],2); eq(status[4],2); eq(status[5],false)
        noOldResult(f)
    end
    local function replayOldHooks(f)
        local env=f.env; local messages=#env.messages; local timerChanges=#f.timerChanges
        for _, enemy in pairs(f.enemies) do
            env.fire("OnNPCKilled",enemy,f.ply); env.fire("EntityRemoved",enemy)
            env.fire("EntityRemoved",enemy); env.fire("OnNPCKilled",enemy,f.ply)
        end
        eq(#env.messages,messages,"old hooks cannot publish replacement progress")
        eq(#f.timerChanges,timerChanges,"old hooks cannot alter replacement timer")
        replacementIntact(f)
    end

    for _, bad in ipairs({{name="nil"},{name="table",value={}}}) do
        for _, ordinal in ipairs({1,2}) do
            for _, deferred in ipairs({false,true}) do
                for _, paused in ipairs({false,true}) do
                    test("health " .. bad.name .. " cancels candidate " .. ordinal .. ", deferred=" .. tostring(deferred) .. ", paused=" .. tostring(paused),function()
                        local f=prepare(function(i) if i == ordinal then return bad.value end return 100 end,deferred,paused)
                        f.onRemoveRequest=function()
                            eq(state(f.env,"eventActive"),false,"retire ownership before cleanup")
                            eq(state(f.env,"constructingEnemies"),nil)
                            eq(f.env.totalEnemies,0); eq(state(f.env,"initialEnemies"),0)
                        end
                        f.start()
                        eq(table.concat(f.timerChanges,","),paused and "Stop" or "Stop,Start","receiver has no late timer write")
                        cancelled(f,ordinal,paused)
                        eq(table.concat(f.timerChanges,","),retirementTimers(paused,deferred),"only existing ready-actor cleanup restarts")
                    end)
                end
            end
        end
    end

    for _, bad in ipairs({{name="numeric string",value="100"},{name="true",value=true},{name="false",value=false},
        {name="table with hostile tostring",value=setmetatable({},{__tostring=function() error("must not serialize health") end})}}) do
        test("health rejects " .. bad.name .. " without serialization",function()
            local f=prepare(function() return bad.value end,false,false)
            f.start(); cancelled(f,1,false)
            eq(f.ply.chats[#f.ply.chats],correction)
        end)
    end

    for _, deferred in ipairs({false,true}) do
        for _, replacing in ipairs({false,true}) do
            test("post-getter ownership wins over bad health, replacement=" .. tostring(replacing) .. ", deferred=" .. tostring(deferred),function()
                local f=prepare(function(i,fixture)
                    if i == 1 then return 100 end
                    eq(fixture.env.stopActivatorEvent(),true)
                    if replacing then replace(fixture) end
                    return nil
                end,deferred,false)
                f.start(); eq(f.attempts,2); eq(f.samples,2); eq(f.setters,1); eq(f.stops,1)
                eq(notices(f.ply,correction),0,"retired getter cannot report health rejection")
                removed(f); noOldResult(f)
                if replacing then replacementIntact(f); replayOldHooks(f)
                else inactive(f,false); eq(successNotices(f.ply),0) end
            end)
        end
        for _, stage in ipairs({"tracked","current"}) do
            for _, paused in ipairs({false,true}) do
                test("health cleanup replacement from " .. stage .. ", deferred=" .. tostring(deferred) .. ", paused=" .. tostring(paused),function()
                    local f=prepare(function(i) if i == 1 then return 100 end return {} end,deferred,paused)
                    local target=stage == "tracked" and 1 or 2
                    f.onCreate=function(enemy,ordinal)
                        if ordinal == target then function enemy:OnRemove() replace(f) end end
                    end
                    f.start(); eq(f.stops,1); eq(f.attempts,2); eq(f.samples,2); eq(f.setters,1)
                    -- Removal of the untracked NPC is still requested even if
                    -- tracked cleanup synchronously installed the replacement.
                    eq(f.enemies[2]:IsMarkedForDeletion(),true)
                    removed(f); replacementIntact(f); replayOldHooks(f)
                    eq(notices(f.ply,correction),1); eq(notices(f.observer,correction),0)
                    eq(successNotices(f.ply),1,"only replacement announces success")
                    eq(f.env.messageCount("ActivatorEventStatus"),2,"old inactive and replacement active only")
                    eq(table.concat(f.timerChanges,","),retirementTimers(paused,deferred) .. ",Stop")
                end)
            end
        end
        for _, action in ipairs({"kill","remove"}) do
            test("earlier tracked " .. action .. " before bad health, deferred=" .. tostring(deferred),function()
                local f=prepare(function(i,fixture)
                    if i == 1 then return 100 end
                    if action == "kill" then fixture.env.fire("OnNPCKilled",fixture.enemies[1],fixture.ply) end
                    fixture.enemies[1]:Remove()
                    eq(state(fixture.env,"eventActive"),true)
                    eq(fixture.env.messageCount("roundFinished"),0)
                    eq(fixture.env.messageCount("ActivatorEventStatus"),0)
                    return nil
                end,deferred,false)
                f.start(); cancelled(f,2,false)
            end)
        end
        test("bad-health candidate self-removes in getter, deferred=" .. tostring(deferred),function()
            local f=prepare(function(_,fixture) fixture.current:Remove(); return nil end,deferred,false)
            f.start(); cancelled(f,1,false)
        end)
        for _, invalidation in ipairs({"getter","tracked cleanup","current cleanup"}) do
            test("health cancellation cleans up an invalid requester in " .. invalidation .. ", deferred=" .. tostring(deferred),function()
                local f=prepare(function(i,fixture)
                    if i == 1 then return 100 end
                    if invalidation == "getter" then fixture.ply.valid=false end
                    return nil
                end,deferred,false)
                -- Invalidate synchronously on the removal request, before the
                -- feedback guard, even when EntityRemoved itself is deferred.
                f.onRemoveRequest=function(enemy)
                    if (invalidation == "tracked cleanup" and enemy == f.enemies[1])
                        or (invalidation == "current cleanup" and enemy == f.enemies[2]) then f.ply.valid=false end
                end
                f.start(); cancelled(f,2,false,0)
            end)
        end
        test("correction ChatPrint callback starts replacement, deferred=" .. tostring(deferred),function()
            local f=prepare(function() return nil end,deferred,false)
            local chat=f.ply.ChatPrint
            function f.ply:ChatPrint(text)
                chat(self,text)
                if text == correction then replace(f) end
            end
            f.start(); eq(f.stops,1); eq(f.attempts,1); eq(f.samples,1); eq(f.setters,0)
            removed(f); replacementIntact(f); replayOldHooks(f)
            eq(notices(f.ply,correction),1); eq(successNotices(f.ply),1)
            eq(f.env.messageCount("ActivatorEventStatus"),2)
            eq(table.concat(f.timerChanges,","),"Stop,Start,Stop","no work after feedback callback")
        end)
        for _, stage in ipairs({"tracked","current"}) do
            for _, paused in ipairs({false,true}) do
                test("health cleanup toggles schedule in " .. stage .. ", deferred=" .. tostring(deferred) .. ", initially paused=" .. tostring(paused),function()
                    local f=prepare(function(i) if i == 1 then return 100 end return nil end,deferred,paused)
                    f.onCreate=function(enemy,ordinal)
                        if ordinal == (stage == "tracked" and 1 or 2) then
                            function enemy:OnRemove()
                                f.env.fire("PlayerSay",f.ply,paused and "!resumeActivatorSpawns" or "!pauseActivatorSpawns")
                            end
                        end
                    end
                    f.start(); eq(f.stops,1); eq(f.attempts,2); eq(f.samples,2); eq(f.setters,1)
                    removed(f); inactive(f,not paused); noOldResult(f)
                    eq(notices(f.ply,correction),1); eq(successNotices(f.ply),0)
                    eq(table.concat(f.timerChanges,","),retirementTimers(paused,deferred) .. (paused and ",Start" or ",Stop"))
                end)
            end
        end
    end

    test("health correction requires a still-valid player",function()
        local f=prepare(function(_,fixture) fixture.ply.class="prop_physics"; return nil end,false,false)
        f.start(); cancelled(f,1,false,0)
    end)

    for _, numeric in ipairs({{name="100",value=100},{name="zero",value=0},{name="negative",value=-25},
        {name="fraction",value=2.75},{name="NaN",value=0/0},{name="positive infinity",value=math.huge},
        {name="negative infinity",value=-math.huge}}) do
        test("number health pass-through and call order: " .. numeric.name,function()
            local f=prepare(function() return numeric.value end,false,false)
            f.start(); eq(f.attempts,5); eq(f.samples,5); eq(f.setters,5); eq(f.stops,0)
            local expected={}
            for i, enemy in ipairs(f.enemies) do
                for _, stage in ipairs({"Create","SetPos","SetName","Spawn","lookup","SetHealth"}) do
                    expected[#expected+1]=i .. ":" .. stage
                end
                if numeric.name == "NaN" then assert(enemy.health ~= enemy.health,"NaN remains NaN")
                else eq(enemy.health,numeric.value) end
            end
            eq(table.concat(f.trace,","),table.concat(expected,","))
            eq(state(f.env,"eventActive"),true); eq(state(f.env,"constructingEnemies"),nil)
            eq(state(f.env,"initialEnemies"),5); eq(f.env.totalEnemies,5)
            eq(notices(f.ply,correction),0); eq(notices(f.ply,empty),0); eq(successNotices(f.ply),1)
            eq(f.env.timers.activatorSpawner.stopped,true); eq(#f.env.errors,0)
            for _, enemy in ipairs(f.enemies) do f.env.fire("OnNPCKilled",enemy,f.ply); enemy:Remove() end
            eq(f.env.messageCount("roundFinished"),1); eq(f.env.totalEnemies,0)
        end)
    end
    for _, deferred in ipairs({false,true}) do
        test("health samples only eligible candidates after failed Create and Spawn self-removal, deferred=" .. tostring(deferred),function()
            local f=prepare(function(i) return i*2.75 end,deferred,false)
            f.failedAttempt=2; f.selfRemoveAttempt=4
            f.start(); eq(f.attempts,5); eq(f.samples,3); eq(f.setters,3); eq(f.stops,0)
            eq(table.concat(f.trace,","),"1:Create,1:SetPos,1:SetName,1:Spawn,1:lookup,1:SetHealth,2:Create,3:Create,3:SetPos,3:SetName,3:Spawn,3:lookup,3:SetHealth,4:Create,4:SetPos,4:SetName,4:Spawn,5:Create,5:SetPos,5:SetName,5:Spawn,5:lookup,5:SetHealth")
            eq(f.enemies[1].health,2.75); eq(f.enemies[3].health,5.5); eq(f.enemies[5].health,8.25)
            eq(f.enemies[4].health,nil)
            eq(state(f.env,"initialEnemies"),3); eq(f.env.totalEnemies,3)
            eq(notices(f.ply,correction),0); eq(successNotices(f.ply),1)
            f.env.flushRemovals(); eq(f.env.totalEnemies,3)
        end)
    end
    for _, paused in ipairs({false,true}) do
        test("health cancellation consumes ready batch and preserves next choice, paused=" .. tostring(paused),function()
            local f=prepare(function() return nil end,false,paused); local env=f.env
            env.NPCEdits[#env.NPCEdits+1]={name="Future",information={
                activatorModel="models/alyx.mdl",npcPath="npc_zombie",maxNPCs=2,dialogue="Future"}}
            eq(env.fire("PlayerSay",f.ply,"!nextEvent Future"),"")
            local pending=upvalue(env.timers.activatorSpawner.callback,"pendingSelection")
            f.start(); cancelled(f,1,paused)
            eq(upvalue(env.timers.activatorSpawner.callback,"pendingSelection"),pending)
            -- Controlled repair only; production config changes require restart.
            env.returnEnemyHealth=function() return 100 end
            if paused then
                env.fireTimer("activatorSpawner"); eq(#env.ents.FindByClass("activatorent"),0)
                env.fire("PlayerSay",f.ply,"!resumeActivatorSpawns")
            end
            env.fireTimer("activatorSpawner")
            local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
            eq(actors[1].EventIdentifier,"Future")
            f.ply:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",f.ply,f.ply)
            env.receive("SendNPCInformation",f.ply,"Future")
            eq(env.totalEnemies,2); eq(state(env,"activeEventName"),"Future")
            for _, enemy in ipairs(env.ents.FindByClass("npc_zombie")) do env.fire("OnNPCKilled",enemy,f.ply); enemy:Remove() end
            eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),1)
            eq(env.timers.activatorSpawner.stopped,false)
        end)
    end
end
