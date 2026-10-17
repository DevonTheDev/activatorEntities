-- Finite callback-double acceptance cases for pending queue moves.
-- No Start/Cancel/Use, packet, grant, definition-copy or shared batch Undo routes.
return function(gmod, test, eq)
    local upvalue = dofile("tests/find-upvalue.lua")
    local A, B, C, D = "Move A", "Move B", "Move C", "Move D"
    local function state(e, key) return upvalue(e.timers.activatorSpawner.callback, key) end
    local function setState(e, key, value)
        local seen, visits = {}, 0
        local function visit(fn, depth)
            if seen[fn] or depth > 32 then return false end
            seen[fn] = true; visits = visits + 1; assert(visits <= 256, "closure traversal cap")
            for i=1,100 do
                local name = debug.getupvalue(fn,i); if not name then break end
                if name == key then debug.setupvalue(fn,i,value); return true end
            end
            for i=1,100 do
                local name, child = debug.getupvalue(fn,i); if not name then break end
                if type(child)=="function" and visit(child,depth+1) then return true end
            end
            return false
        end
        assert(visit(e.timers.activatorSpawner.callback,0),"missing state seam " .. key)
    end
    local function command(e,p,text) return e.hooks.PlayerSay.manageActivatorEventQueue(p,text) end
    local function setup(count, maximum)
        local e = gmod.new(); local p = e.entity("player"); p.admin=true
        for i,name in ipairs({A,B,C,D}) do
            e.NPCEdits[6+i]={name=name,information={activatorModel="models/alyx.mdl",npcPath="npc_combine_s",maxNPCs=2,dialogue="Move fixture."}}
        end
        e.maxActivators=maximum or 1; e.determineRandomEvent=function() return "Raid" end
        for i=1,(count or 0) do eq(command(e,p,"!queueEvent " .. ({A,B,C,D})[(i-1)%4+1]),"") end
        return e,p
    end
    local function snapshot(e)
        local out={}; for i,item in ipairs(state(e,"encounterQueue")) do out[i]=item end; return out
    end
    local function exact(e, expected)
        local q=state(e,"encounterQueue"); eq(#q,#expected,"length")
        for i,item in ipairs(expected) do eq(q[i],item,"occurrence identity at " .. i) end
    end
    local function textContains(text,part) assert(text:find(part,1,true),"missing expected reply fragment " .. part) end
    local function move(e,p,text)
        local first=#p.chats+1; eq(command(e,p,text),"","recognized move remains private")
        local lines={}
        for i=first,#p.chats do
            assert(#p.chats[i]<=255 and not p.chats[i]:find("%c"),"bounded sanitized feedback")
            lines[#lines+1]=p.chats[i]
        end
        return table.concat(lines,"\n")
    end
    local function forbid(e, callback)
        local saved,attempted={},{}
        local function deny(owner,key)
            saved[#saved+1]={owner,key,owner[key]}
            owner[key]=function() attempted[#attempted+1]=key; error("forbidden move effect " .. key) end
        end
        for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnActivatorSpawns","hasActivatorSpawns","returnMaxActivators","destroyActivators"}) do deny(e,key) end
        for _,key in ipairs({"Create","Start","Stop","Simple"}) do deny(e.timer,key) end
        for _,key in ipairs({"Read","Write"}) do deny(e.file,key) end
        for _,key in ipairs({"Start","Send","Broadcast"}) do deny(e.net,key) end
        for _,key in ipairs({"Create","FindByClass","FindByName"}) do deny(e.ents,key) end
        local ok,problem=pcall(callback)
        for _,entry in ipairs(saved) do entry[1][entry[2]]=entry[3] end
        assert(ok,problem); eq(#attempted,0,"no swallowed forbidden side effects")
    end
    local function attempt(e) return e.timers.activatorSpawner.callback() end
    local function ready(e)
        local out={}; for _,actor in ipairs(e.entities) do
            if actor.class=="activatorent" and actor.valid and not actor.markedForDeletion then out[#out+1]=actor end
        end; return out
    end
    local function removeReady(e) for _,actor in ipairs(ready(e)) do actor:Remove() end end
    local function refuseDuringAttempt(e,p,phase)
        assert(state(e,"spawnAttemptDepth")>0,"positive depth at " .. phase)
        local before=snapshot(e); local claim=state(e,"queueClaim")
        local settled=claim and claim.settled; local retired=claim and claim.retired
        for _,text in ipairs({"!moveQueuedEvent 1 2","!moveQueuedEvent 1 1"}) do
            textContains(move(e,p,text),"spawn attempt is in flight")
            exact(e,before); eq(state(e,"queueClaim"),claim); eq(claim and claim.settled,settled); eq(claim and claim.retired,retired)
        end
    end
    local function wrapSpawn(e,callback)
        local create=e.ents.Create; local count=0
        e.ents.Create=function(class)
            local actor=create(class)
            if class=="activatorent" then
                local spawn=actor.Spawn
                actor.Spawn=function(self) count=count+1; callback(self,count); return spawn(self) end
            end
            return actor
        end
    end

    test("QM01 six stable final-position moves",6,function()
        for _,case in ipairs({{1,4,{2,3,4,1}},{4,1,{4,1,2,3}},{2,4,{1,3,4,2}},{3,1,{3,1,2,4}},{2,3,{1,3,2,4}},{3,2,{1,3,2,4}}}) do
            local e,p=setup(4); local q=snapshot(e); local expected={}
            for i,index in ipairs(case[3]) do expected[i]=q[index] end
            textContains(move(e,p,"!moveQueuedEvent " .. case[1] .. " " .. case[2]),"live position " .. case[1] .. " -> " .. case[2])
            exact(e,expected)
        end
    end)
    test("QM02 duplicate names preserve occurrence identity",1,function()
        local e,p=setup(1); command(e,p,"!queueEvent " .. A); command(e,p,"!queueEvent " .. B)
        local q=snapshot(e); assert(q[1]~=q[2]); move(e,p,"!moveQueuedEvent 2 3"); exact(e,{q[1],q[3],q[2]})
    end)
    test("QM03 idle same-position request preserves queue and reports no-op",1,function()
        local e,p=setup(4); local q=snapshot(e); local tableIdentity=state(e,"encounterQueue")
        textContains(move(e,p,"!moveQueuedEvent 2 2"),"already at live position 2; unchanged")
        exact(e,q); eq(state(e,"encounterQueue"),tableIdentity)
    end)
    test("QM04 fixed malformed and out-of-range matrix preserves identity",1,function()
        local e,p=setup(4); local q=snapshot(e)
        for _,text in ipairs({"!moveQueuedEvent","!moveQueuedEvent ","!moveQueuedEvent 1","!moveQueuedEvent 1 2 extra","!moveQueuedEvent  1 2","!moveQueuedEvent 1  2","!moveQueuedEvent 1 2 ","!moveQueuedEvent\t1 2","!moveQueuedEvent 1\t2","!moveQueuedEvent +1 2","!moveQueuedEvent 1 -2","!moveQueuedEvent 0 2","!moveQueuedEvent 1 0","!moveQueuedEvent 01 2","!moveQueuedEvent 1 02","!moveQueuedEvent 1.0 2","!moveQueuedEvent 1 2.0","!moveQueuedEvent 1e0 2","!moveQueuedEvent 1 2e0","!moveQueuedEvent 99999999999999999999 2","!moveQueuedEvent 1 99999999999999999999","!moveQueuedEvent 5 1","!moveQueuedEvent 1 5","!moveQueuedEvent 17 1","!moveQueuedEvent 1 17"}) do
            local reply=move(e,p,text); assert(reply:find("Usage",1,true) or reply:find("both live positions",1,true)); exact(e,q)
        end
    end)
    test("QM05 empty queue rejects valid positions",1,function()
        local e,p=setup(); textContains(move(e,p,"!moveQueuedEvent 1 1"),"both live positions"); exact(e,{})
    end)
    test("QM06 full queue moves without append admission",1,function()
        local e,p=setup(16); local q=snapshot(e); local expected={q[16]}; for i=1,15 do expected[i+1]=q[i] end
        forbid(e,function() move(e,p,"!moveQueuedEvent 16 1") end); exact(e,expected)
    end)
    test("QM07 unavailable name moves without configuration lookup",1,function()
        local e,p=setup(3); local q=snapshot(e); local reads=0
        e.NPCEdits=setmetatable({},{__pairs=function() reads=reads+1; error("configuration must not be inspected") end})
        forbid(e,function() move(e,p,"!moveQueuedEvent 1 3") end); eq(reads,0); exact(e,{q[2],q[3],q[1]})
    end)
    test("QM08 dead admin remains permitted",1,function()
        local e,p=setup(2); local q=snapshot(e); p.alive=false; move(e,p,"!moveQueuedEvent 2 1"); exact(e,{q[2],q[1]})
    end)
    test("QM09 invalid nonplayer and nonadmin callers remain private",1,function()
        local e,p=setup(2); local q=snapshot(e)
        local invalid=e.entity("player"); invalid.admin=true; invalid.valid=false
        local nonplayer=e.entity("prop_physics"); nonplayer.admin=true
        local visitor=e.entity("player")
        for _,caller in ipairs({invalid,nonplayer,visitor}) do eq(command(e,caller,"!moveQueuedEvent 2 1"),""); exact(e,q) end
        eq(#invalid.chats,0); eq(#nonplayer.chats,0); textContains(visitor.chats[1],"Only admins")
    end)
    test("QM10 permission loss at final callback leaves queue unchanged",1,function()
        local e,p=setup(2); local q=snapshot(e); local calls=0
        p.IsAdmin=function() calls=calls+1; return calls==1 end
        eq(command(e,p,"!moveQueuedEvent 2 1"),""); eq(calls,2); exact(e,q)
    end)
    test("QM11 permission getter errors stay private and preserve queue",1,function()
        local e,p=setup(2); local q=snapshot(e)
        for _,stage in ipairs({"valid","player","admin"}) do
            local valid,player,admin=e.IsValid,p.IsPlayer,p.IsAdmin
            if stage=="valid" then e.IsValid=function() error("valid getter") end
            elseif stage=="player" then p.IsPlayer=function() error("player getter") end
            else p.IsAdmin=function() error("admin getter") end end
            eq(command(e,p,"!moveQueuedEvent 2 1"),""); exact(e,q)
            e.IsValid,p.IsPlayer,p.IsAdmin=valid,player,admin
        end
    end)
    test("QM12 final permission callback edits resolve fresh live positions",1,function()
        local e,p=setup(4); local q=snapshot(e); local calls=0; local original=p.IsAdmin
        p.IsAdmin=function(self)
            calls=calls+1
            if calls==2 then p.IsAdmin=original; command(e,p,"!dropQueuedEvent") end
            return true
        end
        textContains(move(e,p,"!moveQueuedEvent 3 1"),D); exact(e,{q[4],q[2],q[3]})
    end)
    test("QM13 final permission callback shrinking queue triggers fresh bounds",1,function()
        local e,p=setup(4); local q=snapshot(e); local calls=0; local original=p.IsAdmin
        p.IsAdmin=function(self)
            calls=calls+1
            if calls==2 then p.IsAdmin=original; command(e,p,"!dropQueuedEvent") end
            return true
        end
        textContains(move(e,p,"!moveQueuedEvent 4 1"),"both live positions"); exact(e,{q[2],q[3],q[4]})
    end)
    test("QM14 final permission callback depth change refuses even no-op",1,function()
        local e,p=setup(2); local q=snapshot(e); local calls=0; local original=p.IsAdmin
        p.IsAdmin=function(self)
            calls=calls+1
            if calls==2 then p.IsAdmin=original; setState(e,"spawnAttemptDepth",1) end
            return true
        end
        textContains(move(e,p,"!moveQueuedEvent 1 1"),"spawn attempt is in flight"); exact(e,q)
        setState(e,"spawnAttemptDepth",0)
    end)
    test("QM15 reply reentry never repeats move and preserves captured fields",1,function()
        local e,p=setup(4); local q=snapshot(e); local entered=false; local print=p.ChatPrint
        p.ChatPrint=function(self,line)
            print(self,line)
            if not entered then entered=true; exact(e,{q[2],q[3],q[1],q[4]}); command(e,p,"!clearEventQueue"); command(e,p,"!queueEvent " .. D) end
        end
        local reply=move(e,p,"!moveQueuedEvent 1 3"); textContains(reply,'Moved pending encounter: "' .. A .. '" (live position 1 -> 3).')
        eq(entered,true); local after=snapshot(e); eq(#after,1); eq(after[1].name,D); assert(after[1]~=q[4])
    end)
    test("QM16 move no-op usage and refusal have no unrelated side effects",1,function()
        local e,p=setup(3); local q=snapshot(e); local generation=state(e,"spawnScheduleGeneration")
        local selection=e.hooks.PlayerSay.selectNextActivatorEvent
        local catalog=upvalue(selection,"catalogGeneration"); local inspections=upvalue(selection,"catalogInspections")
        forbid(e,function()
            move(e,p,"!moveQueuedEvent 3 1"); move(e,p,"!moveQueuedEvent 1 1"); move(e,p,"!moveQueuedEvent 0 1")
            setState(e,"spawnAttemptDepth",1); move(e,p,"!moveQueuedEvent 1 2"); setState(e,"spawnAttemptDepth",0)
        end)
        exact(e,{q[3],q[1],q[2]}); eq(state(e,"spawnScheduleGeneration"),generation)
        eq(upvalue(selection,"catalogGeneration"),catalog); eq(upvalue(selection,"catalogInspections"),inspections)
    end)
    test("QM17 pre-claim callback refuses move and no-op",1,function()
        local e,p=setup(4); local q=snapshot(e); local original=e.ents.FindByClass; local entered=false
        e.ents.FindByClass=function(class)
            if class=="activatorent" and not entered then entered=true; eq(state(e,"queueClaim"),nil); refuseDuringAttempt(e,p,"pre-claim") end
            return original(class)
        end
        attempt(e); eq(entered,true); exact(e,{q[2],q[3],q[4]}); eq(state(e,"spawnAttemptDepth"),0)
    end)
    test("QM18 unsettled claim getter refuses move and no-op",1,function()
        local e,p=setup(4); local q=snapshot(e); local original=e.returnNPCInformation; local entered=false
        e.returnNPCInformation=function(...)
            if not entered then entered=true; eq(state(e,"queueClaim").settled,false); refuseDuringAttempt(e,p,"unsettled") end
            return original(...)
        end
        attempt(e); eq(entered,true); exact(e,{q[2],q[3],q[4]}); eq(state(e,"queueClaim"),nil)
    end)
    test("QM19 first Spawn refuses move and no-op",1,function()
        local e,p=setup(4); local q=snapshot(e); local entered=false
        wrapSpawn(e,function(_,count) eq(count,1); entered=true; eq(state(e,"queueClaim").settled,false); refuseDuringAttempt(e,p,"first Spawn") end)
        attempt(e); eq(entered,true); exact(e,{q[2],q[3],q[4]}); eq(ready(e)[1].EventIdentifier,A)
    end)
    test("QM20 settled later Spawn refuses move and no-op",1,function()
        local e,p=setup(4,2); local q=snapshot(e); local entered=false
        wrapSpawn(e,function(_,count) if count==2 then entered=true; eq(state(e,"queueClaim").settled,true); refuseDuringAttempt(e,p,"later Spawn") end end)
        attempt(e); eq(entered,true); eq(#ready(e),2); exact(e,{q[2],q[3],q[4]})
    end)
    test("QM21 retired claim callback refuses move and no-op",1,function()
        local e,p=setup(4); local q=snapshot(e); local entered=false
        wrapSpawn(e,function() entered=true; state(e,"clearSelectedBatch")(); eq(state(e,"queueClaim").retired,true); refuseDuringAttempt(e,p,"retired") end)
        attempt(e); eq(entered,true); exact(e,q); eq(state(e,"queueClaim"),nil); eq(state(e,"selectedBatchName"),nil)
    end)
    test("QM22 nested attempt depth refuses moves until outer unwind",1,function()
        local e,p=setup(4,2); local q=snapshot(e); local entered=false
        wrapSpawn(e,function(_,count)
            if count==1 then attempt(e)
            elseif count==2 then entered=true; eq(state(e,"spawnAttemptDepth"),2); refuseDuringAttempt(e,p,"nested") end
        end)
        attempt(e); eq(entered,true); exact(e,{q[2],q[3],q[4]}); eq(state(e,"spawnAttemptDepth"),0)
        move(e,p,"!moveQueuedEvent 3 1"); exact(e,{q[4],q[2],q[3]})
    end)
    test("QM23 moved head is consumed exactly once by ordinary selection",1,function()
        local e,p=setup(4); local q=snapshot(e); move(e,p,"!moveQueuedEvent 3 1")
        attempt(e); eq(ready(e)[1].EventIdentifier,C); exact(e,{q[1],q[2],q[4]})
        removeReady(e); attempt(e); eq(ready(e)[1].EventIdentifier,A); exact(e,{q[2],q[4]})
    end)
    test("QM24 ready ownership and override priority survive pending move",1,function()
        local e,p=setup(4,2); e.fire("PlayerSay",p,"!nextEvent " .. D); attempt(e)
        local owners=state(e,"selectedBatchEntities"); local q=snapshot(e)
        e.fire("PlayerSay",p,"!nextEvent " .. B); local pending=state(e,"pendingSelection")
        move(e,p,"!moveQueuedEvent 3 1"); exact(e,{q[3],q[1],q[2],q[4]}); eq(state(e,"selectedBatchEntities"),owners); eq(state(e,"pendingSelection"),pending)
        ready(e)[1]:Remove(); attempt(e); eq(ready(e)[1].EventIdentifier,D); exact(e,{q[3],q[1],q[2],q[4]})
        removeReady(e); attempt(e); eq(ready(e)[1].EventIdentifier,B); exact(e,{q[3],q[1],q[2],q[4]})
        removeReady(e); attempt(e); eq(ready(e)[1].EventIdentifier,C); exact(e,{q[1],q[2],q[4]})
    end)
    test("QM25 active paused lifecycle seam permits pending moves only",1,function()
        local e,p=setup(4); local q=snapshot(e)
        setState(e,"eventActive",true); e.fire("PlayerSay",p,"!pauseActivatorSpawns")
        local generation=state(e,"spawnScheduleGeneration")
        forbid(e,function() move(e,p,"!moveQueuedEvent 4 2") end)
        exact(e,{q[1],q[4],q[2],q[3]}); eq(state(e,"eventActive"),true); eq(state(e,"automaticSpawnsPaused"),true); eq(state(e,"spawnScheduleGeneration"),generation)
        e.fire("PlayerSay",p,"!resumeActivatorSpawns"); exact(e,{q[1],q[4],q[2],q[3]})
        e.stopActivatorEvent(); exact(e,{q[1],q[4],q[2],q[3]})
        e.fire("PlayerSay",p,"!refreshActivators"); exact(e,{q[1],q[4],q[2],q[3]})
    end)
    test("QM26 long control and UTF8 names retain bounded reply metadata",1,function()
        local e,p=setup(1); local long="Long\n\t" .. string.rep("\195\169",150)
        e.NPCEdits[90]={name=long,information=e.NPCEdits[7].information}; command(e,p,"!queueEvent " .. long)
        local q=snapshot(e); local reply=move(e,p,"!moveQueuedEvent 2 1"); textContains(reply,"live position 2 -> 1"); exact(e,{q[2],q[1]})
        local line=p.chats[#p.chats]; eq(#line<=255,true); assert(not line:find("%c")); assert(not line:find("\195%.%.%.",1))
    end)
    test("QM27 literal help describes live positions and explicit refusal",1,function()
        local e,p=setup(2); local q=snapshot(e)
        forbid(e,function() e.fire("PlayerSay",p,"!activatorHelp events"); command(e,p,"!eventQueue") end)
        local all=table.concat(p.chats,"\n"); textContains(all,"!moveQueuedEvent <from> <to>"); textContains(all,"final position"); textContains(all,"same position does nothing")
        textContains(all,"Live positions can change between commands/admins"); textContains(all,"Moves are refused during an in-flight spawn attempt; retry after it finishes")
        for _,line in ipairs(p.chats) do assert(#line<=255) end; exact(e,q)
    end)
    test("QM28 exact recognition leaves unrelated commands alone",1,function()
        local e,p=setup(2); local q=snapshot(e); local count=#p.chats
        for _,text in ipairs({"!MoveQueuedEvent 2 1","!moveQueuedEvents 2 1"," !moveQueuedEvent 2 1","!moveNextEvent 2 1","hello"}) do eq(command(e,p,text),nil) end
        eq(#p.chats,count); exact(e,q)
    end)
    test("QM29 final permission error preserves queue",1,function()
        local e,p=setup(2); local q=snapshot(e); local calls=0
        p.IsAdmin=function() calls=calls+1; if calls==2 then error("final permission getter") end; return true end
        eq(command(e,p,"!moveQueuedEvent 2 1"),""); eq(calls,2); exact(e,q)
    end)
    test("QM30 permission callback selection uses fresh post-attempt positions",1,function()
        local e,p=setup(4); local q=snapshot(e); local calls=0; local original=p.IsAdmin
        p.IsAdmin=function(self)
            calls=calls+1
            if calls==2 then p.IsAdmin=original; attempt(e) end
            return true
        end
        textContains(move(e,p,"!moveQueuedEvent 3 1"),D)
        eq(ready(e)[1].EventIdentifier,A); exact(e,{q[4],q[2],q[3]}); eq(state(e,"spawnAttemptDepth"),0)
    end)
    test("QM31 reply permission reentry retains committed name and positions",1,function()
        local e,p=setup(3); local q=snapshot(e); local calls=0; local original=p.IsAdmin
        p.IsAdmin=function(self)
            calls=calls+1
            if calls==3 then p.IsAdmin=original; exact(e,{q[2],q[3],q[1]}); command(e,p,"!clearEventQueue") end
            return true
        end
        local reply=move(e,p,"!moveQueuedEvent 1 3"); textContains(reply,'Moved pending encounter: "' .. A .. '" (live position 1 -> 3).')
        exact(e,{})
    end)
end
