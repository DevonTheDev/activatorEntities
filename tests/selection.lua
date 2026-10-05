-- Execute the addon itself; the doubles cover Lua lifecycle behavior, not a
-- live GMod server. Deferred Remove keeps IsValid true until EntityRemoved.
return function(gmod, test, eq)
    local function configured()
        local env=gmod.new()
        local raid=env.NPCEdits[1].information
        env.NPCEdits[7]={name="Ambush", information={activatorModel=raid.activatorModel,
            npcPath="npc_combine_s", maxNPCs=2, dialogue="An ambush awaits."}}
        env.NPCEdits[19]={name="Supply Raid: Alpha!", information=raid}
        env.determineRandomEvent=function() return "Raid" end
        local admin=env.entity("player"); admin.admin=true
        return env, admin
    end
    local function say(env, ply, command)
        return env.fire("PlayerSay", ply, command)
    end
    local function queue(env, admin, name)
        eq(say(env, admin, "!nextEvent " .. name), "", "selection command is handled privately")
    end
    local function status(env, admin)
        local before=#admin.chats
        eq(say(env, admin, "!eventStatus"), "", "status command is handled privately")
        local lines={}
        for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        assert(#lines > 0, "status explains current state")
        return table.concat(lines, "\n")
    end
    local function contains(text, expected)
        assert(text:find(expected, 1, true), "expected '" .. expected .. "' in '" .. text .. "'")
    end
    local function pending(env, admin, name)
        contains(status(env, admin), "Pending next batch: " .. (name and ('"' .. name .. '"') or "none"))
    end
    local function pinned(env, admin, name)
        contains(status(env, admin), "Selected ready batch: " .. (name and ('"' .. name .. '"') or "none"))
    end
    local function actors(env, name, expected)
        local count=0
        for _, ent in ipairs(env.ents.FindByClass("activatorent")) do
            if not ent:IsMarkedForDeletion() then
                if name then eq(ent.EventIdentifier, name, "spawned event identifier") end
                count=count+1
            end
        end
        if expected then eq(count, expected, "usable activator count") end
        return count
    end
    local function removeActors(env)
        for _, ent in ipairs(env.ents.FindByClass("activatorent")) do ent:Remove() end
    end
    local function start(env, ply, ent)
        ent=ent or assert(env.ents.FindByClass("activatorent")[1])
        ply:SetPos(ent:GetPos()); ent:AcceptInput("Use", ply, ply)
        env.receive("SendNPCInformation", ply, ent.EventIdentifier)
        return env.ents.FindByName("devonsSpawnedEntity")
    end
    local function noSideEffects(env, callback)
        local originals={}
        local function forbid(owner, key)
            originals[#originals+1]={owner,key,owner[key]}
            owner[key]=function() error("command called forbidden " .. key) end
        end
        env.math=setmetatable({}, {__index=math})
        forbid(env.math,"random"); forbid(env,"determineRandomEvent")
        forbid(env,"returnActivatorSpawns"); forbid(env,"returnSpawnPositions")
        for _, key in ipairs({"Start","Stop","Create","Simple"}) do forbid(env.timer,key) end
        for _, key in ipairs({"Read","Write"}) do forbid(env.file,key) end
        for _, key in ipairs({"Start","Send","Broadcast"}) do forbid(env.net,key) end
        forbid(env.ents,"Create"); forbid(env,"destroyActivators")
        for _, ent in ipairs(env.entities) do forbid(ent,"Remove"); forbid(ent,"Spawn") end
        local ok, err=pcall(callback)
        for _, entry in ipairs(originals) do entry[1][entry[2]]=entry[3] end
        assert(ok,err)
    end

    for _, name in ipairs({"Raid", "Ambush", "Supply Raid: Alpha!", "none", "clear", "random", "raid"}) do
        test("admin selection accepts exact configured name " .. name, function()
            local env, admin=configured()
            if name == "none" or name == "clear" or name == "random" or name == "raid" then
                env.NPCEdits[30]={name=name, information=env.NPCEdits[7].information}
            end
            queue(env,admin,name); pending(env,admin,name); actors(env,nil,0)
            env.fireTimer("activatorSpawner"); actors(env,name,3)
            pending(env,admin,nil); pinned(env,admin,name)
        end)
    end
    for _, bad in ipairs({"ambush", "AMBUSH", "Supply Raid", "Unknown", "Ambush "}) do
        test("invalid exact selection preserves pending choice: " .. bad, function()
            local env,admin=configured(); queue(env,admin,"Ambush")
            queue(env,admin,bad); pending(env,admin,"Ambush")
            env.fireTimer("activatorSpawner"); actors(env,"Ambush",3)
        end)
    end
    for _, failure in ipairs({"duplicate", "missing information", "invalid information"}) do
        test("selection rejects " .. failure .. " without replacing pending", function()
            local env,admin=configured(); queue(env,admin,"Raid")
            if failure == "duplicate" then env.NPCEdits[50]={name="Ambush",information=env.NPCEdits[7].information}
            elseif failure == "missing information" then env.NPCEdits[7].information=nil
            else env.NPCEdits[7].information=false end
            queue(env,admin,"Ambush"); pending(env,admin,"Raid")
            env.fireTimer("activatorSpawner"); actors(env,"Raid",3)
        end)
    end
    test("empty selection explains usage and preserves the queue", function()
        local env,admin=configured(); queue(env,admin,"Ambush")
        local before=#admin.chats
        eq(say(env,admin,"!nextEvent"), "")
        contains(admin.chats[before+1], "!nextEvent")
        pending(env,admin,"Ambush")
    end)
    test("replacement and clear operate on the one pending slot", function()
        local env,admin=configured(); queue(env,admin,"Raid"); queue(env,admin,"Ambush")
        pending(env,admin,"Ambush")
        eq(say(env,admin,"!clearNextEvent"), ""); pending(env,admin,nil)
        eq(say(env,admin,"!clearNextEvent"), ""); pending(env,admin,nil)
        env.fireTimer("activatorSpawner"); actors(env,"Raid",3); pinned(env,admin,nil)
    end)
    test("selection commands require an admin and leave unrelated chat alone", function()
        local env,admin=configured(); queue(env,admin,"Ambush")
        local ordinary=env.entity("player")
        for _, command in ipairs({"!nextEvent Raid", "!clearNextEvent", "!eventStatus"}) do
            eq(say(env,ordinary,command), "")
        end
        contains(table.concat(ordinary.chats,"\n"), "admin")
        pending(env,admin,"Ambush")
        for _, command in ipairs({"hello", "!nextEventual Raid", "!eventStatusExtra", "!clearNextEventExtra"}) do
            eq(say(env,admin,command), nil)
        end
    end)
    test("commands never spawn remove write network use RNG or restart timers", function()
        local env,admin=configured(); env.fireTimer("activatorSpawner")
        local ent=env.ents.FindByClass("activatorent")[1]
        admin:SetPos(ent:GetPos()); ent:AcceptInput("Use",admin,admin)
        noSideEffects(env,function()
            queue(env,admin,"Ambush"); status(env,admin)
            say(env,admin,"!clearNextEvent"); queue(env,admin,"Missing")
            say(env,admin,"!nextEvent"); queue(env,admin,"Ambush")
        end)
        env.receive("SendNPCInformation",admin,"Raid")
        eq(env.totalEnemies,5,"commands preserve a valid open interaction")
        pending(env,admin,"Ambush")
    end)
    test("queue and status keep a running timer's schedule and configured delay", function()
        local env,admin=configured(); local timer=env.timers.activatorSpawner
        eq(timer.delay,env.returnDelayBetweenEvents()); eq(timer.stopped,false)
        noSideEffects(env,function() queue(env,admin,"Ambush"); status(env,admin); say(env,admin,"!clearNextEvent") end)
        eq(env.timers.activatorSpawner,timer); eq(timer.stopped,false)
    end)
    test("queued choice waits for a fresh batch while random ready actors refill normally", function()
        local env,admin=configured(); env.fireTimer("activatorSpawner")
        queue(env,admin,"Ambush"); actors(env,"Raid",3); pinned(env,admin,nil)
        env.ents.FindByClass("activatorent")[1]:Remove(); env.fireTimer("activatorSpawner")
        actors(env,"Raid",3); pending(env,admin,"Ambush")
        removeActors(env); env.fireTimer("activatorSpawner")
        actors(env,"Ambush",3); pending(env,admin,nil)
    end)
    test("pending replacement and clear leave a selected ready batch and its refills pinned", function()
        local env,admin=configured(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        queue(env,admin,"Supply Raid: Alpha!"); say(env,admin,"!clearNextEvent")
        env.ents.FindByClass("activatorent")[1]:Remove(); env.fireTimer("activatorSpawner")
        actors(env,"Ambush",3); pinned(env,admin,"Ambush"); pending(env,admin,nil)
    end)
    test("queue during an active event applies only after normal completion and the next timer", function()
        local env,admin=configured(); env.fireTimer("activatorSpawner"); local enemies=start(env,admin)
        queue(env,admin,"Ambush"); noSideEffects(env,function()
            contains(status(env,admin),'Active event: "Raid"')
            contains(status(env,admin),'5/5')
        end)
        env.timers.activatorSpawner.callback(); actors(env,nil,0); eq(env.totalEnemies,5)
        for _, enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
        pending(env,admin,"Ambush"); actors(env,nil,0)
        env.fireTimer("activatorSpawner"); actors(env,"Ambush",3)
    end)
    for _, blocked in ipairs({"minimum players", "missing map", "missing positions", "zero cap", "creation failure", "self-removal"}) do
        test("pending choice survives " .. blocked .. " and retries on the normal timer", function()
            local env,admin=configured(); queue(env,admin,"Ambush")
            local oldCreate=env.ents.Create; local positions=env.SpawnPositions[1].activatorSpawnPositions
            if blocked == "minimum players" then env.minNumberOfPlayers=2
            elseif blocked == "missing map" then env.map="missing"
            elseif blocked == "missing positions" then env.SpawnPositions[1].activatorSpawnPositions={}
            elseif blocked == "zero cap" then env.maxActivators=0
            elseif blocked == "creation failure" then env.failClass="activatorent"
            else
                env.deferRemoval=true
                env.ents.Create=function(class)
                    local ent=oldCreate(class)
                    if class == "activatorent" then ent.Spawn=function(self) self:Remove() end end
                    return ent
                end
            end
            env.fireTimer("activatorSpawner"); actors(env,nil,0); pending(env,admin,"Ambush"); pinned(env,admin,nil)
            eq(env.timers.activatorSpawner.stopped,false)
            env.minNumberOfPlayers=0; env.map="gm_construct"; env.maxActivators=3; env.failClass=nil
            env.SpawnPositions[1].activatorSpawnPositions=positions; env.ents.Create=oldCreate
            env.fireTimer("activatorSpawner"); actors(env,"Ambush",3); pending(env,admin,nil)
        end)
    end
    test("first surviving partial spawn consumes pending and pins all later automatic refills", function()
        local env,admin=configured(); queue(env,admin,"Ambush"); env.deferRemoval=true
        local create=env.ents.Create; local attempt=0
        env.ents.Create=function(class)
            if class ~= "activatorent" then return create(class) end
            attempt=attempt+1
            if attempt == 1 then return {valid=false} end
            local ent=create(class)
            if attempt == 2 then ent.Spawn=function(self) self:Remove() end end
            return ent
        end
        env.fireTimer("activatorSpawner"); actors(env,"Ambush",1)
        pending(env,admin,nil); pinned(env,admin,"Ambush"); eq(env.timers.activatorSpawner.stopped,false)
        queue(env,admin,"Raid"); env.ents.Create=create
        env.fireTimer("activatorSpawner"); actors(env,"Ambush",3); pending(env,admin,"Raid")
        eq(env.timers.activatorSpawner.stopped,true)
    end)
    for _, change in ipairs({"replace", "clear", "replace and restore"}) do
        test("Spawn callback " .. change .. " cannot be consumed by an older admitted slot", function()
            local env,admin=configured(); queue(env,admin,"Ambush")
            local create=env.ents.Create; local changed=false
            env.ents.Create=function(class)
                local ent=create(class); local spawn=ent.Spawn
                if class == "activatorent" then
                    ent.Spawn=function(self)
                        spawn(self)
                        if changed then return end
                        changed=true
                        if change == "clear" then say(env,admin,"!clearNextEvent")
                        else
                            queue(env,admin,"Raid")
                            if change == "replace and restore" then queue(env,admin,"Ambush") end
                        end
                    end
                end
                return ent
            end
            env.fireTimer("activatorSpawner"); actors(env,"Ambush",3); pinned(env,admin,"Ambush")
            local expected
            if change == "replace" then expected="Raid"
            elseif change == "replace and restore" then expected="Ambush" end
            pending(env,admin,expected)
            env.ents.FindByClass("activatorent")[1]:Remove(); env.fireTimer("activatorSpawner")
            actors(env,"Ambush",3); pending(env,admin,expected)
        end)
    end
    test("successful refill retains its admitted pin when Spawn removes the last old owner", function()
        local env,admin=configured(); env.maxActivators=1; queue(env,admin,"Ambush")
        env.fireTimer("activatorSpawner"); local old=env.ents.FindByClass("activatorent")[1]
        env.maxActivators=2
        local create=env.ents.Create
        env.ents.Create=function(class)
            local ent=create(class); local spawn=ent.Spawn
            if class == "activatorent" then ent.Spawn=function(self) old:Remove(); spawn(self) end end
            return ent
        end
        env.timers.activatorSpawner.callback(); actors(env,"Ambush",1); pinned(env,admin,"Ambush")
        env.ents.Create=create; env.fireTimer("activatorSpawner")
        actors(env,"Ambush",2); pinned(env,admin,"Ambush")
    end)
    test("manual activators do not consume pending or adopt its event", function()
        local env,admin=configured(); queue(env,admin,"Ambush")
        local manual=env.entity("activatorent"); manual:Spawn()
        eq(manual.EventIdentifier,"Raid"); pending(env,admin,"Ambush")
        env.fireTimer("activatorSpawner"); actors(env,"Raid",3); pending(env,admin,"Ambush")
        removeActors(env); env.fireTimer("activatorSpawner"); actors(env,"Ambush",3)
    end)
    test("manual survivors cannot keep a removed selected batch pinned", function()
        local env,admin=configured(); env.maxActivators=2; queue(env,admin,"Ambush")
        env.fireTimer("activatorSpawner"); local selected=env.ents.FindByClass("activatorent")
        local manual=env.entity("activatorent"); manual:Spawn()
        queue(env,admin,"Supply Raid: Alpha!")
        for _, ent in ipairs(selected) do ent:Remove() end
        pinned(env,admin,nil); pending(env,admin,"Supply Raid: Alpha!")
        env.fireTimer("activatorSpawner"); actors(env,"Raid",2)
        removeActors(env); env.fireTimer("activatorSpawner"); actors(env,"Supply Raid: Alpha!",2)
    end)
    test("last EntityRemoved releases the pin before native physical invalidation", function()
        local env,admin=configured(); env.maxActivators=1; queue(env,admin,"Ambush")
        env.fireTimer("activatorSpawner"); local ent=env.ents.FindByClass("activatorent")[1]
        -- Native EntityRemoved can observe the departing entity as still valid.
        env.hooks.EntityRemoved.clearRemovedEventEntities(ent)
        eq(ent.valid,true); ent.valid=false
        env.fireTimer("activatorSpawner"); actors(env,"Raid",1); pinned(env,admin,nil)
    end)
    test("a deletion-marked actor cannot consume a new selection before physical removal", function()
        local env,admin=configured(); env.maxActivators=2; queue(env,admin,"Ambush")
        env.fireTimer("activatorSpawner"); local old=env.ents.FindByClass("activatorent")
        admin:SetPos(old[1]:GetPos()); old[1]:AcceptInput("Use",admin,admin)
        env.deferRemoval=true; removeActors(env); queue(env,admin,"Supply Raid: Alpha!")
        -- Timer callback may already be due while Remove is still deferred.
        env.timers.activatorSpawner.callback(); actors(env,"Supply Raid: Alpha!",2)
        env.receive("SendNPCInformation",admin,"Ambush"); eq(env.totalEnemies,0)
        old[1]:AcceptInput("Use",admin,admin); env.receive("SendNPCInformation",admin,"Ambush")
        eq(env.totalEnemies,0); pinned(env,admin,"Supply Raid: Alpha!")
        env.flushRemovals(); pinned(env,admin,"Supply Raid: Alpha!")
    end)
    for _, unavailable in ipairs({"removed", "duplicate", "missing information", "missing config"}) do
        test("unavailable pending " .. unavailable .. " pauses without random fallback", function()
            local env,admin=configured(); queue(env,admin,"Ambush")
            local edits=env.NPCEdits; local info=edits[7].information
            if unavailable == "removed" then edits[7]=nil
            elseif unavailable == "duplicate" then edits[50]={name="Ambush",information=info}
            elseif unavailable == "missing information" then edits[7].information=nil
            else env.NPCEdits=nil end
            env.determineRandomEvent=function() error("unavailable choice cannot fall back to random") end
            env.fireTimer("activatorSpawner"); actors(env,nil,0)
            contains(status(env,admin), "unavailable")
            env.NPCEdits=edits; edits[7]={name="Ambush",information=info}; edits[50]=nil
            env.fireTimer("activatorSpawner"); actors(env,"Ambush",3); pending(env,admin,nil)
        end)
    end
    test("unavailable selected batch pauses refills and recovers with the same name", function()
        local env,admin=configured(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        local definition=env.NPCEdits[7]; env.NPCEdits[7]=nil
        env.ents.FindByClass("activatorent")[1]:Remove()
        env.determineRandomEvent=function() error("a pinned batch cannot fall back to random") end
        env.fireTimer("activatorSpawner"); actors(env,"Ambush",2)
        contains(status(env,admin), "unavailable"); queue(env,admin,"Raid")
        env.NPCEdits[7]=definition; env.fireTimer("activatorSpawner")
        actors(env,"Ambush",3); pending(env,admin,"Raid")
    end)
    test("missing enemy positions and dialogue cancel preserve ready pin and later pending", function()
        local env,admin=configured(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        queue(env,admin,"Raid"); local ent=env.ents.FindByClass("activatorent")[1]
        admin:SetPos(ent:GetPos()); ent:AcceptInput("Use",admin,admin)
        env.receive("CloseInteractionMenu",admin,ent); env.receive("SendNPCInformation",admin,"Ambush")
        eq(env.totalEnemies,0); pinned(env,admin,"Ambush"); pending(env,admin,"Raid")
        env.SpawnPositions[1].enemySpawnPositions={}; start(env,admin,ent)
        eq(env.totalEnemies,0); pinned(env,admin,"Ambush"); pending(env,admin,"Raid")
    end)
    test("invalid enemy count retains selection until an activation is accepted", function()
        local env,admin=configured(); env.NPCEdits[7].information.maxNPCs=0
        queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner"); start(env,admin)
        eq(env.totalEnemies,0); pinned(env,admin,"Ambush")
    end)
    test("zero enemy spawn failure ends the pin without restoring the consumed choice", function()
        local env,admin=configured(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        env.failClass="npc_combine_s"; start(env,admin)
        eq(env.totalEnemies,0); pending(env,admin,nil); pinned(env,admin,nil)
        eq(env.messageCount("roundFinished"),0); env.fireTimer("activatorSpawner"); actors(env,"Raid",3)
    end)
    test("admin stop preserves pending and clears no already-consumed choice", function()
        local env,admin=configured(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        start(env,admin); queue(env,admin,"Supply Raid: Alpha!"); say(env,admin,"!stopEvent")
        eq(env.totalEnemies,0); pinned(env,admin,nil); pending(env,admin,"Supply Raid: Alpha!")
        eq(env.messageCount("roundFinished"),0); env.fireTimer("activatorSpawner")
        actors(env,"Supply Raid: Alpha!",3)
    end)
    test("status distinguishes active ready and pending without publishing encounter state", function()
        local env,admin=configured(); queue(env,admin,"Ambush"); env.fireTimer("activatorSpawner")
        queue(env,admin,"Raid")
        noSideEffects(env,function()
            local text=status(env,admin)
            contains(text,"Active event: none"); contains(text,"Ready activators: 3")
            contains(text,'Ready event: "Ambush" (3)'); contains(text,'Pending next batch: "Raid"')
        end)
        local enemies=start(env,admin); enemies[1]:Remove()
        noSideEffects(env,function()
            local text=status(env,admin)
            contains(text,'Active event: "Ambush"'); contains(text,"1/2")
            contains(text,"interrupted"); contains(text,"Ready activators: 0")
            contains(text,"Selected ready batch: none"); contains(text,'Pending next batch: "Raid"')
        end)
    end)
    test("status and help bound configured and ready name lists to ChatPrint limits", function()
        local env,admin=configured(); local name=string.rep("Long",150)
        env.NPCEdits[60]={name=name,information=env.NPCEdits[7].information}
        queue(env,admin,name); env.fireTimer("activatorSpawner")
        for i=1,50 do
            local custom="Custom event " .. i .. " " .. string.rep("x",300)
            env.NPCEdits[100+i]={name=custom,information=env.NPCEdits[7].information}
            local ent=env.entity("activatorent"); ent.EventIdentifier=custom; ent:Spawn()
        end
        noSideEffects(env,function()
            local before=#admin.chats; status(env,admin)
            assert(#admin.chats-before <= 16, "ready status has a bounded number of lines")
            before=#admin.chats; say(env,admin,"!nextEvent")
            assert(#admin.chats-before <= 12, "configured help has a bounded number of lines")
        end)
        for _, line in ipairs(admin.chats) do assert(#line <= 255,"ChatPrint line exceeds 255 bytes") end
    end)
    for _, character in ipairs({"é", "火", "🚀"}) do
        for _, state in ipairs({"active", "pending unavailable", "selected unavailable", "ready count"}) do
            test("long UTF-8 name preserves " .. state .. " metadata: " .. character, function()
                local env,admin=configured(); local name=string.rep(character,200)
                env.NPCEdits[60]={name=name,information=env.NPCEdits[7].information}
                queue(env,admin,name)
                local prefix, expected
                if state == "pending unavailable" then
                    env.NPCEdits[60]=nil
                    prefix,expected="Pending next batch: ","(unavailable)"
                else
                    env.fireTimer("activatorSpawner")
                    if state == "active" then
                        local enemies=start(env,admin); enemies[1]:Remove()
                        prefix,expected="Active event: ","1/2 enemies remaining; interrupted"
                    elseif state == "selected unavailable" then
                        env.NPCEdits[60]=nil
                        prefix,expected="Selected ready batch: ","(unavailable)"
                    else prefix,expected="Ready event: ","(3)" end
                end
                noSideEffects(env,function()
                    local found
                    for line in status(env,admin):gmatch("[^\n]+") do
                        if line:sub(1,#prefix) == prefix then found=line end
                    end
                    assert(found,"status contains the expected state line")
                    contains(found,expected)
                    assert(#found <= 255,"status exceeds ChatPrint's byte limit")
                    contains(found,"...")
                    local remainder=found:gsub(character,"")
                    assert(not remainder:find("[\128-\255]"),"name was split inside a UTF-8 character")
                end)
            end)
        end
    end
    test("selected encounter uses real client start progress and normal completion", function()
        local server,admin=configured(); local client=gmod.new(true)
        queue(server,admin,"Ambush"); server.fireTimer("activatorSpawner")
        local ent=server.ents.FindByClass("activatorent")[1]
        local player=server.entity("player"); player:SetPos(ent:GetPos())
        ent:AcceptInput("Use",player,player); client.deliver(server.messages[#server.messages])
        local button
        for _, panel in ipairs(client.panels) do
            if panel.class == "DButton" and panel.text:find("Start",1,true) then button=panel end
        end
        assert(button):DoClick(); server.deliver(client.messages[#client.messages],player)
        eq(server.totalEnemies,2); pinned(server,admin,nil); pending(server,admin,nil)
        local snapshot=server.messages[#server.messages]; eq(snapshot.name,"ActivatorEventStatus")
        eq(snapshot.values[2],"Ambush"); client.deliver(snapshot)
        for _, enemy in ipairs(server.ents.FindByName("devonsSpawnedEntity")) do
            eq(enemy:GetClass(),"npc_combine_s"); eq(enemy.health,server.returnEnemyHealth())
            server.fire("OnNPCKilled",enemy,player)
        end
        eq(server.totalEnemies,0); eq(server.messageCount("roundFinished"),1)
        client.deliver(server.messages[#server.messages-1]); client.deliver(server.messages[#server.messages])
        eq(client.messageCount("SendNPCInformation"),1)
        eq(server.timers.activatorSpawner.stopped,false)
        server.fireTimer("activatorSpawner"); actors(server,"Raid",3)
    end)
end
