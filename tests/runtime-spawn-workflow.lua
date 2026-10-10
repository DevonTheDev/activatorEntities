-- Actual menu -> Start -> server refusal/recovery, plus callback invalidation.
-- Spies assert creation/RNG boundaries, not the loose entity double's SetPos type.
return function(gmod,test,eq)
    local H=dofile("tests/runtime-spawn-fixtures.lua")(gmod,eq)
    local missing="No enemy spawn position is available. Ask an admin to fix it, then use the activator again."
    local function selected()
        local server,ioState,codec=H.setup(); local client=gmod.new(true)
        H.addAmbush(server)
        local admin=server.entity("player"); admin.admin=true
        local observer=server.entity("player"); local ply=server.entity("player")
        H.queue(server,admin,"Ambush"); server.fireTimer("activatorSpawner")
        H.queue(server,admin,"Raid")
        local actor=assert(server.ents.FindByClass("activatorent")[1])
        ply:SetPos(actor:GetPos())
        return server,client,ply,actor,admin,observer,ioState,codec
    end
    local function snapshot(env,ioState)
        local saved={data=H.dataState(env,ioState),entities=#env.entities,messages=#env.messages,
            errors=#env.errors,enemies=env.totalEnemies,count=env.activatorCount,
            timer=H.snapshot(env.timers.activatorSpawner),actors=env.ents.FindByClass("activatorent"),
            actorState={},chats={}}
        for _,actor in ipairs(saved.actors) do
            saved.actorState[actor]={marked=actor:IsMarkedForDeletion(),identifier=actor.EventIdentifier,
                info=actor.NPCInfo,model=actor:GetModel(),position=actor:GetPos(),spawned=actor.spawned}
        end
        for _,ply in ipairs(env.player.GetAll()) do saved.chats[ply]=#ply.chats end
        return saved
    end
    local function unchanged(env,ioState,saved,requester)
        eq(#env.entities,saved.entities,"rejected Start never reaches entity creation")
        eq(#env.messages,saved.messages,"rejected Start emits no addon packet or progress")
        eq(#env.errors,saved.errors+(requester and 1 or 0))
        eq(env.totalEnemies,saved.enemies); eq(env.activatorCount,saved.count)
        H.same(env.timers.activatorSpawner,saved.timer); H.sameData(env,ioState,saved.data)
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,#saved.actors)
        for i,actor in ipairs(actors) do
            eq(actor,saved.actors[i]); eq(actor.valid,true)
            local original=saved.actorState[actor]
            eq(actor:IsMarkedForDeletion(),original.marked); eq(actor.EventIdentifier,original.identifier)
            eq(actor.NPCInfo,original.info); eq(actor:GetModel(),original.model)
            eq(actor:GetPos(),original.position); eq(actor.spawned,original.spawned)
        end
        for ply,count in pairs(saved.chats) do
            eq(#ply.chats,count+(ply == requester and 1 or 0),"one private reply to the requester only")
        end
        if requester then
            eq(requester.chats[#requester.chats],missing)
            eq(env.errors[#env.errors],"ERROR - There are no enemy spawn positions set for gm_construct\n")
        end
    end
    for _,case in ipairs(H.invalid) do
        test("actual Start safely refuses " .. case[1] .. " and a fresh Use completes after repair",function()
            local server,client,ply,actor,admin,observer,ioState,codec=selected()
            local repair=codec.copy(server.SpawnPositions)
            local frame,button=H.open(server,client,ply,actor)
            case[2](server,H.kinds[2])
            local beforeStatus=H.status(server,admin)
            H.contains(beforeStatus,"Encounter start enemy positions: " .. (case[3] or "malformed list"))
            H.contains(beforeStatus,'Selected ready batch: "Ambush"')
            H.contains(beforeStatus,'Pending next batch: "Raid"')
            local before=snapshot(server,ioState); local observed=H.watch(server)
            local request=H.click(server,client,ply,frame,button)
            unchanged(server,ioState,before,ply)
            eq(#observed.draws,0,"unavailable enemy input consumes no position RNG")
            eq(#observed.creates,0); eq(#observed.placements,0)
            eq(H.status(server,admin),beforeStatus,"refusal retains selected and pending ownership")
            local refused=snapshot(server,ioState)
            H.call("consumed Start replay",function() server.deliver(request,ply) end)
            unchanged(server,ioState,refused)

            -- Repair configured data in memory; repair itself must not start.
            server.SpawnPositions=repair
            local repaired=snapshot(server,ioState)
            H.call("replay after repair",function() server.deliver(request,ply) end)
            unchanged(server,ioState,repaired)
            eq(#observed.draws,0); eq(#observed.creates,0)
            frame,button=H.open(server,client,ply,actor)
            H.click(server,client,ply,frame,button)
            eq(#observed.draws,1); eq(#observed.creates,2); eq(#observed.placements,2)
            eq(server.totalEnemies,2); eq(#server.ents.FindByClass("activatorent"),0)
            eq(server.timers.activatorSpawner.stopped,true)
            eq(server.messageCount("ActivatorEventStatus"),1)
            local progress=server.messages[#server.messages]
            eq(progress.name,"ActivatorEventStatus"); eq(progress.values[1],true)
            eq(progress.values[2],"Ambush"); eq(progress.values[3],2); eq(progress.values[4],2)
            eq(progress.values[5],false); client.deliver(progress)
            eq(observer.chats[#observer.chats],"2 enemies have been spawned. Eliminate them.")
            local enemies=server.ents.FindByName("devonsSpawnedEntity"); eq(#enemies,2)
            server.fire("OnNPCKilled",enemies[1],ply)
            eq(server.totalEnemies,1); eq(server.messageCount("ActivatorEventStatus"),2)
            eq(server.messageCount("roundFinished"),0)
            progress=server.messages[#server.messages]
            eq(progress.values[1],true); eq(progress.values[3],1); eq(progress.values[4],2)
            client.deliver(progress)
            server.fire("OnNPCKilled",enemies[2],ply)
            eq(server.totalEnemies,0); eq(server.messageCount("ActivatorEventStatus"),3)
            eq(server.messageCount("roundFinished"),1); eq(server.timers.activatorSpawner.stopped,false)
            server.fire("OnNPCKilled",enemies[2],ply)
            eq(server.messageCount("roundFinished"),1,"completion still occurs only once")
            local afterStatus=H.status(server,admin)
            H.contains(afterStatus,"Selected ready batch: none")
            H.contains(afterStatus,'Pending next batch: "Raid"')
            H.sameData(server,ioState,repaired.data)
        end)
    end
    test("initial timer rejection retains pending choice and a repaired normal attempt admits it",function()
        local env,ioState=H.setup(); H.addAmbush(env)
        local admin=env.entity("player"); admin.admin=true
        H.queue(env,admin,"Ambush")
        local positions=env.SpawnPositions[1].activatorSpawnPositions
        env.SpawnPositions[1].activatorSpawnPositions={[1]="invalid"}
        local before=H.dataState(env,ioState); local observed=H.watch(env)
        H.call("selected timer rejection",function() env.fireTimer("activatorSpawner") end)
        eq(#observed.draws,0); eq(#observed.creates,0); H.sameData(env,ioState,before)
        local status=H.status(env,admin)
        H.contains(status,"Selected ready batch: none"); H.contains(status,'Pending next batch: "Ambush"')
        eq(env.timers.activatorSpawner.stopped,false)
        env.SpawnPositions[1].activatorSpawnPositions=positions
        local repaired=H.dataState(env,ioState)
        env.fireTimer("activatorSpawner")
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
        for _,actor in ipairs(actors) do eq(actor.EventIdentifier,"Ambush") end
        status=H.status(env,admin)
        H.contains(status,'Selected ready batch: "Ambush"'); H.contains(status,"Pending next batch: none")
        eq(env.timers.activatorSpawner.stopped,true); H.sameData(env,ioState,repaired)
    end)

    -- Later external invalidation preserves the successfully created owner; it
    -- must stop the next creation, not roll back the successful partial batch.
    for _,damage in ipairs({"empty list","malformed list","removed map"}) do
        for _,queueChange in ipairs({"unchanged","replace","clear"}) do
            test("Spawn callback " .. damage .. " stops partial batch with queue " .. queueChange,function()
                local env,ioState=H.setup(); H.addAmbush(env)
                local admin=env.entity("player"); admin.admin=true
                H.queue(env,admin,"Ambush")
                local root,positions=env.SpawnPositions,env.SpawnPositions[1].activatorSpawnPositions
                local data=H.dataState(env,ioState); local observed=H.watch(env)
                local create=env.ents.Create; local changed=false; local invalidated
                env.ents.Create=function(class)
                    local ent=create(class)
                    if class == "activatorent" and env.IsValid(ent) then
                        local spawn=ent.Spawn
                        ent.Spawn=function(self)
                            spawn(self)
                            if changed then return end
                            changed=true
                            if damage == "empty list" then root[1].activatorSpawnPositions={}
                            elseif damage == "malformed list" then root[1].activatorSpawnPositions={[31]="invalid"}
                            else env.SpawnPositions={} end
                            invalidated=H.dataState(env,ioState)
                            if queueChange == "replace" then H.queue(env,admin,"Raid")
                            elseif queueChange == "clear" then eq(env.fire("PlayerSay",admin,"!clearNextEvent"),"") end
                        end
                    end
                    return ent
                end
                H.call("invalidated partial batch",function() env.fireTimer("activatorSpawner") end)
                eq(#observed.creates,1,"rejected resample stops before another entity is created")
                eq(#observed.placements,1); eq(#observed.draws,1)
                local actors=env.ents.FindByClass("activatorent"); eq(#actors,1)
                local survivor=actors[1]; eq(survivor.valid,true); eq(survivor.EventIdentifier,"Ambush")
                eq(survivor:IsMarkedForDeletion(),false); eq(env.activatorCount,1)
                eq(env.timers.activatorSpawner.stopped,false); eq(#env.messages,0); eq(#env.errors,0)
                H.sameData(env,ioState,invalidated)
                local expected=queueChange == "replace" and '"Raid"' or "none"
                local status=H.status(env,admin)
                H.contains(status,'Selected ready batch: "Ambush"'); H.contains(status,"Pending next batch: " .. expected)

                env.SpawnPositions=root; root[1].activatorSpawnPositions=positions
                env.fireTimer("activatorSpawner")
                actors=env.ents.FindByClass("activatorent"); eq(#actors,3); eq(actors[1],survivor)
                for _,actor in ipairs(actors) do eq(actor.EventIdentifier,"Ambush") end
                eq(#observed.creates,3); eq(#observed.placements,3)
                eq(env.activatorCount,3); eq(env.timers.activatorSpawner.stopped,true)
                status=H.status(env,admin)
                H.contains(status,'Selected ready batch: "Ambush"'); H.contains(status,"Pending next batch: " .. expected)
                H.sameData(env,ioState,data)
            end)
        end
    end
end
