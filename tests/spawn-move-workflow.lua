-- Exercise public chat, persistence and real encounter/client handlers. The
-- existing GMod doubles do not prove native DATA encoding, physics or delivery.
return function(gmod,test,eq)
    local newCodec=dofile("tests/spawn-storage-codec.lua")
    local canonical,backup="devonsspawninfo.json","devonsspawninfo.backup.json"
    local kinds={
        {name="enemy",field="enemySpawnPositions",move="!moveEnemySpawn",remove="!removeEnemySpawn",add="!setEnemySpawn",first=2,key=10,last=27},
        {name="activator",field="activatorSpawnPositions",move="!moveActivatorSpawn",remove="!removeActivatorSpawn",add="!setActivatorSpawn",first=3,key=11,last=29},
    }
    local function contains(text,fragment)
        assert(text:find(fragment,1,true),"missing " .. fragment .. " in " .. text)
    end
    local function coords(actual,expected,offset)
        offset=offset or 0
        eq(actual.x,expected.x+offset,"x coordinate")
        eq(actual.y,expected.y+offset,"y coordinate")
        eq(actual.z,expected.z,"z coordinate")
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result={}
        for key,child in pairs(value) do result[key]=copy(child) end
        return result
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
        assert(rawequal(value,state.value),"existing object or value changed")
        if state.entries then
            for key,child in pairs(state.entries) do sameTree(value[key],child) end
            for key in pairs(value) do assert(state.entries[key],"unexpected field " .. tostring(key)) end
        end
    end
    local function count(values)
        local result=0
        for _ in pairs(values) do result=result+1 end
        return result
    end
    local function storage(env)
        local state={files={},reads=0,decodes=0,encodes=0,writes={},canonicalWrites={},backupWrites={},encoded={}}
        local codec=newCodec(env,eq); state.codec=codec
        env.print=function() end
        env.file.Exists=function(path,realm) eq(realm,"DATA"); return state.files[path] ~= nil end
        env.file.Read=function(path,realm)
            eq(realm,"DATA"); state.reads=state.reads+1; return state.files[path]
        end
        env.file.Write=function(path,contents)
            local write={path=path,contents=contents}
            state.writes[#state.writes+1]=write
            local destination=path == canonical and state.canonicalWrites or state.backupWrites
            if path ~= canonical then eq(path,backup) end
            destination[#destination+1]=write
            if state.failure == "write error" then error("synthetic write failure") end
            if state.failure == "write false" then return false end
            state.files[path]=contents; return true
        end
        env.util.JSONToTable=function(...)
            state.decodes=state.decodes+1; return codec.decode(...)
        end
        env.util.TableToJSON=function(value)
            state.encodes=state.encodes+1; state.encoded[#state.encoded+1]=codec.copy(value)
            if state.failure == "encode error" then error("synthetic encode failure") end
            if state.failure == "encode nil" then return nil end
            if state.failure == "encode empty" then return "" end
            return codec.encode(value)
        end
        return state
    end
    local function fixture(mode)
        local env=gmod.new(); local ioState=storage(env)
        if mode == "rejected" then ioState.files[canonical]="recoverable invalid data" end
        if mode ~= "uninitialized" then env.fire("Initialize") end
        local current={map="gm_construct",
            enemySpawnPositions={[2]=env.Vector(102,202,302),[10]=env.Vector(110,210,310),[27]=env.Vector(127,227,327)},
            activatorSpawnPositions={[3]=env.Vector(203,303,403),[11]=env.Vector(211,311,411),[29]=env.Vector(229,329,429)}}
        env.SpawnPositions={[4]=current,[19]={map="other_map",
            enemySpawnPositions={[10]=env.Vector(6,7,8)},activatorSpawnPositions={[11]=env.Vector(9,8,7)}}}
        local admin=env.entity("player"); admin.admin=true
        local second=env.entity("player"); second.admin=true
        local observer=env.entity("player")
        return env,admin,second,observer,ioState,current
    end
    local function say(env,player,command) return env.fire("PlayerSay",player,command) end
    local function privateSay(env,player,command)
        local chats={}
        for _,other in ipairs(env.player.GetAll()) do chats[other]=#other.chats end
        eq(say(env,player,command),"","move/list/indexed edit is handled privately")
        local lines={}
        for i=chats[player]+1,#player.chats do
            assert(#player.chats[i] <= 255,"ChatPrint line exceeds 255 bytes")
            lines[#lines+1]=player.chats[i]
        end
        assert(#lines > 0,"caller receives a private explanation")
        assert(#lines <= 10,"inspection fits one eight-point page and framing")
        for other,before in pairs(chats) do
            if other ~= player then eq(#other.chats,before,"no bystander edit information") end
        end
        return table.concat(lines,"\n")
    end
    local function inspect(env,player,kind,page)
        return privateSay(env,player,"!listSpawns " .. kind.name .. (page and " " .. page or ""))
    end
    local function move(env,player,kind,key)
        return privateSay(env,player,kind.move .. " " .. tostring(key or kind.key))
    end
    local function remove(env,player,kind,key)
        return privateSay(env,player,kind.remove .. " " .. tostring(key or kind.key))
    end
    local function lifecycle(env)
        local state={entities={},size=#env.entities,enemies=env.totalEnemies,activators=env.activatorCount,
            messages=#env.messages,timers=tree(env.timers),receivers=tree(env.receivers),network=tree(env.networkStrings)}
        for _,entity in ipairs(env.entities) do
            state.entities[entity]=tree({valid=entity.valid,marked=entity.markedForDeletion,pos=entity.pos,
                class=entity.class,name=entity.name,health=entity.health,model=entity.model,movement=entity.moveType,
                moves=entity.moveChanges,stopped=entity.stopped,spawned=entity.spawned,event=entity.EventIdentifier,info=entity.NPCInfo})
        end
        return state
    end
    local function sameLifecycle(env,state)
        eq(#env.entities,state.size,"no actor created by the edit")
        eq(env.totalEnemies,state.enemies); eq(env.activatorCount,state.activators)
        eq(#env.messages,state.messages,"no addon packet emitted by the edit"); sameTree(env.timers,state.timers)
        sameTree(env.receivers,state.receivers); sameTree(env.networkStrings,state.network)
        for _,entity in ipairs(env.entities) do
            local before=assert(state.entities[entity],"entity identity changed").entries
            local fields={valid="valid",marked="markedForDeletion",pos="pos",class="class",name="name",health="health",
                model="model",movement="moveType",moves="moveChanges",stopped="stopped",spawned="spawned",event="EventIdentifier",info="NPCInfo"}
            for field,property in pairs(fields) do
                if before[field] then sameTree(entity[property],before[field]) else eq(entity[property],nil) end
            end
        end
    end
    local function unchanged(env,ioState,callback)
        local positions=tree(env.SpawnPositions); local state=lifecycle(env)
        local reads,decodes,encodes,writes,errors=ioState.reads,ioState.decodes,ioState.encodes,#ioState.writes,#env.errors
        callback()
        sameTree(env.SpawnPositions,positions); sameLifecycle(env,state)
        eq(ioState.reads,reads); eq(ioState.decodes,decodes); eq(ioState.encodes,encodes); eq(#ioState.writes,writes); eq(#env.errors,errors)
    end
    local function status(env,admin)
        local before=#admin.chats; eq(say(env,admin,"!eventStatus"),"")
        local lines={}
        for i=before+1,#admin.chats do
            local line=admin.chats[i]
            if line:find("^Active event:") or line:find("^Ready activators:") or line:find("^Ready event:")
                or line:find("^Selected ready batch:") or line:find("^Pending next batch:") then lines[#lines+1]=line end
        end
        return table.concat(lines,"\n")
    end
    local function ready(env,admin,current)
        -- Singleton sparse lists make real random selection deterministic without
        -- replacing the production selectors, random function or constructors.
        current.enemySpawnPositions={[10]=current.enemySpawnPositions[10]}
        current.activatorSpawnPositions={[11]=current.activatorSpawnPositions[11]}
        env.NPCEdits[7]={name="Ambush",information={activatorModel=env.NPCEdits[1].information.activatorModel,
            npcPath="npc_combine_s",maxNPCs=2,dialogue="An ambush awaits."}}
        eq(say(env,admin,"!nextEvent Ambush"),""); env.fireTimer("activatorSpawner")
        eq(say(env,admin,"!nextEvent Raid"),"")
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
        for _,actor in ipairs(actors) do eq(actor.EventIdentifier,"Ambush") end
        return actors[1]
    end
    local function open(env,client,player,actor)
        player:SetPos(actor:GetPos()); actor:AcceptInput("Use",player,player)
        local message=env.messages[#env.messages]; eq(message.name,"OpenInteractionMenu"); eq(message.player,player)
        local first=#client.panels+1; client.deliver(message)
        local menu={}
        for i=first,#client.panels do
            local panel=client.panels[i]
            if panel.class == "DFrame" then menu.frame=panel
            elseif panel.class == "DButton" and panel.text:find("Start",1,true) then menu.start=panel
            elseif panel.class == "DButton" and panel.text:find("Quit",1,true) then menu.cancel=panel end
        end
        assert(menu.frame and menu.start and menu.cancel,"actual Start and Quit controls")
        return menu
    end
    local function click(env,client,player,menu,cancel)
        local before=#client.messages
        if cancel then menu.cancel:DoClick() else menu.start:DoClick() end
        eq(menu.frame.valid,false); eq(#client.messages,before+1)
        local message=client.messages[#client.messages]
        eq(message.name,cancel and "CloseInteractionMenu" or "SendNPCInformation")
        env.deliver(message,player); return message
    end
    local function newEnemies(env,first,base,expected)
        local result={}
        for i=first+1,#env.entities do
            local entity=env.entities[i]
            if entity.name == "devonsSpawnedEntity" then
                result[#result+1]=entity; coords(entity:GetPos(),base,30*#result)
                eq(entity.valid,true); eq(entity.spawned,true)
            end
        end
        eq(#result,expected,"count only newly constructed enemies, not valid corpses")
        return result
    end
    local function finish(env,player,enemies)
        for _,enemy in ipairs(enemies) do if enemy.valid then env.fire("OnNPCKilled",enemy,player) end end
        eq(env.totalEnemies,0)
    end

    for _,kind in ipairs(kinds) do
        test("public " .. kind.name .. " move replaces only the displayed sparse key and saves a detached Vector",function()
            local env,admin,_,_,ioState,current=fixture()
            local root,list,map=env.SpawnPositions,current[kind.field],current
            local before=tree(env.SpawnPositions); local old=list[kind.key]; local oldCoordinates=copy(old)
            local destination=env.Vector(700,800,900); admin:SetPos(destination)
            local calls=0; admin.GetPos=function() calls=calls+1; return destination end
            local output=inspect(env,admin,kind); contains(output,"Key " .. kind.key .. ":")
            contains(output,kind.move .. " <key>")
            local state=lifecycle(env); move(env,admin,kind)
            eq(calls,1,"GetPos captured once"); sameLifecycle(env,state)
            assert(rawequal(env.SpawnPositions,root) and rawequal(current,map) and rawequal(current[kind.field],list))
            eq(count(list),3); eq(list[1],nil); eq(list[kind.last+1],nil)
            coords(list[kind.key],destination); assert(env.isvector(list[kind.key]))
            assert(not rawequal(list[kind.key],old) and not rawequal(list[kind.key],destination),"fresh independent Vector")
            coords(old,oldCoordinates)
            before.entries[4].entries[kind.field].entries[kind.key]=tree(list[kind.key])
            sameTree(env.SpawnPositions,before)
            eq(ioState.encodes,1); eq(#ioState.writes,1); eq(ioState.writes[1].path,canonical)
            coords(ioState.encoded[1][4][kind.field][kind.key],destination)
            destination.x=-999; eq(list[kind.key].x,700,"later player-vector mutation cannot move saved point")
            unchanged(env,ioState,function() move(env,admin,kind,kind.first) end)
        end)

        test("same-coordinate " .. kind.name .. " move is accepted and invalidates both admins' move and removal authority",function()
            local env,admin,second,_,ioState,current=fixture(); local old=current[kind.field][kind.key]
            getmetatable(old).__eq=function(a,b) return a.x == b.x and a.y == b.y and a.z == b.z end
            second:SetPos(old)
            inspect(env,admin,kind); inspect(env,second,kind); move(env,second,kind)
            local replacement=current[kind.field][kind.key]
            coords(replacement,old); assert(not rawequal(replacement,old),"equal coordinates still need a fresh Vector")
            eq(ioState.encodes,1); eq(#ioState.writes,1)
            unchanged(env,ioState,function()
                move(env,admin,kind); remove(env,admin,kind); move(env,second,kind); remove(env,second,kind)
            end)
            inspect(env,admin,kind); remove(env,admin,kind)
            eq(current[kind.field][kind.key],nil); eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3)
        end)

        test("acknowledged same-coordinate " .. kind.name .. " move verifies bytes and still expires inspection",function()
            local env,admin,second,_,ioState,current=fixture()
            second:SetPos(env.Vector(601,602,603)); inspect(env,second,kind); move(env,second,kind)
            local acknowledged=ioState.files[canonical]; local old=current[kind.field][kind.key]
            inspect(env,admin,kind); inspect(env,second,kind)
            local reads,decodes=ioState.reads,ioState.decodes
            local message=move(env,second,kind)
            assert(not message:find("remains in memory",1,true),"verification is an acknowledged save")
            coords(current[kind.field][kind.key],old)
            assert(not rawequal(current[kind.field][kind.key],old),"accepted move still replaces the Vector")
            eq(ioState.encodes,2,"each accepted command enters the save path")
            eq(ioState.decodes,decodes+1,"candidate is still checked")
            eq(ioState.reads,reads+1,"current bytes are still verified")
            eq(#ioState.canonicalWrites,1); eq(#ioState.backupWrites,0); eq(#ioState.writes,1)
            eq(ioState.files[canonical],acknowledged); eq(ioState.files[backup],nil)
            unchanged(env,ioState,function()
                move(env,admin,kind); remove(env,admin,kind); move(env,second,kind); remove(env,second,kind)
            end)
            eq(env.fire("ShutDown"),nil); eq(ioState.encodes,3); eq(#ioState.writes,1)
            inspect(env,admin,kind); remove(env,admin,kind)
            eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3)
            eq(ioState.files[backup],acknowledged,"next changed save backs up the acknowledged point")
            ioState.codec.same(ioState.codec.decode(ioState.files[backup]),ioState.encoded[1])
        end)

        for _,alias in ipairs({"player destination","old target"}) do
            test("public " .. kind.name .. " move rejects Vector constructor alias of " .. alias .. " without consuming inspection",function()
                local env,admin,_,_,ioState,current=fixture(); local old=current[kind.field][kind.key]
                local destination=env.Vector(old.x,old.y,old.z); admin:SetPos(destination)
                getmetatable(old).__eq=function(a,b) return a.x == b.x and a.y == b.y and a.z == b.z end
                inspect(env,admin,kind); local constructor=env.Vector
                env.Vector=function() return alias == "player destination" and destination or old end
                unchanged(env,ioState,function() move(env,admin,kind) end)
                env.Vector=constructor; move(env,admin,kind)
                assert(not rawequal(current[kind.field][kind.key],old)); eq(#ioState.writes,1)
            end)
        end

        for _,edit in ipairs({"move","indexed removal","bare removal","legacy add"}) do
            test("two admins cannot move a stale " .. kind.name .. " point after " .. edit,function()
                local env,admin,second,_,ioState,current=fixture()
                inspect(env,admin,kind); inspect(env,second,kind); second:SetPos(env.Vector(901,902,903))
                if edit == "move" then move(env,second,kind)
                elseif edit == "indexed removal" then remove(env,second,kind)
                elseif edit == "bare removal" then eq(say(env,second,kind.remove),nil)
                else eq(say(env,second,kind.add),nil) end
                eq(#ioState.writes,1)
                unchanged(env,ioState,function() move(env,admin,kind,kind.first); remove(env,admin,kind,kind.first) end)
                inspect(env,admin,kind); admin:SetPos(env.Vector(501,502,503)); move(env,admin,kind,kind.first)
                coords(current[kind.field][kind.first],admin:GetPos()); eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3)
            end)
        end

        test("a " .. kind.name .. " move invalidates only inspections of the edited map and kind",function()
            local env,admin,second,_,ioState,current=fixture()
            local otherKind=kind == kinds[1] and kinds[2] or kinds[1]
            local otherAdmin=env.entity("player"); otherAdmin.admin=true
            local remoteAdmin=env.entity("player"); remoteAdmin.admin=true
            inspect(env,admin,kind); inspect(env,second,kind); inspect(env,otherAdmin,otherKind)
            env.map="other_map"; inspect(env,remoteAdmin,kind); env.map="gm_construct"
            second:SetPos(env.Vector(601,602,603)); move(env,second,kind)
            unchanged(env,ioState,function() move(env,admin,kind); remove(env,admin,kind) end)
            otherAdmin:SetPos(env.Vector(701,702,703)); move(env,otherAdmin,otherKind)
            coords(current[otherKind.field][otherKind.key],otherAdmin:GetPos())
            env.map="other_map"; remoteAdmin:SetPos(env.Vector(801,802,803)); move(env,remoteAdmin,kind)
            coords(env.SpawnPositions[19][kind.field][kind.key],remoteAdmin:GetPos()); eq(#ioState.canonicalWrites,3); eq(#ioState.backupWrites,2); eq(#ioState.writes,5)
        end)

        test("public " .. kind.name .. " move requires the current map and most recently inspected kind",function()
            local env,admin,_,_,ioState,current=fixture()
            inspect(env,admin,kind); env.map="other_map"
            unchanged(env,ioState,function() move(env,admin,kind) end)
            env.map="gm_construct"; inspect(env,admin,kind == kinds[1] and kinds[2] or kinds[1])
            unchanged(env,ioState,function() move(env,admin,kind) end)
            inspect(env,admin,kind); admin:SetPos(env.Vector(901,902,903)); move(env,admin,kind)
            coords(current[kind.field][kind.key],admin:GetPos()); eq(#ioState.writes,1)
        end)

        test("public " .. kind.name .. " move accepts only the literal key on the latest successful page",function()
            local env,admin,_,_,ioState,current=fixture(); current[kind.field]={}
            for i=1,9 do current[kind.field][i*10]=env.Vector(i,i+1,i+2) end
            inspect(env,admin,kind,1); inspect(env,admin,kind,2)
            unchanged(env,ioState,function() move(env,admin,kind,10); move(env,admin,kind,"090") end)
            admin:SetPos(env.Vector(90,91,92)); move(env,admin,kind,90)
            coords(current[kind.field][90],admin:GetPos()); eq(#ioState.writes,1)
        end)

        test("failed " .. kind.name .. " inspection supersedes an earlier page before a move",function()
            local env,admin,_,_,ioState=fixture(); inspect(env,admin,kind)
            unchanged(env,ioState,function() inspect(env,admin,kind,0); move(env,admin,kind) end)
            inspect(env,admin,kind); move(env,admin,kind); eq(#ioState.writes,1)
        end)

        for _,failure in ipairs({"write false","write error","encode error","encode nil","encode empty"}) do
            test("public " .. kind.name .. " move retains memory on " .. failure .. " and shutdown persists it",function()
                local env,admin,second,_,ioState,current=fixture(); ioState.failure=failure
                inspect(env,admin,kind); inspect(env,second,kind)
                local old=current[kind.field][kind.key]; second:SetPos(env.Vector(601,602,603))
                local text=move(env,second,kind); contains(text,"remains in memory; saving failed, is disabled or could not be verified")
                coords(current[kind.field][kind.key],second:GetPos()); assert(not rawequal(current[kind.field][kind.key],old))
                eq(ioState.encodes,1); eq(#ioState.writes,failure:find("write",1,true) and 1 or 0)
                eq(ioState.files[canonical],nil)
                unchanged(env,ioState,function() move(env,admin,kind); remove(env,admin,kind) end)
                ioState.failure=nil; local attempts=#ioState.writes
                eq(env.fire("ShutDown"),nil); eq(ioState.encodes,2); eq(#ioState.writes,attempts+1)
                eq(ioState.writes[#ioState.writes].path,canonical)
                coords(ioState.encoded[2][4][kind.field][kind.key],second:GetPos())
            end)
        end

        for _,mode in ipairs({"uninitialized","rejected"}) do
            test("public " .. kind.name .. " move honors " .. mode .. " save protection while keeping the edit",function()
                local env,admin,second,_,ioState,current=fixture(mode)
                if mode == "uninitialized" then ioState.files[canonical]="recoverable existing data" end
                local original=ioState.files[canonical]
                inspect(env,admin,kind); inspect(env,second,kind); second:SetPos(env.Vector(401,402,403))
                contains(move(env,second,kind),"remains in memory; saving failed, is disabled or could not be verified"); coords(current[kind.field][kind.key],second:GetPos())
                unchanged(env,ioState,function() move(env,admin,kind); remove(env,admin,kind) end)
                env.fire("ShutDown"); eq(ioState.encodes,0); eq(#ioState.writes,0); eq(ioState.files[canonical],original)
            end)
        end

        for _,cancel in ipairs({false,true}) do
            test("ready " .. kind.name .. " move preserves selected pending and actual " .. (cancel and "Quit" or "Start") .. " permission",function()
                local env,admin,second,_,ioState,current=fixture(); local client=gmod.new(true)
                local actor=ready(env,admin,current); local menu=open(env,client,admin,actor)
                local oldActivator=copy(actor:GetPos()); local destination=env.Vector(701,801,901); second:SetPos(destination)
                local before=status(env,admin); local state=lifecycle(env)
                inspect(env,second,kind); move(env,second,kind)
                sameLifecycle(env,state); eq(status(env,admin),before); eq(menu.frame.valid,true); eq(#client.messages,0)
                eq(#ioState.writes,1); coords(current[kind.field][kind.key],destination)
                if cancel then
                    click(env,client,admin,menu,true); eq(env.totalEnemies,0)
                    env.receive("SendNPCInformation",admin,"Ambush"); eq(env.totalEnemies,0,"Quit still consumes permission")
                    menu=open(env,client,admin,actor)
                end
                local first=#env.entities; click(env,client,admin,menu)
                local enemies=newEnemies(env,first,current.enemySpawnPositions[10],2); eq(env.totalEnemies,2)
                contains(status(env,admin),'Pending next batch: "Raid"'); contains(status(env,admin),"Selected ready batch: none")
                for _,entity in ipairs(env.entities) do
                    if entity.class == "activatorent" then coords(entity:GetPos(),oldActivator) end
                end
                finish(env,admin,enemies); eq(env.messageCount("roundFinished"),1); env.fireTimer("activatorSpawner")
                local nextActors=env.ents.FindByClass("activatorent"); eq(#nextActors,3)
                for _,nextActor in ipairs(nextActors) do
                    eq(nextActor.EventIdentifier,"Raid"); coords(nextActor:GetPos(),current.activatorSpawnPositions[11])
                end
                eq(#ioState.writes,1)
            end)
        end

        for _,outcome in ipairs({"victory","interrupted","admin stop"}) do
            test("active " .. kind.name .. " move preserves " .. outcome .. " and later normal spawns use the new point",function()
                local env,admin,second,_,ioState,current=fixture(); local client=gmod.new(true)
                local actor=ready(env,admin,current); local menu=open(env,client,admin,actor)
                local first=#env.entities; click(env,client,admin,menu)
                local enemies=newEnemies(env,first,current.enemySpawnPositions[10],2)
                if outcome == "interrupted" then enemies[1]:Remove() end
                second:SetPos(env.Vector(801,901,1001))
                local before=status(env,admin); local state=lifecycle(env)
                inspect(env,second,kind); move(env,second,kind)
                sameLifecycle(env,state); eq(status(env,admin),before); eq(#ioState.writes,1)
                coords(current[kind.field][kind.key],second:GetPos())
                if outcome == "admin stop" then say(env,admin,"!stopEvent") else finish(env,admin,enemies) end
                eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),outcome == "victory" and 1 or 0)
                eq(env.timers.activatorSpawner.stopped,false); env.fireTimer("activatorSpawner")
                local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
                for _,nextActor in ipairs(actors) do
                    eq(nextActor.EventIdentifier,"Raid"); coords(nextActor:GetPos(),current.activatorSpawnPositions[11])
                end
                menu=open(env,client,admin,actors[1]); first=#env.entities; click(env,client,admin,menu)
                local nextEnemies=newEnemies(env,first,current.enemySpawnPositions[10],5)
                eq(env.totalEnemies,5); finish(env,admin,nextEnemies)
                eq(env.messageCount("roundFinished"),outcome == "victory" and 2 or 1); eq(#ioState.writes,1)
            end)
        end
    end

    test("malformed move commands stay private and preserve real open Start permission",function()
        local env,admin,second,_,ioState,current=fixture(); local client=gmod.new(true)
        local actor=ready(env,admin,current); local menu=open(env,client,admin,actor)
        for _,kind in ipairs(kinds) do
            inspect(env,second,kind)
            for _,suffix in ipairs({""," "," nope"," 0"," -1"," 1.5"," " .. kind.key .. " extra"}) do
                unchanged(env,ioState,function() privateSay(env,second,kind.move .. suffix) end)
            end
        end
        local first=#env.entities; click(env,client,admin,menu)
        newEnemies(env,first,current.enemySpawnPositions[10],2); eq(env.totalEnemies,2)
    end)

    test("invalid destinations retain a listed key and actual open encounter permission for retry",function()
        local env,admin,second,_,ioState,current=fixture(); local client=gmod.new(true)
        local actor=ready(env,admin,current); local menu=open(env,client,admin,actor); local kind=kinds[1]
        inspect(env,second,kind)
        local valid=second.GetPos
        local invalid={function() error("position unavailable") end,function() return nil end,
            function() return {x=1,y=2,z=3} end,function() return env.Vector(math.huge,2,3) end}
        for _,getter in ipairs(invalid) do
            local calls=0; second.GetPos=function() calls=calls+1; return getter() end
            unchanged(env,ioState,function() move(env,second,kind) end); eq(calls,1)
        end
        second.GetPos=valid; second:SetPos(env.Vector(401,402,403)); move(env,second,kind)
        eq(#ioState.writes,1); local first=#env.entities; click(env,client,admin,menu)
        newEnemies(env,first,current.enemySpawnPositions[10],2); eq(env.totalEnemies,2)
    end)

    test("non-admin move commands cannot edit and unrelated chat stays untouched",function()
        local env,admin,_,observer,ioState=fixture()
        for _,kind in ipairs(kinds) do
            unchanged(env,ioState,function() privateSay(env,observer,kind.move .. " " .. kind.key) end)
        end
        unchanged(env,ioState,function()
            eq(say(env,admin,"ordinary conversation"),nil)
            eq(say(env,admin,"!moveEnemySpawnExtra 10"),nil)
            eq(say(env,admin,"!moveActivatorSpawnExtra 11"),nil)
        end)
    end)
end
