-- Shared test-only fixtures for runtime lookup, timer and actual Start regressions.
-- The detached codec models accepted storage, not native Garry's Mod JSON.
return function(gmod, eq)
    local H={}
    local newCodec=dofile("tests/spawn-storage-codec.lua")
    local canonical,backup="devonsspawninfo.json","devonsspawninfo.backup.json"
    local counters={"exists","reads","writes","encodes","decodes"}
    H.kinds={
        {name="activator",field="activatorSpawnPositions",other="enemySpawnPositions",lookup="returnActivatorSpawns"},
        {name="enemy",field="enemySpawnPositions",other="activatorSpawnPositions",lookup="returnSpawnPositions"},
    }
    function H.record(env, map, offset)
        offset=offset or 0
        return {map=map or env.map,
            activatorSpawnPositions={[3]=env.Vector(offset+3,4,5),[23]=env.Vector(offset+23,24,25)},
            enemySpawnPositions={[2]=env.Vector(offset+2,3,4),[19]=env.Vector(offset+19,20,21)}}
    end
    function H.setup(seed)
        local env=gmod.new()
        local ioState={files={},exists=0,reads=0,writes=0,encodes=0,decodes=0}
        local codec=newCodec(env,eq)
        env.print=function() end
        env.file.Exists=function(path,realm)
            eq(realm,"DATA"); ioState.exists=ioState.exists+1; return ioState.files[path] ~= nil
        end
        env.file.Read=function(path,realm)
            eq(realm,"DATA"); ioState.reads=ioState.reads+1; return ioState.files[path]
        end
        env.file.Write=function(path,bytes)
            assert(path == canonical or path == backup)
            ioState.writes=ioState.writes+1; ioState.files[path]=bytes; return true
        end
        env.util.TableToJSON=function(value)
            ioState.encodes=ioState.encodes+1; return codec.encode(value)
        end
        env.util.JSONToTable=function(...)
            ioState.decodes=ioState.decodes+1; return codec.decode(...)
        end
        local source=seed and seed(env) or {[1]=H.record(env)}
        ioState.files[canonical]=codec.encode(source)
        ioState.files[backup]=codec.encode({[1]=H.record(env,"backup_map",900)})
        local defaults=env.SpawnPositions
        env.fire("Initialize")
        assert(not rawequal(env.SpawnPositions,defaults),"fixture passes actual Initialize")
        codec.same(env.SpawnPositions,source)
        eq(ioState.decodes,1); eq(ioState.writes,0); eq(#env.errors,0)
        return env,ioState,codec
    end
    -- Preserve identities and all contents, including NaN, without serializing.
    function H.snapshot(value)
        local saved={value=value}
        if type(value) == "table" then
            saved.children={}
            for key,child in pairs(value) do saved.children[key]=H.snapshot(child) end
        end
        return saved
    end
    function H.same(actual,saved)
        if saved.children then
            assert(rawequal(actual,saved.value),"runtime preserves every input table identity")
            for key,child in pairs(saved.children) do H.same(actual[key],child) end
            for key in pairs(actual) do assert(saved.children[key],"runtime does not add input keys") end
        elseif type(saved.value) == "number" and saved.value ~= saved.value then
            assert(type(actual) == "number" and actual ~= actual,"runtime leaves NaN untouched")
        else eq(actual,saved.value,"runtime leaves input contents untouched") end
    end
    function H.dataState(env,ioState)
        local saved={positions=H.snapshot(env.SpawnPositions),files=H.snapshot(ioState.files),counts={}}
        for _,key in ipairs(counters) do saved.counts[key]=ioState[key] end
        return saved
    end
    function H.sameData(env,ioState,saved)
        H.same(env.SpawnPositions,saved.positions); H.same(ioState.files,saved.files)
        for _,key in ipairs(counters) do eq(ioState[key],saved.counts[key],"runtime performs no storage " .. key) end
    end
    function H.watch(env, choices)
        local observed={draws={},creates={},placements={}}
        env.math=setmetatable({}, {__index=math})
        env.math.random=function(first,last)
            observed.draws[#observed.draws+1]={first,last}
            local choice=choices and choices[#observed.draws] or first
            assert(choice and choice >= first and choice <= last,"test RNG choice is in range")
            return choice
        end
        local create=env.ents.Create
        env.ents.Create=function(class)
            observed.creates[#observed.creates+1]=class
            local ent=create(class)
            if env.IsValid(ent) then
                local setPos=ent.SetPos
                ent.SetPos=function(self,position)
                    observed.placements[#observed.placements+1]={entity=self,position=position}
                    return setPos(self,position)
                end
            end
            return ent
        end
        return observed
    end
    function H.call(label, callback)
        local ok,result=pcall(callback)
        assert(ok,label .. " must not throw: " .. tostring(result))
        return result
    end
    function H.status(env,admin)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,"!eventStatus"),"")
        local lines={}
        for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        return table.concat(lines,"\n")
    end
    function H.contains(text,expected)
        assert(text:find(expected,1,true),"expected '" .. expected .. "' in '" .. text .. "'")
    end
    function H.addAmbush(env)
        env.NPCEdits[7]={name="Ambush",information={activatorModel="models/alyx.mdl",
            npcPath="npc_combine_s",maxNPCs=2,dialogue="An ambush awaits."}}
    end
    function H.queue(env,admin,name)
        eq(env.fire("PlayerSay",admin,"!nextEvent " .. name),"")
    end
    function H.open(server,client,ply,actor)
        local first=#client.panels+1
        actor:AcceptInput("Use",ply,ply)
        local message=server.messages[#server.messages]
        eq(message.name,"OpenInteractionMenu"); eq(message.player,ply)
        client.deliver(message)
        local frame,button
        for i=first,#client.panels do
            local panel=client.panels[i]
            if panel.class == "DFrame" then frame=panel
            elseif panel.class == "DButton" and panel.text:find("Start",1,true) then button=panel end
        end
        return assert(frame),assert(button)
    end
    function H.click(server,client,ply,frame,button)
        local messages,cancels=#client.messages,client.messageCount("CloseInteractionMenu")
        button:DoClick()
        eq(frame.valid,false); eq(#client.messages,messages+1)
        eq(client.messageCount("CloseInteractionMenu"),cancels)
        local request=client.messages[#client.messages]
        eq(request.name,"SendNPCInformation")
        H.call("actual Start",function() server.deliver(request,ply) end)
        return request
    end
    H.invalid={
        {"missing root",function(e) e.SpawnPositions=nil end,"malformed map data"},
        {"false root",function(e) e.SpawnPositions=false end,"malformed map data"},
        {"string root",function(e) e.SpawnPositions="invalid" end,"malformed map data"},
        {"number root",function(e) e.SpawnPositions=17 end,"malformed map data"},
        {"false record",function(e) e.SpawnPositions[7]=false end,"malformed map data"},
        {"string record",function(e) e.SpawnPositions[7]="invalid" end,"malformed map data"},
        {"missing map identity",function(e) e.SpawnPositions[7]={} end,"malformed map data"},
        {"empty map identity",function(e) e.SpawnPositions[7]={map=""} end,"malformed map data"},
        {"number map identity",function(e) e.SpawnPositions[7]={map=17} end,"malformed map data"},
        {"duplicate current map",function(e) e.SpawnPositions[7]=H.record(e,nil,100) end,"ambiguous map records (2)"},
        {"empty root",function(e) e.SpawnPositions={} end,"missing map record"},
        {"absent current map",function(e) e.SpawnPositions[1].map="other_map" end,"missing map record"},
        {"missing target list",function(e,k) e.SpawnPositions[1][k.field]=nil end,"missing list"},
        {"empty target list",function(e,k) e.SpawnPositions[1][k.field]={} end,"empty list"},
        {"false target list",function(e,k) e.SpawnPositions[1][k.field]=false end},
        {"string target list",function(e,k) e.SpawnPositions[1][k.field]="invalid" end},
        {"number target list",function(e,k) e.SpawnPositions[1][k.field]=17 end},
        {"truthy non-Vector point",function(e,k) e.SpawnPositions[1][k.field]={[31]="invalid"} end},
        {"plain coordinates",function(e,k) e.SpawnPositions[1][k.field]={[31]={x=1,y=2,z=3}} end},
        {"mixed valid and false points",function(e,k) e.SpawnPositions[1][k.field][31]=false end},
        {"mixed valid and truthy points",function(e,k) e.SpawnPositions[1][k.field][31]="invalid" end},
        {"infinite coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(math.huge,2,3) end},
        {"negative infinite coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(1,-math.huge,3) end},
        {"NaN coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(1,2,0/0) end},
        {"missing coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(1,nil,3) end},
        {"string coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector("1",2,3) end},
    }
    for _,key in ipairs({"extra",0,-2,1.5,math.huge}) do
        local badKey=key
        H.invalid[#H.invalid+1]={"map key " .. tostring(key),function(e)
            e.SpawnPositions={[badKey]=e.SpawnPositions[1]}
        end,"malformed map data"}
        H.invalid[#H.invalid+1]={"position key " .. tostring(key),function(e,k)
            e.SpawnPositions[1][k.field]={[badKey]=e.Vector(1,2,3)}
        end}
    end
    return H
end
