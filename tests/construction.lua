-- Deliberately synchronous callbacks exercise actual addon ownership boundaries.
-- These doubles do not establish native GMod hook timing or gameplay failures.
return function(gmod, test, eq)
    local function lastStatus(env)
        for i=#env.messages,1,-1 do
            if env.messages[i].name == "ActivatorEventStatus" then return env.messages[i].values end
        end
        error("missing encounter status")
    end
    local function active(env, name, remaining, initial, interrupted)
        local status=lastStatus(env)
        eq(#status, 5); eq(status[1], true); eq(status[2], name)
        eq(status[3], remaining); eq(status[4], initial); eq(status[5], interrupted)
        eq(env.totalEnemies, remaining)
        eq(env.timers.activatorSpawner.stopped, true)
    end
    local function spawnNotices(ply)
        local count=0
        for _, text in ipairs(ply.chats) do
            if text:find("enemies have been spawned", 1, true) then count=count+1 end
        end
        return count
    end
    local function prepare()
        local env=gmod.new(); local ply, actor=env.ready()
        actor:AcceptInput("Use", ply, ply)
        return env, ply, actor
    end
    local function canceled(env, ply)
        eq(env.totalEnemies, 0)
        eq(#env.ents.FindByName("devonsSpawnedEntity"), 0, "no old event survivors")
        eq(#lastStatus(env), 1); eq(lastStatus(env)[1], false)
        eq(env.messageCount("roundFinished"), 0)
        eq(spawnNotices(ply), 0, "retired construction cannot announce a start")
        eq(env.timers.activatorSpawner.stopped, false)
        eq(env.stopActivatorEvent(), false)
        eq(#env.errors, 0, "cancellation is not reported as failed creation")
    end
    local function recover(env)
        local ply, enemies=env.start()
        eq(#enemies, 5)
        for _, enemy in ipairs(enemies) do env.fire("OnNPCKilled", enemy, ply); enemy:Remove() end
        eq(env.totalEnemies, 0); eq(env.messageCount("roundFinished"), 1)
        eq(env.timers.activatorSpawner.stopped, false)
    end
    local function replacement(env)
        env.NPCEdits[#env.NPCEdits+1]={name="Replacement", information={
            activatorModel="models/alyx.mdl", npcPath="npc_zombie", maxNPCs=2, dialogue="Replacement"
        }}
        local actor=env.entity("activatorent"); actor.EventIdentifier="Replacement"; actor:Spawn()
        local ply=env.entity("player"); ply:SetPos(actor:GetPos())
        actor:AcceptInput("Use", ply, ply); env.receive("SendNPCInformation", ply, "Replacement")
        return ply, env.ents.FindByClass("npc_zombie")
    end

    test("cancellation during activator destruction prevents the first NPC creation", function()
        local env, ply, actor=prepare(); local create=env.ents.Create; local attempts=0
        env.ents.Create=function(class)
            if class == "npc_stalker" then attempts=attempts+1 end
            return create(class)
        end
        function actor:OnRemove() eq(env.stopActivatorEvent(), true) end
        env.receive("SendNPCInformation", ply, "Raid")
        eq(attempts, 0); canceled(env, ply); recover(env)
    end)

    -- Each call can synchronously run addon code. The returned-but-unregistered
    -- NPC must be retired too, even when cancellation happened inside Create.
    for _, boundary in ipairs({"Create", "SetPos", "SetName", "Spawn", "health lookup", "SetHealth"}) do
        for _, ordinal in ipairs({1, 2}) do
            test("cancellation in NPC " .. ordinal .. " " .. boundary .. " retires old construction", function()
                local env, ply=prepare(); local create=env.ents.Create; local attempts=0; local old={}
                local health=env.returnEnemyHealth
                if boundary == "health lookup" then
                    env.returnEnemyHealth=function()
                        if attempts == ordinal then eq(env.stopActivatorEvent(), true) end
                        return health()
                    end
                end
                env.ents.Create=function(class)
                    local enemy=create(class)
                    if class ~= "npc_stalker" then return enemy end
                    attempts=attempts+1; old[#old+1]=enemy
                    if attempts == ordinal then
                        if boundary == "Create" then eq(env.stopActivatorEvent(), true)
                        elseif boundary ~= "health lookup" then
                            local method=enemy[boundary]
                            enemy[boundary]=function(self, ...)
                                method(self, ...); eq(env.stopActivatorEvent(), true)
                            end
                        end
                    end
                    return enemy
                end
                env.receive("SendNPCInformation", ply, "Raid")
                eq(attempts, ordinal, "no later creation after cancellation")
                for _, enemy in ipairs(old) do eq(enemy.valid, false, "every old entity was removed") end
                if boundary == "Create" or boundary == "SetPos" or boundary == "SetName" then
                    eq(old[ordinal].spawned, nil, "cancellation before Spawn cannot spawn the returned NPC")
                end
                if boundary ~= "SetHealth" then
                    eq(old[ordinal].health, nil, "cancellation prevents later health mutation")
                end
                canceled(env, ply)
                env.ents.Create=create; env.returnEnemyHealth=health; recover(env)
            end)
        end
    end

    test("admin stop in NPC two Spawn retires construction without survivors", function()
        local env, ply=prepare(); ply.admin=true
        local create=env.ents.Create; local attempts=0
        env.ents.Create=function(class)
            local enemy=create(class)
            if class == "npc_stalker" then
                attempts=attempts+1
                if attempts == 2 then
                    local spawn=enemy.Spawn
                    function enemy:Spawn() spawn(self); env.fire("PlayerSay", ply, "!stopEvent") end
                end
            end
            return enemy
        end
        env.receive("SendNPCInformation", ply, "Raid")
        eq(attempts, 2); canceled(env, ply); eq(env.messageCount("entitiesDeleted"), 1)
    end)

    test("cancellation with deferred removal retires the in-flight NPC as well", function()
        local env, ply=prepare(); env.deferRemoval=true
        local create=env.ents.Create; local attempts=0; local old={}
        env.ents.Create=function(class)
            local enemy=create(class)
            if class == "npc_stalker" then
                attempts=attempts+1; old[#old+1]=enemy
                if attempts == 2 then
                    local spawn=enemy.Spawn
                    function enemy:Spawn() spawn(self); eq(env.stopActivatorEvent(), true) end
                end
            end
            return enemy
        end
        env.receive("SendNPCInformation", ply, "Raid")
        eq(attempts, 2); eq(env.totalEnemies, 0)
        for _, enemy in ipairs(old) do eq(enemy:IsMarkedForDeletion(), true) end
        env.flushRemovals(); canceled(env, ply)
        env.ents.Create=create; recover(env)
    end)

    for _, action in ipairs({"kill", "remove"}) do
        test("earlier tracked " .. action .. " during later Spawn waits for construction", function()
            local env, ply=prepare(); local create=env.ents.Create; local spawned={}
            env.ents.Create=function(class)
                local enemy=create(class)
                if class == "npc_stalker" then
                    spawned[#spawned+1]=enemy
                    if #spawned == 2 then
                        local spawn=enemy.Spawn
                        function enemy:Spawn()
                            spawn(self)
                            if action == "kill" then env.fire("OnNPCKilled", spawned[1], ply) end
                            spawned[1]:Remove()
                            eq(env.totalEnemies, 0)
                            eq(env.messageCount("roundFinished"), 0, "no premature victory")
                            eq(env.messageCount("ActivatorEventStatus"), 0, "publish settled construction only")
                            eq(env.timers.activatorSpawner.stopped, true, "temporary zero cannot retire the event")
                        end
                    end
                end
                return enemy
            end
            env.receive("SendNPCInformation", ply, "Raid")
            eq(#spawned, 5); active(env, "Raid", 4, 5, action == "remove")
            eq(spawnNotices(ply), 1)
            eq(ply.chats[#ply.chats], "5 enemies have been spawned. Eliminate them.")
            for i=2,5 do env.fire("OnNPCKilled", spawned[i], ply); spawned[i]:Remove() end
            eq(env.messageCount("roundFinished"), action == "kill" and 1 or 0)
            eq(env.totalEnemies, 0); eq(env.timers.activatorSpawner.stopped, false)
        end)
    end

    for _, action in ipairs({"kill", "remove"}) do
        test("all admitted NPCs " .. action .. " during construction settle only after final failed attempt", function()
            local env, ply=prepare(); local create=env.ents.Create; local previous; local attempts=0
            env.ents.Create=function(class)
                if class ~= "npc_stalker" then return create(class) end
                attempts=attempts+1
                if previous then
                    if action == "kill" then env.fire("OnNPCKilled", previous, ply) end
                    previous:Remove()
                    eq(env.messageCount("roundFinished"), 0, "construction has not settled")
                    eq(env.timers.activatorSpawner.stopped, true)
                end
                if attempts == 5 then return {valid=false} end
                previous=create(class); return previous
            end
            env.receive("SendNPCInformation", ply, "Raid")
            eq(attempts, 5); eq(env.totalEnemies, 0); eq(lastStatus(env)[1], false)
            eq(env.messageCount("roundFinished"), action == "kill" and 1 or 0)
            eq(env.messageCount("ActivatorEventStatus"), 1); eq(spawnNotices(ply), 0)
            eq(#env.errors, 0, "admitted NPCs existed, so this is not spawn failure")
            eq(env.timers.activatorSpawner.stopped, false)
        end)
    end

    test("partial creation with an earlier kill preserves admitted initial count", function()
        local env, ply=prepare(); local create=env.ents.Create; local attempts=0; local first
        env.ents.Create=function(class)
            if class ~= "npc_stalker" then return create(class) end
            attempts=attempts+1
            if attempts == 2 then env.fire("OnNPCKilled", first, ply); first:Remove() end
            if attempts == 2 or attempts == 4 then return {valid=false} end
            local enemy=create(class); first=first or enemy; return enemy
        end
        env.receive("SendNPCInformation", ply, "Raid")
        eq(attempts, 5); active(env, "Raid", 2, 3, false)
        eq(ply.chats[#ply.chats], "3 enemies have been spawned. Eliminate them.")
    end)

    test("native-style deferred earlier removal retains interruption and initial count", function()
        local env, ply=prepare(); env.deferRemoval=true
        local create=env.ents.Create; local spawned={}
        env.ents.Create=function(class)
            local enemy=create(class)
            if class == "npc_stalker" then
                spawned[#spawned+1]=enemy
                if #spawned == 2 then
                    local spawn=enemy.Spawn
                    function enemy:Spawn() spawn(self); spawned[1]:Remove() end
                end
            end
            return enemy
        end
        env.receive("SendNPCInformation", ply, "Raid")
        active(env, "Raid", 5, 5, false)
        env.flushRemovals(); active(env, "Raid", 4, 5, true)
        for i=2,5 do env.fire("OnNPCKilled", spawned[i], ply) end
        eq(env.messageCount("roundFinished"), 0); eq(env.timers.activatorSpawner.stopped, false)
    end)

    for _, boundary in ipairs({"Spawn", "SetHealth"}) do
        for _, deferred in ipairs({false, true}) do
            test("self-removal during " .. boundary .. " excludes the candidate, deferred=" .. tostring(deferred), function()
                local env, ply=prepare(); env.deferRemoval=deferred
                local create=env.ents.Create; local attempts=0; local survivors={}; local rejected
                env.ents.Create=function(class)
                    if class ~= "npc_stalker" then return create(class) end
                    attempts=attempts+1
                    if attempts == 2 then return {valid=false} end
                    local enemy=create(class)
                    if attempts == 4 then
                        rejected=enemy; local method=enemy[boundary]
                        enemy[boundary]=function(self, ...) method(self, ...); self:Remove() end
                    else survivors[#survivors+1]=enemy end
                    return enemy
                end
                env.receive("SendNPCInformation", ply, "Raid")
                eq(attempts, 5); eq(#survivors, 3); active(env, "Raid", 3, 3, false)
                eq(spawnNotices(ply), 1)
                eq(ply.chats[#ply.chats], "3 enemies have been spawned. Eliminate them.")
                if boundary == "Spawn" then eq(rejected.health, nil, "deleted candidate skips health setup") end
                env.flushRemovals(); active(env, "Raid", 3, 3, false)
                eq(env.messageCount("ActivatorEventStatus"), 1, "excluded removal cannot publish progress")
                for _, enemy in ipairs(survivors) do env.fire("OnNPCKilled", enemy, ply); enemy:Remove() end
                eq(env.totalEnemies, 0); eq(env.messageCount("roundFinished"), 1)
                eq(env.timers.activatorSpawner.stopped, false)
                env.flushRemovals(); eq(env.messageCount("roundFinished"), 1)
                eq(#env.errors, 0)
            end)
        end
        for _, paused in ipairs({false, true}) do
            test("all candidates delete during " .. boundary .. " recover after failed start, paused=" .. tostring(paused), function()
                local env, ply=prepare(); env.deferRemoval=true; ply.admin=true
                if paused then env.fire("PlayerSay", ply, "!pauseActivatorSpawns") end
                local create=env.ents.Create; local attempts=0
                env.ents.Create=function(class)
                    local enemy=create(class)
                    if class == "npc_stalker" then
                        attempts=attempts+1; local method=enemy[boundary]
                        enemy[boundary]=function(self, ...) method(self, ...); self:Remove() end
                    end
                    return enemy
                end
                env.receive("SendNPCInformation", ply, "Raid")
                eq(attempts, 5); eq(env.totalEnemies, 0)
                eq(#lastStatus(env), 1); eq(lastStatus(env)[1], false)
                eq(env.messageCount("roundFinished"), 0); eq(spawnNotices(ply), 0)
                eq(env.timers.activatorSpawner.stopped, paused)
                eq(#env.errors, 1); eq(env.errors[1], "ERROR - No event enemies could be spawned\n")
                env.flushRemovals()
                eq(#env.ents.FindByName("devonsSpawnedEntity"), 0)
                eq(env.messageCount("ActivatorEventStatus"), 1)
                eq(env.timers.activatorSpawner.stopped, paused)
                env.ents.Create=create
                if paused then env.fire("PlayerSay", ply, "!resumeActivatorSpawns") end
                recover(env)
            end)
        end
    end

    for _, boundary in ipairs({"Create", "Spawn", "SetHealth"}) do
        test("replacement during old NPC " .. boundary .. " retains exclusive ownership", function()
            local env, ply=prepare(); local create=env.ents.Create; local attempts=0; local old={}
            local nextPlayer, nextEnemies
            local function replace()
                eq(env.stopActivatorEvent(), true)
                nextPlayer, nextEnemies=replacement(env)
                active(env, "Replacement", 2, 2, false)
            end
            env.ents.Create=function(class)
                local enemy=create(class)
                if class ~= "npc_stalker" then return enemy end
                attempts=attempts+1; old[#old+1]=enemy
                if attempts == 2 then
                    if boundary == "Create" then replace()
                    else
                        local method=enemy[boundary]
                        enemy[boundary]=function(self, ...) method(self, ...); replace() end
                    end
                end
                return enemy
            end
            env.receive("SendNPCInformation", ply, "Raid")
            eq(attempts, 2); active(env, "Replacement", 2, 2, false)
            eq(#env.ents.FindByName("devonsSpawnedEntity"), 2)
            for _, enemy in ipairs(old) do
                eq(enemy.valid, false); env.fire("OnNPCKilled", enemy, ply); env.fire("EntityRemoved", enemy)
            end
            active(env, "Replacement", 2, 2, false)
            eq(spawnNotices(ply), 1, "only the replacement announces a start")
            for _, enemy in ipairs(nextEnemies) do env.fire("OnNPCKilled", enemy, nextPlayer) end
            eq(env.messageCount("roundFinished"), 1); eq(env.totalEnemies, 0)
        end)
    end

    test("replacement started by cleanup of an unregistered old NPC remains active", function()
        local env, ply=prepare(); local create=env.ents.Create; local attempts=0
        env.ents.Create=function(class)
            local enemy=create(class)
            if class ~= "npc_stalker" then return enemy end
            attempts=attempts+1
            if attempts == 1 then
                local spawn=enemy.Spawn
                function enemy:Spawn() spawn(self); eq(env.stopActivatorEvent(), true) end
                function enemy:OnRemove() replacement(env) end
            end
            return enemy
        end
        env.receive("SendNPCInformation", ply, "Raid")
        eq(attempts, 1); active(env, "Replacement", 2, 2, false)
        eq(#env.ents.FindByName("devonsSpawnedEntity"), 2); eq(spawnNotices(ply), 1)
    end)

    for _, deferred in ipairs({false, true}) do
        test("old tracked cleanup cannot retire a replacement with deferred removal " .. tostring(deferred), function()
            local env=gmod.new(); local ply, old=env.start(); env.deferRemoval=deferred
            local began=false
            for _, enemy in ipairs(old) do
                function enemy:OnRemove()
                    if not began then began=true; replacement(env) end
                end
            end
            eq(env.stopActivatorEvent(), true)
            if deferred then env.flushRemovals() end
            active(env, "Replacement", 2, 2, false)
            eq(#env.ents.FindByName("devonsSpawnedEntity"), 2)
            for _, enemy in ipairs(old) do env.fire("OnNPCKilled", enemy, ply); env.fire("EntityRemoved", enemy) end
            active(env, "Replacement", 2, 2, false)
            eq(env.messageCount("roundFinished"), 0)
        end)
    end
end
