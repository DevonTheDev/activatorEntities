-- Exactly 36 conditional custom-getter cases through the registered Start
-- receiver. Lua callbacks deliberately reenter or throw; entity methods retain
-- the existing doubles. This does not establish native GMod error/removal timing.
return function(gmod, test, eq)
    local upvalue = dofile("tests/find-upvalue.lua")
    local function state(env, name) return upvalue(env.receivers.SendNPCInformation, name) end
    local function selection(env, name) return upvalue(env.timers.activatorSpawner.callback, name) end
    local function hostile()
        return setmetatable({}, {__tostring=function() error("must not serialize the original error") end})
    end
    local function prepare(ordinal, deferred, paused, payload)
        local env=gmod.new(); local ply=env.entity("player"); ply.admin=true
        for _, name in ipairs({"Replacement", "Future"}) do
            env.NPCEdits[#env.NPCEdits+1]={name=name, information={
                activatorModel="models/alyx.mdl", npcPath="npc_zombie", maxNPCs=2, dialogue=name}}
        end
        env.fire("PlayerSay", ply, "!nextEvent Raid")
        env.fireTimer("activatorSpawner")
        local actor=assert(env.ents.FindByClass("activatorent")[1])
        env.fire("PlayerSay", ply, "!nextEvent Future")
        if paused then env.fire("PlayerSay", ply, "!pauseActivatorSpawns") end
        ply:SetPos(actor:GetPos()); actor:AcceptInput("Use", ply, ply)
        env.deferRemoval=deferred
        local f={env=env, ply=ply, actor=actor, enemies={}, samples=0, setters=0, attempts=0,
            payload=payload, timerChanges={}, trace={}, random=0, chatsBefore=#ply.chats,
            pending=selection(env,"pendingSelection"), observer=env.entity("player")}
        local function trace(stage) f.trace[#f.trace+1]=f.attempts .. ":" .. stage end
        local create=env.ents.Create
        env.ents.Create=function(class)
            local enemy=create(class)
            if class ~= "npc_stalker" then return enemy end
            f.attempts=f.attempts+1; f.enemies[f.attempts]=enemy; trace("Create")
            for _, name in ipairs({"SetPos", "SetName", "Spawn", "SetHealth"}) do
                local original=enemy[name]
                enemy[name]=function(self, ...)
                    trace(name)
                    if name == "SetHealth" then f.setters=f.setters+1 end
                    return original(self, ...)
                end
            end
            local remove=enemy.Remove
            function enemy:Remove()
                self.removeRequests=(self.removeRequests or 0)+1
                if f.onRemoveRequest then f.onRemoveRequest(self) end
                return remove(self)
            end
            if f.onCreate then f.onCreate(enemy, f.attempts) end
            return enemy
        end
        env.returnEnemyHealth=function()
            f.samples=f.samples+1; trace("lookup")
            f.owner=f.owner or state(env,"activeEnemies")
            if f.samples ~= ordinal then return 100 end
            eq(state(env,"constructingEnemies"), f.owner)
            f.oldInspections={}
            for _, name in ipairs({"enemyHealthRequests", "enemyMarkerCaptures", "enemyMarkerGrants",
                "enemyInspections", "enemyRemovalRequests"}) do
                local captured=state(env,name)
                captured[ply]={controlledStaleEntry=true}
                f.oldInspections[name]=captured
            end
            if f.beforeThrow then f.beforeThrow() end
            error(f.payload, 0)
        end
        for _, name in ipairs({"Start", "Stop", "Create", "Simple"}) do
            local original=env.timer[name]
            env.timer[name]=function(...)
                f.timerChanges[#f.timerChanges+1]=name
                return original(...)
            end
        end
        env.math=setmetatable({}, {__index=math})
        env.math.random=function(...) f.random=f.random+1; return math.random(...) end
        function f.start() env.receive("SendNPCInformation", ply, "Raid") end
        function f.throw()
            local ok, result=pcall(f.start)
            eq(ok, false, "getter failure must still propagate")
            -- Never hand the arbitrary payload to eq's eager diagnostic tostring.
            assert(rawequal(result, f.payload), "original error object changed")
            eq(f.attempts, ordinal, "no subsequent old candidate")
            eq(f.samples, ordinal, "one lookup per eligible old candidate")
            eq(f.setters, ordinal-1, "failing candidate never reaches setter")
            local expected={}
            for i=1,ordinal do
                for _, stage in ipairs({"Create", "SetPos", "SetName", "Spawn", "lookup"}) do
                    expected[#expected+1]=i .. ":" .. stage
                end
                if i < ordinal then expected[#expected+1]=i .. ":SetHealth" end
            end
            eq(table.concat(f.trace,","), table.concat(expected,","), "old API order")
        end
        return f
    end
    local function retired(f, paused)
        local env=f.env
        eq(state(env,"eventActive"),false); eq(state(env,"constructingEnemies"),nil)
        eq(state(env,"activeEventName"),nil); eq(state(env,"initialEnemies"),0); eq(env.totalEnemies,0)
        eq(next(state(env,"activeEnemies")),nil)
        eq(env.timers.activatorSpawner.stopped,paused)
        for _, name in ipairs({"enemyHealthRequests", "enemyMarkerCaptures", "enemyMarkerGrants",
            "enemyInspections", "enemyRemovalRequests"}) do
            local current=state(env,name)
            eq(next(current),nil,name .. " retired")
            if f.oldInspections then assert(current ~= f.oldInspections[name],name .. " ownership retired") end
        end
    end
    local function noOldResult(f, replacement)
        eq(f.env.messageCount("roundFinished"),0,"no old victory")
        eq(f.env.messageCount("entitiesDeleted"),0,"no all-removed claim")
        eq(#f.env.errors,0,"no failure serialization/empty-result diagnostic")
        local successes=0
        for i=f.chatsBefore+1,#f.ply.chats do
            local line=f.ply.chats[i]
            assert(not line:find("health is not a number",1,true),"exception is not non-number feedback")
            assert(not line:find("No enemies could be spawned",1,true),"exception is not empty-result feedback")
            if line:find("enemies have been spawned",1,true) then successes=successes+1 end
        end
        eq(successes,replacement and 1 or 0,"only replacement can announce success")
    end
    local function removed(f)
        for _, enemy in ipairs(f.enemies) do
            eq(enemy:IsMarkedForDeletion(),true,"old candidate removal requested")
        end
        f.env.flushRemovals()
        for _, enemy in ipairs(f.enemies) do eq(enemy.valid,false,"old candidate removed by double") end
    end
    local function quietReplay(f)
        local messages=#f.env.messages; local chats=#f.ply.chats
        local timers=#f.timerChanges; local attempts=f.attempts; local random=f.random
        f.start()
        eq(#f.env.messages,messages); eq(#f.ply.chats,chats)
        eq(#f.timerChanges,timers); eq(f.attempts,attempts); eq(f.random,random)
        for _, enemy in ipairs(f.enemies) do
            f.env.fire("OnNPCKilled",enemy,f.ply); f.env.fire("EntityRemoved",enemy)
            f.env.fire("EntityRemoved",enemy); f.env.fire("OnNPCKilled",enemy,f.ply)
        end
        eq(#f.env.messages,messages,"old hooks cannot publish stale progress")
        eq(#f.timerChanges,timers,"old hooks cannot change timer")
    end
    local function recover(f, paused)
        local env=f.env
        eq(selection(env,"pendingSelection"),f.pending,"future queue preserved")
        env.returnEnemyHealth=function() return 100 end
        if paused then
            env.fireTimer("activatorSpawner")
            eq(#env.ents.FindByClass("activatorent"),0)
            env.fire("PlayerSay",f.ply,"!resumeActivatorSpawns")
        end
        env.fireTimer("activatorSpawner")
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
        eq(actors[1].EventIdentifier,"Future")
        f.ply:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",f.ply,f.ply)
        env.receive("SendNPCInformation",f.ply,"Future")
        eq(state(env,"activeEventName"),"Future"); eq(env.totalEnemies,2)
        for _, enemy in ipairs(env.ents.FindByClass("npc_zombie")) do
            env.fire("OnNPCKilled",enemy,f.ply); enemy:Remove()
        end
        env.flushRemovals()
        eq(env.messageCount("roundFinished"),1); retired(f,false)
    end
    local function replace(f, kind)
        local env=f.env
        if kind == "event" then
            local actor=env.entity("activatorent"); actor.EventIdentifier="Replacement"; actor:Spawn()
            local ply=env.entity("player"); ply:SetPos(actor:GetPos())
            local getter=env.returnEnemyHealth; env.returnEnemyHealth=function() return 100 end
            actor:AcceptInput("Use",ply,ply); env.receive("SendNPCInformation",ply,"Replacement")
            env.returnEnemyHealth=getter
            f.replacement={kind=kind, owner=state(env,"activeEnemies"), enemies=env.ents.FindByClass("npc_zombie")}
        else
            env.fire("PlayerSay",f.ply,"!nextEvent Replacement")
            env.timers.activatorSpawner.callback()
            local actors={}
            for _, actor in ipairs(env.ents.FindByClass("activatorent")) do
                if not actor:IsMarkedForDeletion() then actors[#actors+1]=actor end
            end
            eq(#actors,3)
            f.replacement={kind=kind, actors=actors, owner=selection(env,"selectedBatchEntities")}
        end
        -- A new command's distinct pending-selection object must also survive.
        env.fire("PlayerSay",f.ply,"!nextEvent Future")
        f.replacement.pending=selection(env,"pendingSelection")
        f.replacement.timer=env.timers.activatorSpawner.stopped
        f.replacement.timerChanges=#f.timerChanges
        f.replacement.messages=#env.messages
    end
    local function replacementIntact(f)
        local env=f.env; local r=assert(f.replacement)
        eq(selection(env,"pendingSelection"),r.pending)
        eq(env.timers.activatorSpawner.stopped,r.timer)
        eq(#f.timerChanges,r.timerChanges,"old cleanup cannot overwrite replacement timer")
        eq(#env.messages,r.messages,"old cleanup cannot publish a stale result")
        if r.kind == "event" then
            eq(state(env,"eventActive"),true); eq(state(env,"activeEventName"),"Replacement")
            eq(state(env,"activeEnemies"),r.owner); eq(state(env,"constructingEnemies"),nil)
            eq(env.totalEnemies,2); eq(state(env,"initialEnemies"),2)
            for _, enemy in ipairs(r.enemies) do
                eq(enemy.valid,true); eq(enemy:IsMarkedForDeletion(),false); eq(r.owner[enemy],true)
            end
        else
            eq(state(env,"eventActive"),false); eq(state(env,"constructingEnemies"),nil)
            eq(selection(env,"selectedBatchName"),"Replacement")
            eq(selection(env,"selectedBatchEntities"),r.owner)
            for _, actor in ipairs(r.actors) do
                eq(actor.valid,true); eq(actor:IsMarkedForDeletion(),false); eq(r.owner[actor],true)
            end
        end
        noOldResult(f,r.kind == "event")
    end
    local function retirementTimers(paused,deferred)
        if paused then return "Stop" end
        -- Existing deferred ready-actor EntityRemoved hooks each restart an
        -- enabled idle timer; the recovery branch itself must not write late.
        return deferred and "Stop,Start,Start,Start,Start" or "Stop,Start"
    end

    -- 8: ordinal x removal timing x initial schedule.
    for _, ordinal in ipairs({1,2}) do
        for _, deferred in ipairs({false,true}) do
            for _, paused in ipairs({false,true}) do
                test("lookup throw recovery candidate " .. ordinal .. ", deferred=" .. tostring(deferred) .. ", paused=" .. tostring(paused),function()
                    local f=prepare(ordinal,deferred,paused,hostile())
                    f.onRemoveRequest=function() retired(f,paused) end
                    f.throw(); retired(f,paused); noOldResult(f)
                    eq(f.random,1,"no additional spawn randomness")
                    eq(#f.ply.chats,f.chatsBefore,"minimum contract adds no feedback callback")
                    eq(#f.observer.chats,0); eq(f.env.messageCount("ActivatorEventStatus"),1)
                    eq(selection(f.env,"selectedBatchName"),nil)
                    eq(table.concat(f.timerChanges,","),paused and "Stop" or "Stop,Start")
                    removed(f); retired(f,paused)
                    eq(table.concat(f.timerChanges,","),retirementTimers(paused,deferred))
                    quietReplay(f); recover(f,paused)
                end)
            end
        end
    end
    -- 6: cancellation / replacement event / replacement selected ready batch.
    for _, kind in ipairs({"cancel","event","ready"}) do
        for _, deferred in ipairs({false,true}) do
            test("lookup throw after getter " .. kind .. ", deferred=" .. tostring(deferred),function()
                local f=prepare(2,deferred,false,hostile())
                f.beforeThrow=function()
                    -- Settle the already-requested original ready removals while
                    -- the old encounter is active. Their ordinary idle-removal
                    -- timer restarts are separate from old NPC recovery.
                    if deferred then f.env.flushRemovals() end
                    eq(f.env.stopActivatorEvent(),true)
                    if kind ~= "cancel" then replace(f,kind) end
                end
                f.throw(); removed(f); quietReplay(f)
                if kind == "cancel" then retired(f,false); noOldResult(f); recover(f,false)
                else replacementIntact(f) end
            end)
        end
    end
    -- 8: cleanup source x replacement kind x removal timing.
    for _, stage in ipairs({"admitted","current"}) do
        for _, kind in ipairs({"event","ready"}) do
            for _, deferred in ipairs({false,true}) do
                test("lookup throw cleanup " .. stage .. " replaces " .. kind .. ", deferred=" .. tostring(deferred),function()
                    local f=prepare(2,deferred,false,hostile())
                    f.onCreate=function(enemy,ordinal)
                        if ordinal == (stage == "admitted" and 1 or 2) then
                            function enemy:OnRemove() replace(f,kind) end
                        end
                    end
                    f.throw(); removed(f); replacementIntact(f); quietReplay(f); replacementIntact(f)
                end)
            end
        end
    end
    -- 8: cleanup source x initial schedule x removal timing.
    for _, stage in ipairs({"admitted","current"}) do
        for _, paused in ipairs({false,true}) do
            for _, deferred in ipairs({false,true}) do
                test("lookup throw cleanup " .. stage .. " toggles schedule, paused=" .. tostring(paused) .. ", deferred=" .. tostring(deferred),function()
                    local f=prepare(2,deferred,paused,hostile())
                    f.onCreate=function(enemy,ordinal)
                        if ordinal == (stage == "admitted" and 1 or 2) then
                            function enemy:OnRemove()
                                f.env.fire("PlayerSay",f.ply,paused and "!resumeActivatorSpawns" or "!pauseActivatorSpawns")
                            end
                        end
                    end
                    f.throw(); removed(f); retired(f,not paused); noOldResult(f)
                    eq(table.concat(f.timerChanges,","),retirementTimers(paused,deferred) .. (paused and ",Start" or ",Stop"))
                    quietReplay(f); recover(f,not paused)
                end)
            end
        end
    end
    -- 3: preserve non-table payloads, including false and nil, at level zero.
    for _, payload in ipairs({{name="string",value="configured getter error"},{name="nil"},{name="false",value=false}}) do
        test("lookup throw preserves " .. payload.name .. " payload",function()
            local f=prepare(2,false,false,payload.value)
            f.throw(); removed(f); retired(f,false); noOldResult(f); quietReplay(f); recover(f,false)
        end)
    end
    -- 3: secondary controlled Lua callback failures are isolated. Deliberately
    -- failed Remove requests leave an observed survivor; no diagnostic may claim
    -- it was removed. These are not native API-failure guarantees.
    for _, stage in ipairs({"status","admitted","current"}) do
        test("lookup throw survives secondary " .. stage .. " callback failure",function()
            local f=prepare(2,false,false,hostile()); local secondary=hostile(); local failures=0
            if stage == "status" then
                local send=f.env.net.Send
                f.env.net.Send=function(...)
                    if f.env.outgoing.name == "ActivatorEventStatus" then
                        failures=failures+1; error(secondary,0)
                    end
                    return send(...)
                end
            else
                f.onRemoveRequest=function(enemy)
                    retired(f,false)
                    if enemy == f.enemies[stage == "admitted" and 1 or 2] then
                        failures=failures+1; error(secondary,0)
                    end
                end
            end
            f.throw(); eq(failures,1); retired(f,false); noOldResult(f)
            eq(f.enemies[1].removeRequests,1); eq(f.enemies[2].removeRequests,1,"independent cleanup attempted")
            for i,enemy in ipairs(f.enemies) do
                local failed=(stage == "admitted" and i == 1) or (stage == "current" and i == 2)
                eq(enemy.valid,failed,"a failed Remove request is not successful cleanup")
                eq(enemy:IsMarkedForDeletion(),not failed)
            end
            eq(f.env.messageCount("ActivatorEventStatus"),stage == "status" and 0 or 1)
            eq(#f.ply.chats,f.chatsBefore); eq(table.concat(f.timerChanges,","),"Stop,Start")
            quietReplay(f)
        end)
    end
end
