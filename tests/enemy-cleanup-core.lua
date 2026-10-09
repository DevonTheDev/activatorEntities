-- Actual server handlers with engine doubles: selection admission and callback
-- accounting, not native handle lifetime or removal timing.
return function(gmod, test, eq)
    local function contains(text, part)
        assert(text:find(part,1,true), "missing " .. part .. " in " .. text)
    end
    local function setup(count)
        local env=gmod.new(); env.NPCEdits[1].information.maxNPCs=count or 5
        local admin,enemies=env.start(); admin.admin=true; admin.chats={}
        return env,admin,enemies
    end
    local function say(env,admin,text)
        local first=#admin.chats+1
        eq(env.fire("PlayerSay",admin,text),"","targeted cleanup command is private")
        local lines={}
        for i=first,#admin.chats do
            assert(#admin.chats[i]<=255,"private feedback fits ChatPrint")
            lines[#lines+1]=admin.chats[i]
        end
        return table.concat(lines,"\n")
    end
    local function inspect(env,admin,page)
        return say(env,admin,"!listEventEnemies" .. (page and (" " .. page) or ""))
    end
    local function remove(env,admin,index)
        return say(env,admin,"!removeEventEnemy " .. index)
    end
    local function status(env)
        for i=#env.messages,1,-1 do
            if env.messages[i].name=="ActivatorEventStatus" then return env.messages[i].values end
        end
        error("no actual progress packet")
    end
    local function untouched(env,callback)
        local total,messages,timer=env.totalEnemies,#env.messages,env.timers.activatorSpawner
        local stopped=timer.stopped
        local old={}
        local function forbid(owner,key)
            old[#old+1]={owner,key,owner[key]}
            owner[key]=function() error("rejected command invoked " .. key) end
        end
        for _,entity in ipairs(env.entities) do forbid(entity,"Remove"); forbid(entity,"Spawn") end
        for _,owner in ipairs({env.timer,env.file,env.net}) do
            local keys={}; for key,value in pairs(owner) do if type(value)=="function" then keys[#keys+1]=key end end
            for _,key in ipairs(keys) do forbid(owner,key) end
        end
        env.math=setmetatable({},{__index=math}); forbid(env.math,"random"); forbid(env.math,"randomseed")
        forbid(env,"Entity"); forbid(env.ents,"Create"); forbid(env.ents,"FindByName"); forbid(env.ents,"FindByClass")
        local ok,err=pcall(callback)
        for _,entry in ipairs(old) do entry[1][entry[2]]=entry[3] end
        assert(ok,err)
        eq(env.totalEnemies,total); eq(#env.messages,messages)
        eq(env.timers.activatorSpawner,timer); eq(timer.stopped,stopped)
    end

    test("targeted cleanup removes only the inspected owned object and privately acknowledges a request",function()
        local env,admin,enemies=setup(); local observer=env.entity("player")
        local unrelated=env.entity(enemies[1]:GetClass()); unrelated:SetName("devonsSpawnedEntity")
        env.Entity=function() error("global index lookup must never run") end
        inspect(env,admin)
        local text=remove(env,admin,enemies[2].index)
        contains(text,"removal requested"); contains(text,"interrupted")
        eq(enemies[2].valid,false); eq(unrelated.valid,true); eq(#observer.chats,0)
        for i,enemy in ipairs(enemies) do if i~=2 then eq(enemy.valid,true) end end
        eq(env.totalEnemies,4); eq(status(env)[3],4); eq(status(env)[4],5); eq(status(env)[5],true)
        eq(env.messageCount("entitiesDeleted"),0); eq(env.messageCount("roundFinished"),0)
        for _,enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
        eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),0)
    end)
    for _,argument in ipairs({"", "0", "-1", "+5", "1.5", "1e1", "nope", "5 6", "5 extra", string.rep("9",400)}) do
        test("targeted cleanup rejects malformed or absent selection " .. argument:sub(1,20),function()
            local env,admin=setup(); inspect(env,admin)
            untouched(env,function() say(env,admin,"!removeEventEnemy" .. (argument=="" and "" or " " .. argument)) end)
            eq(env.totalEnemies,5)
        end)
    end
    test("targeted cleanup guards current admin permission and invalid callers",function()
        local env,admin,enemies=setup(); inspect(env,admin); admin.admin=false
        untouched(env,function() contains(remove(env,admin,enemies[1].index),"Only admins") end)
        eq(env.fire("PlayerSay",nil,"!removeEventEnemy 5"),nil)
        eq(env.fire("PlayerSay",{valid=false},"!removeEventEnemy 5"),nil)
        local prop=env.entity("prop_physics"); prop.admin=true
        eq(env.fire("PlayerSay",prop,"!removeEventEnemy 5"),nil); eq(#prop.chats,0)
        eq(env.fire("PlayerSay",admin,"!removeEventEnemyOther 5"),nil)
    end)
    for _,boundary in ipairs({"EntIndex","IsMarkedForDeletion"}) do
        for _,change in ipairs({"demotion","invalidation"}) do
            test("targeted cleanup rechecks player permission after " .. boundary .. " " .. change,function()
                local env,admin,enemies=setup(2); inspect(env,admin)
                local target=enemies[1]; local old=target[boundary]
                target[boundary]=function(self)
                    if change=="demotion" then admin.admin=false else admin.valid=false end
                    return old(self)
                end
                untouched(env,function() remove(env,admin,target.index) end)
                eq(env.totalEnemies,2); eq(target.valid,true)
                admin.admin=true; admin.valid=true
                for _,enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
                eq(env.messageCount("roundFinished"),1,"refused request cannot interrupt encounter")
            end)
        end
    end
    test("targeted cleanup requires this admin's own inspection",function()
        local env,admin,enemies=setup(); local second=env.entity("player"); second.admin=true
        untouched(env,function() remove(env,admin,enemies[1].index) end)
        inspect(env,admin)
        untouched(env,function() remove(env,second,enemies[1].index) end)
        remove(env,admin,enemies[1].index); eq(env.totalEnemies,4)
    end)
    test("targeted cleanup uses only the latest successful page and exact displayed token",function()
        local env,admin,enemies=setup(9)
        inspect(env,admin); inspect(env,admin,2)
        untouched(env,function() remove(env,admin,enemies[1].index) end)
        untouched(env,function() remove(env,admin,"0" .. enemies[9].index) end)
        inspect(env,admin,999) -- Failed inspection does not grant another page.
        remove(env,admin,enemies[9].index); eq(enemies[9].valid,false); eq(env.totalEnemies,8)
        untouched(env,function() remove(env,admin,enemies[8].index) end)
    end)
    test("targeted cleanup refuses a duplicate index split across captured pages",function()
        local env,admin,enemies=setup(9)
        for i,enemy in ipairs(enemies) do enemy.index=math.min(i,8) end
        inspect(env,admin,2)
        untouched(env,function() remove(env,admin,8) end)
        eq(env.totalEnemies,9)
    end)
    for _,kind in ipairs({"unindexed","changed","killed","removed","deleting","unreadable"}) do
        test("targeted cleanup rejects a captured target that is " .. kind,function()
            local env,admin,enemies=setup(); local enemy=enemies[1]; local index=enemy.index
            if kind=="unindexed" then enemy.index=0 end
            inspect(env,admin)
            if kind=="unindexed" then enemy.index=index
            elseif kind=="changed" then enemy.index=index+100
            elseif kind=="killed" then env.fire("OnNPCKilled",enemy,admin)
            elseif kind=="removed" then enemy:Remove()
            elseif kind=="deleting" then env.deferRemoval=true; enemy:Remove()
            else enemy.EntIndex=function() error("index unavailable") end end
            local replacement=env.entity(enemy:GetClass()); replacement.index=index
            untouched(env,function() remove(env,admin,index) end)
            eq(replacement.valid,true)
        end)
    end
    test("targeted cleanup disconnect clears inspection even if the player object still exists",function()
        local env,admin,enemies=setup(); inspect(env,admin); env.fire("PlayerDisconnected",admin)
        untouched(env,function() remove(env,admin,enemies[1].index) end)
        inspect(env,admin); remove(env,admin,enemies[1].index); eq(env.totalEnemies,4)
    end)
    test("targeted cleanup retirement cannot redirect old indices to a replacement encounter",function()
        local env,admin,enemies=setup(); inspect(env,admin); local index=enemies[1].index
        env.stopActivatorEvent(); local _,replacement=env.start(); replacement[1].index=index
        untouched(env,function() remove(env,admin,index) end)
        for _,enemy in ipairs(replacement) do env.fire("OnNPCKilled",enemy,admin) end
        eq(env.messageCount("roundFinished"),1,"rejected stale request cannot interrupt replacement")
    end)
    test("targeted cleanup consumes the page and blocks another admin while removal is deferred",function()
        local env,admin,enemies=setup(2); local second=env.entity("player"); second.admin=true
        inspect(env,admin); inspect(env,second); env.deferRemoval=true
        local enemy=enemies[1]; local original,calls=enemy.Remove,0
        enemy.Remove=function(self) calls=calls+1; original(self) end
        remove(env,admin,enemy.index); eq(calls,1); eq(env.totalEnemies,2)
        eq(enemy.valid,true); eq(enemy.markedForDeletion,true)
        untouched(env,function() remove(env,admin,enemy.index); remove(env,second,enemy.index); remove(env,admin,enemies[2].index) end)
        env.receive("RequestActivatorEventStatus",second)
        eq(status(env)[3],2); eq(status(env)[4],2); eq(status(env)[5],true)
        env.fire("OnNPCKilled",enemy,admin); env.fire("OnNPCKilled",enemies[2],admin)
        eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),0,"admission interrupts before deferred removal callback")
        env.flushRemovals(); eq(env.totalEnemies,0); eq(calls,1)
    end)
    test("targeted cleanup rejects reentrant replay before Remove has marked the entity",function()
        local env,admin,enemies=setup(2); local second=env.entity("player"); second.admin=true
        inspect(env,admin); inspect(env,second)
        local enemy=enemies[1]; local original,calls=enemy.Remove,0
        enemy.Remove=function(self)
            calls=calls+1
            if calls==1 then
                remove(env,admin,self.index); remove(env,second,self.index)
                inspect(env,second); remove(env,second,self.index)
            end
            original(self)
        end
        remove(env,admin,enemy.index)
        eq(calls,1,"one accepted removal despite synchronous reentry")
        eq(env.totalEnemies,1); eq(env.messageCount("entitiesDeleted"),0)
    end)
end
