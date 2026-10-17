-- Focused encounter-queue contract tests. Drafted without execution.
-- Uses published doubles; no interaction, packet, enemy-admission, persistence,
-- loader, backup or definition-copy tests are called here.
return function(gmod, test, eq)
    local upvalue = dofile("tests/find-upvalue.lua")
    local A, B, C = "Queue A", "Queue B", "Queue C"
    local function setup(maximum)
        local env = gmod.new()
        local admin = env.entity("player"); admin.admin = true
        for i, name in ipairs({A, B, C}) do
            env.NPCEdits[6+i] = {name=name, information={activatorModel="models/alyx.mdl",
                npcPath="npc_combine_s", maxNPCs=2, dialogue="Queue fixture."}}
        end
        env.maxActivators = maximum == nil and 1 or maximum
        env.determineRandomEvent = function() return "Raid" end
        return env, admin
    end
    local function state(env, name)
        return upvalue(env.timers.activatorSpawner.callback, name)
    end
    local function setState(env, wanted, replacement)
        local seen = {}
        local function visit(fn, depth)
            if seen[fn] or depth > 32 then return false end
            seen[fn] = true
            for i=1,100 do
                local name = debug.getupvalue(fn, i)
                if not name then break end
                if name == wanted then debug.setupvalue(fn, i, replacement); return true end
            end
            for i=1,100 do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                if type(value) == "function" and visit(value, depth+1) then return true end
            end
            return false
        end
        assert(visit(env.timers.activatorSpawner.callback, 0), "missing test seam " .. wanted)
    end
    local function say(env, admin, text) return env.fire("PlayerSay", admin, text) end
    local function queue(env, admin, name)
        eq(say(env, admin, "!queueEvent " .. name), "", "private append")
    end
    local function names(env, expected)
        local items = state(env, "encounterQueue")
        eq(#items, #expected, "queue size")
        for i, name in ipairs(expected) do eq(items[i].name, name, "queue row " .. i) end
        return items
    end
    local function ready(env)
        local result = {}
        for _, actor in ipairs(env.entities) do
            if actor.class == "activatorent" and actor.valid and not actor.markedForDeletion then
                result[#result+1] = actor
            end
        end
        return result
    end
    local function attempt(env) return env.timers.activatorSpawner.callback() end
    local function removeReady(env)
        for _, actor in ipairs(ready(env)) do actor:Remove() end
    end
    local function contains(text, fragment)
        assert(text:find(fragment, 1, true), "expected " .. fragment .. " in " .. text)
    end
    local function replies(env, admin, text)
        local first = #admin.chats+1
        eq(say(env, admin, text), "", "private command")
        local lines = {}
        for i=first,#admin.chats do
            local line = admin.chats[i]
            assert(#line <= 255 and not line:find("%c"), "bounded sanitized private line")
            lines[#lines+1] = line
        end
        return table.concat(lines, "\n"), lines
    end
    local function owners(env, expected, name)
        local actual = state(env, "selectedBatchEntities")
        local count = 0
        for actor in pairs(actual) do
            count=count+1
            local found=false
            for _, wanted in ipairs(expected) do if actor == wanted then found=true end end
            assert(found, "unexpected selected owner")
        end
        eq(count,#expected,"selected owner count")
        eq(state(env,"selectedBatchName"),name,"selected name")
        return actual
    end
    local function onceSpawn(env, callback, before)
        local create, entered = env.ents.Create, false
        env.ents.Create = function(class)
            local actor = create(class)
            if class == "activatorent" and env.IsValid(actor) then
                local spawn = actor.Spawn
                actor.Spawn = function(self)
                    if before and not entered then entered=true; callback(self) end
                    spawn(self)
                    if not before and not entered then entered=true; callback(self) end
                end
            end
            return actor
        end
        return function() assert(entered,"expected Spawn callback") end
    end
    local function idleClaim(env)
        eq(state(env,"queueClaim"),nil,"claim released at outer unwind")
        eq(state(env,"spawnAttemptDepth"),0,"attempt depth released")
    end
    local function forbidEffects(env, callback)
        local saved, attempted = {}, {}
        local function forbid(owner,key)
            saved[#saved+1]={owner,key,owner[key]}
            owner[key]=function()
                attempted[#attempted+1]=key
                error("unexpected queue-command effect: " .. key)
            end
        end
        for _,key in ipairs({"determineRandomEvent","returnActivatorSpawns","destroyActivators"}) do forbid(env,key) end
        for _,key in ipairs({"Start","Stop","Create","Simple"}) do forbid(env.timer,key) end
        for _,key in ipairs({"Write","Read"}) do forbid(env.file,key) end
        for _,key in ipairs({"Start","Send","Broadcast"}) do forbid(env.net,key) end
        forbid(env.ents,"Create")
        local ok,err=pcall(callback)
        for _,entry in ipairs(saved) do entry[1][entry[2]]=entry[3] end
        assert(ok,err)
        eq(#attempted,0,"no swallowed forbidden effect: " .. table.concat(attempted,","))
    end

    test("CQ01 FIFO A B C then random fallback",function()
        local env,admin=setup()
        for _,name in ipairs({A,B,C}) do queue(env,admin,name) end
        names(env,{A,B,C})
        for _,name in ipairs({A,B,C,"Raid"}) do
            attempt(env); eq(#ready(env),1); eq(ready(env)[1].EventIdentifier,name)
            removeReady(env)
        end
        names(env,{}); idleClaim(env)
    end)
    test("CQ02 repeats have distinct item identity and consume once per batch",function()
        local env,admin=setup(3); queue(env,admin,A); queue(env,admin,A)
        local items=names(env,{A,A}); local first,second=items[1],items[2]
        assert(first~=second,"repeated names must have distinct item identities")
        attempt(env); eq(#ready(env),3); eq(names(env,{A})[1],second)
        ready(env)[1]:Remove(); attempt(env); names(env,{A}); eq(#ready(env),3)
        removeReady(env); attempt(env); names(env,{}); eq(#ready(env),3)
    end)
    test("CQ03 cap sixteen rejects seventeenth and drop reopens one slot",function()
        local env,admin=setup()
        for _=1,16 do queue(env,admin,A) end
        local items=state(env,"encounterQueue"); local head,tail=items[1],items[16]
        queue(env,admin,B); eq(#state(env,"encounterQueue"),16); eq(items[1],head); eq(items[16],tail)
        eq(say(env,admin,"!dropQueuedEvent"),""); eq(#state(env,"encounterQueue"),15)
        queue(env,admin,B); eq(#state(env,"encounterQueue"),16); eq(state(env,"encounterQueue")[16].name,B)
    end)
    for _,case in ipairs({
        {label="unknown",name="Missing",reason="unknown"},
        {label="duplicate",name=A,reason="duplicate",apply=function(e) e.NPCEdits[90]=e.NPCEdits[7] end},
        {label="missing information",name=A,reason="information",apply=function(e) e.NPCEdits[7].information=nil end},
    }) do
        test("CQ04 invalid append " .. case.label .. " preserves future sources",function()
            local env,admin=setup(); queue(env,admin,B); say(env,admin,"!nextEvent " .. C)
            local head=names(env,{B})[1]; local pending=state(env,"pendingSelection")
            if case.apply then case.apply(env) end
            contains(replies(env,admin,"!queueEvent " .. case.name),case.reason)
            eq(names(env,{B})[1],head); eq(state(env,"pendingSelection"),pending)
        end)
    end
    test("CQ05 append preserves exact case spaces punctuation and one separator",function()
        local env,admin=setup(); local exact="  Raid: alpha! "
        env.NPCEdits[90]={name=exact,information=env.NPCEdits[7].information}
        queue(env,admin,exact); names(env,{exact})
        queue(env,admin,"Queue a"); queue(env,admin,"Queue A "); names(env,{exact})
        eq(say(env,admin,"!queueEvent\t" .. B),""); names(env,{exact,B})
    end)
    for _,command in ipairs({"!queueEvent","!queueEvent ","!eventQueue extra","!eventQueue ","!dropQueuedEvent extra","!clearEventQueue extra"}) do
        test("CQ06 malformed syntax leaves queue intact: " .. command,function()
            local env,admin=setup(); queue(env,admin,A)
            contains(replies(env,admin,command),"Usage")
            names(env,{A})
        end)
    end
    test("CQ07 exact command recognition leaves unrelated chat alone",function()
        local env,admin=setup()
        for _,command in ipairs({"hello","!queueEventual " .. A,"!QueueEvent " .. A," !eventQueue","!eventQueueMore"}) do
            eq(say(env,admin,command),nil)
        end
        eq(#admin.chats,0); names(env,{})
    end)
    test("CQ08 dead admins manage queue while invalid and non-admin callers cannot",function()
        local env,admin=setup(); admin.alive=false; queue(env,admin,A)
        local visitor=env.entity("player")
        for _,command in ipairs({"!queueEvent " .. B,"!eventQueue","!dropQueuedEvent","!clearEventQueue"}) do
            eq(say(env,visitor,command),""); names(env,{A})
        end
        local count=#visitor.chats; visitor.valid=false
        for _,command in ipairs({"!queueEvent " .. B,"!eventQueue","!dropQueuedEvent","!clearEventQueue"}) do say(env,visitor,command) end
        eq(#visitor.chats,count); names(env,{A})
        eq(say(env,admin,"!dropQueuedEvent"),""); names(env,{})
        contains(replies(env,admin,"!dropQueuedEvent"),"empty")
        contains(replies(env,admin,"!clearEventQueue"),"empty")
    end)
    test("CQ09 queue commands never create combat actors timers saves or RNG",function()
        local env,admin=setup(); local generation=state(env,"spawnScheduleGeneration")
        local selection=env.hooks.PlayerSay.selectNextActivatorEvent
        local references=upvalue(selection,"catalogGeneration")
        local inspections=upvalue(selection,"catalogInspections")
        forbidEffects(env,function()
            queue(env,admin,A); queue(env,admin,B); replies(env,admin,"!eventQueue")
            say(env,admin,"!dropQueuedEvent"); say(env,admin,"!clearEventQueue")
        end)
        names(env,{}); eq(#ready(env),0); eq(env.totalEnemies,0)
        eq(state(env,"spawnScheduleGeneration"),generation)
        eq(upvalue(selection,"catalogGeneration"),references)
        eq(upvalue(selection,"catalogInspections"),inspections); eq(next(inspections),nil)
    end)
    test("CQ10 append rechecks current capacity after validation callbacks",function()
        local env,admin=setup()
        for _=1,15 do queue(env,admin,B) end
        local information=env.NPCEdits[7].information; local entered=false
        env.NPCEdits[7]=setmetatable({name=A},{__index=function(_,key)
            if key=="information" then
                if not entered then entered=true; queue(env,admin,B) end
                return information
            end
        end})
        queue(env,admin,A); eq(entered,true); eq(#state(env,"encounterQueue"),16)
        for _,item in ipairs(state(env,"encounterQueue")) do eq(item.name,B) end
    end)
    test("CQ11 mutation commits before reply and nested edits survive",function()
        local env,admin=setup(); local chat=admin.ChatPrint; local entered=false
        admin.ChatPrint=function(self,line)
            chat(self,line)
            if entered then return end; entered=true
            names(env,{A}); say(env,admin,"!clearEventQueue"); queue(env,admin,B)
        end
        queue(env,admin,A); names(env,{B})
    end)
    test("CQ12 listing captures ordered availability before first feedback",function()
        local env,admin=setup(); queue(env,admin,A); queue(env,admin,B)
        env.NPCEdits[8]=nil
        local lines,entered,nested={},false,false; local chat=admin.ChatPrint
        admin.ChatPrint=function(self,line)
            chat(self,line)
            if not nested then lines[#lines+1]=line end
            if entered then return end; entered=true; nested=true
            say(env,admin,"!clearEventQueue"); queue(env,admin,C); nested=false
        end
        eq(say(env,admin,"!eventQueue"),"")
        local text=table.concat(lines,"\n"); contains(text,"2"); contains(text,"16")
        local a=assert(text:find(A,1,true)); local b=assert(text:find(B,1,true)); assert(a<b,"FIFO rows")
        contains(text,"unavailable"); assert(not text:find(C,1,true),"snapshot does not mix later queue")
        names(env,{C}); assert(#lines<=18,"sixteen rows and bounded metadata")
    end)
    test("CQ13 listing bounds long UTF-8 names and preserves row and reason metadata",function()
        local env,admin=setup(); local long=string.rep("界",100) .. "\n\tend"
        env.NPCEdits[90]={name=long,information=env.NPCEdits[7].information}; queue(env,admin,long)
        env.NPCEdits[90]=nil
        local text,lines=replies(env,admin,"!eventQueue"); contains(text,"unavailable")
        local row
        for _,line in ipairs(lines) do if line:find("界",1,true) then row=line end end
        assert(row,"name row exists"); assert(row:match("1"),"row number remains")
        -- Every high byte in this fixture is part of the complete three-byte glyph.
        local stripped=row:gsub("界","")
        assert(not stripped:find("[\128-\255]"),"UTF-8 truncation keeps complete glyphs")
    end)
    for _,action in ipairs({"disconnect","demote"}) do
        test("CQ14 listing revalidates requester after feedback " .. action,function()
            local env,admin=setup(); queue(env,admin,A); queue(env,admin,B)
            local chat=admin.ChatPrint; local calls=0
            admin.ChatPrint=function(self,line)
                calls=calls+1; chat(self,line)
                if action=="disconnect" then self.valid=false else self.admin=false end
            end
            say(env,admin,"!eventQueue"); eq(calls,1); names(env,{A,B})
        end)
    end

    test("CQ15 selected refill precedes override which precedes FIFO",function()
        local env,admin=setup(2); say(env,admin,"!nextEvent " .. A); attempt(env)
        say(env,admin,"!nextEvent " .. B); queue(env,admin,C)
        ready(env)[1]:Remove(); attempt(env)
        for _,actor in ipairs(ready(env)) do eq(actor.EventIdentifier,A) end
        names(env,{C}); eq(state(env,"pendingSelection").name,B)
        removeReady(env); attempt(env); eq(ready(env)[1].EventIdentifier,B); names(env,{C})
        removeReady(env); attempt(env); eq(ready(env)[1].EventIdentifier,C); names(env,{})
    end)
    test("CQ16 manual matching actors neither consume nor pin a queue batch",function()
        local env,admin=setup(2); queue(env,admin,A); say(env,admin,"!nextEvent " .. B)
        local manual=env.entity("activatorent"); manual.EventIdentifier=A; manual:Spawn()
        attempt(env); eq(#ready(env),2); names(env,{A}); eq(state(env,"pendingSelection").name,B)
        eq(state(env,"selectedBatchName"),nil); eq(ready(env)[2].EventIdentifier,"Raid")
        removeReady(env); say(env,admin,"!clearNextEvent"); attempt(env)
        names(env,{}); owners(env,ready(env),A)
    end)
    for _,path in ipairs({"timer","immediate"}) do
        test("CQ17 " .. path .. " chooses identical FIFO head",function()
            local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
            if path=="timer" then attempt(env) else eq(say(env,admin,"!spawnActivatorsNow"),"") end
            names(env,{B}); eq(#ready(env),2); owners(env,ready(env),A); eq(env.totalEnemies,0)
        end)
    end
    test("CQ18 unavailable head blocks tail and random with explicit private remedies",function()
        local env,admin=setup(); queue(env,admin,A); queue(env,admin,B); env.NPCEdits[7]=nil
        env.determineRandomEvent=function() error("blocked FIFO must not choose random") end
        attempt(env); names(env,{A,B}); eq(#ready(env),0)
        local status=replies(env,admin,"!eventStatus"); contains(status,"queue"); contains(status,"unavailable")
        assert(not status:find("random:",1,true),"blocked head is not random fallback")
        contains(replies(env,admin,"!eventQueue"),"unavailable")
        contains(replies(env,admin,"!spawnActivatorsNow"),"queue")
        names(env,{A,B}); say(env,admin,"!dropQueuedEvent"); attempt(env)
        eq(ready(env)[1].EventIdentifier,B); names(env,{})
    end)
    test("CQ19 unavailable override blocks FIFO until only override is cleared",function()
        local env,admin=setup(); queue(env,admin,B); say(env,admin,"!nextEvent " .. A); env.NPCEdits[7]=nil
        attempt(env); names(env,{B}); eq(#ready(env),0)
        say(env,admin,"!clearNextEvent"); attempt(env); names(env,{}); eq(ready(env)[1].EventIdentifier,B)
    end)
    test("CQ20 valid override runs ahead of unavailable retained head",function()
        local env,admin=setup(); queue(env,admin,A); env.NPCEdits[7]=nil; say(env,admin,"!nextEvent " .. B)
        attempt(env); names(env,{A}); eq(ready(env)[1].EventIdentifier,B)
        removeReady(env); attempt(env); names(env,{A}); eq(#ready(env),0)
    end)
    for _,case in ipairs({
        {label="players",apply=function(e) e.minNumberOfPlayers=99 end},
        {label="positions",apply=function(e) e.SpawnPositions={} end},
        {label="sample",apply=function(e) e.returnActivatorSpawns=function() return nil end end},
        {label="zero capacity",apply=function(e) e.maxActivators=0 end},
        {label="invalid capacity",apply=function(e) e.maxActivators="invalid" end},
        {label="invalid Create",apply=function(e) e.failClass="activatorent" end},
        {label="deleting Spawn",apply=function(e) e.deferRemoval=true; onceSpawn(e,function(a) a:Remove() end) end},
        {label="invalid Spawn",apply=function(e) onceSpawn(e,function(a) a.valid=false end) end},
    }) do
        test("CQ21 no qualifying actor retains FIFO: " .. case.label,function()
            local env,admin=setup(); queue(env,admin,A); local head=names(env,{A})[1]
            case.apply(env); attempt(env); eq(names(env,{A})[1],head); eq(state(env,"selectedBatchName"),nil)
            idleClaim(env)
        end)
    end
    test("CQ22 renamed Spawn remains unowned and cannot consume queue",function()
        local env,admin=setup(); queue(env,admin,A)
        onceSpawn(env,function(actor) actor.EventIdentifier=B end)
        attempt(env); names(env,{A}); eq(#ready(env),1); eq(ready(env)[1].EventIdentifier,B)
        owners(env,{},nil)
    end)
    test("CQ23 later matching actor settles after earlier renamed actor",function()
        local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
        onceSpawn(env,function(actor) actor.EventIdentifier=C end)
        attempt(env); local actors=ready(env); eq(#actors,2); names(env,{B})
        eq(actors[1].EventIdentifier,C); owners(env,{actors[2]},A)
    end)
    test("CQ24 returned identifier is sampled after usability callback",function()
        local env,admin=setup(); queue(env,admin,A)
        onceSpawn(env,function(actor)
            local marked=actor.IsMarkedForDeletion; local changed=false
            actor.IsMarkedForDeletion=function(self)
                if not changed then changed=true; self.EventIdentifier=B end
                return marked(self)
            end
        end)
        attempt(env); names(env,{A}); owners(env,{},nil); eq(ready(env)[1].EventIdentifier,B)
    end)

    for _,action in ipairs({"drop","clear then same name","append","override replace","override clear"}) do
        test("CQ25 Spawn future edit preserves captured item custody: " .. action,function()
            local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
            local head=names(env,{A,B})[1]; local replacement,claim
            onceSpawn(env,function()
                claim=state(env,"queueClaim"); eq(claim.item,head); eq(claim.name,A)
                if action=="drop" then say(env,admin,"!dropQueuedEvent")
                elseif action=="clear then same name" then say(env,admin,"!clearEventQueue"); queue(env,admin,A); replacement=state(env,"encounterQueue")[1]
                elseif action=="append" then queue(env,admin,C)
                elseif action=="override replace" then say(env,admin,"!nextEvent " .. C)
                else say(env,admin,"!nextEvent " .. C); say(env,admin,"!clearNextEvent") end
            end)
            attempt(env); owners(env,ready(env),A); eq(claim.settled,true); idleClaim(env)
            if action=="clear then same name" then
                eq(names(env,{A})[1],replacement); assert(replacement~=head,"new same-name identity survives")
            elseif action=="append" then names(env,{B,C}) else names(env,{B}) end
            if action=="override replace" then eq(state(env,"pendingSelection").name,C)
            else eq(state(env,"pendingSelection"),nil) end
        end)
    end
    test("CQ26 nested continuation shares owners and respects capacity two",function()
        local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
        local claim,innerOwners,creates; creates=0
        local create=env.ents.Create
        env.ents.Create=function(class) creates=creates+1; assert(creates<=2,"outer stale loop created a third actor"); return create(class) end
        onceSpawn(env,function()
            claim=state(env,"queueClaim"); eq(claim.settled,false)
            attempt(env); innerOwners=state(env,"selectedBatchEntities")
            eq(claim.settled,true); eq(state(env,"queueClaim"),claim)
        end)
        attempt(env); eq(creates,2); eq(#ready(env),2); names(env,{B})
        eq(owners(env,ready(env),A),innerOwners); eq(claim.owners,innerOwners)
        eq(env.timers.activatorSpawner.stopped,true); idleClaim(env)
    end)
    test("CQ27 nested continuation ignores new override and changed FIFO",function()
        local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
        onceSpawn(env,function()
            say(env,admin,"!dropQueuedEvent"); say(env,admin,"!nextEvent " .. C); attempt(env)
        end)
        attempt(env); owners(env,ready(env),A); names(env,{B}); eq(state(env,"pendingSelection").name,C)
    end)
    for _,getter in ipairs({"hasActivatorSpawns","returnNPCInformation","returnActivatorSpawns","returnMaxActivators"}) do
        test("CQ28 first creation recount follows callback from " .. getter,function()
            local env,admin=setup(1); queue(env,admin,A); local original=env[getter]; local entered=false
            env[getter]=function(...)
                if not entered then
                    entered=true; assert(state(env,"queueClaim"),"claim installed before getter")
                    local manual=env.entity("activatorent"); manual.EventIdentifier=B; manual:Spawn()
                end
                return original(...)
            end
            local creates=0; local create=env.ents.Create
            env.ents.Create=function(class) creates=creates+1; return create(class) end
            attempt(env); eq(entered,true); eq(creates,0); eq(#ready(env),1); names(env,{A})
            eq(state(env,"selectedBatchName"),nil); idleClaim(env)
        end)
    end
    test("CQ29 nested getter completion cannot exceed sampled cap or consume second head",function()
        local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
        local getter=env.returnActivatorSpawns; local entered=false
        env.returnActivatorSpawns=function(...)
            if not entered then entered=true; attempt(env) end
            return getter(...)
        end
        attempt(env); eq(#ready(env),2); names(env,{B}); owners(env,ready(env),A); idleClaim(env)
    end)
    test("CQ30 nested pre-claim attempt defers FIFO and outer call remains eligible",function()
        local env,admin=setup(); queue(env,admin,A); queue(env,admin,B)
        local scan=env.ents.FindByClass; local entered=false
        env.ents.FindByClass=function(class)
            if class=="activatorent" and not entered then
                entered=true; eq(state(env,"queueClaim"),nil); attempt(env)
                names(env,{A,B}); eq(#ready(env),0); eq(state(env,"selectedBatchName"),nil)
            end
            return scan(class)
        end
        attempt(env); eq(entered,true); names(env,{B}); owners(env,ready(env),A); idleClaim(env)
    end)
    test("CQ31 capacity callback cannot enlarge original iteration bound",function()
        local env,admin=setup(1); queue(env,admin,A)
        local samples=0; local getter=env.returnMaxActivators
        env.returnMaxActivators=function(...) samples=samples+1; return getter(...) end
        onceSpawn(env,function() env.maxActivators=16 end)
        attempt(env); eq(#ready(env),1); eq(samples,1); names(env,{})
    end)
    for _,action in ipairs({"pause","pause resume"}) do
        test("CQ32 admitted actor settles but stale generation stops after " .. action,function()
            local env,admin=setup(3); queue(env,admin,A); queue(env,admin,B)
            local claim,afterGeneration
            onceSpawn(env,function()
                claim=state(env,"queueClaim"); say(env,admin,"!pauseActivatorSpawns")
                if action=="pause resume" then say(env,admin,"!resumeActivatorSpawns") end
                afterGeneration=state(env,"spawnScheduleGeneration")
            end)
            attempt(env); eq(#ready(env),1); names(env,{B}); owners(env,ready(env),A)
            assert(afterGeneration~=claim.generation); eq(claim.settled,true)
            eq(env.timers.activatorSpawner.stopped,action=="pause"); idleClaim(env)
        end)
    end
    test("CQ33 refresh retires old Spawn and preserves queue with no ownership resurrection",function()
        local env,admin=setup(3); env.deferRemoval=true; queue(env,admin,A); queue(env,admin,B)
        local claim
        onceSpawn(env,function()
            claim=state(env,"queueClaim"); say(env,admin,"!refreshActivators"); eq(claim.retired,true)
            attempt(env); eq(state(env,"queueClaim"),claim)
        end)
        attempt(env); names(env,{A,B}); eq(#ready(env),0); owners(env,{},nil)
        eq(claim.settled,false); idleClaim(env)
        env.flushRemovals(); attempt(env); names(env,{B}); owners(env,ready(env),A)
    end)
    test("CQ34 last nested owner removal retires claim before outer return",function()
        local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
        local claim
        onceSpawn(env,function(outer)
            claim=state(env,"queueClaim"); attempt(env); eq(claim.settled,true)
            for actor in pairs(state(env,"selectedBatchEntities")) do assert(actor~=outer); actor:Remove() end
            eq(claim.retired,true)
        end)
        attempt(env); names(env,{B}); owners(env,{},nil); eq(#ready(env),1); idleClaim(env)
    end)
    test("CQ35 active-state lifecycle seam suppresses old queue ownership",function()
        local env,admin=setup(); queue(env,admin,A)
        local claim
        onceSpawn(env,function()
            claim=state(env,"queueClaim")
            -- Focused lifecycle seam only; no Use, Start, Cancel or packet handler.
            setState(env,"eventActive",true); state(env,"clearSelectedBatch")()
        end)
        attempt(env); names(env,{A}); owners(env,{},nil); eq(claim.retired,true); idleClaim(env)
    end)
    for _,boundary in ipairs({"Create","IsValid","SetPos","IsMarkedForDeletion"}) do
        test("CQ36 retired custody checked after queue callback " .. boundary,function()
            local env,admin=setup(2); queue(env,admin,A); local retired=false
            local function retire()
                if retired then return end; retired=true; state(env,"clearSelectedBatch")()
            end
            local create=env.ents.Create
            env.ents.Create=function(class)
                local actor=create(class)
                if class=="activatorent" then
                    if boundary=="Create" then retire()
                    elseif boundary=="IsValid" then
                        local valid=env.IsValid; env.IsValid=function(value)
                            if value==actor then retire() end
                            return valid(value)
                        end
                    elseif boundary=="SetPos" then
                        local set=actor.SetPos; actor.SetPos=function(self,position) set(self,position); retire() end
                    else
                        local spawn=actor.Spawn; actor.Spawn=function(self)
                            spawn(self); local marked=self.IsMarkedForDeletion
                            self.IsMarkedForDeletion=function(a) retire(); return marked(a) end
                        end
                    end
                end
                return actor
            end
            attempt(env); eq(retired,true); names(env,{A}); owners(env,{},nil); assert(#ready(env)<=1); idleClaim(env)
        end)
    end
    test("CQ37 retirement during capacity scan prevents following Create",function()
        local env,admin=setup(2); queue(env,admin,A)
        local scan=env.ents.FindByClass; local retired=false; local creates=0
        env.ents.FindByClass=function(class)
            local result=scan(class)
            if class=="activatorent" and state(env,"queueClaim") and not retired then
                retired=true; state(env,"clearSelectedBatch")()
            end
            return result
        end
        local create=env.ents.Create; env.ents.Create=function(class) creates=creates+1; return create(class) end
        attempt(env); eq(retired,true); eq(creates,0); names(env,{A}); owners(env,{},nil); idleClaim(env)
    end)
    test("CQ38 error before Spawn return releases claim without consumption",function()
        local env,admin=setup(); queue(env,admin,A); queue(env,admin,B)
        onceSpawn(env,function() error("queue-before-return") end)
        local ok,err=pcall(attempt,env); eq(ok,false); contains(tostring(err),"queue-before-return")
        names(env,{A,B}); owners(env,{},nil); idleClaim(env)
    end)
    test("CQ39 error after nested settlement preserves consumption and newest override",function()
        local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
        onceSpawn(env,function()
            attempt(env); say(env,admin,"!nextEvent " .. C); error("queue-after-settlement")
        end)
        local ok,err=pcall(attempt,env); eq(ok,false); contains(tostring(err),"queue-after-settlement")
        names(env,{B}); eq(state(env,"selectedBatchName"),A); eq(state(env,"pendingSelection").name,C)
        local count=0; for _ in pairs(state(env,"selectedBatchEntities")) do count=count+1 end; eq(count,1)
        idleClaim(env)
    end)
    test("CQ40 next attempt can establish claim after protected error unwind",function()
        local env,admin=setup(); queue(env,admin,A)
        local getter=env.returnActivatorSpawns; env.returnActivatorSpawns=function() error("temporary position getter") end
        eq(pcall(attempt,env),false); names(env,{A}); idleClaim(env)
        env.returnActivatorSpawns=getter; attempt(env); names(env,{}); owners(env,ready(env),A)
    end)
    test("CQ41 legacy override renamed Spawn still uses its original qualification",function()
        local env,admin=setup(); say(env,admin,"!nextEvent " .. A); queue(env,admin,B)
        onceSpawn(env,function(actor) actor.EventIdentifier=C end)
        attempt(env); eq(state(env,"pendingSelection"),nil); owners(env,ready(env),A); names(env,{B})
        eq(ready(env)[1].EventIdentifier,C)
    end)
    test("CQ42 refresh after consumption retains tail and never restores consumed item",function()
        local env,admin=setup(); queue(env,admin,A); queue(env,admin,B); attempt(env); names(env,{B})
        say(env,admin,"!refreshActivators"); names(env,{B}); owners(env,{},nil)
        attempt(env); names(env,{}); owners(env,ready(env),B)
    end)
    test("CQ43 session queue outlives requester and ready cleanup but fresh module is empty",function()
        local env,admin=setup(); queue(env,admin,A); queue(env,admin,B); admin.valid=false
        names(env,{A,B}); local other=env.entity("player"); other.admin=true
        attempt(env); removeReady(env); names(env,{B})
        local fresh=setup(); names(fresh,{}); names(env,{B})
    end)
    test("CQ44 preparing status neither reports random nor settles or prunes claim",function()
        local env,admin=setup(); queue(env,admin,A); local getter=env.returnActivatorSpawns; local entered=false
        env.returnActivatorSpawns=function(...)
            if not entered then
                entered=true; local claim=state(env,"queueClaim"); eq(claim.settled,false)
                local text=replies(env,admin,"!eventStatus"); contains(text,"preparing")
                assert(not text:find("random:",1,true)); eq(state(env,"queueClaim"),claim); eq(claim.retired,false)
                names(env,{A}); owners(env,{},nil)
            end
            return getter(...)
        end
        attempt(env); eq(entered,true); names(env,{})
    end)
    test("CQ45 active-state gate independently prevents returned queue ownership",function()
        local env,admin=setup(); queue(env,admin,A); local claim
        onceSpawn(env,function()
            claim=state(env,"queueClaim"); setState(env,"eventActive",true)
            eq(claim.retired,false,"active gate tested independently of retirement")
        end)
        attempt(env); names(env,{A}); owners(env,{},nil); eq(claim.settled,false); idleClaim(env)
    end)
    test("CQ46 retired outer callback cannot overwrite newer selected ownership",function()
        local env,admin=setup(); queue(env,admin,A); local newer,ownerSet
        onceSpawn(env,function()
            state(env,"clearSelectedBatch")()
            newer=env.entity("activatorent"); newer.EventIdentifier=C; newer:Spawn()
            ownerSet={[newer]=true}
            setState(env,"selectedBatchName",C); setState(env,"selectedBatchEntities",ownerSet)
        end)
        attempt(env); names(env,{A}); eq(owners(env,{newer},C),ownerSet); idleClaim(env)
    end)
    test("CQ47 error in later getter cannot roll back an already settled outer actor",function()
        local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
        local getter=env.returnActivatorSpawns; local calls=0
        env.returnActivatorSpawns=function(...)
            calls=calls+1; if calls==2 then error("queue-after-outer-settlement") end
            return getter(...)
        end
        local ok,err=pcall(attempt,env); eq(ok,false); contains(tostring(err),"queue-after-outer-settlement")
        names(env,{B}); owners(env,ready(env),A); eq(#ready(env),1); idleClaim(env)
    end)
    test("CQ48 clear commands independently preserve selected and other future source",function()
        local env,admin=setup(); say(env,admin,"!nextEvent " .. A); attempt(env)
        local selectedOwners=state(env,"selectedBatchEntities")
        queue(env,admin,B); say(env,admin,"!nextEvent " .. C); local pending=state(env,"pendingSelection")
        say(env,admin,"!clearEventQueue"); names(env,{})
        eq(state(env,"pendingSelection"),pending); eq(owners(env,ready(env),A),selectedOwners)
        queue(env,admin,B); say(env,admin,"!clearNextEvent"); names(env,{B})
        eq(state(env,"pendingSelection"),nil); eq(owners(env,ready(env),A),selectedOwners)
    end)
    for _,boundary in ipairs({"IsValid","IsMarkedForDeletion"}) do
        test("CQ49 nested continuation during capacity scan " .. boundary .. " cannot admit actor three",function()
            local env,admin=setup(2); queue(env,admin,A); queue(env,admin,B)
            local creates=0; local create=env.ents.Create; local fired=false
            env.ents.Create=function(class)
                creates=creates+1; assert(creates<=2,"stale capacity snapshot admitted actor three")
                return create(class)
            end
            onceSpawn(env,function(outer)
                local scans,armed=0,false; local scan=env.ents.FindByClass
                env.ents.FindByClass=function(class)
                    local result=scan(class)
                    if class=="activatorent" then
                        scans=scans+1
                        -- Middle attempt: first scan is its ordinary prerequisite;
                        -- second scan is the queue-only pre-Create recount.
                        if scans==2 then armed=true end
                    end
                    return result
                end
                local function nested()
                    if armed and not fired then fired=true; attempt(env) end
                end
                if boundary=="IsValid" then
                    local valid=env.IsValid
                    env.IsValid=function(value) if value==outer then nested() end; return valid(value) end
                else
                    local marked=outer.IsMarkedForDeletion
                    outer.IsMarkedForDeletion=function(self) nested(); return marked(self) end
                end
                attempt(env)
            end)
            attempt(env); eq(fired,true,"callback hit pre-Create scan"); eq(creates,2)
            eq(#ready(env),2); names(env,{B}); owners(env,ready(env),A); idleClaim(env)
        end)
    end
end
