-- Exercise actual chat, spawn, encounter and client handlers in isolated realms.
-- The explicit API, storage and deferred-removal doubles prove calls and state,
-- not native wall-clock delays, network delivery, Derma rendering or DATA JSON.
return function(gmod,test,eq)
    local canonical="devonsspawninfo.json"
    local function contains(text,fragment)
        assert(text:find(fragment,1,true),"missing " .. fragment .. " in " .. text)
    end
    local function tree(value)
        local result={value=value}
        if type(value) == "table" then
            result.entries={}
            for key,child in pairs(value) do result.entries[key]=tree(child) end
        end
        return result
    end
    local function sameTree(value,state)
        assert(rawequal(value,state.value),"existing value or object changed")
        if state.entries then
            for key,child in pairs(state.entries) do sameTree(value[key],child) end
            for key in pairs(value) do assert(state.entries[key],"unexpected field " .. tostring(key)) end
        end
    end
    local function coords(actual,expected,offset)
        offset=offset or 0
        eq(actual.x,expected.x+offset); eq(actual.y,expected.y+offset); eq(actual.z,expected.z)
    end
    local function privateSay(env,player,command)
        local before={}
        for _,other in ipairs(env.player.GetAll()) do before[other]=#other.chats end
        eq(env.fire("PlayerSay",player,command),"","exact command is handled privately")
        local lines={}
        for i=before[player]+1,#player.chats do
            assert(#player.chats[i] <= 255,"private reply stays within ChatPrint limit")
            lines[#lines+1]=player.chats[i]
        end
        assert(#lines > 0,"caller receives a private explanation")
        for other,count in pairs(before) do
            if other ~= player then eq(#other.chats,count,"bystander receives no command response") end
        end
        return table.concat(lines,"\n")
    end
    local function status(env,player) return privateSay(env,player,"!eventStatus") end
    local function pending(env,player,name)
        contains(status(env,player),name and ('Pending next batch: "' .. name .. '"') or "Pending next batch: none")
    end
    local function usable(env)
        local result={}
        for _,actor in ipairs(env.ents.FindByClass("activatorent")) do
            if not actor:IsMarkedForDeletion() then result[#result+1]=actor end
        end
        return result
    end
    local function fixture(mode)
        local env=gmod.new()
        local ioState={files={},reads=0,writes=0,encodes=0}
        env.print=function() end
        env.file.Exists=function(path,realm) eq(realm,"DATA"); return ioState.files[path] ~= nil end
        env.file.Read=function(path,realm) eq(realm,"DATA"); ioState.reads=ioState.reads+1; return ioState.files[path] end
        env.file.Write=function(path,contents) ioState.writes=ioState.writes+1; ioState.files[path]=contents; return true end
        env.util.TableToJSON=function() ioState.encodes=ioState.encodes+1; return '{"fixture":' .. ioState.encodes .. '}' end
        env.util.JSONToTable=function() return nil end
        if mode == "rejected storage" then ioState.files[canonical]="invalid but recoverable data" end
        if mode ~= "uninitialized storage" then env.fire("Initialize") end
        local current={map="gm_construct",enemySpawnPositions={[2]=env.Vector(10,20,30)},
            activatorSpawnPositions={[11]=env.Vector(100,200,300)}}
        env.SpawnPositions={[4]=current,[19]={map="other_map",enemySpawnPositions={},activatorSpawnPositions={}}}
        env.NPCEdits[7]={name="Ambush",information={activatorModel="models/barney.mdl",
            npcPath="npc_combine_s",maxNPCs=2,dialogue="Another encounter"}}
        local admin=env.entity("player"); admin.admin=true
        local observer=env.entity("player")
        local calls={random=0,starts=0,stops=0,creates=0}
        env.math=setmetatable({random=function(...) calls.random=calls.random+1; return math.random(...) end},{__index=math})
        local start,stop,create=env.timer.Start,env.timer.Stop,env.ents.Create
        env.timer.Start=function(name) calls.starts=calls.starts+1; return start(name) end
        env.timer.Stop=function(name) calls.stops=calls.stops+1; return stop(name) end
        env.ents.Create=function(class) calls.creates=calls.creates+1; return create(class) end
        return env,admin,observer,current,ioState,calls
    end
    local function ready(env,admin)
        privateSay(env,admin,"!nextEvent Raid"); env.fireTimer("activatorSpawner")
        local actors=usable(env); eq(#actors,3); eq(env.timers.activatorSpawner.stopped,true)
        for _,actor in ipairs(actors) do eq(actor.EventIdentifier,"Raid") end
        return actors
    end
    local function editAndQueue(env,admin,current)
        privateSay(env,admin,"!listSpawns activator")
        local point=env.Vector(700,800,900); admin:SetPos(point)
        privateSay(env,admin,"!moveActivatorSpawn 11"); coords(current.activatorSpawnPositions[11],point)
        privateSay(env,admin,"!listSpawns enemy")
        local enemyPoint=env.Vector(1700,1800,1900); admin:SetPos(enemyPoint)
        privateSay(env,admin,"!moveEnemySpawn 2"); coords(current.enemySpawnPositions[2],enemyPoint)
        privateSay(env,admin,"!nextEvent Ambush")
        return point,enemyPoint
    end
    local entityFields={"valid","markedForDeletion","pos","name","class","model","health","spawned",
        "EventIdentifier","NPCInfo","moveType","moveChanges","stopped"}
    local function quietRefresh(env,admin,ioState,calls,refused)
        local positions,definitions,files=tree(env.SpawnPositions),tree(env.NPCEdits),tree(ioState)
        local timer=env.timers.activatorSpawner
        local timers=tree(env.timers)
        local callback,delay,repetitions=timer.callback,timer.delay,timer.repetitions
        local messages,entities,errors=#env.messages,#env.entities,#env.errors
        local random,creates,enemies=calls.random,calls.creates,env.totalEnemies
        local starts,stops=calls.starts,calls.stops
        local registry,receivers=tree(env.networkStrings),tree(env.receivers)
        local before={}
        if refused then
            for _,entity in ipairs(env.entities) do
                before[entity]={}
                for _,field in ipairs(entityFields) do before[entity][field]=tree(entity[field]) end
            end
        end
        local response=privateSay(env,admin,"!refreshActivators")
        sameTree(env.SpawnPositions,positions); sameTree(env.NPCEdits,definitions); sameTree(ioState,files)
        sameTree(env.networkStrings,registry); sameTree(env.receivers,receivers)
        eq(#env.messages,messages,"refresh emits no network packet")
        eq(#env.entities,entities,"refresh creates no entities")
        eq(#env.errors,errors); eq(calls.random,random,"refresh samples no random value")
        eq(calls.creates,creates,"refresh does not attempt creation"); eq(env.totalEnemies,enemies)
        eq(env.timers.activatorSpawner,timer,"reuse existing timer")
        eq(timer.callback,callback,"preserve normal spawn callback"); eq(timer.delay,delay)
        eq(timer.delay,env.returnDelayBetweenEvents()); eq(timer.repetitions,repetitions); eq(repetitions,0)
        if refused then
            sameTree(env.timers,timers)
            eq(calls.starts,starts,"refusal cannot restart timer"); eq(calls.stops,stops)
            for entity,fields in pairs(before) do
                for field,value in pairs(fields) do sameTree(entity[field],value) end
            end
        else
            assert(calls.starts > starts,"accepted refresh requests timer restart even when already running")
            eq(timer.stopped,false,"normal spawn delay is restarted")
        end
        return response
    end
    local function newBatch(env,admin,current,name)
        env.fireTimer("activatorSpawner")
        local actors=usable(env); eq(#actors,3)
        for _,actor in ipairs(actors) do eq(actor.EventIdentifier,name); coords(actor:GetPos(),current.activatorSpawnPositions[11]) end
        pending(env,admin,nil)
        contains(status(env,admin),'Selected ready batch: "' .. name .. '"')
        return actors
    end
    local function clientRealm() return {env=gmod.new(true),copies={},originals={}} end
    local function toClient(client,message)
        local copy={name=message.name,values={},fields=message.fields}
        for i,value in ipairs(message.values) do
            if message.fields[i].kind == "entity" then
                local entity=client.copies[value]
                if not entity then
                    entity=client.env.entity(value:GetClass()); entity.model=value:GetModel()
                    client.copies[value],client.originals[entity]=entity,value
                end
                copy.values[i]=entity
            else copy.values[i]=value end
        end
        client.env.deliver(copy)
    end
    local function toServer(server,client,player,message)
        local copy={name=message.name,values={},fields=message.fields}
        for i,value in ipairs(message.values) do
            copy.values[i]=message.fields[i].kind == "entity" and assert(client.originals[value],"unmapped client entity") or value
        end
        server.deliver(copy,player)
    end
    local function open(server,client,player,actor)
        player:SetPos(actor:GetPos()); actor:AcceptInput("Use",player,player)
        local message=server.messages[#server.messages]; eq(message.name,"OpenInteractionMenu"); eq(message.player,player)
        local first=#client.env.panels+1; toClient(client,message)
        local menu={actor=client.copies[actor]}
        for i=first,#client.env.panels do
            local panel=client.env.panels[i]
            if panel.class == "DFrame" then menu.frame=panel
            elseif panel.class == "DButton" and panel.text:find("Start",1,true) then menu.start=panel
            elseif panel.class == "DButton" then menu.cancel=panel end
        end
        assert(menu.frame and menu.start and menu.cancel,"actual dialogue controls")
        assert(menu.actor ~= actor,"client has its own actor lifetime")
        return menu
    end
    local function oldCallbacks(menu)
        menu.frame:OnClose(); menu.start:DoClick(); menu.cancel:DoClick()
        if menu.frame.LayoutDialogue then menu.frame:LayoutDialogue() end
    end
    local function start(server,client,player,menu)
        local before=#client.env.messages; menu.start:DoClick()
        eq(#client.env.messages,before+1); local message=client.env.messages[#client.env.messages]
        eq(message.name,"SendNPCInformation"); toServer(server,client,player,message)
    end
    local function finish(env,player,expected,point)
        local enemies=env.ents.FindByName("devonsSpawnedEntity"); eq(#enemies,expected); eq(env.totalEnemies,expected)
        for i,enemy in ipairs(enemies) do
            if point then coords(enemy:GetPos(),point,i*30) end
            env.fire("OnNPCKilled",enemy,player)
        end
        eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),1)
        eq(env.messageCount("entitiesDeleted"),0)
    end

    for _,mode in ipairs({"selected","manual","mixed"}) do
        test("refresh workflow uses edited points and pending encounter after retiring " .. mode .. " actors",function()
            local env,admin,observer,current,ioState,calls=fixture()
            local old={}
            if mode ~= "manual" then old=ready(env,admin) end
            if mode ~= "selected" then
                for i=1,(mode == "manual" and 3 or 1) do
                    local actor=env.entity("activatorent"); actor.EventIdentifier="Raid"
                    actor:SetPos(current.activatorSpawnPositions[11]); actor:Spawn(); old[#old+1]=actor
                end
                env.fireTimer("activatorSpawner"); old=usable(env)
            end
            local oldPoint=current.activatorSpawnPositions[11]
            local point,enemyPoint=editAndQueue(env,admin,current)
            eq(ioState.writes,2,"both real position edits persist")
            for _,actor in ipairs(old) do coords(actor:GetPos(),oldPoint); eq(actor.EventIdentifier,"Raid") end
            eq(env.timers.activatorSpawner.stopped,true)
            local unrelated=env.entity("npc_zombie"); local prop=env.entity("prop_physics")
            quietRefresh(env,admin,ioState,calls)
            for _,actor in ipairs(old) do eq(actor.valid,false) end
            eq(unrelated.valid,true); eq(prop.valid,true); eq(#usable(env),0)
            pending(env,admin,"Ambush"); contains(status(env,admin),"Selected ready batch: none")
            eq(env.messageCount("roundFinished"),0); eq(env.messageCount("entitiesDeleted"),0)
            local fresh=newBatch(env,admin,current,"Ambush")
            local client=clientRealm(); local menu=open(env,client,observer,fresh[1])
            eq(#client.env.messages,0,"fresh Use cannot start by itself")
            start(env,client,observer,menu); finish(env,observer,2,enemyPoint)
        end)
    end

    for _,retirement in ipairs({"EntityRemoved","Think"}) do
        test("refresh retires the captured client dialogue through " .. retirement .. " without stale controls",function()
            local env,admin,observer,current,ioState,calls=fixture(); local old=ready(env,admin)
            local client=clientRealm(); local menu=open(env,client,observer,old[1])
            editAndQueue(env,admin,current); env.deferRemoval=true
            quietRefresh(env,admin,ioState,calls)
            eq(old[1].valid,true); eq(old[1]:IsMarkedForDeletion(),true)
            eq(menu.actor.valid,true); eq(menu.frame.valid,true,"separate client has not observed removal yet")
            eq(#client.env.messages,0,"refresh does not auto-start or cancel")
            env.receive("SendNPCInformation",observer,"Raid"); eq(env.totalEnemies,0)
            if retirement == "EntityRemoved" then
                client.env.fire("EntityRemoved",menu.actor); eq(menu.actor.valid,true,"hook precedes client invalidation")
            else menu.actor.valid=false; client.env.fire("Think") end
            eq(menu.frame.valid,false); eq(menu.frame:IsVisible(),false)
            oldCallbacks(menu); client.env.fire("Think"); eq(#client.env.messages,0)
            local fresh=newBatch(env,admin,current,"Ambush")
            env.receive("SendNPCInformation",observer,"Raid"); eq(env.totalEnemies,0,"late old Start cannot activate replacement")
            local nextMenu=open(env,client,observer,fresh[1])
            env.flushRemovals(); client.env.fire("EntityRemoved",menu.actor); menu.actor.valid=false
            oldCallbacks(menu); client.env.fire("Think")
            eq(nextMenu.frame.valid,true); eq(#client.env.messages,0,"stale controls cannot cancel the replacement")
            contains(status(env,admin),'Selected ready batch: "Ambush"')
            start(env,client,observer,nextMenu); finish(env,observer,2)
            eq(client.env.messageCount("CloseInteractionMenu"),0)
        end)
    end

    test("refresh revokes every old interaction before the first unmarked Remove callback",function()
        local env,admin,observer,current,ioState,calls=fixture(); local old=ready(env,admin)
        local second=env.entity("player"); local third=env.entity("player")
        for i,player in ipairs({observer,second,third}) do
            player:SetPos(old[i]:GetPos()); old[i]:AcceptInput("Use",player,player)
        end
        editAndQueue(env,admin,current); env.deferRemoval=true
        local callbacks=0
        for _,actor in ipairs(old) do
            local remove=actor.Remove
            actor.Remove=function(self)
                callbacks=callbacks+1
                if callbacks == 1 then
                    for _,entry in ipairs(old) do eq(entry:IsMarkedForDeletion(),false) end
                    env.receive("SendNPCInformation",observer,"Raid"); eq(env.totalEnemies,0)
                    local changes=old[2].moveChanges
                    env.receive("CloseInteractionMenu",second,old[2]); eq(old[2].moveChanges,changes)
                    env.receive("SendNPCInformation",second,"Raid"); eq(env.totalEnemies,0)
                end
                return remove(self)
            end
        end
        quietRefresh(env,admin,ioState,calls); eq(callbacks,3)
        env.receive("SendNPCInformation",third,"Raid"); eq(env.totalEnemies,0)
        eq(#usable(env),0); pending(env,admin,"Ambush")
        local fresh=newBatch(env,admin,current,"Ambush")
        env.flushRemovals(); contains(status(env,admin),'Selected ready batch: "Ambush"')
        observer:SetPos(fresh[1]:GetPos()); fresh[1]:AcceptInput("Use",observer,observer)
        env.receive("CloseInteractionMenu",observer,old[1])
        env.receive("SendNPCInformation",observer,"Ambush"); finish(env,observer,2)
    end)

    test("refresh preserves a newer pending command issued from an old removal callback",function()
        local env,admin,observer,current,ioState,calls=fixture(); local old=ready(env,admin)
        editAndQueue(env,admin,current)
        local second=env.entity("player"); second.admin=true
        local remove=old[1].Remove
        old[1].Remove=function(self)
            privateSay(env,second,"!nextEvent Raid")
            return remove(self)
        end
        -- The nested administrator is deliberately expected to receive its own reply.
        eq(env.fire("PlayerSay",admin,"!refreshActivators"),"")
        pending(env,admin,"Raid"); newBatch(env,admin,current,"Raid")
    end)

    test("selected refresh without a pending choice resumes normal event selection",function()
        local env,admin,observer,current,ioState,calls=fixture(); ready(env,admin)
        quietRefresh(env,admin,ioState,calls); pending(env,admin,nil)
        contains(status(env,admin),"Selected ready batch: none")
        env.NPCEdits[1]=nil -- Singleton real random definition, different from old selected Raid.
        local before=calls.random; env.fireTimer("activatorSpawner")
        assert(calls.random > before,"ordinary timer samples its event and positions")
        for _,actor in ipairs(usable(env)) do eq(actor.EventIdentifier,"Ambush") end
        eq(#usable(env),3); contains(status(env,admin),"Selected ready batch: none")
    end)

    for _,blocker in ipairs({"player minimum","capacity","positions","definition","Create failure","Spawn removal"}) do
        test("normal delayed " .. blocker .. " gate preserves pending after refresh until an actual usable spawn",function()
            local env,admin,observer,current,ioState,calls=fixture(); ready(env,admin)
            editAndQueue(env,admin,current); quietRefresh(env,admin,ioState,calls)
            local point,definition,create=current.activatorSpawnPositions,env.NPCEdits[7],env.ents.Create
            if blocker == "player minimum" then env.minNumberOfPlayers=99
            elseif blocker == "capacity" then env.maxActivators=0
            elseif blocker == "positions" then current.activatorSpawnPositions={}
            elseif blocker == "definition" then env.NPCEdits[7]=nil
            elseif blocker == "Create failure" then env.failClass="activatorent"
            else
                env.ents.Create=function(class)
                    local actor=create(class)
                    if class == "activatorent" and env.IsValid(actor) then
                        local spawn=actor.Spawn
                        actor.Spawn=function(self) spawn(self); self:Remove() end
                    end
                    return actor
                end
            end
            env.fireTimer("activatorSpawner")
            eq(#usable(env),0); eq(env.totalEnemies,0); pending(env,admin,"Ambush")
            eq(env.messageCount("roundFinished"),0); eq(env.timers.activatorSpawner.stopped,false)
            env.minNumberOfPlayers=0; env.maxActivators=3; current.activatorSpawnPositions=point
            env.NPCEdits[7]=definition; env.failClass=nil; env.ents.Create=create
            local entered=0
            env.ents.Create=function(class)
                local actor=create(class)
                if class == "activatorent" then
                    local spawn=actor.Spawn
                    actor.Spawn=function(self)
                        entered=entered+1
                        pending(env,admin,entered == 1 and "Ambush" or nil)
                        spawn(self)
                        if entered == 1 then pending(env,admin,"Ambush") end
                    end
                end
                return actor
            end
            newBatch(env,admin,current,"Ambush"); eq(entered,3)
        end)
    end

    test("manual capacity after refresh still defers pending until the manual actor leaves",function()
        local env,admin,observer,current,ioState,calls=fixture(); ready(env,admin)
        editAndQueue(env,admin,current); quietRefresh(env,admin,ioState,calls)
        for i=1,3 do
            local actor=env.entity("activatorent"); actor.EventIdentifier="Raid"; actor:Spawn()
        end
        env.fireTimer("activatorSpawner"); pending(env,admin,"Ambush")
        for _,actor in ipairs(usable(env)) do eq(actor.EventIdentifier,"Raid"); actor:Remove() end
        newBatch(env,admin,current,"Ambush")
    end)

    test("empty and repeated refresh preserve pending and reuse the configured normal timer",function()
        local env,admin,observer,current,ioState,calls=fixture(); privateSay(env,admin,"!nextEvent Ambush")
        for i=1,3 do quietRefresh(env,admin,ioState,calls); pending(env,admin,"Ambush"); eq(#usable(env),0) end
        newBatch(env,admin,current,"Ambush"); env.deferRemoval=true
        privateSay(env,admin,"!nextEvent Raid")
        quietRefresh(env,admin,ioState,calls); quietRefresh(env,admin,ioState,calls)
        pending(env,admin,"Raid"); eq(#usable(env),0)
        newBatch(env,admin,current,"Raid"); env.flushRemovals()
        contains(status(env,admin),'Selected ready batch: "Raid"')
    end)

    for _,mode in ipairs({"uninitialized storage","rejected storage"}) do
        test("refresh preserves " .. mode .. " recovery and later edit behavior",function()
            local env,admin,observer,current,ioState,calls=fixture(mode); ready(env,admin)
            editAndQueue(env,admin,current); eq(ioState.writes,0)
            quietRefresh(env,admin,ioState,calls); newBatch(env,admin,current,"Ambush")
            local files=tree(ioState.files)
            admin:SetPos(env.Vector(4,5,6)); privateSay(env,admin,"!moveActivatorSpawn 11")
            eq(ioState.writes,0,"refresh does not silently enable persistence")
            sameTree(ioState.files,files)
        end)
    end

    test("active encounter refresh refusal preserves pending, enemies, progress and eventual victory",function()
        local env,admin,observer,current,ioState,calls=fixture(); local actors=ready(env,admin)
        editAndQueue(env,admin,current)
        observer:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",observer,observer)
        env.receive("SendNPCInformation",observer,"Raid")
        local enemies=env.ents.FindByName("devonsSpawnedEntity"); eq(#enemies,5)
        env.fire("OnNPCKilled",enemies[1],observer); eq(env.totalEnemies,4)
        local extra=env.entity("activatorent"); extra.EventIdentifier="Raid"; extra:Spawn()
        local before=status(env,admin)
        quietRefresh(env,admin,ioState,calls,true); eq(status(env,admin),before)
        eq(extra.valid,true); eq(extra:IsMarkedForDeletion(),false); pending(env,admin,"Ambush")
        for i=2,5 do env.fire("OnNPCKilled",enemies[i],observer) end
        eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),1)
        eq(env.messageCount("entitiesDeleted"),0); pending(env,admin,"Ambush")
    end)

    for _,boundary in ipairs({"activator removal","first NPC Spawn","second NPC Spawn"}) do
        test("refresh refuses during " .. boundary .. " without changing construction ownership",function()
            local env,admin,observer,current,ioState,calls=fixture(); local actors=ready(env,admin)
            editAndQueue(env,admin,current); local checked=0
            local function refuse()
                local before=status(env,admin); quietRefresh(env,admin,ioState,calls,true)
                eq(status(env,admin),before); pending(env,admin,"Ambush"); checked=checked+1
            end
            if boundary == "activator removal" then
                local remove=actors[1].Remove
                actors[1].Remove=function(self) refuse(); return remove(self) end
            else
                local create=env.ents.Create; local count=0
                env.ents.Create=function(class)
                    local enemy=create(class)
                    if class == "npc_stalker" then
                        count=count+1
                        if count == (boundary == "first NPC Spawn" and 1 or 2) then
                            local spawn=enemy.Spawn
                            enemy.Spawn=function(self) spawn(self); refuse() end
                        end
                    end
                    return enemy
                end
            end
            observer:SetPos(actors[1]:GetPos()); actors[1]:AcceptInput("Use",observer,observer)
            env.receive("SendNPCInformation",observer,"Raid"); eq(checked,1)
            finish(env,observer,5); pending(env,admin,"Ambush")
        end)
    end
end
