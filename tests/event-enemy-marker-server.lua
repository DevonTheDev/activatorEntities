-- Actual command handlers and engine callback doubles; no native wire/rendering claim.
return function(gmod,test,eq)
    local channel="ActivatorSpawnMarker"
    local function say(env,admin,text) return env.fire("PlayerSay",admin,text) end
    local function packets(env)
        local result={}; for _,out in ipairs(env.messages) do if out.name==channel then result[#result+1]=out end end
        return result
    end
    local function setup(count,listed)
        local env=gmod.new(); env.NPCEdits[1].information.maxNPCs=count or 3
        local admin,enemies=env.start(); admin.admin=true
        for i,enemy in ipairs(enemies) do enemy.index=100+i; enemy.EntIndex=function(self) return self.index end end
        if listed~=false then say(env,admin,"!listEventEnemies") end
        return env,admin,enemies
    end
    local function mark(env,admin,token)
        eq(say(env,admin,"!markEventEnemy "..(token or "101")),"","marker command stays private")
    end
    local function one(env,admin,token)
        local all=packets(env); eq(#all,1); local out=all[1]
        eq(out.player,admin); eq(out.broadcast,nil); eq(out.unreliable,false)
        eq(out.values[1],true); eq(out.values[2],env.map); eq(out.values[3],"event_enemy"); eq(out.values[4],token or "101")
        eq(#out.fields,8); for i,kind in ipairs({"bool","string","string","string","double","double","double","double"}) do eq(out.fields[i].kind,kind) end
        eq(out.values[8],env.now+15); return out
    end
    test("event enemy marker actual inspected object sends one current fractional position",function()
        local env,admin,enemies=setup(); local target=enemies[1]; local reads=0
        target.pos=env.Vector(123.125,-456.5,789.03125)
        target.GetPos=function(self) reads=reads+1; return self.pos end
        mark(env,admin); local out=one(env,admin); eq(reads,1)
        eq(out.values[5],123.125); eq(out.values[6],-456.5); eq(out.values[7],789.03125)
        target.pos.x=10000; eq(out.values[5],123.125)
        assert(admin.chats[#admin.chats]:find("snapshot",1,true)); assert(#admin.chats[#admin.chats]<=255)
    end)
    for _,input in ipairs({"!markEventEnemy","!markEventEnemy 101 extra","!markEventEnemy 0101","!markEventEnemy +101","!markEventEnemy 101.0","!markEventEnemy 0x65","!markEventEnemy 0","!markEventEnemy -1","!markEventEnemy 1e999","!markEventEnemy "..string.rep("1",65),"!clearEventEnemyMarker extra"}) do
        test("event enemy marker malformed input is private: "..input,function()
            local env,admin=setup(); eq(say(env,admin,input),""); eq(#packets(env),0)
            assert(#admin.chats[#admin.chats]<=255)
        end)
    end
    test("event enemy marker recognizes exact commands only",function()
        local env,admin=setup()
        for _,input in ipairs({"!markEventEnemySuffix 101","!clearEventEnemyMarkers","hello !markEventEnemy 101"}) do eq(say(env,admin,input),nil) end
    end)
    for _,case in ipairs({"invalid","not player","not admin","dead","throwing player","throwing admin","throwing alive"}) do
        test("event enemy marker rejects requester "..case,function()
            local env,admin=setup()
            if case=="invalid" then admin.valid=false elseif case=="not player" then admin.class="worldspawn"
            elseif case=="not admin" then admin.admin=false elseif case=="dead" then admin.alive=false
            else admin[case=="throwing player" and "IsPlayer" or case=="throwing admin" and "IsAdmin" or "Alive"]=function() error("getter failed") end end
            mark(env,admin); eq(#packets(env),0)
        end)
    end
    for _,case in ipairs({"absent","other admin","off page","unindexed","duplicate","duplicate across pages","changed index","killed","invalid","deleting","pending removal","unrelated same index","reused index","stop","complete","replacement","map changed","new failed list","new page","disconnect","initialize"}) do
        test("event enemy marker exact page rejects "..case,function()
            local env,admin,enemies=setup(10,case~="absent"); local target=enemies[1]
            if case=="other admin" then admin=env.entity("player"); admin.admin=true
            elseif case=="off page" then say(env,admin,"!listEventEnemies 2")
            elseif case=="unindexed" then target.EntIndex=function() return nil end; say(env,admin,"!listEventEnemies")
            elseif case=="duplicate" or case=="duplicate across pages" then
                enemies[case=="duplicate" and 2 or 10].index=101; say(env,admin,"!listEventEnemies")
            elseif case=="changed index" then target.index=909
            elseif case=="killed" then env.fire("OnNPCKilled",target,admin)
            elseif case=="invalid" then target.valid=false
            elseif case=="deleting" then target.markedForDeletion=true
            elseif case=="pending removal" then target.Remove=function() end; say(env,admin,"!removeEventEnemy 101")
            elseif case=="unrelated same index" or case=="reused index" then
                local other=env.entity(target.class); other.name=target.name; other.index=101; other.EntIndex=function(self) return self.index end
                target.valid=false; if case=="reused index" then env.fire("EntityRemoved",target) end
            elseif case=="stop" then env.stopActivatorEvent()
            elseif case=="complete" then for _,enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
            elseif case=="replacement" then env.stopActivatorEvent(); local _,nextEnemies=env.start(); nextEnemies[1].index=101
            elseif case=="map changed" then env.map="gm_flatgrass"
            elseif case=="new failed list" then say(env,admin,"!listEventEnemies 99")
            elseif case=="new page" then say(env,admin,"!listEventEnemies 2")
            elseif case=="disconnect" then env.fire("PlayerDisconnected",admin)
            elseif case=="initialize" then env.file.Exists=function() return false end; env.fire("Initialize") end
            mark(env,admin); eq(#packets(env),0)
        end)
    end
    test("event enemy marker grants exactly the actual eight-row page",function()
        local env,admin=setup(10); mark(env,admin,"108"); eq(#packets(env),1)
        mark(env,admin,"109"); eq(#packets(env),1)
        say(env,admin,"!listEventEnemies 2"); mark(env,admin,"109"); eq(#packets(env),2)
        mark(env,admin,"108"); eq(#packets(env),2)
    end)
    test("event enemy marker does not consume removal and clear does not refresh it",function()
        local env,admin,enemies=setup(); mark(env,admin); mark(env,admin)
        say(env,admin,"!clearEventEnemyMarker"); say(env,admin,"!removeEventEnemy 101"); eq(enemies[1].valid,false)
        mark(env,admin,"102"); eq(#packets(env),3)
        say(env,admin,"!clearEventEnemyMarker"); say(env,admin,"!removeEventEnemy 102"); eq(enemies[2].valid,true)
    end)
    test("event enemy failed relist invalidates marker only, retaining legacy removal",function()
        local env,admin,enemies=setup(); say(env,admin,"!listEventEnemies 99"); mark(env,admin); eq(#packets(env),0)
        say(env,admin,"!removeEventEnemy 101"); eq(enemies[1].valid,false)
    end)
    test("event enemy marker allows interrupted owned remainder and paused schedule",function()
        local env,admin,enemies=setup(); say(env,admin,"!pauseActivatorSpawns")
        say(env,admin,"!removeEventEnemy 103"); say(env,admin,"!listEventEnemies"); mark(env,admin); one(env,admin)
        eq(env.totalEnemies,2); eq(env.timers.activatorSpawner.stopped,true)
    end)
    test("event enemy marker construction capture never gains delayed authority",function()
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local create=env.ents.Create; local count=0; local token
        env.ents.Create=function(class)
            local enemy=create(class)
            if class=="npc_stalker" then
                count=count+1; enemy.index=100+count; enemy.EntIndex=function(self) return self.index end
                if count==2 then say(env,admin,"!listEventEnemies"); token="101"; mark(env,admin,token); eq(#packets(env),0) end
            end
            return enemy
        end
        env.fireTimer("activatorSpawner"); local actor=env.ents.FindByClass("activatorent")[1]; admin.pos=actor.pos
        actor:AcceptInput("Use",admin,admin); env.receive("SendNPCInformation",admin,"Raid")
        assert(token); mark(env,admin,token); eq(#packets(env),0)
        say(env,admin,"!listEventEnemies"); mark(env,admin,token); one(env,admin)
    end)
    for _,case in ipairs({"throwing","missing","nonvector","nan","infinity"}) do
        test("event enemy marker rejects unusable position "..case,function()
            local env,admin,enemies=setup(); local target=enemies[1]
            if case=="throwing" then target.GetPos=function() error("position unavailable") end
            elseif case=="missing" then target.GetPos=false
            elseif case=="nonvector" then target.GetPos=function() return {x=1,y=2,z=3} end
            else target.pos=env.Vector(case=="nan" and 0/0 or math.huge,2,3) end
            mark(env,admin); eq(#packets(env),0)
        end)
    end
    for _,case in ipairs({"nan time","infinite time","lost deadline","throwing time","empty map","long map","control map","throwing map"}) do
        test("event enemy marker rejects unusable context "..case,function()
            local env,admin=setup()
            if case=="nan time" then env.now=0/0 elseif case=="infinite time" then env.now=math.huge
            elseif case=="lost deadline" then env.now=1e308 elseif case=="throwing time" then env.CurTime=function() error("time") end
            elseif case=="empty map" then env.map="" elseif case=="long map" then env.map=string.rep("a",129)
            elseif case=="control map" then env.map="bad\nmap" else env.game.GetMap=function() error("map") end end
            mark(env,admin); eq(#packets(env),0)
        end)
    end
    local actions={"list","failed list","clear enemy","clear spawn","mark enemy","mark spawn","disconnect","retire","replace"}
    for _,getter in ipairs({"IsPlayer","IsAdmin","Alive","GetMap","CurTime","IsMarkedForDeletion","EntIndex","GetPos"}) do
        for _,action in ipairs(actions) do
            test("event enemy marker nested "..action.." at "..getter.." supersedes outer",function()
                local env,admin,enemies=setup(); say(env,admin,"!listSpawns enemy")
                local object=(getter=="GetMap" and env.game or getter=="CurTime" and env
                    or (getter=="IsMarkedForDeletion" or getter=="EntIndex" or getter=="GetPos") and enemies[1] or admin)
                local original=object[getter]
                object[getter]=function(...)
                    object[getter]=original
                    if action=="list" then say(env,admin,"!listEventEnemies")
                    elseif action=="failed list" then say(env,admin,"!listEventEnemies 99")
                    elseif action=="clear enemy" then say(env,admin,"!clearEventEnemyMarker")
                    elseif action=="clear spawn" then say(env,admin,"!clearSpawnMarker")
                    elseif action=="mark enemy" then mark(env,admin,"102")
                    elseif action=="mark spawn" then say(env,admin,"!markSpawn enemy 1")
                    elseif action=="disconnect" then env.fire("PlayerDisconnected",admin)
                    elseif action=="retire" then env.stopActivatorEvent()
                    else env.stopActivatorEvent(); env.start() end
                    return original(...)
                end
                mark(env,admin); local all=packets(env)
                local expected=action:find("clear",1,true) or action:find("mark",1,true)
                eq(#all,expected and 1 or 0)
                if action=="mark enemy" then eq(all[1].values[4],"102") end
                if action=="mark spawn" then eq(all[1].values[3],"enemy") end
                if action:find("clear",1,true) then eq(all[1].values[1],false) end
            end)
        end
    end
    for _,getter in ipairs({"IsMarkedForDeletion","EntIndex","GetPos"}) do
        test("event enemy older listing fails closed after nested capture at "..getter,function()
            local env,admin,enemies=setup(10,false); local target=enemies[1]; local original=target[getter]
            target[getter]=function(...)
                target[getter]=original; say(env,admin,"!listEventEnemies 2"); return original(...)
            end
            say(env,admin,"!listEventEnemies"); mark(env,admin,"109"); mark(env,admin,"101"); eq(#packets(env),0)
            -- Do not silently repair the legacy outer page: cleanup still selects row 101.
            say(env,admin,"!removeEventEnemy 101"); eq(enemies[1].valid,false)
            say(env,admin,"!listEventEnemies 2"); mark(env,admin,"110"); eq(#packets(env),1)
        end)
    end
    test("event enemy list permission callback cannot overwrite a newer grant",function()
        local env,admin=setup(10,false); local original=admin.IsAdmin
        admin.IsAdmin=function(self) admin.IsAdmin=original; say(env,admin,"!listEventEnemies 2"); return original(self) end
        say(env,admin,"!listEventEnemies"); mark(env,admin,"109"); mark(env,admin); eq(#packets(env),0)
    end)
    for _,inner in ipairs({"!markEventEnemy 102","!clearEventEnemyMarker"}) do
        test("spawn marker outer operation loses to "..inner,function()
            local env,admin=setup(); say(env,admin,"!listSpawns enemy")
            local original=admin.Alive
            admin.Alive=function(self) admin.Alive=original; say(env,admin,inner); return original(self) end
            say(env,admin,"!markSpawn enemy 1"); local all=packets(env); eq(#all,1)
            if inner:find("clear",1,true) then eq(all[1].values[1],false) else eq(all[1].values[3],"event_enemy") end
        end)
    end
    test("event enemy marker sends before feedback reentry and leaves newer clear last",function()
        local env,admin=setup(); local original=admin.ChatPrint
        admin.ChatPrint=function(self,line)
            original(self,line); if line:find("snapshot sent",1,true) then admin.ChatPrint=original; say(env,admin,"!clearEventEnemyMarker") end
        end
        mark(env,admin); local all=packets(env); eq(#all,2); eq(all[1].values[1],true); eq(all[2].values[1],false)
    end)
    test("event enemy clear is private idempotent and permits dead admin",function()
        local env,admin=setup(); admin.alive=false
        for i=1,2 do eq(say(env,admin,"!clearEventEnemyMarker"),"") end
        local all=packets(env); eq(#all,2)
        for _,out in ipairs(all) do eq(out.player,admin); eq(#out.fields,1); eq(out.values[1],false); eq(env.packetBits(out),1) end
    end)
    test("event enemy marker no entity lookup mutation RNG timer persistence or broadcast",function()
        local env,admin,enemies=setup(); local attempts={}; local function forbid(owner,key)
            owner[key]=function() attempts[#attempts+1]=key; error("forbidden "..key) end
        end
        env.math=setmetatable({}, {__index=math})
        for _,key in ipairs({"random","randomseed"}) do forbid(env.math,key) end
        for _,key in ipairs({"Create","FindByClass","FindByName"}) do forbid(env.ents,key) end
        for _,key in ipairs({"Create","Simple","Start","Stop","Remove","Adjust"}) do forbid(env.timer,key) end
        for _,key in ipairs({"Read","Write","Delete","Append","Exists"}) do forbid(env.file,key) end
        for _,key in ipairs({"Broadcast","WriteEntity","SendToServer"}) do forbid(env.net,key) end
        forbid(env,"Entity")
        for _,enemy in ipairs(enemies) do for _,key in ipairs({"Remove","Spawn","SetPos","SetHealth","SetName","SetModel","TakeDamage","Fire"}) do forbid(enemy,key) end end
        mark(env,admin); one(env,admin); eq(#attempts,0); eq(env.totalEnemies,3)
    end)
    test("event enemy marker feedback cannot follow a newer operation from recipient checks",function()
        local env,admin=setup(); local original=admin.IsPlayer; local entered=false
        admin.IsPlayer=function(self)
            if not entered and #packets(env)>0 then
                entered=true; say(env,admin,"!clearEventEnemyMarker")
            end
            return original(self)
        end
        mark(env,admin)
        if entered then assert(not admin.chats[#admin.chats]:find("snapshot sent",1,true),"obsolete success followed newer clear") end
    end)
    test("event enemy accepted removal rejects another admin's retained marker page",function()
        local env,admin,enemies=setup(); local second=env.entity("player"); second.admin=true
        say(env,second,"!listEventEnemies"); enemies[1].Remove=function() end
        say(env,admin,"!removeEventEnemy 101"); mark(env,second); eq(#packets(env),0)
        mark(env,second,"102"); eq(#packets(env),1)
    end)
    for _,getter in ipairs({"IsMarkedForDeletion","EntIndex"}) do
        test("event enemy marker contains throwing target "..getter,function()
            local env,admin,enemies=setup(); enemies[1][getter]=function() error("getter failed") end
            mark(env,admin); eq(#packets(env),0)
        end)
    end
    for _,getter in ipairs({"IsPlayer","IsAdmin","Alive","GetMap","CurTime","IsMarkedForDeletion","EntIndex","GetPos"}) do
        for _,change in ipairs({"demotion","death","invalidation","map change","changed index","target deletion"}) do
            test("event enemy marker current context after "..getter..": "..change,function()
                local env,admin,enemies=setup()
                local object=(getter=="GetMap" and env.game or getter=="CurTime" and env
                    or (getter=="IsMarkedForDeletion" or getter=="EntIndex" or getter=="GetPos") and enemies[1] or admin)
                local original=object[getter]
                object[getter]=function(...)
                    object[getter]=original; local value=original(...)
                    if change=="demotion" then admin.admin=false elseif change=="death" then admin.alive=false
                    elseif change=="invalidation" then admin.valid=false elseif change=="map change" then env.map="gm_flatgrass"
                    elseif change=="changed index" then enemies[1].index=909 else enemies[1].markedForDeletion=true end
                    return value
                end
                mark(env,admin); eq(#packets(env),0)
            end)
        end
    end

    test("event enemy final player guard cannot authorize a changed target index",function()
        local env,admin,enemies=setup(); local original=admin.Alive; local reads=0
        admin.Alive=function(self) reads=reads+1; if reads==3 then enemies[1].index=909 end; return original(self) end
        mark(env,admin); eq(#packets(env),0)
    end)
    test("event enemy duplicate token straddling two pages grants neither row",function()
        local env,admin,enemies=setup(10,false); enemies[9].index=108
        say(env,admin,"!listEventEnemies"); mark(env,admin,"108"); eq(#packets(env),0)
        say(env,admin,"!listEventEnemies 2"); mark(env,admin,"108"); eq(#packets(env),0)
        mark(env,admin,"110"); eq(#packets(env),1)
    end)

    test("event enemy final deletion getter cannot return a stale index proof",function()
        local env,admin,enemies=setup(); local target=enemies[1]; local original=target.IsMarkedForDeletion; local reads=0
        target.IsMarkedForDeletion=function(self)
            reads=reads+1; if reads==4 then self.index=909 end; return original(self)
        end
        mark(env,admin); eq(#packets(env),0)
    end)

end
