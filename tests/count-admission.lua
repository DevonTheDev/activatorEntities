-- Exercise the real selected-batch timer, Use and Start handlers. The setup
-- edits trusted server configuration; Start still receives only an identifier.
return function(gmod, test, eq)
    local invalidCount = "This encounter has an invalid enemy count. Ask an admin to correct the configuration and restart the server."
    local function status(env, admin)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,"!eventStatus"),"")
        local lines={}
        for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        return table.concat(lines,"\n")
    end
    local function contains(text, expected)
        assert(text:find(expected,1,true),"expected '" .. expected .. "' in '" .. text .. "'")
    end
    local function setup(count, schedule)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local info=env.NPCEdits[1].information
        env.NPCEdits[7]={name="Ambush",information={activatorModel=info.activatorModel,
            npcPath="npc_combine_s",maxNPCs=count,dialogue="An ambush awaits."}}
        local selected=env.NPCEdits[7].information
        eq(env.fire("PlayerSay",admin,"!nextEvent Ambush"),"")
        local create=env.ents.Create; local attempts=0
        if schedule == "running" then
            -- A failed creation leaves a real partial batch and running timer.
            env.ents.Create=function(class)
                if class == "activatorent" then
                    attempts=attempts+1
                    if attempts == 3 then return {valid=false} end
                end
                return create(class)
            end
        end
        env.fireTimer("activatorSpawner"); env.ents.Create=create
        local actors=env.ents.FindByClass("activatorent")
        eq(#actors,schedule == "running" and 2 or 3,"ready batch setup")
        eq(env.fire("PlayerSay",admin,"!nextEvent Raid"),"")
        if schedule == "paused" then eq(env.fire("PlayerSay",admin,"!pauseActivatorSpawns"),"") end
        eq(env.timers.activatorSpawner.stopped,schedule ~= "running","ready timer setup")
        local text=status(env,admin)
        contains(text,'Selected ready batch: "Ambush"')
        contains(text,'Pending next batch: "Raid"')
        contains(text,"Active event: none")
        admin:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",admin,admin)
        return env,admin,selected,actors,text
    end
    local function observe(env)
        local calls={creates=0,timerChanges=0,writes=0,random=0}
        local create=env.ents.Create
        env.ents.Create=function(class) calls.creates=calls.creates+1; return create(class) end
        for _, key in ipairs({"Start","Stop","Create","Simple"}) do
            local original=env.timer[key]
            env.timer[key]=function(...) calls.timerChanges=calls.timerChanges+1; return original(...) end
        end
        local write=env.file.Write
        env.file.Write=function(...) calls.writes=calls.writes+1; return write(...) end
        env.math=setmetatable({}, {__index=math})
        env.math.random=function(...) calls.random=calls.random+1; return math.random(...) end
        return calls
    end
    local function rejected(count, label, schedule)
        local env,admin,info,actors,before=setup(count,schedule)
        local observer=env.entity("player"); before=status(env,admin)
        local chats=#admin.chats
        local calls=observe(env); local timer=env.timers.activatorSpawner
        local stopped=timer.stopped; local messages=#env.messages; local errors=#env.errors
        local definitions,positions=env.NPCEdits,env.SpawnPositions
        local ok,err=pcall(env.receive,"SendNPCInformation",admin,"Ambush")
        eq(#admin.chats,chats+1,"invalid count explains rejection once to the requester")
        eq(admin.chats[#admin.chats],invalidCount)
        eq(#observer.chats,0,"invalid count feedback stays private")
        local after=status(env,admin)
        eq(after,before,label .. " Start preserves ready state")
        assert(ok,label .. " Start raised: " .. tostring(err))
        eq(#env.ents.FindByClass("activatorent"),#actors,"ready actor count")
        for _, actor in ipairs(actors) do
            eq(env.IsValid(actor),true,"original ready actor remains valid")
            eq(actor:IsMarkedForDeletion(),false,"no removal requested")
            eq(actor.NPCInfo,info,"selected configuration remains attached")
        end
        eq(env.NPCEdits,definitions); eq(env.SpawnPositions,positions)
        if label == "NaN" then assert(info.maxNPCs ~= info.maxNPCs,"NaN must not be repaired")
        else eq(info.maxNPCs,count,"rejection must not repair configuration") end
        eq(env.totalEnemies,0); eq(#env.ents.FindByName("devonsSpawnedEntity"),0)
        eq(calls.creates,0); eq(calls.timerChanges,0); eq(calls.writes,0)
        eq(calls.random,1,"existing enemy-position sample remains before count admission")
        eq(env.timers.activatorSpawner,timer); eq(timer.stopped,stopped)
        eq(#env.messages,messages,"no progress or completion message")
        eq(#env.errors,errors,"no zero-enemy activation error")

        -- Controlled repair proves grant consumption and retry. Live config
        -- edits still require the documented server restart, not hot-reload.
        info.maxNPCs=2.75
        chats=#admin.chats
        env.receive("SendNPCInformation",admin,"Ambush")
        eq(#admin.chats,chats,"consumed replay stays silent after count repair")
        eq(#observer.chats,0)
        eq(calls.random,1,"replay cannot sample a spawn")
        eq(calls.creates,0,"replay cannot use the corrected count")
        eq(calls.timerChanges,0); eq(#env.messages,messages)
        eq(status(env,admin),before,"consumed replay retains ready state")
        actors[1]:AcceptInput("Use",admin,admin)
        env.receive("SendNPCInformation",admin,"Ambush")
        local enemies=env.ents.FindByName("devonsSpawnedEntity")
        eq(#enemies,2,"fresh Use starts floored corrected count")
        eq(env.totalEnemies,2); eq(calls.creates,2)
        eq(#env.ents.FindByClass("activatorent"),0)
        contains(status(env,admin),'Pending next batch: "Raid"')
        contains(status(env,admin),'Selected ready batch: none')
        for _, enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
        eq(env.messageCount("roundFinished"),1,"recovered encounter completes normally")
        eq(env.timers.activatorSpawner.stopped,schedule == "paused","completion preserves pause")
        if schedule == "paused" then
            env.fireTimer("activatorSpawner")
            eq(#env.ents.FindByClass("activatorent"),0,"paused completion cannot respawn")
            eq(env.fire("PlayerSay",admin,"!resumeActivatorSpawns"),"")
        end
        env.fireTimer("activatorSpawner")
        for _, actor in ipairs(env.ents.FindByClass("activatorent")) do
            eq(actor.EventIdentifier,"Raid","separate future selection survives rejection and retry")
        end
        eq(#env.ents.FindByClass("activatorent"),3)
    end

    for _, schedule in ipairs({"at capacity","running","paused"}) do
        test("NaN Start retains selected ready state and permits fresh retry: " .. schedule,function()
            rejected(0/0,"NaN",schedule)
        end)
    end
    for _, case in ipairs({
        {"missing",nil},{"boolean",false},{"numeric string","2"},{"table",{}},
        {"zero",0},{"negative",-2},{"fraction below one",0.75},
        {"positive infinity",math.huge},{"negative infinity",-math.huge}
    }) do
        test("invalid count privately explains rejection and retains readiness: " .. case[1],function()
            rejected(case[2],case[1],"at capacity")
        end)
    end
    for _, count in ipairs({1,1.5,2.75,5}) do
        test("finite count keeps floored creation attempts: " .. count,function()
            local env,admin,info=setup(count,"at capacity")
            local observer=env.entity("player"); local chats=#admin.chats
            local calls=observe(env)
            env.receive("SendNPCInformation",admin,"Ambush")
            local started=math.floor(count) .. " enemies have been spawned. Eliminate them."
            eq(#admin.chats,chats+1); eq(admin.chats[#admin.chats],started)
            eq(#observer.chats,1); eq(observer.chats[1],started)
            local enemies=env.ents.FindByName("devonsSpawnedEntity")
            eq(calls.creates,math.floor(count),"exact creation attempts")
            eq(#enemies,math.floor(count)); eq(env.totalEnemies,math.floor(count))
            eq(info.maxNPCs,count,"fractional configuration remains unchanged")
            for _, enemy in ipairs(enemies) do
                eq(enemy:GetClass(),info.npcPath); eq(enemy.health,env.returnEnemyHealth())
                env.fire("OnNPCKilled",enemy,admin)
            end
            eq(env.messageCount("roundFinished"),1); eq(env.totalEnemies,0)
            eq(env.timers.activatorSpawner.stopped,false)
            contains(status(env,admin),'Pending next batch: "Raid"')
        end)
    end
end
