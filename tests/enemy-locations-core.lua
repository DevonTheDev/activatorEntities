-- Exercise the real private server command on started encounters. Native
-- ChatPrint delivery, NPC navigation and engine index reuse remain unverified.
return function(gmod, test, eq)
    local function contains(text, expected)
        assert(text:find(expected,1,true), "missing " .. expected .. " in " .. text)
    end
    local function setup(count, name)
        local env=gmod.new()
        env.NPCEdits[1].information.maxNPCs=count or 5
        env.NPCEdits[1].name=name or "Raid"
        local admin,actor=env.ready(); admin.admin=true
        actor:AcceptInput("Use",admin,admin)
        env.receive("SendNPCInformation",admin,name or "Raid")
        local enemies=env.ents.FindByName("devonsSpawnedEntity")
        eq(#enemies,count or 5,"actual encounter started")
        eq(env.totalEnemies,count or 5,"actual progress initialized")
        admin.chats={}
        return env,admin,enemies
    end
    local function say(env,admin,command)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,command or "!listEventEnemies"),"","command consumed privately")
        local lines={}
        for i=before+1,#admin.chats do
            local line=admin.chats[i]
            assert(#line<=255,"ChatPrint exceeds 255 bytes")
            assert(not line:find("[%c]"),"raw control byte in reply")
            lines[#lines+1]=line
        end
        assert(#lines>0,"private reply exists")
        return lines,table.concat(lines,"\n")
    end
    local function rows(lines)
        local found={}
        for _,line in ipairs(lines) do
            if line:match("^Entity index ") or line:match("^Unindexed:") then found[#found+1]=line end
        end
        assert(#found<=8,"eight body rows per page")
        return found
    end
    local function privateState(env)
        local values,visited={},{}
        local names={interactions=true,pendingSelection=true,selectedBatchName=true,
            selectedBatchEntities=true,activeEnemies=true,constructingEnemies=true,
            eventActive=true,eventInterrupted=true,activeEventName=true,initialEnemies=true,statusRequestAfter=true}
        local function inspect(callback)
            if visited[callback] then return end
            visited[callback]=true
            for i=1,100 do
                local name,value=debug.getupvalue(callback,i)
                if not name then break end
                if names[name] then values[name]=value end
                if type(value)=="function" then inspect(value) end
            end
        end
        for _,hooks in pairs(env.hooks) do for _,callback in pairs(hooks) do inspect(callback) end end
        for _,timer in pairs(env.timers) do inspect(timer.callback) end
        for _,callback in pairs(env.receivers) do inspect(callback) end
        return values
    end
    local function snapshot(value,seen)
        if type(value)~="table" then return value end
        seen=seen or {}; if seen[value] then return seen[value] end
        local copy={original=value,entries={}}; seen[value]=copy
        for key,child in pairs(value) do
            if key~="chats" then copy.entries[key]=snapshot(child,seen) end
        end
        return copy
    end
    local function unchanged(before,value,checked)
        if type(before)~="table" then eq(value,before,"unchanged value"); return end
        eq(value,before.original,"unchanged table identity")
        checked=checked or {}; if checked[before] then return end; checked[before]=true
        local old,new=0,0
        for key,child in pairs(before.entries) do old=old+1; unchanged(child,value[key],checked) end
        for key in pairs(value) do if key~="chats" then new=new+1 end end
        eq(new,old,"unchanged table entries")
    end

    test("enemy locations privately report current owned positions and progress",function()
        local env,admin,enemies=setup(); local observer=env.entity("player")
        local unrelated=env.entity(enemies[1]:GetClass()); unrelated:SetName("devonsSpawnedEntity")
        unrelated:SetPos(env.Vector(999,888,777))
        enemies[1]:SetPos(env.Vector(12.4,-23.6,34.5))
        local messages=#env.messages
        local lines,text=say(env,admin)
        contains(text,'Active encounter: "Raid"'); contains(text,"progress 5/5")
        contains(text,"listed 5"); contains(text,"omitted invalid/deleting 0")
        contains(text,"approx rounded world position (12, -24, 35)")
        contains(text,"Temporary entity indices"); eq(#rows(lines),5)
        assert(not text:find("999, 888, 777",1,true),"unrelated shared-name enemy leaked")
        eq(#observer.chats,0); eq(#env.messages,messages,"no network publication")
        enemies[1]:SetPos(env.Vector(45,56,67))
        local _,fresh=say(env,admin); contains(fresh,"(45, 56, 67)")
        assert(not fresh:find("(12, -24, 35)",1,true),"stale coordinates retained")
    end)
    test("enemy locations sort indices numerically across all eight-row pages",function()
        local env,admin,enemies=setup(19)
        for i,enemy in ipairs(enemies) do enemy.index=(20-i)*7 end
        local all={}
        for page=1,3 do
            local lines,text=say(env,admin,"!listEventEnemies " .. page)
            contains(text,"page " .. page .. "/3"); contains(text,"listed 19")
            local body=rows(lines); eq(#body,page==3 and 3 or 8)
            for _,line in ipairs(body) do all[#all+1]=assert(tonumber(line:match("^Entity index (%d+)"))) end
        end
        eq(#all,19); for i,index in ipairs(all) do eq(index,i*7) end
        local _,first=say(env,admin); local _,again=say(env,admin,"!listEventEnemies 01"); eq(first,again)
    end)
    for _,argument in ipairs({"0","-1","+1","1.0","1e1","two","1 2","2 extra",string.rep("9",400)}) do
        test("enemy locations reject malformed page " .. argument:sub(1,20),function()
            local env,admin=setup()
            local lines,text=say(env,admin,"!listEventEnemies " .. argument)
            eq(#lines,1); contains(text,"Usage: !listEventEnemies [page]"); eq(env.totalEnemies,5)
        end)
    end
    test("enemy locations reject an active out-of-range page",function()
        local env,admin=setup(9)
        local lines,text=say(env,admin,"!listEventEnemies 3")
        eq(#lines,1); contains(text,"Usage: !listEventEnemies [page]"); contains(text,"1-2")
    end)
    test("enemy locations apply valid-player admin guards and preserve unrelated chat",function()
        local env,admin=setup(); local outsider=env.entity("player")
        local _,text=say(env,outsider); contains(text,"Only admins")
        eq(env.fire("PlayerSay",{valid=false},"!listEventEnemies"),nil)
        local prop=env.entity("prop_physics"); prop.admin=true
        eq(env.fire("PlayerSay",prop,"!listEventEnemies"),nil); eq(#prop.chats,0)
        eq(env.fire("PlayerSay",admin,"!listEventEnemiesOther"),nil)
        eq(env.fire("PlayerSay",admin,"ordinary chat"),nil); eq(#admin.chats,0)
        eq(env.totalEnemies,5)
    end)
    test("enemy locations count omitted invalid and deleting ownership without pruning",function()
        local env,admin,enemies=setup(); local owners=privateState(env).activeEnemies
        enemies[1].valid=false
        env.deferRemoval=true; enemies[2]:Remove()
        local lines,text=say(env,admin)
        contains(text,"progress 5/5"); contains(text,"listed 3"); contains(text,"omitted invalid/deleting 2")
        eq(#rows(lines),3); eq(owners[enemies[1]],true); eq(owners[enemies[2]],true)
        eq(env.totalEnemies,5); eq(privateState(env).activeEnemies,owners)
    end)
    test("enemy locations preserve the active zero-row diagnostic page",function()
        local env,admin,enemies=setup(2)
        for _,enemy in ipairs(enemies) do enemy.valid=false end
        local lines,text=say(env,admin)
        contains(text,"page 1/1"); contains(text,"progress 2/2")
        contains(text,"listed 0"); contains(text,"omitted invalid/deleting 2"); eq(#rows(lines),0)
    end)
    for _,kind in ipairs({"missing method","throwing method","nil result","non-vector","nan","infinity","throwing vector"}) do
        test("enemy locations show unavailable coordinates for " .. kind,function()
            local env,admin,enemies=setup(1); local enemy=enemies[1]
            if kind=="missing method" then enemy.GetPos=false
            elseif kind=="throwing method" then enemy.GetPos=function() error("position failed") end
            elseif kind=="nil result" then enemy.GetPos=function() return nil end
            elseif kind=="non-vector" then enemy.pos={x=0,y=0,z=0}
            elseif kind=="nan" then enemy.pos=env.Vector(0/0,0,0)
            elseif kind=="infinity" then enemy.pos=env.Vector(1,math.huge,3)
            else
                enemy.pos=env.Vector(1,2,3); enemy.pos.x=nil
                setmetatable(enemy.pos,{__index=function() error("coordinate failed") end})
                env.isvector=function() return true end
            end
            local lines,text=say(env,admin)
            eq(#rows(lines),1); contains(text,"world position unavailable")
            assert(not text:find("(0, 0, 0)",1,true),"fabricated origin")
            contains(text,"listed 1"); contains(text,"omitted invalid/deleting 0"); eq(env.totalEnemies,1)
        end)
    end
    for _,kind in ipairs({"missing","throwing","nil","zero","negative","fractional","nan","infinity","string"}) do
        test("enemy locations keep readable positions when index is " .. kind,function()
            local env,admin,enemies=setup(1); local enemy=enemies[1]
            enemy:SetPos(env.Vector(111,222,333))
            if kind=="missing" then enemy.EntIndex=false
            elseif kind=="throwing" then enemy.EntIndex=function() error("index failed") end
            elseif kind=="nil" then enemy.index=nil
            elseif kind=="zero" then enemy.index=0
            elseif kind=="negative" then enemy.index=-1
            elseif kind=="fractional" then enemy.index=1.5
            elseif kind=="nan" then enemy.index=0/0
            elseif kind=="infinity" then enemy.index=math.huge
            else enemy.index="7" end
            local lines,text=say(env,admin); eq(#rows(lines),1)
            contains(text,"Unindexed: index unavailable"); contains(text,"(111, 222, 333)")
            contains(text,"listed 1"); eq(env.totalEnemies,1)
        end)
    end
    test("enemy locations order copied unindexed diagnostics consistently after indices",function()
        local env,admin,enemies=setup(5)
        enemies[1].index=30; enemies[2].index=2
        for i=3,5 do enemies[i].index=0; enemies[i]:SetPos(env.Vector((6-i)*100,0,0)) end
        local lines,first=say(env,admin); local body=rows(lines)
        contains(body[1],"Entity index 2:"); contains(body[2],"Entity index 30:")
        contains(body[3],"(100, 0, 0)"); contains(body[5],"(300, 0, 0)")
        local _,again=say(env,admin); eq(again,first)
    end)
    test("enemy locations bound Unicode names controls extreme coordinates and indices",function()
        local name=string.rep("雪",160) .. "\n\r\0tail"
        local env,admin,enemies=setup(1,name)
        enemies[1]:SetPos(env.Vector(1e308,-1e308,0.00001)); enemies[1].index=1e308
        local lines,text=say(env,admin)
        contains(text,"progress 1/1"); contains(text,"listed 1"); contains(text,"omitted invalid/deleting 0")
        local body=rows(lines); eq(#body,1); contains(body[1],"approx rounded world position")
        assert(#body[1]<150,"numeric representations are bounded")
        local nameLine=lines[1]
        contains(nameLine,"雪...")
    end)
    test("enemy locations bound malformed continuation-byte names without losing facts",function()
        local env,admin=setup(1,string.rep(string.char(128),400))
        local lines,text=say(env,admin)
        contains(text,"progress 1/1"); contains(text,"listed 1"); contains(text,"omitted invalid/deleting 0")
        eq(#rows(lines),1)
    end)
    test("enemy locations render every reply before first ChatPrint reentry",function()
        local env,admin,enemies=setup(9); enemies[1]:SetPos(env.Vector(11,22,33))
        local _,before=say(env,admin)
        admin.chats={}; local original=admin.ChatPrint; local first=true
        admin.ChatPrint=function(self,line)
            original(self,line)
            if first then
                first=false
                env.stopActivatorEvent()
                admin.valid=false -- Replacement's ordinary broadcast is outside this private reply.
                local replacement,nextEnemies=env.start(); replacement.admin=true
                admin.valid=true
                nextEnemies[1]:SetPos(env.Vector(444,555,666))
            end
        end
        local lines,text=say(env,admin); eq(text,before,"reply-time replacement cannot mix snapshots")
        eq(#rows(lines),8); eq(env.totalEnemies,9)
    end)
    test("enemy locations reject encounter replacement during entity capture",function()
        local env,admin,enemies=setup(1); local once=true
        enemies[1].GetPos=function(self)
            if once then
                once=false; env.stopActivatorEvent(); admin.valid=false
                env.start(); admin.valid=true
            end
            return self.pos
        end
        local lines,text=say(env,admin)
        eq(#lines,1); contains(text,"Encounter changed during inspection"); eq(#rows(lines),0)
        eq(env.totalEnemies,1)
    end)
    test("enemy locations reject a stop during entity capture",function()
        local env,admin,enemies=setup(1)
        enemies[1].EntIndex=function() env.stopActivatorEvent(); return 7 end
        local lines,text=say(env,admin)
        eq(#lines,1); contains(text,"Encounter changed during inspection"); eq(#rows(lines),0)
        eq(env.totalEnemies,0)
    end)
    test("enemy locations report idle stopped and completed encounters",function()
        local env,admin,enemies=setup(2)
        env.stopActivatorEvent()
        local _,stopped=say(env,admin,"!listEventEnemies 2"); contains(stopped,"No active encounter")
        local ply,nextEnemies=env.start(); ply.admin=true
        for _,enemy in ipairs(nextEnemies) do env.fire("OnNPCKilled",enemy,ply) end
        local _,completed=say(env,ply); contains(completed,"No active encounter")
        local idle=gmod.new(); local idleAdmin=idle.entity("player"); idleAdmin.admin=true
        local _,text=say(idle,idleAdmin); contains(text,"No active encounter")
        local _,malformed=say(idle,idleAdmin,"!listEventEnemies nope"); contains(malformed,"Usage:")
    end)
    test("active eventStatus advertises enemy locations while preserving status facts",function()
        local env,admin=setup()
        local _,text=say(env,admin,"!eventStatus")
        contains(text,"!listEventEnemies [page]"); contains(text,"5/5 enemies remaining")
        contains(text,"Ready activators: 0"); contains(text,"Pending next batch: none")
    end)
    test("enemy location reads cannot mutate private state or invoke side effects",function()
        local env,admin,enemies=setup(); env.fire("PlayerSay",admin,"!nextEvent Raid")
        enemies[1].valid=false; env.deferRemoval=true; enemies[2]:Remove()
        local restored={}
        local function forbid(owner,key)
            restored[#restored+1]={owner,key,owner[key]}
            owner[key]=function() error("enemy inspection invoked forbidden " .. key) end
        end
        env.math=setmetatable({},{__index=math}); forbid(env.math,"random"); forbid(env.math,"randomseed")
        for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnActivatorSpawns","returnSpawnPositions",
            "destroyActivators","stopActivatorEvent","saveSpawnPositions"}) do forbid(env,key) end
        for _,owner in ipairs({env.timer,env.file,env.net}) do
            local keys={}; for key,value in pairs(owner) do if type(value)=="function" then keys[#keys+1]=key end end
            for _,key in ipairs(keys) do forbid(owner,key) end
        end
        for _,key in ipairs({"Create","FindByName","FindByClass"}) do forbid(env.ents,key) end
        for _,ent in ipairs(env.entities) do
            for _,key in ipairs({"Remove","FinishRemoval","Spawn","SetPos","SetHealth","SetName","SetModel","SetMoveType","StopMoving"}) do forbid(ent,key) end
        end
        local private=privateState(env); assert(type(private.activeEnemies)=="table","actual ownership captured")
        local states={env.NPCEdits,env.SpawnPositions,env.entities,env.timers,env.messages,private}
        local before={}; for i,state in ipairs(states) do before[i]=snapshot(state) end
        local count,total=env.activatorCount,env.totalEnemies
        local ok,err=pcall(function()
            local _,first=say(env,admin)
            for i=1,3 do local _,again=say(env,admin); eq(again,first) end
            say(env,admin,"!listEventEnemies 0"); say(env,admin,"!listEventEnemies 999")
            for i=1,5 do unchanged(before[i],states[i]) end
            local after=privateState(env)
            for key,value in pairs(before[6].entries) do unchanged(value,after[key]) end
            eq(env.activatorCount,count); eq(env.totalEnemies,total)
        end)
        for _,entry in ipairs(restored) do entry[1][entry[2]]=entry[3] end
        assert(ok,err)
    end)
end
