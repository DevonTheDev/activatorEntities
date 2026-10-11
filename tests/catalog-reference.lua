-- Real PlayerSay/catalog workflows with engine doubles, not native chat tests.
return function(gmod,test,eq)
    local function setup(names)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        if names then
            env.NPCEdits={}
            for i,name in ipairs(names) do env.NPCEdits[i*7]={name=name,information={}} end
        end
        return env,admin
    end
    local function say(env,admin,text)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,text),"","recognized command stays private")
        local lines={}; for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        return table.concat(lines,"\n"),lines
    end
    local function listed(env,admin,page)
        local text,lines=say(env,admin,"!listEvents" .. (page and (" " .. page) or ""))
        local refs={}
        for _,line in ipairs(lines) do
            assert(#line<=240,"bounded catalog line")
            assert(not line:find("[%c]"),"control-safe catalog line")
            local id,token=line:match("^Entry (%d+) part %d+/%d+ ref ([%w%-]+) ")
            if token then
                if refs[tonumber(id)] then eq(refs[tonumber(id)],token,"one token for continuation parts") end
                refs[tonumber(id)]=token
            end
        end
        assert(#lines<=10,"eight-body-line page budget")
        return refs,text
    end
    local function state(env,name,replacement)
        local seen={}
        local function visit(fn)
            if seen[fn] then return end; seen[fn]=true
            for i=1,100 do
                local key,value=debug.getupvalue(fn,i); if not key then break end
                if key==name then
                    if replacement~=nil then debug.setupvalue(fn,i,replacement) end
                    return value,true
                end
                if type(value)=="function" then local found,ok=visit(value); if ok then return found,true end end
            end
        end
        for _,callbacks in pairs(env.hooks) do for _,fn in pairs(callbacks) do
            local found,ok=visit(fn); if ok then return found end
        end end
    end
    local function pending(env) local value=state(env,"pendingSelection"); return value and value.name end
    local function refused(env,admin,token)
        local before=state(env,"pendingSelection")
        local text=say(env,admin,"!nextEventRef " .. token)
        assert(text:find("unchanged",1,true) or text:find("Usage:",1,true),"private refusal guidance")
        assert(rawequal(state(env,"pendingSelection"),before),"refusal preserves pending identity")
    end
    local names={"A ref Raid","Raid","  leading and trailing  ","1","!nextEventRef","A \"quoted\" \\raid","火 🚀 é", "A\0\n\\火",string.rep("火",1200)}
    for i,name in ipairs(names) do
        test("catalog reference queues exact raw name case " .. i,function()
            local env,admin=setup({name}); local other=env.entity("player")
            local refs=listed(env,admin); assert(refs[1],"eligible displayed entry needs a reference")
            say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),name)
            eq(#other.chats,0); eq(#env.messages,0)
            refused(env,admin,refs[1])
        end)
    end
    test("catalog reference supports a continuation-only page and replaces the previous page",function()
        local env,admin=setup({"A" .. string.rep("火",2000),"Z off page"})
        local first=listed(env,admin); local second,text=listed(env,admin,2)
        assert(second[1]); assert(not second[2]); assert(first[1]~=second[1],"new generation")
        assert(text:find("part 9/",1,true)); refused(env,admin,first[1])
        say(env,admin,"!nextEventRef " .. second[1]); eq(pending(env),env.NPCEdits[7].name)
    end)
    test("catalog reference is private per admin and only accepts entries on the latest page",function()
        local names={}; for i=1,12 do names[i]=string.format("Event %02d",i) end
        local env,admin=setup(names); local other=env.entity("player"); other.admin=true
        local refs=listed(env,admin); local theirs=listed(env,other,2)
        refused(env,other,refs[1]); refused(env,admin,theirs[9])
        local offpage=refs[1]:gsub("%-%d+$","-9"); refused(env,admin,offpage)
        say(env,admin,"!nextEventRef " .. refs[8]); eq(pending(env),names[8])
    end)
    test("catalog unavailable entries never advertise references",function()
        local env,admin=setup(); env.NPCEdits={false,{}, {name=1},{name="",information={}},
            {name="Duplicate",information={}},{name="Duplicate",information={}},
            {name="Missing"},{name="Wrong",information=false},{name="Valid",information={}}}
        local refs,text=listed(env,admin); eq(refs[1],nil); eq(refs[2],nil); eq(refs[3],nil)
        assert(refs[4]); eq(refs[5],nil); assert(text:find("duplicate name",1,true))
        say(env,admin,"!nextEventRef " .. refs[4]); eq(pending(env),"Valid")
    end)
    test("invalid page preserves the latest successful reference",function()
        local env,admin=setup(); local refs=listed(env,admin)
        say(env,admin,"!listEvents 99"); say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Raid")
    end)
    for _,case in ipairs({"relist","pool","record","information","removed","renamed","duplicate","moved key","map","disconnect","initialize"}) do
        test("catalog reference refuses " .. case .. " without changing a queued choice",function()
            local env,admin=setup({"A","B"}); say(env,admin,"!nextEvent B")
            local refs=listed(env,admin); local record=env.NPCEdits[7]
            if case=="relist" then listed(env,admin)
            elseif case=="pool" then env.NPCEdits={[7]=record,[14]=env.NPCEdits[14]}
            elseif case=="record" then env.NPCEdits[7]={name=record.name,information=record.information}
            elseif case=="information" then record.information={}
            elseif case=="removed" then env.NPCEdits[7]=nil
            elseif case=="renamed" then record.name="Renamed"
            elseif case=="duplicate" then env.NPCEdits[21]={name="A",information={}}
            elseif case=="moved key" then env.NPCEdits[21]=record; env.NPCEdits[7]=nil
            elseif case=="map" then env.map="gm_other"
            elseif case=="disconnect" then env.fire("PlayerDisconnected",admin)
            else env.fire("Initialize") end
            refused(env,admin,refs[1]); eq(pending(env),"B")
        end)
    end
    test("catalog reference ignores iteration order and live information fields",function()
        local env,admin=setup({"A","B"}); local refs=listed(env,admin)
        local record=env.NPCEdits[7]; env.NPCEdits[7]=nil; env.NPCEdits[7]=record
        record.information.maxNPCs=11; record.information.model="changed"
        say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"A")
    end)
    for _,kind in ipairs({"pool","record","information"}) do
        test("catalog reference uses raw " .. kind .. " identity despite custom equality",function()
            local env,admin=setup({"A"}); local calls=0
            local mt={__eq=function() calls=calls+1; return true end}
            local record=env.NPCEdits[7]
            if kind=="pool" then setmetatable(env.NPCEdits,mt)
            elseif kind=="record" then setmetatable(record,mt)
            else setmetatable(record.information,mt) end
            local refs=listed(env,admin)
            if kind=="pool" then env.NPCEdits=setmetatable({[7]=record},mt)
            elseif kind=="record" then env.NPCEdits[7]=setmetatable({name="A",information=record.information},mt)
            else record.information=setmetatable({},mt) end
            refused(env,admin,refs[1]); eq(calls,0,"__eq must not decide identity")
        end)
    end
    for _,case in ipairs({59.999,60,60.001,-0.01,math.huge,-math.huge,0/0}) do
        test("catalog reference checks lifetime at " .. tostring(case),function()
            local env,admin=setup(); local refs=listed(env,admin); env.now=case
            if case>=0 and case<60 then say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Raid")
            else refused(env,admin,refs[1]) end
        end)
    end
    for _,now in ipairs({math.huge,-math.huge,0/0,-1,1e30}) do
        test("catalog refuses unusable issue time " .. tostring(now),function()
            local env,admin=setup(); env.now=now
            local text=say(env,admin,"!listEvents"); assert(not text:find(" ref ",1,true))
        end)
    end
    for _,argument in ipairs({""," ","1","Raid","r1-1 extra","r1-1\nr2-2","-1","r1-1!"}) do
        test("catalog reference never reinterprets malformed or unknown argument " .. argument:gsub("%c"," "),function()
            local env,admin=setup(); say(env,admin,"!nextEvent Raid"); listed(env,admin)
            if argument=="r1-1!" then argument="unknown!" end
            refused(env,admin,argument)
        end)
    end
    test("reference accepts exactly one token with surrounding whitespace and keeps nextEvent raw",function()
        local env,admin=setup({"1","!nextEventRef","Raid"}); local refs=listed(env,admin)
        say(env,admin,"!nextEventRef\t" .. refs[1] .. "  "); eq(pending(env),"!nextEventRef")
        say(env,admin,"!nextEvent 1"); eq(pending(env),"1")
        say(env,admin,"!nextEvent !nextEventRef"); eq(pending(env),"!nextEventRef")
        eq(env.fire("PlayerSay",admin,"!nextEventReference r1-1"),nil)
    end)
    test("reference rejects missing snapshots and non-admin or invalid players",function()
        local env,admin=setup(); refused(env,admin,"r1-1"); local refs=listed(env,admin)
        eq(env.fire("PlayerSay",nil,"!listEvents"),nil)
        eq(env.fire("PlayerSay",nil,"!nextEventRef " .. refs[1]),nil)
        admin.admin=false; local text=say(env,admin,"!nextEventRef " .. refs[1]); assert(text:find("Only admins",1,true)); eq(pending(env),nil)
        admin.admin=true; admin.valid=false; eq(env.fire("PlayerSay",admin,"!nextEventRef " .. refs[1]),nil)
        local prop=env.entity("prop_physics"); prop.admin=true; eq(env.fire("PlayerSay",prop,"!nextEventRef " .. refs[1]),nil)
    end)
    test("nested catalog reply owns its newer snapshot",function()
        local env,admin=setup({"A","B"}); local original=admin.ChatPrint; local newer,once
        admin.ChatPrint=function(self,text)
            original(self,text)
            if not once then once=true; newer=listed(env,admin) end
        end
        say(env,admin,"!listEvents"); admin.ChatPrint=original
        say(env,admin,"!nextEventRef " .. newer[2]); eq(pending(env),"B")
    end)
    test("disconnect during catalog reply cannot restore its snapshot",function()
        local env,admin=setup(); local original=admin.ChatPrint; local once,token
        admin.ChatPrint=function(self,text)
            original(self,text)
            if not once then
                once=true
                token=next(state(env,"catalogInspections")[admin].targets)
                env.fire("PlayerDisconnected",admin)
            end
        end
        say(env,admin,"!listEvents"); admin.ChatPrint=original
        assert(token); refused(env,admin,token)
    end)
    for _,getter in ipairs({"GetMap","CurTime","IsAdmin","IsPlayer"}) do
        test("reference revalidates snapshot after nested " .. getter,function()
            local env,admin=setup({"A","B"}); local refs=listed(env,admin); local once,newer
            local owner= getter=="GetMap" and env.game or ((getter=="CurTime") and env or admin)
            local original=owner[getter]
            owner[getter]=function(...)
                if not once then once=true; newer=listed(env,admin) end
                return original(...)
            end
            refused(env,admin,refs[1]); owner[getter]=original
            say(env,admin,"!nextEventRef " .. newer[2]); eq(pending(env),"B")
        end)
    end
    for _,callback in ipairs({"disconnect","demote","invalidate","replace information","duplicate"}) do
        test("reference revalidates after configuration callback " .. callback,function()
            local env,admin=setup({"A"}); local refs=listed(env,admin); local once
            env.NPCEdits[99]=setmetatable({}, {__index=function()
                if not once then
                    once=true
                    if callback=="disconnect" then env.fire("PlayerDisconnected",admin)
                    elseif callback=="demote" then admin.admin=false
                    elseif callback=="invalidate" then admin.valid=false
                    elseif callback=="replace information" then env.NPCEdits[7].information={}
                    else env.NPCEdits[9]={name="A",information={}} end
                end
                return nil
            end})
            say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),nil)
        end)
    end
    test("listing cannot overwrite a newer listing entered from its initial admin check",function()
        local env,admin=setup(); local original=admin.IsAdmin; local once,newer
        admin.IsAdmin=function(self)
            if not once then once=true; newer=listed(env,admin) end
            return original(self)
        end
        eq(env.hooks.PlayerSay.selectNextActivatorEvent(admin,"!listEvents"),""); admin.IsAdmin=original
        say(env,admin,"!nextEventRef " .. newer[1]); eq(pending(env),"Raid")
    end)
    test("catalog preserves inherited names and rejects inherited duplicates",function()
        local env,admin=setup(); local info={}
        env.NPCEdits={setmetatable({}, {__index={name="A",information=info}})}
        local refs=listed(env,admin); assert(refs[1],"inherited eligible name stays visible")
        say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"A")
        env.NPCEdits={{name="A",information=info},setmetatable({}, {__index={name="A",information=info}})}
        local duplicate,text=listed(env,admin); eq(duplicate[1],nil); assert(text:find("duplicate name",1,true))
    end)
    test("reference refuses a newly inherited duplicate",function()
        local env,admin=setup({"A"}); local refs=listed(env,admin)
        env.NPCEdits[99]=setmetatable({}, {__index={name="A",information={}}})
        refused(env,admin,refs[1])
    end)
    test("reference refuses a map changed by the clock getter",function()
        local env,admin=setup(); local refs=listed(env,admin)
        env.CurTime=function() env.map="gm_other"; return env.now end
        refused(env,admin,refs[1])
    end)
    test("reference refuses expiry reached during final admin validation",function()
        local env,admin=setup(); local refs=listed(env,admin); local calls=0
        admin.IsAdmin=function() calls=calls+1; if calls==2 then env.now=60 end; return true end
        eq(env.hooks.PlayerSay.selectNextActivatorEvent(admin,"!nextEventRef " .. refs[1]),"")
        eq(pending(env),nil)
    end)
    test("reference rechecks eligibility after an inherited getter reenters",function()
        local env,admin=setup({"A"}); local refs=listed(env,admin); local once
        env.NPCEdits[90]=setmetatable({}, {__index=function()
            if not once then once=true; env.fire("PlayerDisconnected",admin) end
            return nil
        end})
        refused(env,admin,refs[1])
    end)
    test("reference refuses a duplicate added by the selected information getter",function()
        local env,admin=setup(); local info={}; local inject=false
        env.NPCEdits={setmetatable({name="A"}, {__index=function(_,key)
            if key=="information" then
                if inject then env.NPCEdits[90]={name="A",information=info} end
                return info
            end
        end})}
        local refs=listed(env,admin); assert(refs[1]); inject=true
        refused(env,admin,refs[1])
    end)
    test("accepted reference is consumed before feedback can reenter",function()
        local env,admin=setup({"A","B"}); local refs=listed(env,admin); local original=admin.ChatPrint; local once
        admin.ChatPrint=function(self,text)
            original(self,text)
            if not once then once=true; refused(env,admin,refs[2]); say(env,admin,"!nextEvent B") end
        end
        say(env,admin,"!nextEventRef " .. refs[1]); admin.ChatPrint=original; eq(pending(env),"B")
    end)
    test("reference keeps original table-key identity despite key equality",function()
        local env,admin=setup(); local calls=0
        local mt={__eq=function() calls=calls+1; return true end}
        local first,second=setmetatable({},mt),setmetatable({},mt)
        local record={name="A",information={}}; env.NPCEdits={[first]=record}
        local refs=listed(env,admin); env.NPCEdits[first]=nil; env.NPCEdits[second]=record
        refused(env,admin,refs[1]); eq(calls,0)
    end)
    test("a successful empty catalog revokes the previous page",function()
        local env,admin=setup(); local refs=listed(env,admin); local pool=env.NPCEdits
        env.NPCEdits={}; listed(env,admin); env.NPCEdits=pool
        refused(env,admin,refs[1])
    end)
    test("initialization never reuses an earlier reference",function()
        local env,admin=setup(); local first=listed(env,admin); env.fire("Initialize")
        local second=listed(env,admin); assert(first[1]~=second[1]); refused(env,admin,first[1])
        say(env,admin,"!nextEventRef " .. second[1]); eq(pending(env),"Raid")
    end)
    test("throwing configuration access refuses privately and preserves the last page",function()
        local env,admin=setup(); local refs=listed(env,admin)
        env.NPCEdits[90]=setmetatable({}, {__index=function() error("unreadable") end})
        say(env,admin,"!listEvents"); refused(env,admin,refs[1]); env.NPCEdits[90]=nil
        say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Raid")
    end)
    for _,argument in ipairs({""," 99"}) do
        test("catalog avoids replies to a player invalidated while inspecting page" .. argument,function()
            local env,admin=setup(); local original=admin.ChatPrint
            admin.ChatPrint=function(self,text) assert(self.valid,"must not reply to invalid player"); original(self,text) end
            env.NPCEdits[90]=setmetatable({information={}}, {__index=function(_,key)
                if key=="name" then admin.valid=false; return "B" end
            end})
            eq(env.hooks.PlayerSay.selectNextActivatorEvent(admin,"!listEvents" .. argument),"")
            eq(state(env,"catalogInspections")[admin],nil)
        end)
    end
    test("finite generation exhaustion refuses without replacing the last successful page",function()
        local env,admin=setup(); state(env,"catalogGeneration",9007199254740990)
        local refs=listed(env,admin); eq(refs[1],"r9007199254740991-1")
        local text=say(env,admin,"!listEvents"); assert(text:find("exhausted",1,true))
        eq(state(env,"catalogGeneration"),9007199254740991)
        say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Raid")
    end)
    for _,issued in ipairs({4.49,123.456}) do
        test("reference accepts ordinary fractional issue time " .. issued,function()
            local env,admin=setup(); env.now=issued; local refs=listed(env,admin)
            env.now=issued+59.999; say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Raid")
            env.now=issued; refs=listed(env,admin); env.now=issued+60; refused(env,admin,refs[1])
        end)
    end
    test("reference lifetime starts at the server issue time",function()
        local env,admin=setup(); env.now=123; local refs=listed(env,admin)
        env.now=182.999; say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Raid")
        refs=listed(env,admin); env.now=242.999; refused(env,admin,refs[1])
    end)
    test("reference selection feeds the existing live pending-name spawn path",function()
        local env,admin=setup(); local info={}
        for key,value in pairs(env.NPCEdits[1].information) do info[key]=value end
        env.NPCEdits[2]={name="Next",information=info}
        local refs=listed(env,admin); say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Next")
        info.activatorModel="models/barney.mdl"
        local player,actor=env.ready(); eq(actor.EventIdentifier,"Next"); eq(actor:GetModel(),info.activatorModel)
        eq(pending(env),nil); eq(state(env,"selectedBatchName"),"Next")
        actor:AcceptInput("Use",player,player); env.receive("SendNPCInformation",player,"Next")
        eq(env.totalEnemies,info.maxNPCs)
    end)
    for _,mode in ipairs({"idle","selected","active","paused"}) do
        test("catalog reference changes only the pending slot in " .. mode .. " state",function()
            local env,admin=setup(); local info=env.NPCEdits[1].information
            env.NPCEdits[2]={name="Next",information=info}
            if mode=="selected" then say(env,admin,"!nextEvent Raid"); env.ready()
            elseif mode=="active" then env.start()
            elseif mode=="paused" then say(env,admin,"!pauseActivatorSpawns") end
            local names={"selectedBatchName","selectedBatchEntities","interactions","eventActive","eventInterrupted","activeEventName","initialEnemies","activeEnemies","automaticSpawnsPaused","spawnScheduleGeneration"}
            local before={}; for _,name in ipairs(names) do before[name]=state(env,name) end
            local messages,total,count=#env.messages,env.totalEnemies,env.activatorCount
            local function forbid(owner,key) owner[key]=function() error("unexpected side effect " .. key) end end
            env.math=setmetatable({}, {__index=math}); forbid(env.math,"random"); forbid(env.math,"randomseed")
            for _,key in ipairs({"Start","Stop","Create","Simple","Remove","Adjust"}) do forbid(env.timer,key) end
            for _,key in ipairs({"Read","Write","Append","Delete","CreateDir","Exists"}) do forbid(env.file,key) end
            for _,key in ipairs({"Start","Send","Broadcast","WriteString","WriteBool","WriteUInt","WriteEntity"}) do forbid(env.net,key) end
            for _,key in ipairs({"Create","FindByClass","FindByName"}) do forbid(env.ents,key) end
            for _,key in ipairs({"determineRandomEvent","returnNPCInformation","destroyActivators","returnDelayBetweenEvents","returnMaxActivators","returnMinNumberOfPlayers"}) do forbid(env,key) end
            for _,ent in ipairs(env.entities) do for _,key in ipairs({"Remove","Spawn","SetName","SetModel","SetPos","SetHealth"}) do forbid(ent,key) end end
            local refs=listed(env,admin); say(env,admin,"!nextEventRef " .. refs[1]); eq(pending(env),"Next")
            for _,name in ipairs(names) do assert(rawequal(state(env,name),before[name]),"preserve " .. name) end
            eq(#env.messages,messages); eq(env.totalEnemies,total); eq(env.activatorCount,count)
        end)
    end
end
