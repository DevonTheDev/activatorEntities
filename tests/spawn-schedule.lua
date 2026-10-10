-- Execute the real commands and spawn/lifecycle callbacks. Timer doubles prove
-- Start/Stop ordering and preserved delay configuration, not native elapsed time.
return function(gmod, test, eq)
    local pause, resume = "!pauseActivatorSpawns", "!resumeActivatorSpawns"
    local function setup()
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        env.NPCEdits[7]={name="Ambush", information={activatorModel="models/alyx.mdl",
            npcPath="npc_combine_s", maxNPCs=2, dialogue="An ambush awaits."}}
        env.determineRandomEvent=function() return "Raid" end
        local calls={starts=0,stops=0}
        for key,field in pairs({Start="starts",Stop="stops"}) do
            local original=env.timer[key]
            env.timer[key]=function(name)
                eq(name,"activatorSpawner"); calls[field]=calls[field]+1; original(name)
            end
        end
        return env,admin,calls
    end
    local function say(env,ply,text) return env.fire("PlayerSay",ply,text) end
    local function command(env,ply,text)
        local before=#ply.chats
        eq(say(env,ply,text),"","command handled privately")
        eq(#ply.chats,before+1,"one private response")
        assert(#ply.chats[#ply.chats] <= 255,"ChatPrint bound")
        return ply.chats[#ply.chats]
    end
    local function contains(text,expected)
        assert(text:find(expected,1,true),"expected '" .. expected .. "' in '" .. text .. "'")
    end
    local function status(env,admin)
        local first=#admin.chats+1; eq(say(env,admin,"!eventStatus"),"")
        local lines={}
        for i=first,#admin.chats do
            assert(#admin.chats[i] <= 255,"ChatPrint bound"); lines[#lines+1]=admin.chats[i]
        end
        assert(#lines <= 16,"bounded complete status")
        return table.concat(lines,"\n")
    end
    local function state(env,admin,paused,pending,selected)
        local text=status(env,admin)
        contains(text,"Automatic spawn, next normal attempt: " .. (paused and "paused" or "enabled"))
        contains(text,"Pending next batch: " .. (pending and ('"' .. pending .. '"') or "none"))
        contains(text,"Selected ready batch: " .. (selected and ('"' .. selected .. '"') or "none"))
        return text
    end
    local function actors(env,name,count)
        local result={}
        for _,ent in ipairs(env.ents.FindByClass("activatorent")) do
            if not ent:IsMarkedForDeletion() then
                if name then eq(ent.EventIdentifier,name) end
                result[#result+1]=ent
            end
        end
        if count then eq(#result,count,"usable activators") end
        return result
    end
    local function open(env,ply,ent)
        ply:SetPos(ent:GetPos()); ent:AcceptInput("Use",ply,ply)
    end
    local function begin(env,admin)
        env.fireTimer("activatorSpawner"); local ent=actors(env)[1]
        open(env,admin,ent); env.receive("SendNPCInformation",admin,ent.EventIdentifier)
        return env.ents.FindByName("devonsSpawnedEntity")
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
        eq(value,before.original,"table identity")
        seen=seen or {}; if seen[before] then return end; seen[before]=true
        local oldCount,newCount=0,0
        for key,child in pairs(before.entries) do oldCount=oldCount+1; retained(child,value[key],seen) end
        for _ in pairs(value) do newCount=newCount+1 end
        eq(newCount,oldCount,"table entries")
    end
    local function quiet(env,allowTimer,callback)
        local saved={}
        local function forbid(owner,key)
            saved[#saved+1]={owner,key,owner[key]}
            owner[key]=function() error("unexpected operation: " .. key) end
        end
        env.math=setmetatable({}, {__index=math}); forbid(env.math,"random")
        for _,key in ipairs({"determineRandomEvent","returnActivatorSpawns","returnSpawnPositions","destroyActivators","stopActivatorEvent"}) do forbid(env,key) end
        for _,key in ipairs({"Read","Write","Exists"}) do forbid(env.file,key) end
        for _,key in ipairs({"TableToJSON","JSONToTable"}) do forbid(env.util,key) end
        for _,key in ipairs({"Start","Send","Broadcast"}) do forbid(env.net,key) end
        for _,key in ipairs({"Create","Simple"}) do forbid(env.timer,key) end
        if not allowTimer then forbid(env.timer,"Start"); forbid(env.timer,"Stop") end
        forbid(env.ents,"Create")
        for _,ent in ipairs(env.entities) do forbid(ent,"Spawn"); forbid(ent,"Remove") end
        local positions,definitions=snapshot(env.SpawnPositions),snapshot(env.NPCEdits)
        local ok,err=pcall(callback)
        for _,entry in ipairs(saved) do entry[1][entry[2]]=entry[3] end
        assert(ok,err); retained(positions,env.SpawnPositions); retained(definitions,env.NPCEdits)
    end

    test("pause blocks an already due automatic callback before RNG or admission",function()
        local env,admin=setup(); command(env,admin,"!nextEvent Ambush")
        -- Do not assert routing first: the baseline must expose actual spawning.
        say(env,admin,pause)
        local samples=0; local sample=env.returnActivatorSpawns
        env.returnActivatorSpawns=function(...) samples=samples+1; return sample(...) end
        env.fireTimer("activatorSpawner"); env.timers.activatorSpawner.callback()
        actors(env,nil,0); eq(samples,0,"no position RNG")
        state(env,admin,true,"Ambush",nil)
    end)
    test("paused empty callback avoids event lookup sampling and all side effects",function()
        local env,admin=setup(); command(env,admin,pause)
        quiet(env,false,function()
            env.returnNPCInformation=function() error("unexpected event lookup") end
            env.timers.activatorSpawner.callback()
        end)
        actors(env,nil,0)
    end)
    test("resume starts the same full-delay timer once and consumes choice only on later success",function()
        local env,admin,calls=setup(); command(env,admin,"!nextEvent Ambush")
        local timer=env.timers.activatorSpawner; local callback=timer.callback
        command(env,admin,pause); eq(calls.stops,1); eq(timer.stopped,true)
        contains(command(env,admin,resume),"Normal spawn delay restarted")
        eq(calls.starts,1); eq(timer.stopped,false); eq(env.timers.activatorSpawner,timer)
        eq(timer.callback,callback); eq(timer.delay,env.returnDelayBetweenEvents()); eq(timer.repetitions,0)
        actors(env,nil,0); state(env,admin,false,"Ambush",nil)
        env.fireTimer("activatorSpawner"); actors(env,"Ambush",3); state(env,admin,false,nil,"Ambush")
    end)
    test("repeated schedule commands preserve both running and capacity-stopped timers",function()
        local env,admin,calls=setup()
        quiet(env,false,function() contains(command(env,admin,resume),"already enabled") end)
        command(env,admin,pause)
        quiet(env,false,function() contains(command(env,admin,pause),"already paused") end)
        command(env,admin,resume)
        quiet(env,false,function() command(env,admin,resume) end)
        eq(calls.starts,1); eq(calls.stops,1)
        env.fireTimer("activatorSpawner"); eq(calls.stops,2)
        quiet(env,false,function() command(env,admin,resume) end)
        eq(calls.starts,1); eq(calls.stops,2); eq(env.timers.activatorSpawner.stopped,true)
    end)
    for _,cmd in ipairs({pause,resume}) do
        for _,suffix in ipairs({" extra"," ","\t","\nRaid"}) do
            test(cmd .. " rejects extra input " .. string.format("%q",suffix),function()
                local env,admin=setup()
                if cmd == resume then command(env,admin,pause) end
                quiet(env,false,function() eq(command(env,admin,cmd .. suffix),"Usage: " .. cmd) end)
                state(env,admin,cmd == resume,nil,nil)
            end)
        end
        for _,role in ipairs({"nonadmin","nil","invalid","nonplayer"}) do
            test(cmd .. " rejects " .. role .. " without schedule changes",function()
                local env,admin=setup(); if cmd == resume then command(env,admin,pause) end
                local caller
                if role == "nonadmin" then caller=env.entity("player")
                elseif role == "invalid" then caller={valid=false}
                elseif role == "nonplayer" then caller=env.entity("worldspawn"); caller.admin=true end
                quiet(env,false,function()
                    eq(say(env,caller,cmd),role == "nonadmin" and "" or nil)
                end)
                if role == "nonadmin" then eq(#caller.chats,1); contains(caller.chats[1],"Only admins") end
                state(env,admin,cmd == resume,nil,nil)
            end)
        end
        test(cmd .. " leaves unrelated prefix and case variants untouched",function()
            local env,admin=setup()
            for _,text in ipairs({cmd .. "Now",cmd:lower()," " .. cmd,"hello " .. cmd}) do
                local before=#admin.chats
                quiet(env,false,function() eq(say(env,admin,text),nil) end)
                eq(#admin.chats,before)
            end
        end)
    end
    test("pause preserves selected manual actors and existing Start and Cancel grants",function()
        local env,admin,calls=setup(); command(env,admin,"!nextEvent Raid"); env.fireTimer("activatorSpawner")
        local batch=actors(env,"Raid",3); local manual=env.entity("activatorent"); manual.EventIdentifier="Ambush"; manual:Spawn()
        local other=env.entity("player"); open(env,admin,batch[1]); open(env,other,manual)
        command(env,admin,"!nextEvent Ambush"); local before=#env.messages
        quiet(env,true,function() command(env,admin,pause) end)
        eq(#env.messages,before); actors(env,nil,4); state(env,admin,true,"Ambush","Raid")
        local starts=calls.starts; batch[3]:Remove(); eq(calls.starts,starts)
        env.receive("CloseInteractionMenu",other,manual); eq(manual.moveChanges,1)
        env.receive("SendNPCInformation",other,"Ambush"); eq(env.totalEnemies,0)
        env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,5)
        state(env,admin,true,"Ambush",nil); eq(env.timers.activatorSpawner.stopped,true)
    end)
    test("manual activators remain usable when spawned while automatic creation is paused",function()
        local env,admin=setup(); command(env,admin,pause)
        local ent=env.entity("activatorent"); ent.EventIdentifier="Ambush"; ent:Spawn()
        open(env,admin,ent); env.receive("SendNPCInformation",admin,"Ambush")
        eq(env.totalEnemies,2); eq(env.timers.activatorSpawner.stopped,true)
    end)
    for _,deferred in ipairs({false,true}) do
        test("paused refresh retires actors and grants without timer restart, deferred=" .. tostring(deferred),function()
            local env,admin,calls=setup(); command(env,admin,"!nextEvent Raid"); env.fireTimer("activatorSpawner")
            local batch=actors(env); local other=env.entity("player")
            open(env,admin,batch[1]); open(env,other,batch[2]); command(env,admin,"!nextEvent Ambush")
            command(env,admin,pause); env.deferRemoval=deferred; local starts=calls.starts
            contains(command(env,admin,"!refreshActivators"),"Automatic spawning remains paused")
            actors(env,nil,0); eq(calls.starts,starts); state(env,admin,true,"Ambush",nil)
            env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,0)
            env.receive("CloseInteractionMenu",other,batch[2]); eq(batch[2].moveChanges,nil)
            env.flushRemovals(); eq(calls.starts,starts)
            env.timers.activatorSpawner.callback(); actors(env,nil,0)
            command(env,admin,resume); actors(env,nil,0); env.fireTimer("activatorSpawner"); actors(env,"Ambush",3)
        end)
    end
    for _,ending in ipairs({"victory","interrupted cleanup","admin stop"}) do
        test("active " .. ending .. " keeps its ordinary accounting while automatic spawning is paused",function()
            local env,admin,calls=setup(); local enemies=begin(env,admin)
            command(env,admin,"!nextEvent Ambush"); env.fire("OnNPCKilled",enemies[1],admin)
            local before=#env.messages
            quiet(env,true,function() command(env,admin,pause) end)
            eq(#env.messages,before); eq(env.totalEnemies,4)
            contains(state(env,admin,true,"Ambush",nil),'Active event: "Raid" (4/5')
            local starts=calls.starts
            contains(command(env,admin,"!refreshActivators"),"Cannot refresh")
            if ending == "admin stop" then say(env,admin,"!stopEvent")
            else
                for i=2,#enemies do
                    if ending == "interrupted cleanup" and i == 2 then enemies[i]:Remove()
                    else env.fire("OnNPCKilled",enemies[i],admin) end
                end
            end
            eq(env.totalEnemies,0); eq(calls.starts,starts); eq(env.timers.activatorSpawner.stopped,true)
            eq(env.messageCount("roundFinished"),ending == "victory" and 1 or 0)
            eq(env.messageCount("entitiesDeleted"),ending == "admin stop" and 1 or 0)
            env.timers.activatorSpawner.callback(); actors(env,nil,0); state(env,admin,true,"Ambush",nil)
        end)
    end
    test("resume during a fight waits for encounter retirement before starting the delay",function()
        local env,admin,calls=setup(); local enemies=begin(env,admin); command(env,admin,pause)
        local starts=calls.starts
        quiet(env,false,function() contains(command(env,admin,resume),"active encounter") end)
        eq(calls.starts,starts); eq(env.timers.activatorSpawner.stopped,true)
        env.timers.activatorSpawner.callback(); actors(env,nil,0); eq(env.totalEnemies,5)
        for _,enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
        eq(calls.starts,starts+1); eq(env.timers.activatorSpawner.stopped,false); actors(env,nil,0)
        env.fireTimer("activatorSpawner"); actors(env,"Raid",3)
    end)
    for _,gate in ipairs({"players","positions","capacity","definition","creation failure","self-removal"}) do
        test("resume preserves pending choice across blocked " .. gate .. " until a usable admission",function()
            local env,admin=setup(); command(env,admin,"!nextEvent Ambush"); command(env,admin,pause)
            local positions=env.SpawnPositions[1].activatorSpawnPositions; local info=env.NPCEdits[7].information
            local create=env.ents.Create
            if gate == "players" then env.minNumberOfPlayers=2
            elseif gate == "positions" then env.SpawnPositions[1].activatorSpawnPositions={}
            elseif gate == "capacity" then env.maxActivators=0
            elseif gate == "definition" then env.NPCEdits[7].information=nil
            elseif gate == "creation failure" then env.failClass="activatorent"
            else env.ents.Create=function(class)
                local ent=create(class); local spawn=ent.Spawn
                ent.Spawn=function(self) spawn(self); self:Remove() end
                return ent
            end end
            command(env,admin,resume); actors(env,nil,0); env.fireTimer("activatorSpawner")
            actors(env,nil,0); state(env,admin,false,"Ambush",nil)
            env.minNumberOfPlayers=0; env.maxActivators=3; env.NPCEdits[7].information=info
            env.SpawnPositions[1].activatorSpawnPositions=positions; env.failClass=nil; env.ents.Create=create
            env.fireTimer("activatorSpawner"); actors(env,"Ambush",3); state(env,admin,false,nil,"Ambush")
        end)
    end
    test("schedule status is read-only and enabled state is private to each fresh session",function()
        local env,admin=setup(); command(env,admin,"!nextEvent Ambush"); command(env,admin,pause)
        quiet(env,false,function() state(env,admin,true,"Ambush",nil) end)
        local fresh,other=setup(); state(fresh,other,false,nil,nil)
        eq(fresh.timers.activatorSpawner.stopped,false)
    end)
    for _,resumeInside in ipairs({false,true}) do
        for _,maximum in ipairs({1,3}) do
            test("Spawn callback pause retires old attempt, resume=" .. tostring(resumeInside) .. ", cap=" .. maximum,function()
                local env,admin,calls=setup(); env.maxActivators=maximum; command(env,admin,"!nextEvent Ambush")
                local create=env.ents.Create; local fired=false; local samples=0; local sample=env.returnActivatorSpawns
                env.returnActivatorSpawns=function(...) samples=samples+1; return sample(...) end
                env.ents.Create=function(class)
                    local ent=create(class); local spawn=ent.Spawn
                    ent.Spawn=function(self)
                        spawn(self)
                        if not fired then
                            fired=true; command(env,admin,pause)
                            if resumeInside then command(env,admin,resume) end
                        end
                    end
                    return ent
                end
                env.fireTimer("activatorSpawner"); eq(fired,true); actors(env,"Ambush",1)
                eq(samples,1,"old attempt must not sample again after pause")
                eq(calls.stops,1,"old attempt must not stop resumed timer at capacity")
                eq(calls.starts,resumeInside and 1 or 0)
                eq(env.timers.activatorSpawner.stopped,not resumeInside)
                state(env,admin,not resumeInside,nil,"Ambush")
                if not resumeInside then command(env,admin,resume) end
                env.fireTimer("activatorSpawner"); actors(env,"Ambush",maximum)
            end)
        end
    end
    test("pause callback preserves a replacement pending choice while admitting selected ownership",function()
        local env,admin=setup(); command(env,admin,"!nextEvent Ambush")
        local create=env.ents.Create
        env.ents.Create=function(class)
            local ent=create(class); local spawn=ent.Spawn
            ent.Spawn=function(self)
                spawn(self); command(env,admin,"!nextEvent Raid"); command(env,admin,pause)
            end
            return ent
        end
        env.fireTimer("activatorSpawner"); actors(env,"Ambush",1); state(env,admin,true,"Raid","Ambush")
    end)
end
