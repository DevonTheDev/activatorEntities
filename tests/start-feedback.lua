-- Exercise the actual menu and server receivers through the existing doubles.
-- ChatPrint calls and transferred fields are observable; native delivery is not.
return function(gmod, test, eq)
    local newCodec=dofile("tests/spawn-storage-codec.lua")
    local canonical,backup="devonsspawninfo.json","devonsspawninfo.backup.json"
    local expired = "This interaction expired. Use the activator again."
    local missing = "No enemy spawn position is available. Ask an admin to fix it, then use the activator again."
    local started = "2 enemies have been spawned. Eliminate them."

    local function storage(env)
        local state = {files={}, exists=0, reads=0, writes=0, canonicalWrites=0, backupWrites=0, encodes=0, decodes=0}
        local codec=newCodec(env,eq); state.codec=codec
        env.file.Exists = function(path, realm)
            eq(realm,"DATA"); state.exists=state.exists+1; return state.files[path] ~= nil
        end
        env.file.Read = function(path, realm)
            eq(realm,"DATA"); state.reads=state.reads+1; return state.files[path]
        end
        env.file.Write = function(path, content)
            state.writes=state.writes+1; state.path=path; state.content=content
            if path == canonical then state.canonicalWrites=state.canonicalWrites+1
            else eq(path,backup); state.backupWrites=state.backupWrites+1 end
            state.files[path]=content; return true
        end
        env.util.TableToJSON = function(value)
            state.encodes=state.encodes+1; state.value=codec.copy(value)
            return codec.encode(value)
        end
        env.util.JSONToTable = function(...)
            state.decodes=state.decodes+1; return codec.decode(...)
        end
        env.fire("Initialize")
        return state
    end
    local function open(server, client, ply, ent)
        local first = #client.panels+1
        ent:AcceptInput("Use", ply, ply)
        local message = server.messages[#server.messages]
        eq(message.name, "OpenInteractionMenu"); eq(message.player, ply)
        client.deliver(message)
        local frame, start, cancel
        for i=first,#client.panels do
            local panel=client.panels[i]
            if panel.class == "DFrame" then frame=panel
            elseif panel.class == "DButton" then
                if panel.text:find("Start",1,true) then start=panel else cancel=panel end
            end
        end
        return assert(frame), assert(start), assert(cancel)
    end
    local function click(server, client, ply, frame, button)
        local requests, cancels=#client.messages, client.messageCount("CloseInteractionMenu")
        button:DoClick()
        eq(frame.valid, false, "actual Start closes the menu")
        eq(#client.messages, requests+1, "actual Start emits one request")
        eq(client.messageCount("CloseInteractionMenu"), cancels, "Start does not send Cancel")
        local request=client.messages[#client.messages]
        eq(request.name, "SendNPCInformation")
        server.deliver(request, ply)
        return request
    end
    local function status(env, admin)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,"!eventStatus"), "")
        local lines={}
        for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        return table.concat(lines,"\n")
    end
    local function selected()
        local server,client=gmod.new(),gmod.new(true)
        local ioState=storage(server)
        local raid=server.NPCEdits[1].information
        server.NPCEdits[7]={name="Ambush", information={activatorModel=raid.activatorModel,
            npcPath="npc_combine_s", maxNPCs=2, dialogue="An ambush awaits."}}
        local admin=server.entity("player"); admin.admin=true
        local observer=server.entity("player")
        local ply=server.entity("player")
        eq(server.fire("PlayerSay",admin,"!nextEvent Ambush"), "")
        server.fireTimer("activatorSpawner")
        eq(server.fire("PlayerSay",admin,"!nextEvent Raid"), "")
        local ent=assert(server.ents.FindByClass("activatorent")[1])
        ply:SetPos(ent:GetPos())
        return server,client,ply,ent,admin,observer,ioState
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result={}
        for key,child in pairs(value) do result[key]=copy(child) end
        return result
    end
    local function sameData(actual, expected)
        eq(type(actual),type(expected),"spawn data type remains unchanged")
        if type(expected) ~= "table" then eq(actual,expected); return end
        for key,child in pairs(expected) do sameData(actual[key],child) end
        for key in pairs(actual) do assert(expected[key] ~= nil,"failure added spawn data") end
    end
    local function snapshot(env, ioState)
        local state={messages=#env.messages, errors=#env.errors, enemies=env.totalEnemies,
            count=env.activatorCount, actors=env.ents.FindByClass("activatorent"),
            timer=env.timers.activatorSpawner, delay=env.timers.activatorSpawner.delay,
            repetitions=env.timers.activatorSpawner.repetitions,
            stopped=env.timers.activatorSpawner.stopped, callbacks=env.timers.activatorSpawner.callback,
            positions=env.SpawnPositions, positionData=copy(env.SpawnPositions), chats={}, actorState={}}
        for _,ent in ipairs(state.actors) do
            state.actorState[ent]={marked=ent:IsMarkedForDeletion(), identifier=ent.EventIdentifier,
                info=ent.NPCInfo, model=ent:GetModel(), pos=ent:GetPos()}
        end
        for _,ply in ipairs(env.player.GetAll()) do state.chats[ply]=#ply.chats end
        if ioState then
            state.exists=ioState.exists; state.reads=ioState.reads; state.writes=ioState.writes
            state.encodes=ioState.encodes; state.decodes=ioState.decodes; state.files=copy(ioState.files)
        end
        return state
    end
    local function unchanged(env, state, ioState, requester, notice, diagnostic)
        eq(env.totalEnemies, state.enemies); eq(env.activatorCount, state.count)
        eq(#env.messages, state.messages, "failure adds no addon packet or progress broadcast")
        eq(#env.errors, state.errors+(diagnostic or 0), "only missing positions retain the diagnostic")
        eq(env.SpawnPositions, state.positions, "failure retains spawn data")
        sameData(env.SpawnPositions,state.positionData)
        local actors=env.ents.FindByClass("activatorent")
        eq(#actors, #state.actors)
        for i,ent in ipairs(actors) do
            eq(ent,state.actors[i]); local original=state.actorState[ent]
            eq(ent:IsMarkedForDeletion(),original.marked); eq(ent.EventIdentifier,original.identifier)
            eq(ent.NPCInfo,original.info); eq(ent:GetModel(),original.model); eq(ent:GetPos(),original.pos)
        end
        eq(env.timers.activatorSpawner, state.timer); eq(state.timer.delay, state.delay)
        eq(state.timer.repetitions,state.repetitions)
        eq(state.timer.stopped, state.stopped); eq(state.timer.callback, state.callbacks)
        for ply,count in pairs(state.chats) do
            eq(#ply.chats,count+(ply == requester and notice and 1 or 0),"feedback is private and occurs once")
        end
        if notice then
            eq(requester.chats[#requester.chats], notice)
            assert(#notice < 200, "guidance stays comfortably below ChatPrint's 255-byte limit")
        end
        if ioState then
            eq(ioState.reads,state.reads); eq(ioState.writes,state.writes); eq(ioState.encodes,state.encodes)
            eq(ioState.exists,state.exists); eq(ioState.decodes,state.decodes); sameData(ioState.files,state.files)
        end
    end

    for _,reason in ipairs({"expired", "missing positions"}) do
        test("actual Start privately explains " .. reason .. " and fresh Use recovers", function()
            local server,client,ply,ent,admin,observer,ioState=selected()
            local frame,button=open(server,client,ply,ent)
            if reason == "expired" then server.now=61
            else server.SpawnPositions[1].enemySpawnPositions={} end
            local beforeStatus=status(server,admin)
            local state=snapshot(server,ioState)
            local notice=reason == "expired" and expired or missing
            local request=click(server,client,ply,frame,button)
            unchanged(server,state,ioState,ply,notice,reason == "missing positions" and 1 or 0)
            eq(status(server,admin),beforeStatus,"failure preserves selected batch and pending choice")
            for _,actor in ipairs(state.actors) do eq(actor.EventIdentifier,"Ambush") end
            if reason == "missing positions" then
                eq(server.errors[#server.errors],"ERROR - There are no enemy spawn positions set for gm_construct\n")
            end
            local failed=snapshot(server,ioState)
            server.deliver(request,ply)
            unchanged(server,failed,ioState,nil,nil)

            if reason == "missing positions" then
                admin:SetPos(server.Vector(10,20,30))
                server.fire("PlayerSay",admin,"!setEnemySpawn")
                eq(#server.SpawnPositions[1].enemySpawnPositions,1)
                eq(server.SpawnPositions[1].enemySpawnPositions[1],admin:GetPos())
                eq(server.totalEnemies,0,"actual admin repair does not auto-start")
                eq(ioState.writes,1); eq(ioState.canonicalWrites,1); eq(ioState.backupWrites,0)
                eq(ioState.encodes,1); eq(ioState.path,canonical)
                ioState.codec.same(ioState.codec.decode(ioState.files[canonical]),server.SpawnPositions)
                assert(not admin.chats[#admin.chats]:find("remains in memory",1,true),"repair save is acknowledged")
                local repaired=snapshot(server,ioState)
                server.deliver(request,ply)
                unchanged(server,repaired,ioState,nil,nil)
            end
            local chats={}
            for _,player in ipairs(server.player.GetAll()) do chats[player]=#player.chats end
            local writes,encodes,reads,decodes,exists=ioState.writes,ioState.encodes,ioState.reads,ioState.decodes,ioState.exists
            frame,button=open(server,client,ply,ent)
            click(server,client,ply,frame,button)
            eq(server.totalEnemies,2); eq(#server.ents.FindByClass("activatorent"),0)
            eq(server.timers.activatorSpawner.stopped,true)
            eq(server.messageCount("ActivatorEventStatus"),1); eq(server.messageCount("roundFinished"),0)
            local progress=server.messages[#server.messages]
            eq(progress.name,"ActivatorEventStatus"); eq(progress.values[1],true)
            eq(progress.values[2],"Ambush"); eq(progress.values[3],2); eq(progress.values[4],2)
            eq(progress.values[5],false); client.deliver(progress)
            for _,player in ipairs(server.player.GetAll()) do
                eq(#player.chats,chats[player]+1); eq(player.chats[#player.chats],started)
            end
            for _,enemy in ipairs(server.ents.FindByName("devonsSpawnedEntity")) do
                eq(enemy:GetClass(),"npc_combine_s"); eq(enemy.health,server.returnEnemyHealth())
            end
            local afterStatus=status(server,admin)
            assert(afterStatus:find("Selected ready batch: none",1,true))
            assert(afterStatus:find('Pending next batch: "Raid"',1,true))
            eq(ioState.writes,writes); eq(ioState.encodes,encodes)
            eq(ioState.reads,reads); eq(ioState.decodes,decodes); eq(ioState.exists,exists)
            eq(#observer.chats,chats[observer]+1)
        end)
    end

    test("a matching actual Start at exactly 60 seconds still succeeds", function()
        local server,client=gmod.new(),gmod.new(true)
        local ply,ent=server.ready(); local observer=server.entity("player")
        local frame,button=open(server,client,ply,ent)
        server.now=60; click(server,client,ply,frame,button)
        eq(server.totalEnemies,5); eq(#server.errors,0)
        eq(#ply.chats,1); eq(#observer.chats,1)
        eq(ply.chats[1],"5 enemies have been spawned. Eliminate them.")
    end)

    -- Each stale lifetime also tests precedence: an invalid caller/actor/name
    -- cannot obtain an expiry explanation from a once-issued interaction.
    local rejected={"unissued", "wrong player", "wrong identifier", "cancelled", "invalid player",
        "non-player", "dead without hook", "death hook", "respawned", "disconnected",
        "invalid actor", "removed actor", "deletion-marked actor", "distant"}
    for _,time in ipairs({0,61}) do
        for _,kind in ipairs(rejected) do
            test("Start feedback stays silent for " .. kind .. " at " .. time .. " seconds", function()
                local env=gmod.new(); local ioState=storage(env)
                local ply,ent=env.ready(); local observer=env.entity("player")
                if kind ~= "unissued" then ent:AcceptInput("Use",ply,ply) end
                local sender,identifier=ply,"Raid"
                if kind == "wrong player" then sender=observer
                elseif kind == "wrong identifier" then identifier="Forged"
                elseif kind == "cancelled" then env.receive("CloseInteractionMenu",ply,ent)
                elseif kind == "invalid player" then ply.valid=false
                elseif kind == "non-player" then ply.class="npc_zombie"
                elseif kind == "dead without hook" then ply.alive=false
                elseif kind == "death hook" then ply.alive=false; env.fire("PlayerDeath",ply)
                elseif kind == "respawned" then env.fire("PlayerSpawn",ply)
                elseif kind == "disconnected" then env.fire("PlayerDisconnected",ply)
                elseif kind == "invalid actor" then ent.valid=false
                elseif kind == "removed actor" then ent:Remove()
                elseif kind == "deletion-marked actor" then env.deferRemoval=true; ent:Remove()
                elseif kind == "distant" then ply:SetPos(ent:GetPos()+env.Vector(201,0,0)) end
                env.now=time
                local state=snapshot(env,ioState)
                local senderChats=#sender.chats
                env.receive("SendNPCInformation",sender,identifier)
                unchanged(env,state,ioState,nil,nil)
                eq(env.totalEnemies,0)
                eq(#sender.chats,senderChats); eq(#observer.chats,state.chats[observer])
                -- A wrong-player packet must leave the legitimate player's permission intact.
                if kind == "wrong player" and time == 0 then
                    env.receive("SendNPCInformation",ply,"Raid"); eq(env.totalEnemies,5)
                elseif kind == "wrong identifier" then
                    env.now=0; env.receive("SendNPCInformation",ply,"Raid")
                    eq(env.totalEnemies,0); eq(#ply.chats,state.chats[ply],"mismatch consumed permission")
                end
            end)
        end
    end

    test("an active event silently rejects an older actual menu Start", function()
        local server,client=gmod.new(),gmod.new(true)
        local ply,ent=server.ready(); local frame,button=open(server,client,ply,ent)
        local other=server.entity("player"); other:SetPos(ent:GetPos())
        ent:AcceptInput("Use",other,other); server.receive("SendNPCInformation",other,"Raid")
        server.now=61; local state=snapshot(server)
        click(server,client,ply,frame,button); unchanged(server,state,nil,nil,nil)
    end)
    test("actual Cancel consumes permission silently and reopening still starts", function()
        local server,client=gmod.new(),gmod.new(true)
        local ply,ent=server.ready(); local observer=server.entity("player")
        local frame,_,cancel=open(server,client,ply,ent)
        cancel:DoClick(); eq(frame.valid,false)
        eq(client.messageCount("CloseInteractionMenu"),1); eq(client.messageCount("SendNPCInformation"),0)
        server.deliver(client.messages[#client.messages],ply)
        server.now=61; local state=snapshot(server)
        server.receive("SendNPCInformation",ply,"Raid"); unchanged(server,state,nil,nil,nil)
        local button; frame,button=open(server,client,ply,ent)
        click(server,client,ply,frame,button)
        eq(server.totalEnemies,5); eq(#ply.chats,1); eq(#observer.chats,1)
        eq(ply.chats[1],"5 enemies have been spawned. Eliminate them.")
    end)
    for _,reason in ipairs({"expired", "missing positions"}) do
        test("Start guidance for " .. reason .. " contains no configured name or position", function()
            local server,client=gmod.new(),gmod.new(true)
            local name=string.rep("火",200)
            server.NPCEdits[1].name=name; server.determineRandomEvent=function() return name end
            local ply,ent=server.ready(); local observer=server.entity("player")
            local frame,button=open(server,client,ply,ent)
            if reason == "expired" then server.now=61 else server.SpawnPositions[1].enemySpawnPositions={} end
            click(server,client,ply,frame,button)
            eq(#ply.chats,1); eq(#observer.chats,0)
            eq(ply.chats[1],reason == "expired" and expired or missing)
            assert(#ply.chats[1] < 200)
        end)
    end
    test("zero successful enemy creation keeps its existing silent post-activation cleanup", function()
        local server,client=gmod.new(),gmod.new(true)
        local ply,ent=server.ready(); local observer=server.entity("player")
        local frame,button=open(server,client,ply,ent)
        server.failClass="npc_stalker"; click(server,client,ply,frame,button)
        eq(server.totalEnemies,0); eq(#server.ents.FindByClass("activatorent"),0)
        eq(#ply.chats,0); eq(#observer.chats,0); eq(#server.errors,1)
        eq(server.messageCount("ActivatorEventStatus"),1); eq(server.messageCount("roundFinished"),0)
        eq(server.timers.activatorSpawner.stopped,false)
    end)
end
