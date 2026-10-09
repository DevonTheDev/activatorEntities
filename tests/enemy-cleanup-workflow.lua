-- End-to-end command, interaction, progress and normal timer workflows using
-- actual addon handlers. Native Garry's Mod behavior still needs a smoke check.
return function(gmod,test,eq)
    local function say(env,admin,text)
        eq(env.fire("PlayerSay",admin,text),"","actual private command reached")
    end
    local function inspect(env,admin) say(env,admin,"!listEventEnemies") end
    local function remove(env,admin,enemy) say(env,admin,"!removeEventEnemy " .. enemy.index) end
    local function fixture(count)
        local env=gmod.new(); local info=env.NPCEdits[1].information; info.maxNPCs=count or 3
        env.NPCEdits[2]={name="After cleanup",information={activatorModel=info.activatorModel,
            npcPath="npc_combine_s",maxNPCs=2,dialogue="The queued encounter."}}
        env.determineRandomEvent=function() return "Raid" end
        local admin=env.entity("player"); admin.admin=true
        return env,admin
    end
    local function start(env,admin)
        local first=#env.entities+1
        env.fireTimer("activatorSpawner")
        local actor=assert(env.ents.FindByClass("activatorent")[1],"normal timer created activators")
        admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
        local client=gmod.new(true)
        local opened=env.messages[#env.messages]
        eq(opened.name,"OpenInteractionMenu"); client.deliver(opened)
        client.panels[3]:DoClick()
        for _,message in ipairs(client.messages) do env.deliver(message,admin) end
        local enemies={}
        for i=first,#env.entities do
            local enemy=env.entities[i]
            if enemy.name=="devonsSpawnedEntity" and enemy.valid then enemies[#enemies+1]=enemy end
        end
        eq(env.totalEnemies,#enemies); return enemies
    end
    local function finish(env,admin,enemies,victories)
        for _,enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
        eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),victories)
        eq(env.timers.activatorSpawner.stopped,false)
    end

    test("targeted cleanup workflow preserves survivors and queued encounter through the next normal timer",function()
        local env,admin=fixture(); local enemies=start(env,admin)
        say(env,admin,"!nextEvent After cleanup")
        local observer=env.entity("player"); inspect(env,admin)
        remove(env,admin,enemies[2])
        eq(env.totalEnemies,2); eq(enemies[1].valid,true); eq(enemies[3].valid,true)
        eq(#observer.chats,0); eq(env.messageCount("entitiesDeleted"),0)
        local progress=env.messages[#env.messages]; eq(progress.name,"ActivatorEventStatus")
        eq(progress.values[3],2); eq(progress.values[4],3); eq(progress.values[5],true)
        local client=gmod.new(true); client.deliver(progress); eq(client.netReads,5)
        finish(env,admin,enemies,0)
        local nextEnemies=start(env,admin); eq(#nextEnemies,2)
        for _,enemy in ipairs(nextEnemies) do eq(enemy.class,"npc_combine_s") end
        finish(env,admin,nextEnemies,1)
    end)
    test("targeted cleanup of the last enemy restarts the normal timer exactly once after the removal callback",function()
        local env,admin=fixture(1); local enemies=start(env,admin); inspect(env,admin)
        local original,starts=env.timer.Start,0
        env.timer.Start=function(name) if name=="activatorSpawner" then starts=starts+1 end; original(name) end
        env.deferRemoval=true; remove(env,admin,enemies[1])
        eq(starts,0); eq(env.totalEnemies,1); eq(env.timers.activatorSpawner.stopped,true)
        env.flushRemovals(); eq(starts,1); eq(env.totalEnemies,0)
        eq(env.messages[#env.messages].values[1],false); eq(env.messageCount("roundFinished"),0)
        env.fire("EntityRemoved",enemies[1]); env.fire("OnNPCKilled",enemies[1],admin); remove(env,admin,enemies[1])
        eq(starts,1); eq(env.totalEnemies,0); eq(env.messageCount("entitiesDeleted"),0)
        env.deferRemoval=false; local replacement=start(env,admin); finish(env,admin,replacement,1)
    end)
    for _,boundary in ipairs({"EntIndex","IsMarkedForDeletion"}) do
        test("targeted cleanup refuses replacement during admission " .. boundary,function()
            local env,admin=fixture(2); local enemies=start(env,admin); inspect(env,admin)
            local target=enemies[1]; local old=target[boundary]; local changed,replacement=false,nil
            target[boundary]=function(self)
                if not changed then
                    changed=true; env.stopActivatorEvent(); replacement=start(env,admin)
                    replacement[1].index=target.index
                end
                return old(self)
            end
            remove(env,admin,target)
            assert(changed and replacement,"actual entity getter replaced the encounter")
            eq(env.totalEnemies,2)
            for _,enemy in ipairs(replacement) do eq(enemy.valid,true); eq(enemy.markedForDeletion,nil) end
            finish(env,admin,replacement,1)
        end)
    end
    test("targeted cleanup removal callback can retire and replace without interrupting the replacement",function()
        local env,admin=fixture(2); local enemies=start(env,admin); inspect(env,admin)
        local replacement
        enemies[1].OnRemove=function(self)
            self.OnRemove=nil
            env.stopActivatorEvent(); replacement=start(env,admin)
        end
        remove(env,admin,enemies[1]); assert(replacement)
        eq(env.totalEnemies,2); finish(env,admin,replacement,1)
        eq(env.messageCount("entitiesDeleted"),0)
    end)
    test("targeted cleanup stale inspection capture cannot install authority for a replacement",function()
        local env,admin=fixture(2); local enemies=start(env,admin); local replacement
        enemies[1].GetPos=function(self)
            self.GetPos=function(entity) return entity.pos end
            env.stopActivatorEvent(); replacement=start(env,admin); replacement[1].index=self.index
            return self.pos
        end
        inspect(env,admin); remove(env,admin,replacement[1])
        eq(env.totalEnemies,2); finish(env,admin,replacement,1)
    end)
    test("targeted cleanup outer listing cannot restore authority after a newer reentrant page",function()
        local env,admin=fixture(9); local enemies=start(env,admin)
        local print=admin.ChatPrint; local fired=false
        admin.ChatPrint=function(self,line)
            print(self,line)
            if not fired then fired=true; say(env,admin,"!listEventEnemies 2") end
        end
        inspect(env,admin); admin.ChatPrint=print
        remove(env,admin,enemies[1]); eq(env.totalEnemies,9)
        remove(env,admin,enemies[9]); eq(env.totalEnemies,8)
    end)
    test("targeted cleanup listing grants only private selection with no gameplay side effects",function()
        local env,admin=fixture(2); local enemies=start(env,admin)
        say(env,admin,"!nextEvent After cleanup")
        local restore={}
        local function forbid(owner,key)
            restore[#restore+1]={owner,key,owner[key]}
            owner[key]=function() error("inspection invoked " .. key) end
        end
        for _,owner in ipairs({env.timer,env.file,env.net}) do
            local keys={}; for key,value in pairs(owner) do if type(value)=="function" then keys[#keys+1]=key end end
            for _,key in ipairs(keys) do forbid(owner,key) end
        end
        for _,enemy in ipairs(env.entities) do
            for _,key in ipairs({"Remove","Spawn","SetPos","SetHealth","SetName","SetModel"}) do forbid(enemy,key) end
        end
        env.math=setmetatable({},{__index=math}); forbid(env.math,"random"); forbid(env.math,"randomseed")
        for _,key in ipairs({"Create","FindByClass","FindByName"}) do forbid(env.ents,key) end
        local ok,err=pcall(function() inspect(env,admin); inspect(env,admin) end)
        for _,entry in ipairs(restore) do entry[1][entry[2]]=entry[3] end
        assert(ok,err); eq(env.totalEnemies,2); eq(env.timers.activatorSpawner.stopped,true)
        remove(env,admin,enemies[1]); finish(env,admin,enemies,0)
        eq(#start(env,admin),2)
        eq(env.messages[#env.messages].values[2],"After cleanup","listing kept queued choice")
    end)
end
