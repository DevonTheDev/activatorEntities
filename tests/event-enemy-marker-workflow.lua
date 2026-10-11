-- Real addon callbacks transfer their outgoing packets between isolated realms.
-- Exact chat and legacy packet controls below were captured from pre-feature
-- 2dbc37ab56e5aa39263083a817369c863dfd64cf. The finite fixtures are self-contained:
-- no runtime git/history access, alternate source implementation or harness edits.
-- Native networking, entity-handle reuse, privacy and pixels still need GMod.
return function(gmod,test,eq)
    local channel="ActivatorSpawnMarker"
    local baseline={
["idleStatus"]={result="",lines={
    "Active event: none.",
    "Ready activators: 0.",
    "Selected ready batch: none.",
    "Pending next batch: none.",
    "Automatic spawn, next normal attempt: enabled; no active encounter; players 2/min 0 (met); activators 0/cap 3 (space).",
    "Spawn inputs: random: pool present; event unchosen; engine unchecked; current-map activator positions: 1 available.",
    "Encounter start enemy positions: 1 available (required on use).",
}},
["idleList"]={result="",lines={
    "No active encounter.",
}},
["badList"]={result="",lines={
    "Usage: !listEventEnemies [page]; page must be a positive integer.",
}},
["zeroList"]={result="",lines={
    "Usage: !listEventEnemies [page]; page must be a positive integer.",
}},
["enemyBases"]={result="",lines={
    "Current-map enemy spawns, page 1/1 (1 positions). Approx. distance from you to stored bases at list time, in 3D Source units.",
    "Key 2: x=20000.125, y=-30000.5, z=0.03125; ~36056 units away",
    "Shown key: !removeEnemySpawn <key> to remove; !moveEnemySpawn <key> to move here. Copy the exact key; list again after any edit. Coordinates are not placement checks. Enemy placement adds (30,30,0) cumulatively per valid creation.",
}},
["enemyMark"]={result="",lines={
    "15-second enemy stored-base snapshot sent; !clearSpawnMarker to clear.",
}},
-- packet enemy 425 bits
-- 1 bool nil true
-- 2 string nil "gm_construct"
-- 3 string nil "enemy"
-- 4 string nil "2"
-- 5 double nil 0x1.38808p+14
-- 6 double nil -0x1.d4c2p+14
-- 7 double nil 0x1p-5
-- 8 double nil 115
["activatorBases"]={result="",lines={
    "Current-map activator spawns, page 1/1 (1 positions). Approx. distance from you to stored bases at list time, in 3D Source units.",
    "Key 2: x=-24000.25, y=45000.5, z=2.125; ~51000.6 units away",
    "Shown key: !removeActivatorSpawn <key> to remove; !moveActivatorSpawn <key> to move here. Copy the exact key; list again after any edit. Coordinates are not placement checks.",
}},
["activatorMark"]={result="",lines={
    "15-second activator stored-base snapshot sent; !clearSpawnMarker to clear.",
}},
-- packet activator 457 bits
-- 1 bool nil true
-- 2 string nil "gm_construct"
-- 3 string nil "activator"
-- 4 string nil "2"
-- 5 double nil -0x1.7701p+14
-- 6 double nil 0x1.5f91p+15
-- 7 double nil 0x1.1p+1
-- 8 double nil 115
["clear"]={result="",lines={
    "Spawn snapshot marker cleared.",
}},
["activeList"]={result="",lines={
    "Active encounter: \"Raid\".",
    "Enemy locations, page 1/1: progress 3/3; listed 3; omitted invalid/deleting 0.",
    "Entity index 101: approx rounded world position (1, -1, 1).",
    "Entity index 102: approx rounded world position (2, -2, 2).",
    "Entity index 103: approx rounded world position (3, -3, 3).",
    "Temporary entity indices can be reused. !listEventEnemies [page] (1-1); fresh snapshot.",
    "!removeEventEnemy <index> requests one listed enemy's removal; interrupts the encounter (no victory). List again after each request.",
}},
["offPageList"]={result="",lines={
    "Usage: !listEventEnemies [page]; page must be a positive integer in 1-1.",
}},
["activeStatus"]={result="",lines={
    "Active event: \"Raid\" (3/3 enemies remaining).",
    "!listEventEnemies [page] shows current owned enemy locations (approximate).",
    "Ready activators: 0.",
    "Selected ready batch: none.",
    "Pending next batch: none.",
    "Automatic spawn, next normal attempt: enabled; active encounter (blocked); players 2/min 0 (met); activators 0/cap 3 (space).",
    "Spawn inputs: random: pool present; event unchosen; engine unchecked; current-map activator positions: 1 available.",
    "Encounter start enemy positions: 1 available (required on use).",
}},
["pause"]={result="",lines={
    "Automatic activator spawning paused. Existing activators and encounters remain usable.",
}},
["queue"]={result="",lines={
    "Queued for the next fresh automatic batch: \"Raid\".",
}},
["pausedStatus"]={result="",lines={
    "Active event: \"Raid\" (3/3 enemies remaining).",
    "!listEventEnemies [page] shows current owned enemy locations (approximate).",
    "Ready activators: 0.",
    "Selected ready batch: none.",
    "Pending next batch: \"Raid\".",
    "Automatic spawn, next normal attempt: paused; active encounter (blocked); players 2/min 0 (met); activators 0/cap 3 (space).",
    "Spawn inputs: pending selection: information present; engine unchecked; current-map activator positions: 1 available.",
    "Encounter start enemy positions: 1 available (required on use).",
}},
["removal"]={result="",lines={
    "Enemy 101 removal requested; encounter interrupted (no victory). Other enemies and the queued next event are unchanged.",
}},
["interruptedStatus"]={result="",lines={
    "Active event: \"Raid\" (2/3 enemies remaining; interrupted).",
    "!listEventEnemies [page] shows current owned enemy locations (approximate).",
    "Ready activators: 0.",
    "Selected ready batch: none.",
    "Pending next batch: \"Raid\".",
    "Automatic spawn, next normal attempt: paused; active encounter (blocked); players 2/min 0 (met); activators 0/cap 3 (space).",
    "Spawn inputs: pending selection: information present; engine unchecked; current-map activator positions: 1 available.",
    "Encounter start enemy positions: 1 available (required on use).",
}},
["stop"]={result="<nil>",lines={
}},
["stoppedStatus"]={result="",lines={
    "Active event: none.",
    "Ready activators: 0.",
    "Selected ready batch: none.",
    "Pending next batch: \"Raid\".",
    "Automatic spawn, next normal attempt: paused; no active encounter; players 2/min 0 (met); activators 0/cap 3 (space).",
    "Spawn inputs: pending selection: information present; engine unchecked; current-map activator positions: 1 available.",
    "Encounter start enemy positions: 1 available (required on use).",
}},
    }
    local function tree(value)
        local result={value=value}
        if type(value)=="table" then
            result.entries={}
            for key,child in pairs(value) do result.entries[key]=tree(child) end
        end
        return result
    end
    local function same(value,state)
        assert(rawequal(value,state.value),"original object/value retained")
        if state.entries then
            for key,child in pairs(state.entries) do same(value[key],child) end
            for key in pairs(value) do assert(state.entries[key],"unexpected key "..tostring(key)) end
        end
    end
    local function clientRealm()
        local client=gmod.new(true)
        client.localPlayer=client.entity("player"); client.localPlayer.admin=true
        client.now,client.realNow=100,1000
        return client
    end
    local function fixture(count)
        local server,client=gmod.new(),clientRealm()
        server.now=100
        server.NPCEdits[1].information.maxNPCs=count or 3
        server.determineRandomEvent=function() return "Raid" end
        server.SpawnPositions={{map=server.map,
            enemySpawnPositions={[2]=server.Vector(20000.125,-30000.5,0.03125)},
            activatorSpawnPositions={[2]=server.Vector(-24000.25,45000.5,2.125)}}}
        local admin=server.entity("player"); admin.admin=true
        local other=server.entity("player"); other.admin=true
        return server,client,admin,other
    end
    local function say(server,admin,text)
        local before,lines=#admin.chats,{}
        local result=server.fire("PlayerSay",admin,text)
        for i=before+1,#admin.chats do
            local line=admin.chats[i]
            assert(#line>0 and #line<=255 and not line:find("[%c]"),"bounded private feedback")
            lines[#lines+1]=line
        end
        return result,lines
    end
    local function command(server,admin,text)
        local result,lines=say(server,admin,text)
        eq(result,"","actual private command handled")
        return lines
    end
    local function latest(server,name)
        for i=#server.messages,1,-1 do
            if server.messages[i].name==name then return server.messages[i] end
        end
    end
    local function open(server,client,admin,actor)
        actor:AcceptInput("Use",admin,admin)
        local packet=server.messages[#server.messages]
        eq(packet.name,"OpenInteractionMenu")
        local copy={name=packet.name,fields=packet.fields,values={}}
        local originals={}
        for i,value in ipairs(packet.values) do
            if packet.fields[i].kind=="entity" then
                local entity=value==admin and client.localPlayer or client.entity(value:GetClass())
                entity.model=value:GetModel(); copy.values[i]=entity; originals[entity]=value
            else copy.values[i]=value end
        end
        local first=#client.panels+1; client.deliver(copy)
        local menu={originals=originals}
        for i=first,#client.panels do
            local panel=client.panels[i]
            if panel.class=="DFrame" then menu.frame=panel
            elseif panel.class=="DButton" then
                if panel.text:find("Start",1,true) then menu.start=panel else menu.cancel=panel end
            end
        end
        assert(menu.frame and menu.start and menu.cancel,"actual interaction controls created")
        return menu
    end
    local function click(server,client,admin,menu,action)
        local first=#client.messages+1; menu[action]:DoClick()
        for index=first,#client.messages do
            local packet=client.messages[index]
            local copy={name=packet.name,fields=packet.fields,values={}}
            for i,value in ipairs(packet.values) do
                copy.values[i]=packet.fields[i].kind=="entity" and assert(menu.originals[value]) or value
            end
            server.deliver(copy,admin)
        end
        eq(menu.frame.valid,false,"actual button closes its dialogue")
    end
    local function ready(server,client,admin)
        server.fireTimer("activatorSpawner")
        local actor=assert(server.ents.FindByClass("activatorent")[1],"ordinary timer produces ready actor")
        admin:SetPos(actor:GetPos())
        return open(server,client,admin,actor)
    end
    local function start(server,client,admin)
        local first=#server.entities+1
        local menu=ready(server,client,admin); click(server,client,admin,menu,"start")
        local enemies={}
        for i=first,#server.entities do
            local enemy=server.entities[i]
            if enemy.valid and enemy.name=="devonsSpawnedEntity" then enemies[#enemies+1]=enemy end
        end
        eq(server.totalEnemies,#enemies)
        for i,enemy in ipairs(enemies) do
            enemy.index=100+i; enemy.pos=server.Vector(i+0.125,-i-0.5,i+0.03125)
        end
        return enemies
    end
    local function inspect(server,admin,page)
        local lines=command(server,admin,"!listEventEnemies"..(page and (" "..page) or ""))
        local tokens={}
        for _,line in ipairs(lines) do
            local token=line:match("^Entity index (%S+):")
            if token then tokens[#tokens+1]=token end
        end
        return tokens
    end
    local function mark(server,client,admin,token)
        local before=#server.messages
        command(server,admin,"!markEventEnemy "..token)
        eq(#server.messages,before+1,"one actual marker packet")
        local packet=server.messages[#server.messages]
        eq(packet.name,channel); eq(packet.player,admin)
        eq(packet.broadcast,nil); eq(packet.unreliable,false)
        eq(#packet.fields,8); eq(#packet.values,8)
        local fields={"bool","string","string","string","double","double","double","double"}
        for i,kind in ipairs(fields) do eq(packet.fields[i].kind,kind); eq(packet.fields[i].bits,nil) end
        eq(packet.values[1],true); eq(packet.values[2],server.map)
        eq(packet.values[3],"event_enemy"); eq(packet.values[4],token)
        eq(packet.values[8],server.now+15)
        eq(server.packetBits(packet),1+8*(#server.map+#"event_enemy"+#token+3)+256)
        client.deliver(packet)
        return packet
    end
    local function refused(server,admin,token)
        local before=#server.messages
        command(server,admin,"!markEventEnemy "..token)
        eq(#server.messages,before,"stale request emits no packet")
    end
    local function clear(server,client,admin,text)
        local before=#server.messages
        command(server,admin,text or "!clearEventEnemyMarker")
        eq(#server.messages,before+1)
        local packet=server.messages[#server.messages]
        eq(packet.name,channel); eq(packet.player,admin); eq(packet.broadcast,nil)
        eq(packet.values[1],false); eq(#packet.values,1); eq(#packet.fields,1)
        eq(packet.fields[1].kind,"bool"); eq(packet.fields[1].bits,nil)
        eq(server.packetBits(packet),1); client.deliver(packet)
        return packet
    end
    local function paint(client)
        client.drawCalls,client.projections={},{}
        client.fire("HUDPaint"); eq(client.camDepth,0)
        return client.projections[1]
    end
    local function point(client,x,y,z)
        local position=assert(paint(client),"accepted snapshot is projected")
        eq(position.x,x); eq(position.y,y); eq(position.z,z)
        eq(#client.projections,1,"only the single shared snapshot is projected")
        local lines=0
        for _,call in ipairs(client.drawCalls) do if call.kind=="line" then lines=lines+1 end end
        eq(lines,2,"one cross")
    end
    local function finish(server,admin,enemies,victories,paused)
        for _,enemy in ipairs(enemies) do server.fire("OnNPCKilled",enemy,admin) end
        eq(server.totalEnemies,0)
        eq(server.messageCount("roundFinished"),victories,"unchanged exact victory count")
        eq(server.timers.activatorSpawner.stopped,paused==true)
    end
    local function queueOther(server,admin)
        local info=server.NPCEdits[1].information
        server.NPCEdits[2]={name="After snapshot",information={activatorModel=info.activatorModel,
            npcPath="npc_combine_s",maxNPCs=2,dialogue="The queued encounter."}}
        command(server,admin,"!nextEvent After snapshot")
    end
    local function quiet(server,client,callback)
        local positions,definitions,timers=tree(server.SpawnPositions),tree(server.NPCEdits),tree(server.timers)
        local clientTimers=tree(client.timers)
        local counts={server.totalEnemies,server.activatorCount}
        local before,clientBefore,panels=#server.messages,#client.messages,#client.panels
        local entityStates={}
        local entityFields={"valid","class","name","pos","model","spawned","health","EventIdentifier",
            "NPCInfo","moveType","moveChanges","markedForDeletion","stopped","index"}
        for i,entity in ipairs(server.entities) do
            local state={entity=entity}
            for _,key in ipairs(entityFields) do state[key]=tree(entity[key]) end
            entityStates[i]=state
        end
        local panelStates={}
        for i,panel in ipairs(client.panels) do
            local state={}
            for _,key in ipairs({"valid","text","fraction","x","y","width","height","popup","mouseInput","keyboardInput"}) do state[key]=tree(panel[key]) end
            panelStates[i]=state
        end
        local restore,forbidden={},{}
        local function forbid(owner,key)
            restore[#restore+1]={owner=owner,key=key,value=rawget(owner,key)}
            owner[key]=function() forbidden[#forbidden+1]=key; error("marker invoked forbidden "..key) end
        end
        local oldMath,oldClientMath=server.math,client.math
        server.math=setmetatable({},{__index=oldMath})
        client.math=setmetatable({},{__index=oldClientMath})
        for _,owner in ipairs({server.math,client.math}) do
            for _,key in ipairs({"random","randomseed"}) do forbid(owner,key) end
        end
        for _,owner in ipairs({server.timer,server.file,client.timer,client.file}) do
            local keys={}; for key,value in pairs(owner) do if type(value)=="function" then keys[#keys+1]=key end end
            for _,key in ipairs(keys) do forbid(owner,key) end
        end
        for _,owner in ipairs({server.util,client.util}) do
            for _,key in ipairs({"TableToJSON","JSONToTable"}) do forbid(owner,key) end
        end
        for _,key in ipairs({"Create","FindByClass","FindByName"}) do forbid(server.ents,key) end
        forbid(server,"Entity"); forbid(server.net,"Broadcast")
        forbid(client.net,"Start"); forbid(client.net,"SendToServer"); forbid(client.vgui,"Create")
        for _,entity in ipairs(server.entities) do
            for _,key in ipairs({"Remove","FinishRemoval","Spawn","SetPos","SetHealth","SetName","SetModel","SetMoveType","StopMoving","CapabilitiesAdd","DropToFloor"}) do forbid(entity,key) end
        end
        for _,panel in ipairs(client.panels) do
            for _,key in ipairs({"MakePopup","SetMouseInputEnabled","SetKeyboardInputEnabled"}) do forbid(panel,key) end
        end
        local ok,err=pcall(callback)
        for i=#restore,1,-1 do local entry=restore[i]; entry.owner[entry.key]=entry.value end
        server.math,client.math=oldMath,oldClientMath
        assert(ok,err); eq(#forbidden,0,"no swallowed forbidden side effects")
        same(server.SpawnPositions,positions); same(server.NPCEdits,definitions); same(server.timers,timers)
        same(client.timers,clientTimers)
        eq(server.totalEnemies,counts[1]); eq(server.activatorCount,counts[2])
        eq(#server.entities,#entityStates)
        for i,state in ipairs(entityStates) do
            eq(server.entities[i],state.entity)
            for _,key in ipairs(entityFields) do same(state.entity[key],state[key]) end
        end
        eq(#client.messages,clientBefore,"no client request, acknowledgement or retry")
        eq(#client.panels,panels,"no marker panel")
        for i,state in ipairs(panelStates) do for key,value in pairs(state) do same(client.panels[i][key],value) end end
        for i=before+1,#server.messages do
            local packet=server.messages[i]
            eq(packet.name,channel,"marker work publishes no other channel")
            eq(packet.broadcast,nil); assert(packet.player==server.entities[1] or packet.player==server.entities[2],"private admin destination")
        end
        eq(server.receivers[channel],nil,"marker creates no request receiver")
    end
    local function legacy(server,admin,id,text)
        local expected=assert(baseline[id],id)
        local result,lines=say(server,admin,text)
        eq(result or "<nil>",expected.result,id.." command result")
        eq(#lines,#expected.lines,id.." reply count")
        for i,line in ipairs(lines) do eq(line,expected.lines[i],id.." exact response bytes "..i) end
    end
    -- A finite pre-feature typed-payload control, including all scalar/string
    -- bytes and call order. GMod wire serialization is not emulated here.
    local function legacyPacket(server,admin,kind)
        local packet=assert(server.messages[#server.messages])
        local expected=kind=="enemy" and {true,"gm_construct","enemy","2",20000.125,-30000.5,0.03125,115}
            or {true,"gm_construct","activator","2",-24000.25,45000.5,2.125,115}
        local fields={"bool","string","string","string","double","double","double","double"}
        eq(packet.name,channel); eq(packet.player,admin); eq(packet.broadcast,nil); eq(packet.unreliable,false)
        eq(#packet.values,8); eq(#packet.fields,8)
        for i,value in ipairs(expected) do
            eq(packet.values[i],value,"unchanged legacy payload value "..i)
            eq(packet.fields[i].kind,fields[i]); eq(packet.fields[i].bits,nil)
        end
        eq(server.packetBits(packet),kind=="enemy" and 425 or 457)
        return packet
    end
    test("event enemy workflow captures mark-time position once and keeps a detached historical point",function()
        local server,client,admin,other=fixture(); local enemies=start(server,client,admin)
        local target=enemies[1]; local tokens=inspect(server,admin); eq(tokens[1],"101")
        target.pos=server.Vector(12345.125,-23456.5,0.03125)
        local original=target.pos; local reads=0
        target.GetPos=function(self) reads=reads+1; return self.pos end
        local otherChats=#other.chats
        quiet(server,client,function()
            local packet=mark(server,client,admin,tokens[1]); eq(reads,1,"one protected mark-time position capture")
            eq(packet.values[5],12345.125); eq(packet.values[6],-23456.5); eq(packet.values[7],0.03125)
            point(client,12345.125,-23456.5,0.03125)
            local text={}; for _,call in ipairs(client.drawCalls) do if call.kind=="text" then text[#text+1]=call.text end end
            local label=table.concat(text,"\n")
            assert(label:find("Encounter enemy index 101",1,true) and label:find("position snapshot",1,true),"truthful enemy position label")
            assert(not label:find("spawn key",1,true),"live position is never a stored-base label")
            for i=1,4 do client.fire("Think"); client.fire("HUDPaint") end
            eq(reads,1,"rendering never follows the entity")
        end)
        original.x,original.y,original.z=800,900,1000
        target.pos=server.Vector(-1,-2,-3)
        point(client,12345.125,-23456.5,0.03125); eq(reads,1); eq(#other.chats,otherChats)
        client.now=114.999; point(client,12345.125,-23456.5,0.03125)
        client.now=115; client.fire("Think"); eq(paint(client),nil)
    end)

    test("event enemy workflow isolates exact pages and private packets for two admins beside unrelated objects",function()
        local server,client,admin,other=fixture(9); local enemies=start(server,client,admin)
        local second=clientRealm(); local unrelated=server.entity(enemies[1].class)
        unrelated.name="devonsSpawnedEntity"; unrelated.index=enemies[1].index
        unrelated.pos=server.Vector(900,900,900)
        local tokens=inspect(server,admin); eq(#tokens,8)
        refused(server,other,tokens[1]); eq(paint(second),nil)
        local nextTokens=inspect(server,other,2); eq(#nextTokens,1); eq(nextTokens[1],"109")
        local adminChats,otherChats=#admin.chats,#other.chats
        quiet(server,client,function()
            mark(server,client,admin,tokens[1]); eq(#other.chats,otherChats)
            point(client,1.125,-1.5,1.03125); eq(paint(second),nil)
            refused(server,admin,nextTokens[1]); point(client,1.125,-1.5,1.03125)
        end)
        local before=#admin.chats
        mark(server,second,other,nextTokens[1]); eq(#admin.chats,before)
        point(second,9.125,-9.5,9.03125); point(client,1.125,-1.5,1.03125)
        refused(server,other,tokens[1]); point(second,9.125,-9.5,9.03125)
        clear(server,client,admin); eq(paint(client),nil); point(second,9.125,-9.5,9.03125)
        eq(unrelated.valid,true); eq(unrelated.markedForDeletion,nil); eq(server.totalEnemies,9)
        eq(#second.messages,0); assert(#admin.chats>adminChats)
    end)

    for _,change in ipairs({"kill","removal","stop","completion","replacement"}) do
        test("event enemy workflow preserves only historical point after "..change,function()
            local server,client,admin=fixture(); local enemies=start(server,client,admin)
            local token=inspect(server,admin)[1]; mark(server,client,admin,token)
            local before=server.messageCount(channel)
            if change=="kill" then server.fire("OnNPCKilled",enemies[1],admin)
            elseif change=="removal" then enemies[1]:Remove()
            elseif change=="completion" then finish(server,admin,enemies,1)
            else
                server.fire("PlayerSay",admin,"!stopEvent")
                if change=="replacement" then
                    local replacements=start(server,client,admin)
                    eq(replacements[1].index,enemies[1].index,"replacement deliberately reuses the old displayed token")
                    replacements[1].pos=server.Vector(900,800,700)
                end
            end
            eq(server.messageCount(channel),before,"retirement does not publish an automatic marker change")
            point(client,1.125,-1.5,1.03125)
            refused(server,admin,token); point(client,1.125,-1.5,1.03125)
            if change=="replacement" then
                local fresh=inspect(server,admin)[1]; mark(server,client,admin,fresh)
                point(client,900,800,700)
            end
        end)
    end

    test("event enemy workflow leaves normal progress victory and queued next encounter intact",function()
        local server,client,admin=fixture(); local enemies=start(server,client,admin); queueOther(server,admin)
        client.screenWidth,client.screenHeight=320,240
        client.deliver(assert(latest(server,"ActivatorEventStatus")))
        local progress
        for _,panel in ipairs(client.panels) do if panel.class=="DPanel" and not panel.parent and panel.valid then progress=panel end end
        assert(progress,"real progress receiver creates its passive HUD")
        local token=inspect(server,admin)[1]
        quiet(server,client,function()
            mark(server,client,admin,token); point(client,1.125,-1.5,1.03125)
            for _,call in ipairs(client.drawCalls) do
                if call.kind=="text" then
                    local width,height=client.surface.GetTextSize(call.text)
                    assert(call.y>=progress.y+progress.height,"snapshot text clears the real narrow-screen progress panel")
                    assert(call.x>=0 and call.y>=0 and call.x+width<=320 and call.y+height<=240,"bounded text remains visible")
                end
            end
            for i=1,3 do client.fire("Think"); client.fire("HUDPaint") end
        end)
        server.fire("OnNPCKilled",enemies[1],admin); eq(server.totalEnemies,2)
        local status=assert(latest(server,"ActivatorEventStatus"))
        eq(status.values[3],2); eq(status.values[4],3); eq(status.values[5],false)
        client.deliver(status); point(client,1.125,-1.5,1.03125)
        finish(server,admin,enemies,1)
        local replacement=start(server,client,admin); eq(#replacement,2)
        for _,enemy in ipairs(replacement) do eq(enemy.class,"npc_combine_s") end
        finish(server,admin,replacement,2)
        point(client,1.125,-1.5,1.03125)
    end)

    test("event enemy workflow mark and both clears preserve removal permission and interrupted cleanup",function()
        local server,client,admin=fixture(); local enemies=start(server,client,admin); queueOther(server,admin)
        local token=inspect(server,admin)[1]
        quiet(server,client,function()
            mark(server,client,admin,token); mark(server,client,admin,token)
            clear(server,client,admin); eq(paint(client),nil)
            mark(server,client,admin,token); clear(server,client,admin,"!clearSpawnMarker")
            mark(server,client,admin,token)
        end)
        command(server,admin,"!removeEventEnemy "..token)
        eq(server.totalEnemies,2); eq(enemies[1].valid,false)
        point(client,1.125,-1.5,1.03125); refused(server,admin,"102")
        local progress=assert(latest(server,"ActivatorEventStatus"))
        eq(progress.values[3],2); eq(progress.values[5],true)
        local survivor=inspect(server,admin)[1]
        mark(server,client,admin,survivor); point(client,2.125,-2.5,2.03125)
        finish(server,admin,enemies,0)
        local nextEnemies=start(server,client,admin); eq(#nextEnemies,2)
        finish(server,admin,nextEnemies,1)
    end)

    test("event enemy workflow respects paused schedule while retaining queued next event",function()
        local server,client,admin=fixture(); local enemies=start(server,client,admin)
        command(server,admin,"!pauseActivatorSpawns"); queueOther(server,admin)
        local before=table.concat(command(server,admin,"!eventStatus"),"\n")
        local token=inspect(server,admin)[1]
        quiet(server,client,function()
            mark(server,client,admin,token); clear(server,client,admin); mark(server,client,admin,token)
        end)
        eq(table.concat(command(server,admin,"!eventStatus"),"\n"),before)
        finish(server,admin,enemies,1,true)
        local count=#server.entities; server.fireTimer("activatorSpawner")
        eq(#server.entities,count,"paused ordinary timer remains paused")
        command(server,admin,"!resumeActivatorSpawns")
        local nextEnemies=start(server,client,admin); eq(#nextEnemies,2)
        eq(latest(server,"ActivatorEventStatus").values[2],"After snapshot")
        finish(server,admin,nextEnemies,2)
    end)

    for _,action in ipairs({"start","cancel"}) do
        test("event enemy historical snapshot preserves ready dialogue actual "..action.." callback",function()
            local server,client,admin=fixture(); local enemies=start(server,client,admin)
            local token=inspect(server,admin)[1]; mark(server,client,admin,token)
            finish(server,admin,enemies,1)
            local menu=ready(server,client,admin)
            quiet(server,client,function()
                refused(server,admin,token); point(client,1.125,-1.5,1.03125)
                clear(server,client,admin); eq(paint(client),nil)
                clear(server,client,admin); eq(paint(client),nil)
                eq(menu.frame.valid,true)
            end)
            click(server,client,admin,menu,action)
            if action=="start" then eq(server.totalEnemies,3)
            else
                eq(server.totalEnemies,0); server.receive("SendNPCInformation",admin,"Raid")
                eq(server.totalEnemies,0,"cancel still consumes the interaction")
            end
        end)
    end

    test("event enemy workflow shares the slot with unchanged legacy spawn packets and clear bytes",function()
        local server,client,admin=fixture(); local enemies=start(server,client,admin)
        local token=inspect(server,admin)[1]; mark(server,client,admin,token)
        for _,kind in ipairs({"enemy","activator"}) do
            command(server,admin,"!listSpawns "..kind)
            quiet(server,client,function()
                legacy(server,admin,kind.."Mark","!markSpawn "..kind.." 2")
                local packet=legacyPacket(server,admin,kind); client.deliver(packet)
                point(client,packet.values[5],packet.values[6],packet.values[7])
                local label
                for _,call in ipairs(client.drawCalls) do if call.kind=="text" then label=label or call.text end end
                eq(label,(kind=="enemy" and "Enemy" or "Activator").." spawn key 2 - snapshot")
                mark(server,client,admin,token); point(client,1.125,-1.5,1.03125)
                legacy(server,admin,"clear","!clearSpawnMarker")
                local clearPacket=server.messages[#server.messages]
                eq(clearPacket.name,channel); eq(clearPacket.values[1],false); eq(#clearPacket.values,1)
                eq(#clearPacket.fields,1); eq(clearPacket.fields[1].kind,"bool")
                eq(clearPacket.fields[1].bits,nil); eq(server.packetBits(clearPacket),1)
                eq(clearPacket.player,admin); eq(clearPacket.broadcast,nil); eq(clearPacket.unreliable,false)
                client.deliver(clearPacket); eq(paint(client),nil)
                mark(server,client,admin,token); clear(server,client,admin); eq(paint(client),nil)
            end)
        end
        eq(enemies[1].valid,true); eq(server.totalEnemies,3)
    end)

    test("event enemy finite baseline preserves existing command response bytes before and after marking",function()
        local server,client,admin=fixture()
        legacy(server,admin,"idleStatus","!eventStatus")
        legacy(server,admin,"idleList","!listEventEnemies")
        legacy(server,admin,"badList","!listEventEnemies nope")
        legacy(server,admin,"zeroList","!listEventEnemies 0")
        for _,kind in ipairs({"enemy","activator"}) do
            legacy(server,admin,kind.."Bases","!listSpawns "..kind)
            legacy(server,admin,kind.."Mark","!markSpawn "..kind.." 2")
            client.deliver(legacyPacket(server,admin,kind))
        end
        legacy(server,admin,"clear","!clearSpawnMarker")
        local enemies=start(server,client,admin)
        legacy(server,admin,"activeList","!listEventEnemies")
        mark(server,client,admin,"101")
        legacy(server,admin,"activeList","!listEventEnemies")
        legacy(server,admin,"offPageList","!listEventEnemies 2")
        refused(server,admin,"101")
        legacy(server,admin,"activeStatus","!eventStatus")
        legacy(server,admin,"pause","!pauseActivatorSpawns")
        legacy(server,admin,"queue","!nextEvent Raid")
        legacy(server,admin,"pausedStatus","!eventStatus")
        clear(server,client,admin)
        -- The failed page cancels marker authority only: the exact pre-feature
        -- removal selection and removal response must remain available.
        legacy(server,admin,"removal","!removeEventEnemy 101")
        eq(enemies[1].valid,false)
        legacy(server,admin,"interruptedStatus","!eventStatus")
        legacy(server,admin,"stop","!stopEvent")
        legacy(server,admin,"stoppedStatus","!eventStatus")
    end)
end
