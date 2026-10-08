-- Public legacy chat edits through the actual loader, save and encounter code.
-- Existing engine/Vector/file doubles and the shared byte-token codec do not
-- claim native GMod JSON, DATA durability, chat delivery or placement coverage.
return function(gmod, test, eq)
    local newCodec=dofile("tests/spawn-storage-codec.lua")
    local canonical,backup="devonsspawninfo.json","devonsspawninfo.backup.json"
    local kinds={
        {name="enemy",field="enemySpawnPositions",add="!setEnemySpawn",remove="!removeEnemySpawn",first=2,last=27},
        {name="activator",field="activatorSpawnPositions",add="!setActivatorSpawn",remove="!removeActivatorSpawn",first=3,last=29},
    }
    local function count(value) local n=0; for _ in pairs(value) do n=n+1 end; return n end
    local function tree(value)
        local result={value=value}
        if type(value) == "table" then
            result.entries={}
            for key,child in pairs(value) do result.entries[key]=tree(child) end
        end
        return result
    end
    local function sameTree(value,expected)
        if type(expected.value) == "number" and expected.value ~= expected.value then assert(value ~= value)
        else eq(value,expected.value,"retained object or value") end
        if expected.entries then
            for key,child in pairs(expected.entries) do sameTree(value[key],child) end
            for key in pairs(value) do assert(expected.entries[key],"unexpected field " .. tostring(key)) end
        end
    end
    local function contains(text,fragment) assert(text:find(fragment,1,true),"missing " .. fragment .. " in " .. text) end
    local function storage(env)
        local state={files={},exists=0,reads={},encodes=0,decodes=0,writes={},encoded={}}
        local codec=newCodec(env,eq); state.codec=codec
        env.print=function() end
        env.file.Exists=function(path,realm)
            eq(realm,"DATA"); state.exists=state.exists+1; return state.files[path] ~= nil
        end
        env.file.Read=function(path,realm)
            eq(realm,"DATA"); state.reads[#state.reads+1]=path; return state.files[path]
        end
        env.file.Write=function(path,bytes)
            assert(path == canonical or path == backup,"unexpected DATA destination")
            state.writes[#state.writes+1]={path=path,bytes=bytes}
            if state.failure == "write false" or (state.failure == "canonical false" and path == canonical) then return false end
            if state.failure == "write error" then error("synthetic write failure") end
            state.files[path]=bytes; return true
        end
        env.util.TableToJSON=function(value)
            state.encodes=state.encodes+1; state.encoded[#state.encoded+1]=codec.copy(value)
            if state.failure == "encode error" then error("synthetic encode failure") end
            if state.failure == "encode nil" then return nil end
            return codec.encode(value)
        end
        env.util.JSONToTable=function(...)
            state.decodes=state.decodes+1; return codec.decode(...)
        end
        return state
    end
    local function fixture(mode)
        local env=gmod.new(); local ioState=storage(env)
        local current={map="gm_construct",enemySpawnPositions={
            [2]=env.Vector(102,202,302),[10]=env.Vector(110,210,310),[27]=env.Vector(127,227,327)},
            activatorSpawnPositions={
            [3]=env.Vector(203,303,403),[11]=env.Vector(211,311,411),[29]=env.Vector(229,329,429)}}
        local configured={[4]=current,[19]={map="other_map",
            enemySpawnPositions={[6]=env.Vector(6,7,8)},activatorSpawnPositions={[9]=env.Vector(9,8,7)}}}
        env.SpawnPositions=configured
        if mode == "loaded" or mode == "duplicate" then
            if mode == "duplicate" then
                configured[23]={map="gm_construct",enemySpawnPositions={[17]=env.Vector(71,72,73)},
                    activatorSpawnPositions={[18]=env.Vector(81,82,83)}}
            end
            ioState.files[canonical]=ioState.codec.remember("published saved spawn bytes",configured)
        elseif mode == "rejected" then
            ioState.files[canonical]="recoverable rejected canonical bytes"
            ioState.files[backup]=ioState.codec.remember("recoverable backup bytes",configured)
        end
        if mode ~= "uninitialized" then env.fire("Initialize") end
        if mode == "loaded" or mode == "duplicate" then
            assert(not rawequal(env.SpawnPositions,configured),"Initialize installs the decoded root")
            ioState.codec.same(env.SpawnPositions,configured)
            eq(ioState.decodes,1); eq(#ioState.reads,1); eq(ioState.reads[1],canonical)
            eq(ioState.encodes,0); eq(#ioState.writes,0); eq(#env.errors,0)
        elseif mode == "rejected" then
            eq(env.SpawnPositions,configured,"rejected load keeps configured positions")
            eq(#env.errors,1); eq(#ioState.reads,1); eq(ioState.reads[1],canonical,"backup is never auto-loaded")
        end
        local admin=env.entity("player"); admin.admin=true
        local second=env.entity("player"); second.admin=true
        local observer=env.entity("player")
        return env,admin,second,observer,ioState,env.SpawnPositions[4]
    end
    local function say(env,player,text) return env.fire("PlayerSay",player,text) end
    local function output(env,player,command,expected)
        local chats={}; for _,other in ipairs(env.player.GetAll()) do chats[other]=#other.chats end
        eq(say(env,player,command),expected,"legacy/public chat return")
        local lines={}
        for i=chats[player]+1,#player.chats do
            assert(#player.chats[i] <= 255,"private response exceeds chat byte limit")
            lines[#lines+1]=player.chats[i]
        end
        assert(#lines > 0,"requester gets feedback")
        for other,before in pairs(chats) do if other ~= player then eq(#other.chats,before,"feedback stays requester-only") end end
        return table.concat(lines,"\n")
    end
    local function inspect(env,player,kind) return output(env,player,"!listSpawns " .. kind.name,"") end
    local function indexed(env,player,kind,key) return output(env,player,kind.remove .. " " .. tostring(key),"") end
    local function legacy(env,player,kind,operation,expected) return output(env,player,kind[operation],expected) end
    local function lifecycle(env)
        local state={entities={},count=#env.entities,enemies=env.totalEnemies,activators=env.activatorCount,
            messages=#env.messages,timers=tree(env.timers),receivers=tree(env.receivers),network=tree(env.networkStrings)}
        for _,ent in ipairs(env.entities) do
            state.entities[ent]={valid=ent.valid,marked=ent.markedForDeletion,pos=tree(ent.pos),class=ent.class,
                name=ent.name,health=ent.health,model=ent.model,movement=ent.moveType,moves=ent.moveChanges,
                stopped=ent.stopped,spawned=ent.spawned,event=ent.EventIdentifier,info=ent.NPCInfo}
        end
        return state
    end
    local function sameLifecycle(env,state)
        eq(#env.entities,state.count,"no new entity"); eq(env.totalEnemies,state.enemies); eq(env.activatorCount,state.activators)
        eq(#env.messages,state.messages,"no addon packet"); sameTree(env.timers,state.timers)
        sameTree(env.receivers,state.receivers); sameTree(env.networkStrings,state.network)
        for _,ent in ipairs(env.entities) do
            local before=assert(state.entities[ent],"entity identity changed")
            eq(ent.valid,before.valid); eq(ent.markedForDeletion,before.marked); sameTree(ent.pos,before.pos)
            eq(ent.class,before.class); eq(ent.name,before.name); eq(ent.health,before.health); eq(ent.model,before.model)
            eq(ent.moveType,before.movement); eq(ent.moveChanges,before.moves); eq(ent.stopped,before.stopped)
            eq(ent.spawned,before.spawned); eq(ent.EventIdentifier,before.event); eq(ent.NPCInfo,before.info)
        end
    end
    -- Wrap only existing engine doubles, never addon handlers/save/encounter functions.
    local function quietEngine(env,callback)
        local replacements,calls={},0
        local function watch(owner,key)
            local original=owner[key]; replacements[#replacements+1]={owner,key,original}
            owner[key]=function(...) calls=calls+1; return original(...) end
        end
        local oldMath=env.math; env.math=setmetatable({}, {__index=oldMath}); watch(env.math,"random")
        for _,key in ipairs({"Create","Start","Stop","Simple"}) do watch(env.timer,key) end
        for _,key in ipairs({"Start","Send","Broadcast"}) do watch(env.net,key) end
        watch(env.ents,"Create")
        for _,ent in ipairs(env.entities) do
            for _,key in ipairs({"Remove","Spawn","SetPos","SetHealth","SetMoveType"}) do watch(ent,key) end
        end
        local ok,message=pcall(callback)
        for _,entry in ipairs(replacements) do entry[1][entry[2]]=entry[3] end
        env.math=oldMath
        assert(ok,message); eq(calls,0,"no RNG, entity, timer or network activity")
    end
    local function unchanged(env,ioState,callback)
        local positions,state,files=tree(env.SpawnPositions),lifecycle(env),tree(ioState.files)
        local exists,reads,decodes,encodes,writes,errors=ioState.exists,#ioState.reads,ioState.decodes,ioState.encodes,#ioState.writes,#env.errors
        local ok,message=pcall(quietEngine,env,callback)
        sameTree(env.SpawnPositions,positions); sameLifecycle(env,state); sameTree(ioState.files,files)
        eq(ioState.exists,exists); eq(#ioState.reads,reads); eq(ioState.decodes,decodes); eq(ioState.encodes,encodes)
        eq(#ioState.writes,writes); eq(#env.errors,errors,"refusal does not call save")
        assert(ok,message)
    end
    local function accepted(env,player,ioState,kind,operation)
        local state=lifecycle(env); local encodes=ioState.encodes
        quietEngine(env,function() legacy(env,player,kind,operation,nil) end)
        sameLifecycle(env,state); eq(ioState.encodes,encodes+1,"one immediate save path")
    end
    local function status(env,admin)
        local before=#admin.chats; eq(say(env,admin,"!eventStatus"),"")
        local result={}
        for i=before+1,#admin.chats do
            local line=admin.chats[i]
            if line:find("^Active event:") or line:find("^Ready activators:") or line:find("^Ready event:")
                or line:find("^Selected ready batch:") or line:find("^Pending next batch:") then result[#result+1]=line end
        end
        return table.concat(result,"\n")
    end
    local function ready(env,admin)
        local raid=env.NPCEdits[1].information
        env.NPCEdits[7]={name="Ambush",information={activatorModel=raid.activatorModel,npcPath="npc_combine_s",
            maxNPCs=2,dialogue="An ambush awaits."}}
        eq(say(env,admin,"!nextEvent Ambush"),""); env.fireTimer("activatorSpawner")
        eq(say(env,admin,"!nextEvent Raid"),"")
        return assert(env.ents.FindByClass("activatorent")[1])
    end
    local function open(env,client,player,actor)
        player:SetPos(actor:GetPos()); actor:AcceptInput("Use",player,player)
        local message=env.messages[#env.messages]; eq(message.name,"OpenInteractionMenu")
        local first=#client.panels+1; client.deliver(message)
        local frame,start,cancel
        for i=first,#client.panels do
            local panel=client.panels[i]
            if panel.class == "DFrame" then frame=panel
            elseif panel.class == "DButton" and panel.text:find("Start",1,true) then start=panel
            elseif panel.class == "DButton" and panel.text:find("Quit",1,true) then cancel=panel end
        end
        return {frame=assert(frame),start=assert(start),cancel=assert(cancel)}
    end
    local function click(env,client,player,menu,cancel)
        local before=#client.messages
        if cancel then menu.cancel:DoClick() else menu.start:DoClick() end
        eq(menu.frame.valid,false); eq(#client.messages,before+1)
        local request=client.messages[#client.messages]; eq(request.name,cancel and "CloseInteractionMenu" or "SendNPCInformation")
        env.deliver(request,player)
    end
    local function enemiesAfter(env,before,expected)
        local enemies={}
        for i=before+1,#env.entities do
            local ent=env.entities[i]
            if ent.name == "devonsSpawnedEntity" then enemies[#enemies+1]=ent; eq(ent.valid,true); eq(ent.spawned,true) end
        end
        eq(#enemies,expected); eq(env.totalEnemies,expected); return enemies
    end
    local function finish(env,player,enemies)
        for _,enemy in ipairs(enemies) do if enemy.valid then env.fire("OnNPCKilled",enemy,player) end end
        eq(env.totalEnemies,0)
    end

    for _,kind in ipairs(kinds) do
        for _,operation in ipairs({"add","remove"}) do
            local label="legacy " .. kind.name .. " " .. operation
            test(label .. " refuses two distinct current-map records loaded by codec and Initialize",function()
                local env,admin,_,_,ioState,current=fixture("duplicate")
                assert(current ~= env.SpawnPositions[23]); eq(current.map,env.SpawnPositions[23].map)
                assert(current[kind.field] ~= env.SpawnPositions[23][kind.field]); eq(count(env.SpawnPositions),3)
                unchanged(env,ioState,function()
                    contains(legacy(env,admin,kind,operation,nil),"ambiguous")
                end)
                eq(ioState.files[canonical],"published saved spawn bytes"); eq(ioState.files[backup],nil)
                eq(count(env.SpawnPositions),3,"no implicit duplicate repair")
            end)

            local malformed={
                {"false root",function(e) e.SpawnPositions=false end},
                {"string root",function(e) e.SpawnPositions="bad" end},
                {"zero map key",function(e) e.SpawnPositions[0]=e.SpawnPositions[19]; e.SpawnPositions[19]=nil end},
                {"fractional map key",function(e) e.SpawnPositions[1.5]=e.SpawnPositions[19]; e.SpawnPositions[19]=nil end},
                {"string map key",function(e) e.SpawnPositions.other=e.SpawnPositions[19]; e.SpawnPositions[19]=nil end},
                {"infinite map key",function(e) e.SpawnPositions[math.huge]=e.SpawnPositions[19]; e.SpawnPositions[19]=nil end},
                {"current non-table record",function(e) e.SpawnPositions[4]=false end},
                {"unrelated non-table record",function(e) e.SpawnPositions[19]=false end},
                {"missing current map identity",function(_,c) c.map=nil end},
                {"empty current map identity",function(_,c) c.map="" end},
                {"numeric current map identity",function(_,c) c.map=1 end},
                {"missing unrelated map identity",function(e) e.SpawnPositions[19].map=nil end},
                {"empty unrelated map identity",function(e) e.SpawnPositions[19].map="" end},
                {"boolean unrelated map identity",function(e) e.SpawnPositions[19].map=false end},
                {"missing target list",function(_,c) c[kind.field]=nil end},
                {"false target list",function(_,c) c[kind.field]=false end},
                {"string target list",function(_,c) c[kind.field]="bad" end},
                {"zero point key",function(e,c) c[kind.field][0]=e.Vector(1,2,3) end},
                {"negative point key",function(e,c) c[kind.field][-1]=e.Vector(1,2,3) end},
                {"fractional point key",function(e,c) c[kind.field][1.5]=e.Vector(1,2,3) end},
                {"string point key",function(e,c) c[kind.field].bad=e.Vector(1,2,3) end},
                {"infinite point key",function(e,c) c[kind.field][math.huge]=e.Vector(1,2,3) end},
                {"non-Vector point",function(_,c) c[kind.field][kind.first]={x=1,y=2,z=3} end},
                {"false point",function(_,c) c[kind.field][kind.first]=false end},
                {"infinite Vector",function(e,c) c[kind.field][kind.first]=e.Vector(1,math.huge,3) end},
                {"NaN Vector",function(e,c) c[kind.field][kind.first]=e.Vector(1,2,0/0) end},
                {"missing Vector coordinate",function(e,c) c[kind.field][kind.first]=e.Vector(nil,2,3) end},
            }
            for _,case in ipairs(malformed) do
                test(label .. " refuses " .. case[1] .. " before mutation or storage",function()
                    local env,admin,_,_,ioState,current=fixture("loaded"); case[2](env,current)
                    unchanged(env,ioState,function()
                        local text=legacy(env,admin,kind,operation,nil)
                        assert(text:find("malformed",1,true) or text:find("missing",1,true),"explain malformed or missing target")
                        assert(not text:find("successfully",1,true) and not text:find("Successfully",1,true),"no false success")
                    end)
                end)
            end

            test(label .. " keeps valid local edits session-only for unrelated invalid positions",function()
                local env,admin,second,_,ioState,current=fixture("loaded")
                local old=tree(current[kind.field]); local remote=env.SpawnPositions[19]
                remote.enemySpawnPositions[6]=false; local remoteState=tree(remote)
                inspect(env,admin,kind); inspect(env,second,kind)
                local text=legacy(env,second,kind,operation,nil)
                contains(text,"remains in memory; saving failed, is disabled or could not be verified")
                if operation == "add" then
                    eq(current[kind.field][kind.last+1],second:GetPos()); old.entries[kind.last+1]=tree(second:GetPos())
                else old.entries[kind.last]=nil end
                sameTree(current[kind.field],old); sameTree(remote,remoteState)
                eq(ioState.encodes,0); eq(#ioState.writes,0); eq(#ioState.reads,1)
                eq(ioState.files[canonical],"published saved spawn bytes")
                unchanged(env,ioState,function()
                    contains(indexed(env,admin,kind,kind.first),"inspect a current key")
                    contains(indexed(env,second,kind,kind.first),"inspect a current key")
                end)
            end)

            test(label .. " admits a valid target despite an invalid opposite-kind list on the same map",function()
                local env,admin,_,_,ioState,current=fixture("loaded")
                local otherKind=kind == kinds[1] and kinds[2] or kinds[1]
                current[otherKind.field]=false
                contains(legacy(env,admin,kind,operation,nil),"remains in memory")
                if operation == "add" then eq(current[kind.field][kind.last+1],admin:GetPos())
                else eq(current[kind.field][kind.last],nil) end
                eq(current[otherKind.field],false); eq(ioState.encodes,0); eq(#ioState.writes,0)
                eq(ioState.files[canonical],"published saved spawn bytes"); eq(ioState.files[backup],nil)
            end)

            for _,failure in ipairs({"none","write false","write error","encode error","encode nil"}) do
                test(label .. " invalidates both admins only for the affected map and kind after " .. failure,function()
                    local env,admin,second,_,ioState,current=fixture()
                    local otherKind=kind == kinds[1] and kinds[2] or kinds[1]
                    local otherAdmin=env.entity("player"); otherAdmin.admin=true
                    local remoteAdmin=env.entity("player"); remoteAdmin.admin=true
                    inspect(env,admin,kind); inspect(env,second,kind); inspect(env,otherAdmin,otherKind)
                    env.map="other_map"; inspect(env,remoteAdmin,kind); env.map="gm_construct"
                    ioState.failure=failure; local text=legacy(env,second,kind,operation,nil)
                    if failure ~= "none" then contains(text,"remains in memory") end
                    if operation == "add" then eq(current[kind.field][kind.last+1],second:GetPos())
                    else eq(current[kind.field][kind.last],nil) end
                    unchanged(env,ioState,function()
                        contains(indexed(env,admin,kind,kind.first),"inspect a current key")
                        contains(indexed(env,second,kind,kind.first),"inspect a current key")
                    end)
                    ioState.failure=nil
                    contains(indexed(env,otherAdmin,otherKind,otherKind.first),"successfully removed")
                    env.map="other_map"
                    contains(indexed(env,remoteAdmin,kind,kind.name == "enemy" and 6 or 9),"successfully removed")
                end)
            end

            for _,survivor in ipairs({1,2}) do
                test(label .. " refusal preserves prior inspection for admin " .. survivor,function()
                    local env,admin,second,_,ioState,current=fixture()
                    inspect(env,admin,kind); inspect(env,second,kind)
                    env.SpawnPositions[23]={map="gm_construct",enemySpawnPositions={},activatorSpawnPositions={}}
                    unchanged(env,ioState,function() contains(legacy(env,second,kind,operation,nil),"ambiguous") end)
                    env.SpawnPositions[23]=nil
                    contains(indexed(env,survivor == 1 and admin or second,kind,kind.first),"successfully removed")
                    eq(current[kind.field][kind.first],nil); eq(ioState.encodes,1)
                end)
            end

            test(label .. " malformed-target refusal preserves requester and opposite-kind inspection",function()
                local env,admin,second,_,ioState,current=fixture()
                local otherKind=kind == kinds[1] and kinds[2] or kinds[1]
                inspect(env,admin,otherKind); inspect(env,second,kind)
                local positions=current[kind.field]; current[kind.field]=false
                unchanged(env,ioState,function() contains(legacy(env,second,kind,operation,nil),"malformed") end)
                current[kind.field]=positions
                contains(indexed(env,admin,otherKind,otherKind.first),"successfully removed")
                contains(indexed(env,second,kind,kind.first),"successfully removed")
                eq(current[kind.field][kind.first],nil); eq(ioState.encodes,2)
            end)

            for _,mode in ipairs({"rejected","uninitialized"}) do
                test(label .. " keeps accepted memory edits under " .. mode .. " save lockout",function()
                    local env,admin,second,_,ioState,current=fixture(mode)
                    if mode == "uninitialized" then
                        ioState.files[canonical]="unread protected original"; ioState.files[backup]="protected backup"
                    end
                    local files=tree(ioState.files); local reads=#ioState.reads
                    inspect(env,admin,kind); inspect(env,second,kind)
                    contains(legacy(env,second,kind,operation,nil),"remains in memory")
                    if operation == "add" then eq(current[kind.field][kind.last+1],second:GetPos())
                    else eq(current[kind.field][kind.last],nil) end
                    unchanged(env,ioState,function()
                        contains(indexed(env,admin,kind,kind.first),"inspect a current key")
                        contains(indexed(env,second,kind,kind.first),"inspect a current key")
                    end)
                    eq(env.fire("ShutDown"),nil); sameTree(ioState.files,files)
                    eq(ioState.encodes,0); eq(ioState.decodes,mode == "rejected" and 1 or 0)
                    eq(#ioState.reads,reads); eq(#ioState.writes,0)
                end)
            end

            test(label .. " keeps prepared predecessor backup safe through canonical failure and retry",function()
                local env,admin,_,_,ioState=fixture("loaded")
                ioState.failure="canonical false"; contains(legacy(env,admin,kind,operation,nil),"remains in memory")
                eq(#ioState.writes,2); eq(ioState.writes[1].path,backup); eq(ioState.writes[2].path,canonical)
                eq(ioState.files[backup],"published saved spawn bytes"); eq(ioState.files[canonical],"published saved spawn bytes")
                ioState.files[backup]="externally changed prepared backup"; ioState.failure=nil
                local writes=#ioState.writes; eq(env.fire("ShutDown"),nil)
                eq(#ioState.writes,writes,"changed prepared recovery copy is not overwritten")
                eq(ioState.files[backup],"externally changed prepared backup"); eq(ioState.files[canonical],"published saved spawn bytes")
                ioState.files[backup]="published saved spawn bytes"; env.fire("ShutDown")
                eq(#ioState.writes,writes+1); eq(ioState.writes[#ioState.writes].path,canonical)
                ioState.codec.same(ioState.codec.decode(ioState.files[canonical]),env.SpawnPositions)
                eq(ioState.files[backup],"published saved spawn bytes")
            end)

            for _,cancel in ipairs({false,true}) do
                test(label .. " preserves ready actors, pending selection and open " .. (cancel and "Quit" or "Start") .. " permission",function()
                    local env,admin,second,_,ioState=fixture(); local client=gmod.new(true)
                    local actor=ready(env,admin); local menu=open(env,client,admin,actor)
                    local before=status(env,admin); accepted(env,second,ioState,kind,operation)
                    eq(status(env,admin),before); eq(menu.frame.valid,true); eq(#client.messages,0)
                    if cancel then
                        click(env,client,admin,menu,true); eq(env.totalEnemies,0)
                        env.receive("SendNPCInformation",admin,"Ambush"); eq(env.totalEnemies,0,"Quit still consumes the grant")
                        menu=open(env,client,admin,actor)
                    end
                    local first=#env.entities; click(env,client,admin,menu)
                    local enemies=enemiesAfter(env,first,2)
                    contains(status(env,admin),'Pending next batch: "Raid"'); contains(status(env,admin),"Selected ready batch: none")
                    finish(env,admin,enemies); eq(env.messageCount("roundFinished"),1)
                    env.fireTimer("activatorSpawner"); local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
                    for _,nextActor in ipairs(actors) do eq(nextActor.EventIdentifier,"Raid") end
                    eq(ioState.encodes,1)
                end)
            end

            for _,active in ipairs({false,true}) do
                test(label .. " refusal preserves " .. (active and "active" or "ready open-grant") .. " encounter state",function()
                    local env,admin,second,_,ioState=fixture(); local client=gmod.new(true)
                    local actor=ready(env,admin); local menu=open(env,client,admin,actor)
                    local enemies
                    if active then
                        local first=#env.entities; click(env,client,admin,menu); enemies=enemiesAfter(env,first,2)
                    end
                    local before=status(env,admin)
                    env.SpawnPositions[23]={map="gm_construct",enemySpawnPositions={},activatorSpawnPositions={}}
                    unchanged(env,ioState,function() contains(legacy(env,second,kind,operation,nil),"ambiguous") end)
                    eq(status(env,admin),before); env.SpawnPositions[23]=nil
                    if not active then
                        eq(menu.frame.valid,true); eq(#client.messages,0)
                        local first=#env.entities; click(env,client,admin,menu); enemies=enemiesAfter(env,first,2)
                    end
                    finish(env,admin,enemies); eq(env.messageCount("roundFinished"),1)
                    eq(env.timers.activatorSpawner.stopped,false); env.fireTimer("activatorSpawner")
                    local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
                    for _,nextActor in ipairs(actors) do eq(nextActor.EventIdentifier,"Raid") end
                    eq(ioState.encodes,0); eq(#ioState.writes,0)
                end)
            end

            for _,outcome in ipairs({"victory","interrupted","admin stop"}) do
                test(label .. " preserves active ownership, pending selection and " .. outcome,function()
                    local env,admin,second,_,ioState=fixture(); local client=gmod.new(true)
                    local actor=ready(env,admin); local menu=open(env,client,admin,actor)
                    local first=#env.entities; click(env,client,admin,menu); local enemies=enemiesAfter(env,first,2)
                    if outcome == "interrupted" then enemies[1]:Remove() end
                    local before=status(env,admin); accepted(env,second,ioState,kind,operation); eq(status(env,admin),before)
                    if outcome == "admin stop" then say(env,admin,"!stopEvent") else finish(env,admin,enemies) end
                    eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),outcome == "victory" and 1 or 0)
                    eq(env.timers.activatorSpawner.stopped,false); env.fireTimer("activatorSpawner")
                    local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
                    for _,nextActor in ipairs(actors) do eq(nextActor.EventIdentifier,"Raid") end
                    menu=open(env,client,admin,actors[1]); first=#env.entities; click(env,client,admin,menu)
                    finish(env,admin,enemiesAfter(env,first,5))
                    eq(env.messageCount("roundFinished"),outcome == "victory" and 2 or 1); eq(ioState.encodes,1)
                end)
            end
        end

        test("legacy " .. kind.name .. " sparse add and highest removal preserve every other key and object",function()
            local env,admin,_,_,ioState,current=fixture()
            local snapshot=tree(env.SpawnPositions); local list=current[kind.field]
            admin:SetPos(env.Vector(901,902,903)); accepted(env,admin,ioState,kind,"add")
            eq(list[kind.last+1],admin:GetPos()); snapshot.entries[4].entries[kind.field].entries[kind.last+1]=tree(admin:GetPos())
            sameTree(env.SpawnPositions,snapshot); eq(count(list),4); eq(list[1],nil)
            accepted(env,admin,ioState,kind,"remove")
            snapshot.entries[4].entries[kind.field].entries[kind.last+1]=nil; sameTree(env.SpawnPositions,snapshot)
            accepted(env,admin,ioState,kind,"remove")
            snapshot.entries[4].entries[kind.field].entries[kind.last]=nil; sameTree(env.SpawnPositions,snapshot)
            eq(count(list),2); eq(ioState.encodes,3); eq(#ioState.writes,5)
        end)

        for _,empty in ipairs({false,true}) do
            test("legacy " .. kind.name .. " repeated absent-map add creates exactly one complete record from " .. (empty and "empty" or "sparse") .. " maps",function()
                local env,admin,_,_,ioState=fixture(); env.SpawnPositions[4]=nil
                if empty then env.SpawnPositions={} end
                local existing=tree(env.SpawnPositions); local maps=count(env.SpawnPositions)
                unchanged(env,ioState,function() contains(legacy(env,admin,kind,"remove",nil),"no more") end)
                accepted(env,admin,ioState,kind,"add")
                local current,key
                for index,record in pairs(env.SpawnPositions) do if record.map == "gm_construct" then assert(not current); current,key=record,index end end
                assert(current); eq(count(env.SpawnPositions),maps+1); eq(count(current[kind.field]),1); eq(current[kind.field][1],admin:GetPos())
                local otherKind=kind == kinds[1] and kinds[2] or kinds[1]; eq(count(current[otherKind.field]),0)
                existing.entries[key]=tree(current); sameTree(env.SpawnPositions,existing)
                admin:SetPos(env.Vector(301,302,303)); accepted(env,admin,ioState,kind,"add")
                eq(count(env.SpawnPositions),maps+1); eq(current[kind.field][2],admin:GetPos()); eq(count(current[kind.field]),2)
                eq(ioState.encodes,2); eq(#ioState.writes,3)
            end)
        end

        test("legacy " .. kind.name .. " empty bare removal is a no-op and preserves another kind's inspection",function()
            local env,admin,second,_,ioState,current=fixture(); current[kind.field]={}
            local otherKind=kind == kinds[1] and kinds[2] or kinds[1]; inspect(env,admin,otherKind)
            unchanged(env,ioState,function() contains(legacy(env,second,kind,"remove",nil),"no more") end)
            contains(indexed(env,admin,otherKind,otherKind.first),"successfully removed")
        end)

        local maxima={{name="floating successor precision boundary",previous=not math.maxinteger and 2^53-1 or nil,maximum=math.maxinteger and 2^63 or 2^53},
            {name="largest finite double",maximum=1.7976931348623157e308}}
        if math.maxinteger then maxima[#maxima+1]={name="native integer maximum",previous=math.maxinteger-1,maximum=math.maxinteger} end
        for _,maximum in ipairs(maxima) do
            test("legacy " .. kind.name .. " handles " .. maximum.name .. " without overwriting or rounding keys",function()
                local env,admin,second,_,ioState,current=fixture()
                local high=maximum.previous or maximum.maximum
                current[kind.field]={[1]=env.Vector(1,2,3),[high]=env.Vector(4,5,6)}
                if maximum.previous then accepted(env,admin,ioState,kind,"add"); eq(current[kind.field][maximum.maximum],admin:GetPos()) end
                inspect(env,admin,kind); inspect(env,second,kind)
                unchanged(env,ioState,function() contains(legacy(env,second,kind,"add",""),"no exact free key") end)
                contains(indexed(env,admin,kind,1),"successfully removed")
                local remaining=tree(current[kind.field]); accepted(env,second,ioState,kind,"remove")
                remaining.entries[maximum.maximum]=nil; sameTree(current[kind.field],remaining)
            end)
        end

        test("legacy " .. kind.name .. " permission, exact matching and indexed literal-token behavior remain distinct",function()
            local env,admin,_,observer,ioState,current=fixture()
            local nonPlayer=env.entity("prop_physics"); nonPlayer.admin=true
            unchanged(env,ioState,function()
                for _,command in ipairs({kind.add,kind.remove}) do
                    eq(say(env,observer,command),nil); eq(#observer.chats,0)
                    eq(say(env,nonPlayer,command),nil); eq(#nonPlayer.chats,0)
                    eq(say(env,{valid=false},command),nil)
                    eq(say(env,admin,command .. "Extra"),nil)
                    eq(say(env,admin," " .. command),nil)
                end
                eq(say(env,admin,kind.add .. " "),nil); eq(say(env,admin,kind.add .. " 2"),nil)
                eq(say(env,admin,kind.add:lower()),nil); eq(say(env,admin,"ordinary conversation"),nil)
                output(env,observer,kind.remove .. " " .. kind.first,"")
                contains(indexed(env,admin,kind,kind.first),"inspect a current key")
                output(env,admin,kind.remove .. " ","")
            end)
            inspect(env,admin,kind)
            unchanged(env,ioState,function()
                contains(indexed(env,admin,kind,"0" .. kind.first),"inspect a current key")
                contains(indexed(env,admin,kind,kind.first .. ".0"),"inspect a current key")
                output(env,admin,kind.remove .. " " .. kind.first .. " extra","")
            end)
            contains(indexed(env,admin,kind,kind.first),"successfully removed"); eq(current[kind.field][kind.first],nil)
        end)
    end
end
