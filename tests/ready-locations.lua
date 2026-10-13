-- Finite production-hook coverage. Native GMod
-- Vector precision, chat delivery, actor placement and timing remain unverified.
return function(gmod, test, eq)
    local upvalue = dofile("tests/find-upvalue.lua")
    local command = "!nearActivators"
    local function contains(text, wanted)
        assert(text:find(wanted, 1, true), "missing " .. wanted .. " in " .. text)
    end
    local function state(env, name)
        for _, hooks in pairs(env.hooks) do
            for _, callback in pairs(hooks) do
                local ok, value = pcall(upvalue, callback, name)
                if ok then return value end
            end
        end
        for _, callback in pairs(env.receivers) do
            local ok, value = pcall(upvalue, callback, name)
            if ok then return value end
        end
        for _, timer in pairs(env.timers) do
            local ok, value = pcall(upvalue, timer.callback, name)
            if ok then return value end
        end
        error("missing observed state " .. name)
    end
    local function actor(env, index, x, y, z)
        local ent = env.entity("activatorent")
        ent.EventIdentifier = "Raid"; ent:Spawn()
        ent.index = index; ent.pos = env.Vector(x or 0, y or 0, z or 0)
        return ent
    end
    local function setup(count)
        local env = gmod.new(); local admin = env.entity("player"); admin.admin = true
        local actors = {}
        for i = 1, count == nil and 3 or count do actors[i] = actor(env, 100+i, i, 0, 0) end
        return env, admin, actors
    end
    local function say(env, admin, text)
        local before = admin and #admin.chats or 0
        local result = env.fire("PlayerSay", admin, text or command)
        local lines = {}
        if admin then
            for i = before+1, #admin.chats do
                local line = admin.chats[i]
                assert(#line <= 255 and not line:find("%c"), "bounded private chat")
                lines[#lines+1] = line
            end
        end
        return result, lines, table.concat(lines, "\n")
    end
    local function near(env, admin, page)
        local result, lines, text = say(env, admin, command .. (page and " " .. page or ""))
        eq(result, "", "recognized ready-location request stays private")
        if admin then eq(state(env, "readyActivatorRequests")[admin], nil, "finished request retired") end
        return lines, text
    end
    local function rows(lines)
        local found = {}
        for _, line in ipairs(lines) do
            if line:match("^Entity index ") or line:match("^Unindexed:") then found[#found+1] = line end
        end
        return found
    end
    local function order(lines, expected)
        local body = rows(lines); eq(#body, #expected)
        for i, index in ipairs(expected) do
            eq(tonumber(body[i]:match("^Entity index (%S+):")) or 0, index, "ready row " .. i)
        end
    end
    local function once(object, key, callback)
        local original = object[key]; local entered = false
        object[key] = function(...)
            object[key] = original; entered = true
            callback()
            return original(...)
        end
        return function() assert(entered, "controlled " .. key .. " callback exercised") end
    end
    local function noRows(lines) eq(#rows(lines), 0, "no obsolete or refused rows") end
    local function snapshot(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}; if seen[value] then return seen[value] end
        local copy = {original=value, entries={}}; seen[value] = copy
        for key, child in pairs(value) do
            if key ~= "chats" then copy.entries[key] = snapshot(child, seen) end
        end
        return copy
    end
    local function unchanged(before, value, seen)
        if type(before) ~= "table" then eq(value, before, "unchanged value"); return end
        eq(value, before.original, "unchanged table identity")
        seen = seen or {}; if seen[before] then return end; seen[before] = true
        local oldCount, newCount = 0, 0
        for key, child in pairs(before.entries) do oldCount=oldCount+1; unchanged(child, value[key], seen) end
        for key in pairs(value) do if key ~= "chats" then newCount=newCount+1 end end
        eq(newCount, oldCount, "unchanged table entries")
    end

    test("ready locations exact routing yields before shared player getters", function()
        local env, admin = setup(); local shared = assert(env.hooks.PlayerSay.setUpSpawnPoints)
        admin.IsPlayer = function() error("shared route must yield before admission") end
        eq(shared(admin, command), nil); eq(shared(admin, command .. " 2"), nil)
        admin.IsPlayer = function() return true end
        for _, text in ipairs({"!nearActivatorsMore", "!nearactivators", "!NearActivators", " " .. command,
            "hello " .. command, "ordinary conversation"}) do
            eq(env.fire("PlayerSay", admin, text), nil)
        end
        eq(#admin.chats, 0)
        local lines, text = near(env, admin)
        eq(lines[1], "Nearest ready activators, page 1/1: listed 3; omitted invalid/deleting 0.")
        contains(text, "3D Source units"); contains(text, "unknown distances last")
        contains(text, "fresh snapshot"); contains(text, "pages can move")
        local _, again = near(env, admin, "01"); eq(again, text)
        assert(not text:find("!removeEventEnemy", 1, true), "ready rows grant no encounter removal")
        assert(not text:find("!mark", 1, true), "ready rows grant no marker")
    end)
    for _, page in ipairs({"0", "-1", "+1", "1.0", "1e1", "two", "1 2", "2 extra", string.rep("9", 400)}) do
        test("ready locations malformed page " .. page:sub(1, 20), function()
            local env, admin = setup(); local scans = 0
            env.ents.FindByClass = function() scans=scans+1; error("malformed page scanned") end
            local lines, text = near(env, admin, page)
            eq(#lines, 1); eq(text, "Usage: !nearActivators [page]; page must be a positive integer.")
            eq(scans, 0)
        end)
    end
    test("ready locations out of range and empty scans keep one finite page", function()
        local env, admin = setup(0)
        local lines, text = near(env, admin); noRows(lines)
        eq(lines[1], "Nearest ready activators, page 1/1: listed 0; omitted invalid/deleting 0.")
        lines, text = near(env, admin, 2); eq(#lines, 1)
        eq(text, "Usage: !nearActivators [page]; page must be a positive integer in 1-1.")
    end)
    test("ready locations scan current manual automatic and moved actors without configuration filters", function()
        local env, admin = setup(0); env.fireTimer("activatorSpawner")
        local automatic = env.ents.FindByClass("activatorent"); eq(#automatic, 3)
        for i, ent in ipairs(automatic) do ent.index=100+i; ent.pos=env.Vector(i*10, 0, 0) end
        local manual = actor(env, 104, -1, 0, 0)
        local bare = env.entity("activatorent"); bare.index=105; bare.pos=env.Vector(2, 0, 0)
        bare.NPCInfo=false; bare.EventIdentifier="no configured event"
        automatic[1]:SetPos(env.Vector(3, 4, 0))
        local stranger = env.entity("npc_citizen"); stranger.index=999
        env.activatorCount=987; env.maxActivators=0; env.minNumberOfPlayers=999
        env.NPCEdits=false; env.SpawnPositions=false
        local scan = env.ents.FindByClass; local scans=0
        env.ents.FindByClass=function(class) eq(class, "activatorent"); scans=scans+1; return scan(class) end
        local lines = near(env, admin); order(lines, {104,105,101,102,103}); eq(scans, 1)
        eq(rows(lines)[3], "Entity index 101: approx rounded world position (3, 4, 0); ~5 units away.")
        eq(manual.valid, true); eq(stranger.valid, true); eq(env.activatorCount, 987)
    end)
    test("ready locations paginate nineteen fresh rows for independent admin origins", function()
        local env, admin, actors = setup(19); local other=env.entity("player"); other.admin=true
        other.pos=env.Vector(20, 0, 0); local all={}
        for page=1,3 do
            local lines = near(env, admin, page); local body=rows(lines)
            eq(#body, page==3 and 3 or 8)
            eq(lines[1], "Nearest ready activators, page " .. page .. "/3: listed 19; omitted invalid/deleting 0.")
            for _, line in ipairs(body) do all[#all+1]=tonumber(line:match("^Entity index (%S+):")) end
        end
        for i=1,19 do eq(all[i], 100+i) end
        order(near(env, other), {119,118,117,116,115,114,113,112})
        actors[19].pos=env.Vector(0, 0, 0); order(near(env, admin), {119,101,102,103,104,105,106,107})
        eq(next(state(env, "readyActivatorRequests")), nil)
    end)
    test("ready locations use unrounded three dimensional geometry before rounded output", function()
        local env, admin, actors=setup(8)
        local points={{0,0,0},{0.49,0,0},{0.41,0,0},{0,0,-2},{-2,0,0},{0,3,0},{9,0,0},{4,0,0}}
        for i,p in ipairs(points) do actors[i].pos=env.Vector(p[1],p[2],p[3]) end
        actors[7].GetPos=function() return nil end
        local lines=near(env,admin); order(lines,{101,103,102,104,105,106,108,107})
        eq(rows(lines)[2],"Entity index 103: approx rounded world position (0, 0, 0); ~0.41 units away.")
        contains(rows(lines)[4],"(0, 0, -2); ~2 units away.")
        contains(rows(lines)[8],"world position unavailable; distance unavailable.")
    end)
    test("ready locations retain index then text ties and unindexed unknown rows", function()
        local env, admin, actors=setup(7)
        actors[1].index=0; actors[1].pos=env.Vector(-1,0,0)
        actors[2].EntIndex=function() error("private index failure") end; actors[2].pos=env.Vector(1,0,0)
        actors[3].index=9; actors[3].pos=env.Vector(1,0,0)
        actors[4].index=4; actors[4].GetPos=function() return nil end
        actors[5].index=2; actors[5].GetPos=function() return nil end
        actors[6].index=9; actors[6].pos=env.Vector(-1,0,0)
        actors[7].index=math.huge; actors[7].GetPos=function() return nil end
        local lines=near(env,admin); order(lines,{9,9,0,0,2,4,0})
        local body=rows(lines); contains(body[1],"(-1, 0, 0)"); contains(body[2],"(1, 0, 0)")
        eq(body[3],"Unindexed: index unavailable; approx rounded world position (-1, 0, 0); ~1 units away.")
        eq(body[7],"Unindexed: index unavailable; world position unavailable; distance unavailable.")
    end)
    test("ready locations capture every scalar once including off-page rows and omit unusable actors", function()
        local env, admin, actors=setup(11); actors[10].valid=false; actors[11].markedForDeletion=true
        env.ents.FindByClass=function(class) eq(class,"activatorent"); return actors end
        local calls, components={},{}; local native=env.isvector
        env.isvector=function(p) return native(p) or type(p)=="table" and p.native==true end
        local function point(key,x,y,z)
            components[key]={x=0,y=0,z=0}; local values={x=x,y=y,z=z}
            return setmetatable({native=true},{__index=function(_,axis)
                components[key][axis]=components[key][axis]+1; return values[axis]
            end})
        end
        admin.GetPos=function() calls.origin=(calls.origin or 0)+1; return point("origin",0,0,0) end
        for i,ent in ipairs(actors) do
            ent.GetPos=function()
                calls[i]=(calls[i] or 0)+1; return point(i,i,0,0)
            end
            ent.EntIndex=function(self)
                local key="index "..i; calls[key]=(calls[key] or 0)+1; return self.index
            end
        end
        env.Vector=function() error("listing allocated a vector") end
        env.Entity=function() error("listing resolved a temporary index") end
        local sort=table.sort; local comparisons=0
        env.table.sort=function(list,less)
            return sort(list,function(a,b)
                comparisons=comparisons+1; local before=0
                for _,n in pairs(calls) do before=before+n end
                local value=less(a,b); local after=0
                for _,n in pairs(calls) do after=after+n end
                eq(after,before,"sort reads only detached fields"); return value
            end)
        end
        local lines=near(env,admin); eq(#rows(lines),8); contains(lines[1],"listed 9; omitted invalid/deleting 2")
        eq(calls.origin,1); assert(comparisons>0)
        for i=1,9 do
            eq(calls[i],1); eq(calls["index "..i],1)
            for _,axis in ipairs({"x","y","z"}) do eq(components[i][axis],1) end
        end
        eq(calls[10],nil); eq(calls[11],nil); eq(calls["index 10"],nil); eq(calls["index 11"],nil)
        for _,axis in ipairs({"x","y","z"}) do eq(components.origin[axis],1) end
    end)
    test("ready locations detach origin and actor coordinates before later vector mutation", function()
        local env, admin, actors=setup(); local origin=admin.pos; local captured={}
        for _,ent in ipairs(actors) do ent.GetPos=function(self)
            origin.x=999
            for _,p in ipairs(captured) do p.x=999 end
            captured[#captured+1]=self.pos; return self.pos
        end end
        local lines=near(env,admin); order(lines,{101,102,103})
        for i,line in ipairs(rows(lines)) do contains(line,"("..i..", 0, 0); ~"..i.." units away.") end
    end)

    local positionFailures={
        {"missing method",function(_,ent) ent.GetPos=false end},
        {"throwing method",function(_,ent) ent.GetPos=function() error("PRIVATE position failure") end end},
        {"nil position",function(_,ent) ent.GetPos=function() return nil end end},
        {"plain coordinates",function(_,ent) ent.pos={x=1,y=2,z=3} end},
        {"throwing scalar",function(env,ent)
            local native=env.isvector
            env.isvector=function(p) return native(p) or type(p)=="table" and p.native==true end
            ent.pos=setmetatable({native=true},{__index=function() error("PRIVATE scalar failure") end})
        end},
        {"NaN x",function(env,ent) ent.pos=env.Vector(0/0,2,3) end},
        {"positive infinite y",function(env,ent) ent.pos=env.Vector(1,math.huge,3) end},
        {"negative infinite z",function(env,ent) ent.pos=env.Vector(1,2,-math.huge) end},
        {"missing z",function(env,ent) ent.pos=env.Vector(1,2,nil) end},
    }
    for _,case in ipairs(positionFailures) do
        test("ready locations reject origin "..case[1].." before scanning",function()
            local env,admin=setup(); local scans=0
            env.ents.FindByClass=function() scans=scans+1; error("unavailable origin scanned actors") end
            case[2](env,admin); local lines,text=near(env,admin)
            eq(#lines,1); contains(text,"current world position is unavailable"); eq(scans,0)
            assert(not text:find("PRIVATE",1,true),"native exception text remains private")
        end)
        test("ready locations retain unknown actor row for "..case[1],function()
            local env,admin,actors=setup(2); case[2](env,actors[1])
            local lines,text=near(env,admin); order(lines,{102,101})
            contains(lines[1],"listed 2; omitted invalid/deleting 0")
            eq(rows(lines)[2],"Entity index 101: world position unavailable; distance unavailable.")
            assert(not text:find("PRIVATE",1,true))
        end)
    end
    local arithmetic={
        {"triangle",{3,4,12},13},
        {"tiny triangle",{3e-200,4e-200,12e-200},13e-200},
        {"large triangle",{3e200,4e200,12e200},13e200},
        {"norm overflow",{1.7e308,1.7e308,0},false},
        {"subtraction overflow",{1.7e308,0,0},false,{-1.7e308,0,0}},
    }
    for _,case in ipairs(arithmetic) do
        test("ready locations bounded arithmetic "..case[1],function()
            local env,admin,actors=setup(2); local p=case[2]
            actors[1].pos=env.Vector(p[1],p[2],p[3]); actors[2].pos=env.Vector(0,0,0)
            if case[4] then local o=case[4]; admin.pos=env.Vector(o[1],o[2],o[3]); actors[2].pos=env.Vector(o[1],o[2],o[3]) end
            local lines=near(env,admin); order(lines,{102,101})
            local row=rows(lines)[2]; contains(row,"approx rounded world position")
            if case[3] then contains(row,"; ~"..string.format("%.6g",case[3]).." units away.")
            else contains(row,"; distance unavailable.") end
        end)
    end
    for _,role in ipairs({"nil","invalid","nonplayer","nonadmin","dead","throwing IsPlayer","throwing IsAdmin","throwing Alive"}) do
        test("ready locations private caller guard "..role,function()
            local env,admin=setup(); local requester=admin; local reads=0
            admin.GetPos=function() reads=reads+1; error("forbidden origin") end
            env.ents.FindByClass=function() reads=reads+1; error("forbidden scan") end
            if role=="nil" then requester=nil elseif role=="invalid" then admin.valid=false
            elseif role=="nonplayer" then admin.class="worldspawn" elseif role=="nonadmin" then admin.admin=false
            elseif role=="dead" then admin.alive=false
            else admin[role:match("throwing (.+)")]=function() error("PRIVATE guard failure") end end
            eq(env.fire("PlayerSay",requester,command),""); eq(reads,0)
            eq(state(env,"readyActivatorRequests")[admin],nil)
            for _,line in ipairs(admin.chats) do assert(not line:find("PRIVATE",1,true)); assert(#line<=255) end
        end)
    end
    test("ready locations contain throwing native validity checks",function()
        local env,admin=setup(); env.IsValid=function() error("PRIVATE validity failure") end
        local lines,text=near(env,admin); noRows(lines); assert(not text:find("PRIVATE",1,true))
    end)
    for _,change in ipairs({"demotion","death","invalidation"}) do
        test("ready locations recheck requester after origin "..change,function()
            local env,admin=setup(); local scans=0
            local checked=once(admin,"GetPos",function()
                if change=="demotion" then admin.admin=false elseif change=="death" then admin.alive=false else admin.valid=false end
            end)
            env.ents.FindByClass=function() scans=scans+1; return {} end
            local lines=near(env,admin); checked(); noRows(lines); eq(scans,0)
        end)
    end
    for _,failure in ipairs({"throwing","nil","false","string"}) do
        test("ready locations refuse unavailable scan "..failure,function()
            local env,admin=setup()
            env.ents.FindByClass=function()
                if failure=="throwing" then error("PRIVATE scan failure") elseif failure=="nil" then return nil
                elseif failure=="false" then return false else return "bad scan" end
            end
            local lines,text=near(env,admin); noRows(lines); eq(#lines,1)
            assert(text:find("unavailable",1,true) or text:find("refused",1,true),"scan failure has a diagnostic")
            assert(not text:find("PRIVATE",1,true))
        end)
    end
    for _,failure in ipairs({"empty","throwing"}) do
        test("ready locations refuse initial map "..failure.." before origin or scan",function()
            local env,admin=setup(); local reads=0
            if failure=="empty" then env.map=""
            else env.game.GetMap=function() error("PRIVATE map failure") end end
            admin.GetPos=function() reads=reads+1; error("unavailable map read origin") end
            env.ents.FindByClass=function() reads=reads+1; error("unavailable map scanned") end
            local lines,text=near(env,admin); eq(#lines,1); eq(reads,0)
            contains(text,"current map is unavailable"); assert(not text:find("PRIVATE",1,true))
        end)
    end
    local mapChanges={
        {"origin changed","origin","GetPos",1,"gm_flatgrass"},
        {"origin unavailable","origin","GetPos",1,""},
        {"actor position changed","actor","GetPos",1,"gm_flatgrass"},
        {"actor position unavailable","actor","GetPos",1,""},
        {"final actor validation changed","actor","IsMarkedForDeletion",2,"gm_flatgrass"},
        {"final actor validation unavailable","actor","IsMarkedForDeletion",2,""},
        {"late requester validation changed","origin","Alive",4,"gm_flatgrass"},
        {"late requester validation unavailable","origin","Alive",4,""},
    }
    for _,case in ipairs(mapChanges) do
        test("ready locations reject map "..case[1],function()
            local env,admin,actors=setup(); local object=case[2]=="actor" and actors[1] or admin
            local key,at=case[3],case[4]; local original=object[key]; local calls,entered=0,false
            object[key]=function(...)
                calls=calls+1
                if calls==at then
                    entered=true; object[key]=original; env.map=case[5]
                end
                return original(...)
            end
            local lines,text=near(env,admin); assert(entered,"targeted map-changing getter reached")
            eq(calls,at,"targeted callback count"); noRows(lines); contains(text,"context changed")
        end)
    end
    for _,failure in ipairs({"missing","throwing"}) do
        test("ready locations contain ordinary deletion getter "..failure,function()
            local env,admin,actors=setup()
            if failure=="missing" then actors[1].IsMarkedForDeletion=false
            else actors[1].IsMarkedForDeletion=function() error("PRIVATE deletion failure") end end
            local lines,text=near(env,admin); noRows(lines); eq(#lines,1)
            assert(not text:find("PRIVATE",1,true))
        end)
    end
    test("ready locations active refusal preserves existing encounter and marker grants",function()
        local env=gmod.new(); local admin,enemies=env.start(); admin.admin=true
        eq(env.fire("PlayerSay",admin,"!listEventEnemies"),"")
        local names={"enemyInspections","enemyMarkerCaptures","enemyMarkerGrants","enemyRemovalRequests","activeEnemies"}
        local saved={}; for _,name in ipairs(names) do saved[name]=snapshot(state(env,name)) end
        local scans,origins=0,0
        local originalScan,originalPos=env.ents.FindByClass,admin.GetPos
        env.ents.FindByClass=function() scans=scans+1; error("active inspection scanned") end
        admin.GetPos=function() origins=origins+1; error("active inspection read origin") end
        local lines,text=near(env,admin); noRows(lines); eq(#lines,1); contains(text,"active")
        eq(scans,0); eq(origins,0)
        for _,name in ipairs(names) do unchanged(saved[name],state(env,name)) end
        env.ents.FindByClass,admin.GetPos=originalScan,originalPos
        local before=env.messageCount("ActivatorSpawnMarker")
        eq(env.fire("PlayerSay",admin,"!markEventEnemy "..enemies[1]:EntIndex()),"")
        eq(env.messageCount("ActivatorSpawnMarker"),before+1,"prior marker remains usable")
    end)
    for _,change in ipairs({"invalidated","deleting"}) do
        test("ready locations reject actor "..change.." by its captured position callback",function()
            local env,admin,actors=setup()
            local checked=once(actors[1],"GetPos",function()
                if change=="invalidated" then actors[1].valid=false else actors[1].markedForDeletion=true end
            end)
            local lines,text=near(env,admin); checked(); noRows(lines); contains(text,"context changed")
        end)
    end
    test("ready locations revalidate earlier captured actor after a later actor getter",function()
        local env,admin,actors=setup()
        local checked=once(actors[2],"GetPos",function() actors[1].markedForDeletion=true end)
        local lines,text=near(env,admin); checked(); noRows(lines); contains(text,"context changed")
    end)
    for _,ending in ipairs({"still active","started then finished"}) do
        test("ready locations reject encounter transition "..ending.." during origin capture",function()
            local env,admin,actors=setup(); actors[1]:AcceptInput("Use",admin,admin)
            -- Keep the same usable actors so rejection requires encounter context,
            -- including a start/finish cycle that ends with eventActive false.
            env.destroyActivators=function() end
            local checked=once(admin,"GetPos",function()
                env.receive("SendNPCInformation",admin,"Raid"); eq(state(env,"eventActive"),true)
                if ending=="started then finished" then eq(env.stopActivatorEvent(),true); eq(state(env,"eventActive"),false) end
            end)
            local lines,text=near(env,admin); checked(); noRows(lines)
            contains(text,"context changed"); eq(actors[1].valid,true)
        end)
    end

    -- One success case per native boundary, not a getter/action cross product.
    local nestedBoundaries={"IsPlayer","IsAdmin","Alive","origin GetPos","FindByClass","GetMap",
        "actor IsMarkedForDeletion","actor EntIndex","actor GetPos"}
    for _,boundary in ipairs(nestedBoundaries) do
        test("ready locations newer page wins "..boundary.." callback",function()
            local env,admin,actors=setup(10)
            local object,key=admin,boundary
            if boundary=="FindByClass" then object,key=env.ents,"FindByClass"
            elseif boundary=="GetMap" then object,key=env.game,"GetMap"
            elseif boundary=="origin GetPos" then key="GetPos"
            elseif boundary:match("^actor ") then object,key=actors[1],boundary:match(" (%S+)$") end
            local checked=once(object,key,function() near(env,admin,2) end)
            local lines,text=near(env,admin); checked(); order(lines,{109,110})
            contains(text,"page 2/2"); assert(not text:find("page 1/2",1,true),"superseded framing suppressed")
        end)
    end
    test("ready locations newer malformed attempt suppresses obsolete origin failure",function()
        local env,admin=setup(); local get=admin.GetPos; local entered=false
        admin.GetPos=function()
            admin.GetPos=get; entered=true; near(env,admin,"nope"); return nil
        end
        local lines,text=near(env,admin); assert(entered); eq(#lines,1)
        eq(text,"Usage: !nearActivators [page]; page must be a positive integer.")
    end)
    test("ready locations another admin request does not supersede the first",function()
        local env,admin,actors=setup(10); local other=env.entity("player"); other.admin=true
        local checked=once(actors[1],"GetPos",function()
            local pending=assert(state(env,"readyActivatorRequests")[admin])
            near(env,other,2); eq(state(env,"readyActivatorRequests")[admin],pending)
        end)
        local lines=near(env,admin); checked(); order(lines,{101,102,103,104,105,106,107,108})
        order(other.chats,{109,110}); eq(next(state(env,"readyActivatorRequests")),nil)
    end)
    for _,event in ipairs({"PlayerDisconnected","Initialize"}) do
        test("ready locations "..event.." retires in-flight request without stale output",function()
            local env,admin,actors=setup()
            local checked=once(actors[1],"GetPos",function()
                assert(state(env,"readyActivatorRequests")[admin],"request claimed before getters")
                env.file.Exists=function() return false end
                env.fire(event,admin); eq(state(env,"readyActivatorRequests")[admin],nil)
            end)
            local lines=near(env,admin); checked(); eq(#lines,0)
            eq(next(state(env,"readyActivatorRequests")),nil)
        end)
    end
    test("ready locations first ChatPrint nested page stops obsolete remaining replies",function()
        local env,admin=setup(10); local print=admin.ChatPrint; local entered=false
        admin.ChatPrint=function(self,line)
            print(self,line)
            if not entered then entered=true; near(env,admin,2) end
        end
        local lines,text=near(env,admin); assert(entered); order(lines,{109,110})
        eq(lines[1],"Nearest ready activators, page 1/2: listed 10; omitted invalid/deleting 0.")
        contains(text,"page 2/2")
        local _,headers=text:gsub("Nearest ready activators, page ",""); eq(headers,2)
        local _,footers=text:gsub("fresh snapshot",""); eq(footers,1,"only newer page finishes replying")
    end)
    for _,change in ipairs({"demotion","death"}) do
        test("ready locations first ChatPrint "..change.." stops remaining replies",function()
            local env,admin=setup(); local print=admin.ChatPrint; local entered=false
            admin.ChatPrint=function(self,line)
                print(self,line)
                if not entered then
                    entered=true
                    if change=="demotion" then self.admin=false else self.alive=false end
                end
            end
            local lines=near(env,admin); assert(entered); eq(#lines,1); noRows(lines)
            eq(lines[1],"Nearest ready activators, page 1/1: listed 3; omitted invalid/deleting 0.")
        end)
        test("ready locations final map callback "..change.." prevents disclosure",function()
            local env,admin=setup(); local get=env.game.GetMap; local calls=0
            env.game.GetMap=function()
                calls=calls+1
                if calls==4 then
                    env.game.GetMap=get
                    if change=="demotion" then admin.admin=false else admin.alive=false end
                end
                return get()
            end
            local lines=near(env,admin)
            eq(calls,4,"exercise final map confirmation after captured-row validation")
            eq(#lines,0)
        end)
    end
    test("ready locations native ChatPrint error cannot retain an in-flight request",function()
        local env,admin=setup(); admin.ChatPrint=function() error("PRIVATE chat failure") end
        local lines,text=near(env,admin); eq(#lines,0); eq(text,"")
        eq(next(state(env,"readyActivatorRequests")),nil)
    end)
    test("ready locations retain only in-flight identity and retire after every completed page",function()
        local env,admin=setup(); local requests=state(env,"readyActivatorRequests"); local observed
        local checked=once(admin,"GetPos",function()
            observed=assert(requests[admin]); eq(type(observed),"table")
        end)
        local lines=near(env,admin); checked(); order(lines,{101,102,103})
        eq(type(observed),"table"); eq(requests[admin],nil)
        near(env,admin); eq(state(env,"readyActivatorRequests"),requests); eq(next(requests),nil)
    end)
    test("ready locations displayed entity index conveys no removal or marker authority",function()
        local env,admin,actors=setup(); local lines=near(env,admin); order(lines,{101,102,103})
        for _,name in ipairs({"enemyInspections","enemyMarkerCaptures","enemyMarkerGrants","spawnInspections","spawnMarkerOperations"}) do
            eq(state(env,name)[admin],nil,"no grant from ready rows: "..name)
        end
        local count=#env.messages
        eq(env.fire("PlayerSay",admin,"!removeEventEnemy 101"),"")
        eq(env.fire("PlayerSay",admin,"!markEventEnemy 101"),"")
        eq(env.fire("PlayerSay",admin,"!markSpawn activator 101"),"")
        eq(#env.messages,count); eq(actors[1].valid,true); eq(actors[1].markedForDeletion,nil)
    end)
    test("ready locations preserve state and trap RNG mutation timer save network and entity actions",function()
        local env,admin=setup(0)
        env.NPCEdits[7]={name="Ambush",information={activatorModel="models/alyx.mdl",npcPath="npc_combine_s",maxNPCs=2,dialogue="Wait."}}
        eq(env.fire("PlayerSay",admin,"!nextEvent Raid"),""); env.fireTimer("activatorSpawner")
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
        eq(env.fire("PlayerSay",admin,"!nextEvent Ambush"),"")
        actors[3].markedForDeletion=true
        admin.pos=actors[1].pos; actors[1]:AcceptInput("Use",admin,admin)
        eq(env.fire("PlayerSay",admin,"!listSpawns activator"),"")
        eq(env.fire("PlayerSay",admin,"!markSpawn activator 1"),"")
        eq(env.fire("PlayerSay",admin,"!listEvents"),"")
        env.receive("RequestActivatorEventStatus",admin)
        local observer=env.entity("player")
        local names={"interactions","pendingSelection","selectedBatchName","selectedBatchEntities","activeEnemies",
            "constructingEnemies","eventActive","eventInterrupted","activeEventName","initialEnemies","statusRequestAfter",
            "automaticSpawnsPaused","spawnScheduleGeneration","spawnAttemptDepth","enemyInspections","enemyHealthRequests",
            "enemyRemovalRequests","enemyMarkerCaptures","enemyMarkerGrants","catalogInspections","catalogRequests",
            "detailRequests","spawnInspections","spawnMarkerOperations","spawnCatalogueRequests"}
        local saved={}; for _,name in ipairs(names) do saved[name]={snapshot(state(env,name))} end
        local public={env.NPCEdits,env.SpawnPositions,env.entities,env.timers,env.messages}
        local snapshots={}; for i,value in ipairs(public) do snapshots[i]=snapshot(value) end
        local count,total=env.activatorCount,env.totalEnemies; local attempts,originals={},{}
        local function trap(object,key)
            originals[#originals+1]={object,key,rawget(object,key)}
            object[key]=function() attempts[#attempts+1]=key; error("forbidden "..key) end
        end
        env.math=setmetatable({},{__index=math})
        for _,key in ipairs({"random","randomseed"}) do trap(env.math,key) end
        for _,key in ipairs({"Create","Start","Stop","Simple","Adjust","Remove"}) do trap(env.timer,key) end
        for _,key in ipairs({"Read","Write","Append","Delete","Exists","CreateDir"}) do trap(env.file,key) end
        for _,key in ipairs({"Create","FindByName"}) do trap(env.ents,key) end
        for _,key in ipairs({"Start","Send","Broadcast","WriteEntity","WriteString","WriteDouble","WriteBool","WriteUInt"}) do trap(env.net,key) end
        for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnSpawnPositions","returnActivatorSpawns",
            "destroyActivators","stopActivatorEvent","saveSpawnPositions","Vector","Entity"}) do trap(env,key) end
        for _,ent in ipairs(env.entities) do
            for _,key in ipairs({"Remove","FinishRemoval","Spawn","SetPos","SetName","SetHealth","SetModel","SetMoveType","StopMoving","TakeDamage","Fire"}) do trap(ent,key) end
        end
        local lines,text=near(env,admin); eq(#rows(lines),2); contains(text,"omitted invalid/deleting 1")
        local _,again=near(env,admin); eq(again,text,"repeatable read-only snapshot")
        for _,entry in ipairs(originals) do entry[1][entry[2]]=entry[3] end
        env.math=nil; eq(#attempts,0,"protected calls must not hide forbidden side effects")
        for _,name in ipairs(names) do unchanged(saved[name][1],state(env,name)) end
        for i,value in ipairs(public) do unchanged(snapshots[i],value) end
        eq(env.activatorCount,count); eq(env.totalEnemies,total); eq(#observer.chats,0)
        local before=env.messageCount("ActivatorSpawnMarker")
        eq(env.fire("PlayerSay",admin,"!markSpawn activator 1"),"")
        eq(env.messageCount("ActivatorSpawnMarker"),before+1,"existing configured marker grant survives")
        env.receive("SendNPCInformation",admin,"Raid"); eq(state(env,"eventActive"),true)
        eq(env.totalEnemies,5,"listing preserved the already open interaction")
    end)
    test("ready locations leave actual Use and Start functional after ordinary listing",function()
        local env,admin,actors=setup(); near(env,admin)
        admin.pos=actors[1].pos; actors[1]:AcceptInput("Use",admin,admin)
        eq(env.messageCount("OpenInteractionMenu"),1)
        env.receive("SendNPCInformation",admin,"Raid")
        eq(state(env,"eventActive"),true); eq(env.totalEnemies,5)
        eq(#env.ents.FindByClass("activatorent"),0)
        eq(#env.ents.FindByName("devonsSpawnedEntity"),5)
    end)
end
