-- Exercise actual Initialize/chat handlers with the shared detached codec.
-- Native Garry's Mod Vector JSON, DATA I/O and ChatPrint remain smoke-test work.
return function(gmod, test, eq)
    local newCodec=dofile("tests/spawn-storage-codec.lua")
    local canonical,backup="devonsspawninfo.json","devonsspawninfo.backup.json"
    local kinds={
        {name="enemy", field="enemySpawnPositions", other="activatorSpawnPositions", add="!setEnemySpawn", remove="!removeEnemySpawn"},
        {name="activator", field="activatorSpawnPositions", other="enemySpawnPositions", add="!setActivatorSpawn", remove="!removeActivatorSpawn"},
    }
    local counters={"exists", "reads", "writes", "serializations", "decodes"}
    local function record(env, map, offset)
        offset=offset or 0
        return {map=map or env.map,
            enemySpawnPositions={[2]=env.Vector(offset+2,3,4),[19]=env.Vector(offset+19,20,21)},
            activatorSpawnPositions={[3]=env.Vector(offset+3,4,5),[23]=env.Vector(offset+23,24,25)}}
    end
    local function setup(seed)
        local env=gmod.new()
        local ioState={files={},exists=0,reads=0,writes=0,serializations=0,decodes=0}
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
        env.util.JSONToTable=function(...)
            ioState.decodes=ioState.decodes+1; return codec.decode(...)
        end
        env.util.TableToJSON=function(value)
            ioState.serializations=ioState.serializations+1; return codec.encode(value)
        end
        local source=seed and seed(env) or {[1]=record(env)}
        ioState.files[canonical]=codec.encode(source)
        local defaults=env.SpawnPositions
        env.fire("Initialize")
        assert(not rawequal(env.SpawnPositions,defaults), "fixture must pass the actual loader")
        codec.same(env.SpawnPositions,source)
        eq(ioState.decodes,1); eq(ioState.writes,0); eq(#env.errors,0)
        local admin=env.entity("player"); admin.admin=true
        admin:SetPos(env.Vector(90,80,70))
        return env,admin,ioState,codec
    end
    -- Save both contents and every original table identity without invoking JSON.
    local function snapshot(value)
        if type(value) ~= "table" then return {value=value} end
        local saved={value=value,children={}}
        for key,child in pairs(value) do saved.children[key]=snapshot(child) end
        return saved
    end
    local function sameSnapshot(actual,saved)
        if saved.children then
            assert(rawequal(actual,saved.value), "refusal preserves every table identity")
            for key,child in pairs(saved.children) do sameSnapshot(actual[key],child) end
            for key in pairs(actual) do assert(saved.children[key], "refusal must not add a key") end
        elseif type(saved.value) == "number" and saved.value ~= saved.value then
            assert(actual ~= actual, "preserve NaN without repairing it")
        else eq(actual,saved.value,"refusal preserves contents") end
    end
    local function refused(env,admin,ioState,command,reason)
        local before=snapshot(env.SpawnPositions)
        local files=snapshot(ioState.files)
        local counts={}; for _,key in ipairs(counters) do counts[key]=ioState[key] end
        local errors=#env.errors
        admin.chats={}
        local ok,result=pcall(env.fire,"PlayerSay",admin,command)
        assert(ok,"refusal must not throw: " .. tostring(result))
        sameSnapshot(env.SpawnPositions,before)
        sameSnapshot(ioState.files,files)
        for _,key in ipairs(counters) do eq(ioState[key],counts[key],"no refusal " .. key) end
        eq(#env.errors,errors,"refusal does not reach saving")
        eq(result,nil,"original command retains public chat visibility")
        eq(#admin.chats,1,"one private explanation")
        assert(admin.chats[1]:lower():find(reason,1,true),"explain " .. reason)
        assert(not admin.chats[1]:lower():find("success",1,true),"no false success")
        assert(#admin.chats[1] <= 255,"bounded private explanation")
    end

    -- First regression: these are distinct valid records accepted by Initialize,
    -- not a malformed JSON fixture or two aliases of the same Lua record.
    for _,kind in ipairs(kinds) do
        for _,command in ipairs({kind.add,kind.remove}) do
            test("loaded duplicate current-map records refuse original command " .. command,function()
                local env,admin,ioState=setup(function(e)
                    return {[2]=record(e,nil,0),[8]=record(e,nil,100)}
                end)
                local first,second=env.SpawnPositions[2],env.SpawnPositions[8]
                assert(not rawequal(first,second)); assert(not rawequal(first[kind.field],second[kind.field]))
                refused(env,admin,ioState,command,"ambiguous")
            end)
        end
    end

    local malformed={
        {"missing root",function(e) e.SpawnPositions=nil end,"malformed"},
        {"false root",function(e) e.SpawnPositions=false end,"malformed"},
        {"string root",function(e) e.SpawnPositions="invalid" end,"malformed"},
        {"number root",function(e) e.SpawnPositions=17 end,"malformed"},
        {"false record",function(e) e.SpawnPositions[7]=false end,"malformed"},
        {"string record",function(e) e.SpawnPositions[7]="invalid" end,"malformed"},
        {"missing map identity",function(e) e.SpawnPositions[7]={} end,"malformed"},
        {"false map identity",function(e) e.SpawnPositions[7]={map=false} end,"malformed"},
        {"number map identity",function(e) e.SpawnPositions[7]={map=17} end,"malformed"},
        {"empty map identity",function(e) e.SpawnPositions[7]={map=""} end,"malformed"},
        {"missing target list",function(e,k) e.SpawnPositions[1][k.field]=nil end,"missing"},
        {"false target list",function(e,k) e.SpawnPositions[1][k.field]=false end,"malformed"},
        {"string target list",function(e,k) e.SpawnPositions[1][k.field]="invalid" end,"malformed"},
        {"number target list",function(e,k) e.SpawnPositions[1][k.field]=17 end,"malformed"},
        {"plain coordinate table",function(e,k) e.SpawnPositions[1][k.field][31]={x=1,y=2,z=3} end,"malformed"},
        {"false point",function(e,k) e.SpawnPositions[1][k.field][31]=false end,"malformed"},
        {"string point",function(e,k) e.SpawnPositions[1][k.field][31]="invalid" end,"malformed"},
        {"infinite coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(math.huge,2,3) end,"malformed"},
        {"negative infinite coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(1,-math.huge,3) end,"malformed"},
        {"NaN coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(1,2,0/0) end,"malformed"},
        {"missing coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector(1,nil,3) end,"malformed"},
        {"string coordinate",function(e,k) e.SpawnPositions[1][k.field][31]=e.Vector("1",2,3) end,"malformed"},
    }
    for _,key in ipairs({"bad",false,0,-1,2.5,math.huge,-math.huge}) do
        local invalidKey=key
        malformed[#malformed+1]={"map key " .. tostring(key),function(e)
            e.SpawnPositions[invalidKey]=record(e,"gm_other")
        end,"malformed"}
        malformed[#malformed+1]={"point key " .. tostring(key),function(e,k)
            e.SpawnPositions[1][k.field][invalidKey]=e.Vector(1,2,3)
        end,"malformed"}
    end
    for _,kind in ipairs(kinds) do
        for _,command in ipairs({kind.add,kind.remove}) do
            for _,case in ipairs(malformed) do
                test(command .. " refuses " .. case[1] .. " before mutation or saving",function()
                    local env,admin,ioState=setup()
                    case[2](env,kind)
                    refused(env,admin,ioState,command,case[3])
                end)
            end
        end

        for _,shape in ipairs({"empty map table","other map only","empty target list"}) do
            test("bare " .. kind.name .. " removal is a no-op for " .. shape,function()
                local env,admin,ioState=setup(function(e)
                    if shape == "empty map table" then return {} end
                    if shape == "other map only" then return {[7]=record(e,"gm_other")} end
                    local current=record(e); current[kind.field]={}; return {[1]=current}
                end)
                refused(env,admin,ioState,kind.remove,"no more")
            end)
            test("original " .. kind.name .. " repeated additions preserve " .. shape,function()
                local env,admin,ioState,codec=setup(function(e)
                    if shape == "empty map table" then return {} end
                    if shape == "other map only" then return {[7]=record(e,"gm_other")} end
                    local current=record(e); current[kind.field]={}; return {[1]=current}
                end)
                local root=env.SpawnPositions
                local otherMap=root[7] and snapshot(root[7])
                local information,positions
                for i=1,3 do
                    local predecessor=ioState.files[canonical]
                    local writes,serializations=ioState.writes,ioState.serializations
                    eq(env.fire("PlayerSay",admin,kind.add),nil,"legacy accepted addition visibility")
                    eq(env.SpawnPositions,root)
                    local matches=0
                    for _,entry in pairs(root) do
                        if entry.map == env.map then matches=matches+1; information=entry end
                    end
                    eq(matches,1,"create the current map once")
                    assert(type(information[kind.other]) == "table","new maps have both lists")
                    if positions then eq(information[kind.field],positions) end
                    positions=information[kind.field]
                    eq(positions[i],admin:GetPos())
                    local count=0; for _ in pairs(positions) do count=count+1 end
                    eq(count,i,"append once per command without prior inspection")
                    eq(ioState.serializations,serializations+1)
                    eq(ioState.writes,writes+2,"one backup and one canonical save")
                    eq(ioState.files[backup],predecessor)
                    codec.same(codec.decode(ioState.files[canonical]),root)
                    if otherMap then sameSnapshot(root[7],otherMap) end
                end
                eq(#env.errors,0)
            end)
        end

        for _,command in ipairs({kind.add,kind.remove}) do
            test(command .. " changes only its sparse target without an inspection",function()
                local env,admin,ioState,codec=setup(function(e)
                    return {[2]=record(e),[8]=record(e,"gm_other",100)}
                end)
                local root=env.SpawnPositions
                local current,other=root[2],snapshot(root[8])
                local opposite=snapshot(current[kind.other])
                local positions=current[kind.field]
                local maximum=kind.name == "enemy" and 19 or 23
                local expected=codec.copy(positions)
                if command == kind.add then expected[maximum+1]=admin:GetPos() else expected[maximum]=nil end
                local predecessor=ioState.files[canonical]
                eq(env.fire("PlayerSay",admin,command),nil)
                eq(env.SpawnPositions,root); eq(root[2],current); eq(current[kind.field],positions)
                codec.same(positions,expected); sameSnapshot(current[kind.other],opposite); sameSnapshot(root[8],other)
                eq(ioState.serializations,1); eq(ioState.writes,2)
                eq(ioState.files[backup],predecessor)
                codec.same(codec.decode(ioState.files[canonical]),root)
                eq(#env.errors,0)
            end)
        end

        for _,literal in ipairs({"9007199254740992","9223372036854775807","1e100","1.7976931348623157e308"}) do
            test("original " .. kind.name .. " append respects exact successor boundary " .. literal,function()
                local maximum=tonumber(literal)
                local env,admin,ioState,codec=setup(function(e)
                    local current=record(e)
                    current[kind.field]={[2]=e.Vector(1,2,3),[maximum]=e.Vector(4,5,6)}
                    return {[1]=current}
                end)
                local positions=env.SpawnPositions[1][kind.field]
                local before=snapshot(env.SpawnPositions)
                local nextKey=maximum+1
                local result=env.fire("PlayerSay",admin,kind.add)
                if nextKey > maximum and nextKey < math.huge then
                    eq(result,nil); eq(positions[nextKey],admin:GetPos()); eq(ioState.serializations,1); eq(ioState.writes,2)
                else
                    sameSnapshot(env.SpawnPositions,before)
                    eq(result,""); eq(ioState.serializations,0); eq(ioState.writes,0)
                    assert(admin.chats[#admin.chats]:find("exact free key",1,true))
                end
                -- Removing a huge valid key remains supported on every runtime.
                local previous=positions[2]
                eq(env.fire("PlayerSay",admin,kind.remove),nil)
                eq(positions[nextKey > maximum and nextKey < math.huge and nextKey or maximum],nil)
                eq(positions[2],previous)
                codec.same(codec.decode(ioState.files[canonical]),env.SpawnPositions)
            end)
        end

        for _,location in ipairs({"other kind","other map","duplicate other maps"}) do
            for _,command in ipairs({kind.add,kind.remove}) do
                test(command .. " accepts its target despite invalid positions in " .. location,function()
                    local env,admin,ioState=setup()
                    if location == "other kind" then env.SpawnPositions[1][kind.other]=false
                    else
                        env.SpawnPositions[7]=record(env,"gm_other")
                        env.SpawnPositions[7].enemySpawnPositions=false
                        if location == "duplicate other maps" then env.SpawnPositions[8]=record(env,"gm_other",100) end
                    end
                    local positions=env.SpawnPositions[1][kind.field]
                    local maximum=kind.name == "enemy" and 19 or 23
                    local reads,decodes,exists=ioState.reads,ioState.decodes,ioState.exists
                    local files=snapshot(ioState.files)
                    eq(env.fire("PlayerSay",admin,command),nil)
                    if command == kind.add then eq(positions[maximum+1],admin:GetPos()) else eq(positions[maximum],nil) end
                    eq(ioState.serializations,0); eq(ioState.writes,0)
                    eq(ioState.reads,reads); eq(ioState.decodes,decodes); eq(ioState.exists,exists)
                    sameSnapshot(ioState.files,files)
                    eq(#env.errors,1,"unchanged save validator refuses unrelated invalid positions")
                    assert(admin.chats[#admin.chats]:find("remains in memory",1,true),"acknowledge accepted session-only edit")
                end)
            end
        end
    end
end
