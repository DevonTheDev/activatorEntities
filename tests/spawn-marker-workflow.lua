-- Actual server packets cross isolated realms; this does not model native wire
-- serialization, pixels, FOV, input focus or wall-clock timing.
return function(gmod,test,eq)
    local channel="ActivatorSpawnMarker"
    local function tree(value)
        local result={value=value}
        if type(value) == "table" then
            result.entries={}
            for key,child in pairs(value) do result.entries[key]=tree(child) end
        end
        return result
    end
    local function same(value,state)
        assert(rawequal(value,state.value),"existing value/object retained")
        if state.entries then
            for key,child in pairs(state.entries) do same(value[key],child) end
            for key in pairs(value) do assert(state.entries[key],"unexpected key "..tostring(key)) end
        end
    end
    local function setup()
        local server,client=gmod.new(),gmod.new(true)
        local admin=server.entity("player"); admin.admin=true
        local localAdmin=client.entity("player"); localAdmin.admin=true; client.localPlayer=localAdmin
        server.now,client.now,client.realNow=100,100,1000
        server.SpawnPositions={{map=server.map,enemySpawnPositions={
            [2]=server.Vector(20000.125,-30000.5,0.03125),[9]=server.Vector(9,8,7)},
            activatorSpawnPositions={[2]=server.Vector(-24000.25,45000.5,2.125),[9]=server.Vector(5,6,7)}}}
        local calls={random=0,write=0,read=0,encode=0,decode=0}
        server.math=setmetatable({random=function(...) calls.random=calls.random+1; return math.random(...) end},{__index=math})
        server.file.Write=function() calls.write=calls.write+1 end
        server.file.Read=function() calls.read=calls.read+1 end
        server.util.TableToJSON=function() calls.encode=calls.encode+1 end
        server.util.JSONToTable=function() calls.decode=calls.decode+1 end
        return server,client,admin,calls
    end
    local function say(env,player,command) return env.fire("PlayerSay",player,command) end
    local function mark(server,client,admin,kind,key)
        eq(say(server,admin,"!markSpawn "..kind.." "..(key or "2")),"")
        local message=assert(server.messages[#server.messages])
        eq(message.name,channel); eq(message.player,admin); eq(message.unreliable,false); eq(message.broadcast,nil)
        client.deliver(message); return message
    end
    local function paint(client)
        client.drawCalls,client.projections={},{}
        client.fire("HUDPaint")
        eq(client.camDepth,0)
        return client.projections[1]
    end
    local function point(client,x,y,z)
        local position=assert(paint(client),"snapshot was projected")
        eq(position.x,x); eq(position.y,y); eq(position.z,z)
        local count=0
        for _,call in ipairs(client.drawCalls) do if call.kind == "line" then count=count+1 end end
        eq(count,2,"only one cross")
    end
    local function quiet(server,client,calls,callback)
        local positions,definitions,timers,io=tree(server.SpawnPositions),tree(server.NPCEdits),tree(server.timers),tree(calls)
        local entities={}
        for i,entity in ipairs(server.entities) do
            entities[i]={entity=entity}
            for _,field in ipairs({"valid","class","name","pos","model","spawned","health","EventIdentifier","NPCInfo","moveType","moveChanges","markedForDeletion"}) do
                entities[i][field]=tree(entity[field])
            end
        end
        local before,panels,enemies,count=#client.messages,#client.panels,server.totalEnemies,server.activatorCount
        callback()
        same(server.SpawnPositions,positions); same(server.NPCEdits,definitions); same(server.timers,timers); same(calls,io)
        eq(server.totalEnemies,enemies); eq(server.activatorCount,count); eq(#server.entities,#entities)
        for i,state in ipairs(entities) do
            eq(server.entities[i],state.entity)
            for field,value in pairs(state) do if field ~= "entity" then same(state.entity[field],value) end end
        end
        eq(#client.messages,before,"no client request/ack/retry"); eq(#client.panels,panels,"marker creates no panel")
    end
    for _,kind in ipairs({"enemy","activator"}) do
        test("spawn marker actual packet preserves "..kind.." large fractional stored base",function()
            local server,client,admin,calls=setup()
            say(server,admin,"!listSpawns "..kind)
            local original=server.SpawnPositions[1][kind.."SpawnPositions"][2]
            quiet(server,client,calls,function()
                local message=mark(server,client,admin,kind)
                eq(#message.fields,8); eq(server.packetBits(message),1+8*(#server.map+#kind+1+3)+256)
                point(client,original.x,original.y,original.z)
                for i=1,3 do client.fire("Think"); client.fire("HUDPaint") end
                eq(#server.messages,1)
            end)
        end)
        for _,change in ipairs({"move","remove and reuse","wrong-kind relist"}) do
            test("spawn marker historical "..kind.." snapshot survives "..change,function()
                local server,client,admin=setup(); local field=kind.."SpawnPositions"
                say(server,admin,"!listSpawns "..kind); mark(server,client,admin,kind)
                local old=server.SpawnPositions[1][field][2]; local x,y,z=old.x,old.y,old.z
                if change == "move" then
                    admin.pos=server.Vector(500,600,700)
                    say(server,admin,(kind == "enemy" and "!moveEnemySpawn 2" or "!moveActivatorSpawn 2"))
                elseif change == "remove and reuse" then
                    say(server,admin,(kind == "enemy" and "!removeEnemySpawn 2" or "!removeActivatorSpawn 2"))
                    server.SpawnPositions[1][field][2]=server.Vector(800,900,1000)
                else say(server,admin,"!listSpawns "..(kind == "enemy" and "activator" or "enemy")) end
                point(client,x,y,z)
                local before=#server.messages
                eq(say(server,admin,"!markSpawn "..kind.." 2"),""); eq(#server.messages,before,"historical marker grants no new authority")
                point(client,x,y,z)
                say(server,admin,"!listSpawns "..kind); mark(server,client,admin,kind)
                local current=server.SpawnPositions[1][field][2]
                point(client,current.x,current.y,current.z)
                client.now=115; client.fire("Think"); eq(paint(client),nil)
            end)
        end
    end
    test("spawn marker actual delayed packet gets only remaining game-time life",function()
        local server,client,admin=setup(); say(server,admin,"!listSpawns enemy")
        client.now=110; local message=mark(server,client,admin,"enemy")
        eq(message.values[8],115); assert(paint(client))
        client.now=114.99; assert(paint(client))
        client.now=115; client.fire("Think"); eq(paint(client),nil)
        client.now=100; eq(paint(client),nil,"rollback cannot restore an expired snapshot")
    end)
    test("spawn marker two admins receive separate actual packets and clear privately",function()
        local server,client,admin=setup(); local second=server.entity("player"); second.admin=true
        local other=gmod.new(true); other.now=100; other.realNow=1000
        other.localPlayer=other.entity("player"); other.localPlayer.admin=true
        say(server,admin,"!listSpawns enemy"); say(server,second,"!listSpawns activator")
        mark(server,client,admin,"enemy"); eq(paint(other),nil)
        mark(server,other,second,"activator"); point(client,20000.125,-30000.5,0.03125)
        point(other,-24000.25,45000.5,2.125)
        eq(say(server,admin,"!clearSpawnMarker"),"")
        local clear=server.messages[#server.messages]; eq(clear.player,admin); eq(server.packetBits(clear),1)
        client.deliver(clear); eq(paint(client),nil); point(other,-24000.25,45000.5,2.125)
        eq(#client.messages,0); eq(#other.messages,0)
    end)
    local function open(server,client,admin,actor)
        actor:AcceptInput("Use",admin,admin)
        local message=server.messages[#server.messages]
        eq(message.name,"OpenInteractionMenu")
        local copy={name=message.name,values={},fields=message.fields}; local originals={}
        for i,value in ipairs(message.values) do
            if message.fields[i].kind == "entity" then
                local entity=value == admin and client.localPlayer or client.entity(value:GetClass())
                entity.model=value:GetModel(); copy.values[i]=entity; originals[entity]=value
            else copy.values[i]=value end
        end
        client.deliver(copy)
        local menu={originals=originals}
        for _,panel in ipairs(client.panels) do
            if panel.class == "DFrame" then menu.frame=panel
            elseif panel.class == "DButton" then
                if panel.text:find("Start",1,true) then menu.start=panel else menu.cancel=panel end
            end
        end
        assert(menu.frame and menu.start and menu.cancel); return menu
    end
    local function click(server,client,admin,menu,button)
        button:DoClick(); local packet=client.messages[#client.messages]
        local message={name=packet.name,values={},fields=packet.fields}
        for i,value in ipairs(packet.values) do message.values[i]=packet.fields[i].kind == "entity" and assert(menu.originals[value]) or value end
        server.deliver(message,admin)
    end
    for _,action in ipairs({"start","cancel"}) do
        test("spawn marker preserves ready dialogue actual "..action.." callback",function()
            local server,client,admin,calls=setup()
            server.fireTimer("activatorSpawner"); local actor=assert(server.ents.FindByClass("activatorent")[1])
            admin.pos=actor.pos; local menu=open(server,client,admin,actor)
            local frame=tree({x=menu.frame.x,y=menu.frame.y,width=menu.frame.width,height=menu.frame.height})
            say(server,admin,"!listSpawns enemy")
            quiet(server,client,calls,function()
                mark(server,client,admin,"enemy"); point(client,20000.125,-30000.5,0.03125)
                eq(menu.frame.valid,true)
                eq(menu.frame.x,frame.entries.x.value); eq(menu.frame.y,frame.entries.y.value)
                eq(menu.frame.width,frame.entries.width.value); eq(menu.frame.height,frame.entries.height.value)
            end)
            click(server,client,admin,menu,menu[action]); eq(menu.frame.valid,false)
            if action == "start" then eq(server.totalEnemies,5)
            else
                eq(server.totalEnemies,0); server.receive("SendNPCInformation",admin,"Raid"); eq(server.totalEnemies,0)
            end
            point(client,20000.125,-30000.5,0.03125)
        end)
    end
    test("spawn marker preserves active progress and encounter completion",function()
        local server,client,admin,calls=setup()
        server.fireTimer("activatorSpawner"); local actor=assert(server.ents.FindByClass("activatorent")[1]); admin.pos=actor.pos
        local menu=open(server,client,admin,actor); click(server,client,admin,menu,menu.start)
        local status
        for _,message in ipairs(server.messages) do if message.name == "ActivatorEventStatus" then status=message end end
        client.screenWidth,client.screenHeight=320,240
        assert(status); client.deliver(status); eq(server.totalEnemies,5)
        local progress
        for _,panel in ipairs(client.panels) do
            if panel.class == "DPanel" and not panel.parent and panel.valid then progress=panel end
        end
        assert(progress,"actual progress panel exists")
        local panelState={}
        for _,panel in ipairs(client.panels) do panelState[panel]={valid=panel.valid,text=panel.text,fraction=panel.fraction,x=panel.x,y=panel.y,width=panel.width,height=panel.height} end
        say(server,admin,"!listSpawns enemy")
        quiet(server,client,calls,function()
            mark(server,client,admin,"enemy"); point(client,20000.125,-30000.5,0.03125)
            for _,call in ipairs(client.drawCalls) do
                if call.kind == "text" then
                    assert(call.y >= progress.y+progress.height,"marker status clears the actual narrow-screen progress panel")
                    local width,height=client.surface.GetTextSize(call.text)
                    assert(call.x+width <= 320 and call.y+height <= 240,"both status lines remain within the narrow screen")
                end
            end
            eq(say(server,admin,"!clearSpawnMarker"),""); client.deliver(server.messages[#server.messages]); eq(paint(client),nil)
            for panel,state in pairs(panelState) do for key,value in pairs(state) do eq(panel[key],value) end end
        end)
        for _,enemy in ipairs(server.ents.FindByName("devonsSpawnedEntity")) do server.fire("OnNPCKilled",enemy,admin) end
        eq(server.totalEnemies,0); eq(server.messageCount("roundFinished"),1); eq(server.timers.activatorSpawner.stopped,false)
    end)
    test("spawn marker leaves paused scheduler and pending selection unchanged",function()
        local server,client,admin,calls=setup()
        say(server,admin,"!pauseActivatorSpawns"); say(server,admin,"!nextEvent Raid")
        say(server,admin,"!eventStatus"); local before=admin.chats[#admin.chats]
        say(server,admin,"!listSpawns activator")
        quiet(server,client,calls,function() mark(server,client,admin,"activator"); client.fire("Think") end)
        say(server,admin,"!eventStatus"); eq(admin.chats[#admin.chats],before)
        eq(server.timers.activatorSpawner.stopped,true)
    end)
end
