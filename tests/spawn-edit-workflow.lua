-- Actual public hooks, persistence callbacks and encounter/client lifecycles.
-- The harness models Vector/file/ChatPrint behavior; native GMod delivery,
-- DATA round-trips, navigability and arbitrary external same-content edits
-- remain outside this local regression proof.
return function(gmod, test, eq)
    local newCodec=dofile("tests/spawn-storage-codec.lua")
    local canonical,backup="devonsspawninfo.json","devonsspawninfo.backup.json"
    local kinds={
        {name="enemy", field="enemySpawnPositions", remove="!removeEnemySpawn", add="!setEnemySpawn", first=2, middle=10, last=27},
        {name="activator", field="activatorSpawnPositions", remove="!removeActivatorSpawn", add="!setActivatorSpawn", first=3, middle=11, last=29},
    }
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result={}
        for key,child in pairs(value) do result[key]=copy(child) end
        return result
    end
    local function dataEqual(actual, expected)
        eq(type(actual),type(expected))
        if type(expected) ~= "table" then
            if type(expected) == "number" and expected ~= expected then assert(actual ~= actual)
            else eq(actual,expected) end
            return
        end
        for key,child in pairs(expected) do dataEqual(actual[key],child) end
        for key in pairs(actual) do assert(expected[key] ~= nil,"unexpected data field " .. tostring(key)) end
    end
    local function tree(value)
        local result={value=value}
        if type(value) == "table" then
            result.entries={}
            for key,child in pairs(value) do result.entries[key]=tree(child) end
        end
        return result
    end
    local function sameTree(value, expected)
        if type(expected.value) == "number" and expected.value ~= expected.value then assert(value ~= value)
        else eq(value,expected.value,"existing object or value retained") end
        if expected.entries then
            for key,child in pairs(expected.entries) do sameTree(value[key],child) end
            for key in pairs(value) do assert(expected.entries[key],"unexpected object field " .. tostring(key)) end
        end
    end
    local function storage(env)
        local state={files={},reads=0,decodes=0,encodes=0,writes={},canonicalWrites={},backupWrites={},encoded={}}
        local codec=newCodec(env,eq); state.codec=codec
        env.print=function() end
        env.file.Exists=function(path,realm) eq(realm,"DATA"); return state.files[path] ~= nil end
        env.file.Read=function(path,realm)
            eq(realm,"DATA"); state.reads=state.reads+1
            return state.files[path]
        end
        env.file.Write=function(path,contents)
            local write={path=path,contents=contents}
            state.writes[#state.writes+1]=write
            local destination=path == canonical and state.canonicalWrites or state.backupWrites
            if path ~= canonical then eq(path,backup) end
            destination[#destination+1]=write
            if state.failure == "write error" then error("synthetic write failure") end
            if state.failure == "write false" then return false end
            state.files[path]=contents
            return true
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
        local current={map="gm_construct", enemySpawnPositions={
            [2]=env.Vector(102,202,302),[10]=env.Vector(110,210,310),[27]=env.Vector(127,227,327)},
            activatorSpawnPositions={
            [3]=env.Vector(203,303,403),[11]=env.Vector(211,311,411),[29]=env.Vector(229,329,429)}}
        env.SpawnPositions={[4]=current,[19]={map="other_map",
            enemySpawnPositions={[6]=env.Vector(6,7,8)},activatorSpawnPositions={[9]=env.Vector(9,8,7)}}}
        local admin=env.entity("player"); admin.admin=true
        local second=env.entity("player"); second.admin=true
        local observer=env.entity("player")
        return env,admin,second,observer,ioState,current
    end
    local function say(env,ply,command) return env.fire("PlayerSay",ply,command) end
    local function privateSay(env,ply,command)
        local chats={}
        for _,player in ipairs(env.player.GetAll()) do chats[player]=#player.chats end
        eq(say(env,ply,command),"","new command is handled privately")
        local lines={}
        for i=chats[ply]+1,#ply.chats do
            assert(#ply.chats[i] <= 255,"ChatPrint line exceeds byte ceiling")
            lines[#lines+1]=ply.chats[i]
        end
        assert(#lines > 0,"request gets a private explanation")
        assert(#lines <= 10,"inspection output fits eight points plus framing")
        for player,count in pairs(chats) do if player ~= ply then eq(#player.chats,count,"no other player receives edit information") end end
        return table.concat(lines,"\n")
    end
    local function inspect(env,ply,kind) return privateSay(env,ply,"!listSpawns " .. kind.name) end
    local function inspectUnavailable(env,ply,kind)
        local getter,calls=ply.GetPos,0
        ply.GetPos=function() calls=calls+1; error("unavailable list origin") end
        local text=inspect(env,ply,kind)
        ply.GetPos=getter
        eq(calls,1,"one protected origin capture")
        assert(text:find("distance unavailable",1,true),"unavailable distance still produces a valid listing")
    end
    local function remove(env,ply,kind,key) return privateSay(env,ply,kind.remove .. " " .. tostring(key)) end
    local function lifecycle(env)
        local result={entities={},count=#env.entities,enemies=env.totalEnemies,activators=env.activatorCount,
            messages=#env.messages,timers=tree(env.timers),receivers=tree(env.receivers),net=tree(env.networkStrings)}
        for _,ent in ipairs(env.entities) do
            result.entities[ent]={valid=ent.valid,marked=ent.markedForDeletion,pos=ent.pos,position=copy(ent.pos),
                class=ent.class,name=ent.name,health=ent.health,model=ent.model,movement=ent.moveType,
                moves=ent.moveChanges,stopped=ent.stopped,spawned=ent.spawned,event=ent.EventIdentifier,info=ent.NPCInfo}
        end
        return result
    end
    local function sameLifecycle(env,state)
        eq(#env.entities,state.count,"no new entity")
        eq(env.totalEnemies,state.enemies); eq(env.activatorCount,state.activators)
        eq(#env.messages,state.messages,"no addon packet")
        sameTree(env.timers,state.timers); sameTree(env.receivers,state.receivers); sameTree(env.networkStrings,state.net)
        for _,ent in ipairs(env.entities) do
            local before=assert(state.entities[ent],"entity identity changed")
            eq(ent.valid,before.valid); eq(ent.markedForDeletion,before.marked)
            eq(ent.pos,before.pos); dataEqual(ent.pos,before.position)
            eq(ent.class,before.class); eq(ent.name,before.name); eq(ent.health,before.health); eq(ent.model,before.model)
            eq(ent.moveType,before.movement); eq(ent.moveChanges,before.moves); eq(ent.stopped,before.stopped)
            eq(ent.spawned,before.spawned); eq(ent.EventIdentifier,before.event); eq(ent.NPCInfo,before.info)
        end
    end
    local function quietEngine(env,callback)
        local originals,calls={},0
        local function forbid(owner,key)
            originals[#originals+1]={owner,key,owner[key]}
            owner[key]=function() calls=calls+1; error("spawn edit attempted " .. key) end
        end
        local oldMath=env.math
        env.math=setmetatable({}, {__index=math})
        forbid(env.math,"random"); forbid(env,"determineRandomEvent")
        forbid(env,"returnSpawnPositions"); forbid(env,"returnActivatorSpawns")
        for _,key in ipairs({"Create","Start","Stop","Simple"}) do forbid(env.timer,key) end
        for _,key in ipairs({"Start","Send","Broadcast"}) do forbid(env.net,key) end
        forbid(env.ents,"Create"); forbid(env,"destroyActivators")
        for _,ent in ipairs(env.entities) do
            for _,key in ipairs({"Remove","Spawn","SetPos","SetHealth","SetMoveType"}) do forbid(ent,key) end
        end
        local ok,message=pcall(callback)
        for _,original in ipairs(originals) do original[1][original[2]]=original[3] end
        env.math=oldMath
        assert(ok,message); eq(calls,0,"no engine operation even if its error is caught")
    end
    local function unchanged(env,ioState,callback)
        local positions=tree(env.SpawnPositions); local state=lifecycle(env)
        local reads,decodes,encodes,writes,errors=ioState.reads,ioState.decodes,ioState.encodes,#ioState.writes,#env.errors
        quietEngine(env,callback)
        sameTree(env.SpawnPositions,positions); sameLifecycle(env,state)
        eq(ioState.reads,reads); eq(ioState.decodes,decodes); eq(ioState.encodes,encodes); eq(#ioState.writes,writes)
        eq(#env.errors,errors,"unsuccessful request does not attempt persistence")
    end
    local function selection(env,admin)
        local before=#admin.chats; eq(say(env,admin,"!eventStatus"),"")
        local result={}
        for i=before+1,#admin.chats do
            local line=admin.chats[i]
            if line:find("^Active event:") or line:find("^Ready activators:") or line:find("^Ready event:")
                or line:find("^Selected ready batch:") or line:find("^Pending next batch:") then result[#result+1]=line end
        end
        return table.concat(result,"\n")
    end
    local function contains(text,fragment) assert(text:find(fragment,1,true),"missing " .. fragment .. " in " .. text) end
    local function ready(env,admin)
        local raid=env.NPCEdits[1].information
        env.NPCEdits[7]={name="Ambush",information={activatorModel=raid.activatorModel,npcPath="npc_combine_s",
            maxNPCs=2,dialogue="An ambush awaits."}}
        eq(say(env,admin,"!nextEvent Ambush"),""); env.fireTimer("activatorSpawner")
        eq(say(env,admin,"!nextEvent Raid"),"")
        return assert(env.ents.FindByClass("activatorent")[1])
    end
    local function open(env,client,ply,actor)
        ply:SetPos(actor:GetPos()); actor:AcceptInput("Use",ply,ply)
        local message=env.messages[#env.messages]; eq(message.name,"OpenInteractionMenu")
        local first=#client.panels+1; client.deliver(message)
        local frame,button
        for i=first,#client.panels do
            local panel=client.panels[i]
            if panel.class == "DFrame" then frame=panel
            elseif panel.class == "DButton" and panel.text:find("Start",1,true) then button=panel end
        end
        return {frame=assert(frame),button=assert(button)}
    end
    local function click(env,client,ply,menu)
        local before=#client.messages; menu.button:DoClick()
        eq(menu.frame.valid,false); eq(#client.messages,before+1)
        local request=client.messages[#client.messages]; eq(request.name,"SendNPCInformation")
        eq(client.messageCount("CloseInteractionMenu"),0)
        env.deliver(request,ply); return request
    end

    for _,kind in ipairs(kinds) do
        test("workflow persists one exact " .. kind.name .. " removal and legacy add repairs without compaction",function()
            local env,admin,second,observer,ioState,current=fixture()
            local list=current[kind.field]; local first,last=list[kind.first],list[kind.last]
            local other=tree(env.SpawnPositions[19]); local originalMap=current
            local otherField=kind == kinds[1] and kinds[2].field or kinds[1].field
            local otherKind=tree(current[otherField]); local state=lifecycle(env)
            unchanged(env,ioState,function() inspect(env,admin,kind) end)
            quietEngine(env,function() remove(env,admin,kind,kind.middle) end)
            eq(current[kind.field],list); eq(env.SpawnPositions[4],originalMap)
            eq(list[kind.middle],nil); eq(list[kind.first],first); eq(list[kind.last],last)
            sameTree(current[otherField],otherKind); sameTree(env.SpawnPositions[19],other)
            sameLifecycle(env,state); eq(ioState.encodes,1); eq(#ioState.writes,1)
            eq(ioState.writes[1].path,canonical); eq(ioState.encoded[1][4][kind.field][kind.middle],nil)
            assert(not admin.chats[#admin.chats]:find("remains in memory",1,true))
            unchanged(env,ioState,function() remove(env,admin,kind,kind.first) end)
            local predecessor=ioState.files[canonical]
            admin:SetPos(env.Vector(901,902,903))
            eq(say(env,admin,kind.add),nil,"bare command chat visibility remains unchanged")
            eq(list[kind.last+1],admin:GetPos()); eq(list[kind.middle],nil)
            eq(list[kind.first],first); eq(list[kind.last],last)
            eq(ioState.encodes,2); eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3)
            eq(ioState.files[backup],predecessor,"backup keeps the exact prior removal")
            ioState.codec.same(ioState.codec.decode(ioState.files[backup]),ioState.encoded[1])
            ioState.codec.same(ioState.codec.decode(ioState.files[canonical]),ioState.encoded[2])
            eq(#second.chats,0); eq(#observer.chats,0)
        end)

        for _,edit in ipairs({"add","bare removal","indexed removal"}) do
            test("two admins reject a stale " .. kind.name .. " inspection after " .. edit,function()
                local env,admin,second,_,ioState,current=fixture()
                inspect(env,admin,kind); inspect(env,second,kind)
                if edit == "add" then say(env,second,kind.add)
                elseif edit == "bare removal" then say(env,second,kind.remove)
                else remove(env,second,kind,kind.middle) end
                eq(#ioState.writes,1,"second admin's accepted edit saves once")
                local point=current[kind.field][kind.first]
                unchanged(env,ioState,function() remove(env,admin,kind,kind.first) end)
                eq(current[kind.field][kind.first],point)
                inspect(env,admin,kind); remove(env,admin,kind,kind.first)
                eq(current[kind.field][kind.first],nil); eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3)
            end)
        end

        test("two admins cannot delete a reused " .. kind.name .. " key even with identical coordinates",function()
            local env,admin,second,_,ioState,current=fixture()
            current[kind.field]={[2]=env.Vector(1,2,3),[3]=env.Vector(4,5,6)}
            inspect(env,admin,kind)
            second:SetPos(env.Vector(4,5,6)); say(env,second,kind.remove); say(env,second,kind.add)
            local replacement=current[kind.field][3]; eq(replacement,second:GetPos()); eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3)
            unchanged(env,ioState,function() remove(env,admin,kind,3) end)
            eq(current[kind.field][3],replacement)
            inspect(env,admin,kind); remove(env,admin,kind,3)
            eq(current[kind.field][3],nil); eq(#ioState.canonicalWrites,3); eq(#ioState.backupWrites,2); eq(#ioState.writes,5)
        end)

        for _,boundary in ipairs({"disconnect","initialize missing file","initialize rejected file"}) do
            test("a " .. kind.name .. " inspection expires at " .. boundary,function()
                local env,admin,second,_,ioState,current=fixture(); inspect(env,admin,kind); inspect(env,second,kind)
                if boundary == "disconnect" then env.fire("PlayerDisconnected",admin)
                else
                    if boundary == "initialize rejected file" then ioState.files[canonical]="recoverable invalid data" end
                    env.fire("Initialize")
                end
                eq(env.SpawnPositions[4],current,"test preserves source identity across the boundary")
                unchanged(env,ioState,function() remove(env,admin,kind,kind.first) end)
                if boundary == "disconnect" then
                    remove(env,second,kind,kind.middle); eq(current[kind.field][kind.middle],nil)
                else unchanged(env,ioState,function() remove(env,second,kind,kind.middle) end) end
                inspect(env,admin,kind); remove(env,admin,kind,kind.first)
                eq(current[kind.field][kind.first],nil,"a fresh inspection restores authority")
                if boundary == "initialize rejected file" then
                    eq(#ioState.writes,0); eq(ioState.encodes,0); eq(ioState.files[canonical],"recoverable invalid data")
                    contains(admin.chats[#admin.chats],"remains in memory; saving failed, is disabled or could not be verified")
                end
            end)
        end

        for _,failure in ipairs({"write false","write error","encode error","encode nil","encode empty"}) do
            test("indexed " .. kind.name .. " removal retains memory on " .. failure .. " and shutdown retries",function()
                local env,admin,second,observer,ioState,current=fixture()
                inspect(env,admin,kind); inspect(env,second,kind); ioState.failure=failure
                local state=lifecycle(env); local errors=#env.errors
                quietEngine(env,function() remove(env,second,kind,kind.middle) end)
                eq(current[kind.field][kind.middle],nil); sameLifecycle(env,state)
                eq(ioState.encodes,1); eq(#ioState.writes,failure:find("write",1,true) and 1 or 0)
                eq(ioState.files[canonical],nil); contains(second.chats[#second.chats],"remains in memory; saving failed, is disabled or could not be verified")
                eq(#env.errors,errors+1); eq(#observer.chats,0)
                unchanged(env,ioState,function() remove(env,admin,kind,kind.first) end)
                ioState.failure=nil; local attempts=#ioState.writes
                eq(env.fire("ShutDown"),nil,"shutdown does not stop other hooks")
                eq(ioState.encodes,2); eq(#ioState.writes,attempts+1)
                eq(ioState.writes[#ioState.writes].path,canonical)
                eq(ioState.encoded[2][4][kind.field][kind.middle],nil)
                assert(ioState.files[canonical]); eq(current[kind.field][kind.first] ~= nil,true)
            end)
        end

        for _,mode in ipairs({"uninitialized","rejected"}) do
            test("indexed " .. kind.name .. " removal honors " .. mode .. " save protection",function()
                local env,admin,second,_,ioState,current=fixture(mode)
                if mode == "uninitialized" then ioState.files[canonical]="recoverable data" end
                local original=ioState.files[canonical]
                inspect(env,admin,kind); inspect(env,second,kind)
                remove(env,second,kind,kind.middle); eq(current[kind.field][kind.middle],nil)
                contains(second.chats[#second.chats],"remains in memory; saving failed, is disabled or could not be verified")
                unchanged(env,ioState,function() remove(env,admin,kind,kind.first) end)
                env.fire("ShutDown")
                eq(ioState.encodes,0); eq(#ioState.writes,0); eq(ioState.files[canonical],original)
            end)
        end

        test("indexed " .. kind.name .. " edit keeps whole-file validation at the save boundary",function()
            local env,admin,_,_,ioState,current=fixture()
            env.SpawnPositions[19].enemySpawnPositions[6]="invalid unrelated saved position"
            inspect(env,admin,kind); remove(env,admin,kind,kind.middle)
            eq(current[kind.field][kind.middle],nil)
            eq(ioState.encodes,0); eq(#ioState.writes,0)
            contains(admin.chats[#admin.chats],"remains in memory; saving failed, is disabled or could not be verified")
            env.fire("ShutDown"); eq(ioState.encodes,0); eq(#ioState.writes,0)
        end)

        test("ready " .. kind.name .. " edits preserve selected pending and the actual open Start permission",function()
            local env,admin,second,_,ioState,current=fixture(); local client=gmod.new(true)
            local actor=ready(env,admin); local menu=open(env,client,admin,actor)
            local before=selection(env,admin); local state=lifecycle(env)
            unchanged(env,ioState,function() inspectUnavailable(env,second,kind) end)
            quietEngine(env,function() remove(env,second,kind,kind.middle) end)
            eq(current[kind.field][kind.middle],nil); sameLifecycle(env,state); eq(selection(env,admin),before)
            eq(menu.frame.valid,true); eq(#client.messages,0); eq(#ioState.writes,1)
            click(env,client,admin,menu)
            eq(env.totalEnemies,2); eq(env.messageCount("ActivatorEventStatus"),1)
            contains(selection(env,admin),'Pending next batch: "Raid"')
            contains(selection(env,admin),"Selected ready batch: none")
            for _,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do env.fire("OnNPCKilled",enemy,admin) end
            eq(env.messageCount("roundFinished"),1); env.fireTimer("activatorSpawner")
            eq(#env.ents.FindByClass("activatorent"),3)
            for _,nextActor in ipairs(env.ents.FindByClass("activatorent")) do eq(nextActor.EventIdentifier,"Raid") end
            eq(#ioState.writes,1)
        end)

        for _,interrupted in ipairs({false,true}) do
            test("active " .. kind.name .. " edit preserves encounter outcome interrupted=" .. tostring(interrupted),function()
                local env,admin,second,_,ioState,current=fixture(); local client=gmod.new(true)
                local actor=ready(env,admin); click(env,client,admin,open(env,client,admin,actor))
                local enemies=env.ents.FindByName("devonsSpawnedEntity")
                if interrupted then enemies[1]:Remove() end
                local before=selection(env,admin); local state=lifecycle(env)
                unchanged(env,ioState,function() inspectUnavailable(env,second,kind) end)
                quietEngine(env,function() remove(env,second,kind,kind.middle) end)
                sameLifecycle(env,state); eq(selection(env,admin),before)
                eq(current[kind.field][kind.middle],nil); eq(#ioState.writes,1)
                for _,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do env.fire("OnNPCKilled",enemy,admin) end
                eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),interrupted and 0 or 1)
                eq(env.timers.activatorSpawner.stopped,false); env.fireTimer("activatorSpawner")
                for _,nextActor in ipairs(env.ents.FindByClass("activatorent")) do eq(nextActor.EventIdentifier,"Raid") end
                eq(#env.ents.FindByClass("activatorent"),3); eq(#ioState.writes,1)
            end)
        end
    end

    local malformed={
        {"missing current map",function(env) env.map="unconfigured_map" end},
        {"non-table root",function(env) env.SpawnPositions=false end},
        {"malformed map record",function(env) env.SpawnPositions[19]=false end},
        {"duplicate current map",function(env) env.SpawnPositions[19].map=env.map end},
        {"invalid map key",function(env) env.SpawnPositions.bad=env.SpawnPositions[19]; env.SpawnPositions[19]=nil end},
        {"missing list",function(_,current,kind) current[kind.field]=nil end},
        {"non-table list",function(_,current,kind) current[kind.field]=false end},
        {"empty list",function(_,current,kind) current[kind.field]={} end},
        {"plain coordinates",function(_,current,kind) current[kind.field][kind.middle]={x=1,y=2,z=3} end},
        {"non-finite vector",function(env,current,kind) current[kind.field][kind.middle]=env.Vector(math.huge,1,2) end},
        {"string position key",function(env,current,kind) current[kind.field].bad=env.Vector(1,2,3) end},
    }
    for _,kind in ipairs(kinds) do
        for _,case in ipairs(malformed) do
            test("workflow refuses " .. kind.name .. " " .. case[1] .. " with no encounter or persistence side effect",function()
                local env,admin,_,_,ioState,current=fixture(); local actor=ready(env,admin)
                actor:AcceptInput("Use",admin,admin)
                inspect(env,admin,kind); case[2](env,current,kind)
                unchanged(env,ioState,function()
                    inspect(env,admin,kind); remove(env,admin,kind,kind.middle)
                end)
            end)
        end
    end

    for _,role in ipairs({"non-admin","lost admin","invalid player","non-player","nil sender"}) do
        test("workflow denies " .. role .. " at listing and indexed deletion boundaries",function()
            local env,admin,_,_,ioState=fixture(); local kind=kinds[1]
            if role == "lost admin" then inspect(env,admin,kind) end
            local sender=admin
            if role == "non-admin" or role == "lost admin" then admin.admin=false
            elseif role == "invalid player" then admin.valid=false
            elseif role == "non-player" then admin.class="prop_physics"
            else sender=nil end
            local chats=#admin.chats
            unchanged(env,ioState,function()
                say(env,sender,"!listSpawns enemy"); say(env,sender,"!removeEnemySpawn 10")
            end)
            if role == "non-admin" or role == "lost admin" then
                eq(#admin.chats,chats+2)
                for i=chats+1,#admin.chats do assert(#admin.chats[i] <= 255) end
            else eq(#admin.chats,chats) end
        end)
    end

    test("workflow rejects malformed arguments privately without bare-command fallback or engine activity",function()
        local env,admin,_,_,ioState=fixture(); local actor=ready(env,admin)
        admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
        local kind=kinds[1]; inspect(env,admin,kind)
        local commands={"!listSpawns", "!listSpawns enemy 0", "!listSpawns enemy 1.5", "!listSpawns enemy 1 extra",
            "!listSpawns wrong", "!listSpawns enemy nope", "!listSpawns enemy -1", "!listSpawns enemy 99999999",
            "!removeEnemySpawn nope", "!removeEnemySpawn 0", "!removeEnemySpawn -1", "!removeEnemySpawn 1.5",
            "!removeEnemySpawn 10 extra", "!removeActivatorSpawn nope", "!removeActivatorSpawn 11 extra"}
        local before=selection(env,admin)
        for _,command in ipairs(commands) do unchanged(env,ioState,function() privateSay(env,admin,command) end) end
        eq(selection(env,admin),before)
        env.receive("SendNPCInformation",admin,"Ambush"); eq(env.totalEnemies,2,"malformed edit commands retain interaction")
    end)

    test("removing the last enemy point follows actual failed Start guidance and existing add repairs it",function()
        local env,admin,second,observer,ioState,current=fixture(); local client=gmod.new(true)
        local kind=kinds[1]; current.enemySpawnPositions={[10]=env.Vector(10,20,30)}
        local actor=ready(env,admin); local menu=open(env,client,admin,actor)
        local before=selection(env,admin); local state=lifecycle(env)
        inspect(env,second,kind); remove(env,second,kind,10)
        sameLifecycle(env,state); eq(next(current.enemySpawnPositions),nil); eq(#ioState.writes,1)
        eq(selection(env,admin),before); local chats=#admin.chats; local observers=#observer.chats
        local request=click(env,client,admin,menu)
        eq(env.totalEnemies,0); eq(actor.valid,true); eq(#env.ents.FindByClass("activatorent"),3)
        eq(#admin.chats,chats+1); eq(#observer.chats,observers)
        eq(admin.chats[#admin.chats],"No enemy spawn position is available. Ask an admin to fix it, then use the activator again.")
        eq(env.messageCount("ActivatorEventStatus"),0); eq(env.messageCount("roundFinished"),0)
        eq(selection(env,admin),before); eq(#ioState.writes,1)
        unchanged(env,ioState,function() env.deliver(request,admin) end)
        second:SetPos(env.Vector(700,800,900)); eq(say(env,second,kind.add),nil)
        eq(current.enemySpawnPositions[1],second:GetPos()); eq(current.enemySpawnPositions[10],nil)
        eq(ioState.encodes,2); eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3); eq(env.totalEnemies,0)
        unchanged(env,ioState,function() env.deliver(request,admin) end)
        menu=open(env,client,admin,actor); click(env,client,admin,menu)
        eq(env.totalEnemies,2); eq(#env.ents.FindByClass("activatorent"),0)
        contains(selection(env,admin),'Pending next batch: "Raid"')
        for _,enemy in ipairs(env.ents.FindByName("devonsSpawnedEntity")) do env.fire("OnNPCKilled",enemy,admin) end
        eq(env.messageCount("roundFinished"),1); env.fireTimer("activatorSpawner")
        eq(#env.ents.FindByClass("activatorent"),3); eq(#ioState.canonicalWrites,2); eq(#ioState.backupWrites,1); eq(#ioState.writes,3)
    end)
end
