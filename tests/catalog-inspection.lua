-- Actual mounted PlayerSay handlers with engine doubles; no native GMod claims.
return function(gmod,test,eq)
    local function contains(text,part) assert(text:find(part,1,true),"missing " .. part .. " in " .. text) end
    local function setup()
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        return env,admin,env.NPCEdits[1].information
    end
    local function say(env,admin,command)
        local first=#admin.chats+1
        eq(env.fire("PlayerSay",admin,command),"","recognized command stays private")
        local lines={}; for i=first,#admin.chats do lines[#lines+1]=admin.chats[i] end
        for _,line in ipairs(lines) do assert(#line<=255,"bounded ChatPrint"); assert(not line:find("[%c]"),"control-safe ChatPrint") end
        return table.concat(lines,"\n"),lines
    end
    local function listed(env,admin)
        local text=say(env,admin,"!listEvents")
        return assert(text:match(" ref ([%w%-]+) "),"listed eligible reference")
    end
    local function inspect(env,admin,token) return say(env,admin,"!inspectEventRef " .. token) end
    local function state(env,name)
        local seen={}
        local function visit(fn)
            if seen[fn] then return end; seen[fn]=true
            for i=1,100 do
                local key,value=debug.getupvalue(fn,i); if not key then break end
                if key==name then return value,true end
                if type(value)=="function" then local found,ok=visit(value); if ok then return found,true end end
            end
        end
        for _,callbacks in pairs(env.hooks) do for _,fn in pairs(callbacks) do
            local value,found=visit(fn); if found then return value end
        end end
    end
    local function noDetails(text) assert(not text:find("activatorModel:",1,true),"stale details leaked") end
    test("inspection shows a current configuration snapshot and leaves reference selectable",function()
        local env,admin,info=setup(); local other=env.entity("player")
        local token=listed(env,admin); local page=state(env,"catalogInspections")[admin]
        local generation=state(env,"catalogGeneration"); local expires=page.expires
        info.activatorModel="models/barney.mdl"; info.npcPath="npc_zombie"; info.maxNPCs=2.75
        local text,lines=inspect(env,admin,token)
        eq(#lines,5); contains(text,"Configuration snapshot"); contains(text,'"Raid"')
        contains(text,'activatorModel: "models/barney.mdl"'); contains(text,'npcPath (enemy class): "npc_zombie"')
        contains(text,"maxNPCs (requested count): 2.75; finite >= 1; floor = 2 creation attempts")
        contains(text,"engine unchecked"); contains(text,"reference not consumed")
        eq(#other.chats,0); eq(#env.messages,0); eq(state(env,"pendingSelection"),nil)
        assert(rawequal(state(env,"catalogInspections")[admin],page)); eq(page.expires,expires); eq(state(env,"catalogGeneration"),generation)
        say(env,admin,"!nextEventRef " .. token); eq(state(env,"pendingSelection").name,"Raid")
        noDetails(inspect(env,admin,token))
        local player,actor=env.ready(); eq(actor:GetModel(),"models/barney.mdl")
        actor:AcceptInput("Use",player,player); env.receive("SendNPCInformation",player,"Raid")
        eq(env.totalEnemies,2); eq(info.maxNPCs,2.75)
    end)
    test("inspection does not extend expiry after repeated reads",function()
        local env,admin=setup(); env.now=123.456; local token=listed(env,admin)
        env.now=180; eq(select(2,inspect(env,admin,token))[1]:find("Configuration snapshot",1,true),1)
        env.now=183.455; inspect(env,admin,token)
        env.now=state(env,"catalogInspections")[admin].expires; noDetails(inspect(env,admin,token)); noDetails(say(env,admin,"!nextEventRef " .. token))
        eq(state(env,"pendingSelection"),nil)
    end)
    for _,mode in ipairs({"table","function"}) do
        test("inspection preserves inherited configured fields via " .. mode,function()
            local env,admin,old=setup(); local fields={activatorModel=old.activatorModel,npcPath="npc_zombie",maxNPCs=1.5}
            local reads={}; local getter=fields
            if mode=="function" then getter=function(_,key) reads[key]=(reads[key] or 0)+1; return fields[key] end end
            local info=setmetatable({}, {__index=getter})
            env.NPCEdits={setmetatable({}, {__index={name="Inherited",information=info}})}
            local token=listed(env,admin); local text=inspect(env,admin,token)
            contains(text,'"Inherited"'); contains(text,'activatorModel: "' .. old.activatorModel .. '"')
            contains(text,'npcPath (enemy class): "npc_zombie"'); contains(text,"floor = 1 creation attempts")
            if mode=="function" then eq(reads.activatorModel,1); eq(reads.npcPath,1); eq(reads.maxNPCs,1); eq(reads.dialogue,nil) end
            say(env,admin,"!nextEventRef " .. token); eq(state(env,"pendingSelection").name,"Inherited")
        end)
    end
    local malformed={{"missing",nil},{"empty string",""},{"boolean",false},{"number",12},{"function",function() end},
        {"table",setmetatable({}, {__tostring=function() error("never stringify config") end})}}
    for _,field in ipairs({"activatorModel","npcPath"}) do for _,case in ipairs(malformed) do
        test("inspection describes " .. field .. " " .. case[1],function()
            local env,admin,info=setup(); info[field]=case[2]; local text=inspect(env,admin,listed(env,admin))
            contains(text,case[1]=="missing" and "missing" or ("invalid " .. case[1]))
            assert(rawequal(rawget(info,field),case[2]),"field unchanged"); contains(text,"engine unchecked")
        end)
    end end
    for _,case in ipairs({{"missing",nil},{"boolean",false},{"string","2"},{"table",setmetatable({}, {__tostring=function() error("no tostring") end})},
        {"function",function() end},{"zero",0},{"negative",-1},{"below one",0.75},{"NaN",0/0},{"infinity",math.huge},{"negative infinity",-math.huge}}) do
        test("inspection rejects configured count " .. case[1],function()
            local env,admin,info=setup(); info.maxNPCs=case[2]; local _,lines=inspect(env,admin,listed(env,admin))
            contains(lines[4],case[1]=="missing" and "missing" or "invalid")
            contains(lines[4],"finite number >= 1"); assert(not lines[4]:find("creation attempts",1,true))
        end)
    end
    for _,count in ipairs({1,1.5,2.75,5,1e100}) do
        test("inspection describes finite count " .. count .. " without rounding the configuration",function()
            local env,admin,info=setup(); info.maxNPCs=count; local _,lines=inspect(env,admin,listed(env,admin))
            contains(lines[4],"floor = " .. tostring(math.floor(count)) .. " creation attempts")
            contains(lines[4],tostring(count)); eq(info.maxNPCs,count)
        end)
    end
    for _,count in ipairs({1.9999999999999998,2.99999999999999,9007199254740991}) do
        test("inspection reports exact near-integer requested count " .. string.format("%.17g",count),function()
            local env,admin,info=setup(); info.maxNPCs=count
            local _,lines=inspect(env,admin,listed(env,admin))
            local shown=assert(lines[4]:match("^maxNPCs %(requested count%): ([^;]+);"))
            eq(tonumber(shown),count,"display must round-trip without crossing the floor boundary")
            local floor=assert(lines[4]:match("floor = (%S+) creation attempts"))
            eq(tonumber(floor),math.floor(count)); eq(info.maxNPCs,count)
        end)
    end
    for _,character in ipairs({"é","火","🚀"}) do
        test("inspection bounds long UTF-8 labels for " .. character,function()
            local env,admin,info=setup(); local label=string.rep(character,300)
            env.NPCEdits[1].name=label; info.activatorModel=label; info.npcPath=label
            local text,lines=inspect(env,admin,listed(env,admin)); eq(#lines,5)
            for i=1,3 do
                contains(lines[i],"[truncated]")
                local rest=lines[i]:gsub(character,""); assert(not rest:find("[\128-\255]"),"split UTF-8 character")
            end
            eq(env.NPCEdits[1].name,label); eq(info.activatorModel,label); contains(text,"engine unchecked")
        end)
    end
    test("inspection escapes control labels without changing raw configuration",function()
        local env,admin,info=setup(); local raw="A\0\n\r\t\127\\火"
        env.NPCEdits[1].name=raw; info.activatorModel=raw; info.npcPath=raw
        local text,lines=inspect(env,admin,listed(env,admin)); eq(#lines,5)
        for i=1,3 do contains(lines[i],"escaped diagnostic"); contains(lines[i],"\\x00"); contains(lines[i],"\\x0A"); contains(lines[i],"\\x5C") end
        eq(info.activatorModel,raw); eq(env.NPCEdits[1].name,raw)
    end)
    test("inspection copies all rendered fields before ChatPrint callbacks",function()
        local env,admin,info=setup(); local token=listed(env,admin); local original=admin.ChatPrint; local once
        admin.ChatPrint=function(self,text)
            original(self,text)
            if not once then once=true; info.activatorModel="changed model"; info.npcPath="changed class"; info.maxNPCs=20 end
        end
        local text=inspect(env,admin,token); admin.ChatPrint=original
        contains(text,'activatorModel: "models/alyx.mdl"'); contains(text,'npcPath (enemy class): "npc_stalker"')
        contains(text,"floor = 5 creation attempts"); assert(not text:find("changed model",1,true)); assert(not text:find("changed class",1,true)); eq(info.maxNPCs,20)
        contains(inspect(env,admin,token),'activatorModel: "changed model"')
    end)
    for _,command in ipairs({"!inspectEventRef","!inspectEventRef ","!inspectEventRef a b","!inspectEventRef a\nb"}) do
        test("inspection enforces one-token grammar " .. command:gsub("%c"," "),function()
            local env,admin=setup(); listed(env,admin); local text,lines=say(env,admin,command)
            eq(#lines,1); contains(text,"Usage: !inspectEventRef <ref>")
        end)
    end
    test("inspection accepts token whitespace and ignores command lookalikes",function()
        local env,admin=setup(); local token=listed(env,admin)
        contains(say(env,admin,"!inspectEventRef\t" .. token .. "  "),"Configuration snapshot")
        for _,command in ipairs({"!inspectEventRefExtra","!inspectEventRef/1","!inspecteventref"," !inspectEventRef","hello"}) do
            eq(env.fire("PlayerSay",admin,command),nil)
        end
    end)
    test("inspection requires a live admin player and an owned displayed reference",function()
        local env,admin=setup(); local token=listed(env,admin); local other=env.entity("player"); other.admin=true
        noDetails(inspect(env,other,token)); noDetails(inspect(env,admin,"1")); noDetails(inspect(env,admin,"Raid"))
        local offpage=token:gsub("%-%d+$","-9"); noDetails(inspect(env,admin,offpage))
        admin.admin=false; contains(inspect(env,admin,token),"Only admins"); admin.admin=true
        for _,actor in ipairs({env.entity("prop_physics"),{valid=false}}) do eq(env.fire("PlayerSay",actor,"!inspectEventRef " .. token),nil) end
        eq(env.fire("PlayerSay",nil,"!inspectEventRef " .. token),nil)
    end)
    local changes={"relist","select reference","select name","clear choice","disconnect","initialize","demote","invalidate","map","expiry", "pool","record","information","rename","duplicate","moved key"}
    local function change(env,admin,token,kind)
        local record=env.NPCEdits[1]
        if kind=="relist" then listed(env,admin)
        elseif kind=="select reference" then say(env,admin,"!nextEventRef " .. token)
        elseif kind=="select name" then say(env,admin,"!nextEvent Raid")
        elseif kind=="clear choice" then say(env,admin,"!clearNextEvent")
        elseif kind=="disconnect" then env.fire("PlayerDisconnected",admin)
        elseif kind=="initialize" then env.fire("Initialize")
        elseif kind=="demote" then admin.admin=false
        elseif kind=="invalidate" then admin.valid=false
        elseif kind=="map" then env.map="gm_other"
        elseif kind=="expiry" then env.now=60
        elseif kind=="pool" then env.NPCEdits={record}
        elseif kind=="record" then env.NPCEdits[1]={name=record.name,information=record.information}
        elseif kind=="information" then record.information={}
        elseif kind=="rename" then record.name="Renamed"
        elseif kind=="duplicate" then env.NPCEdits[90]={name=record.name,information={}}
        else env.NPCEdits[90]=record; env.NPCEdits[1]=nil end
    end
    for _,kind in ipairs(changes) do
        if kind~="select name" and kind~="clear choice" then
            test("inspection refuses stale authority after " .. kind,function()
                local env,admin=setup(); say(env,admin,"!nextEvent Raid"); local token=listed(env,admin)
                local before=state(env,"pendingSelection"); change(env,admin,token,kind)
                if kind=="invalidate" then eq(env.fire("PlayerSay",admin,"!inspectEventRef " .. token),nil)
                else noDetails(inspect(env,admin,token)) end
                if kind~="select reference" then assert(rawequal(state(env,"pendingSelection"),before)) end
            end)
        end
        for row=1,4 do
            test("inspection stops after reply " .. row .. " reenters " .. kind,function()
                local env,admin=setup(); say(env,admin,"!nextEvent Raid"); local token=listed(env,admin)
                local original=admin.ChatPrint; local lines,nested={},false
                admin.ChatPrint=function(self,text)
                    original(self,text)
                    if nested then return end
                    lines[#lines+1]=text
                    if #lines==row then nested=true; change(env,admin,token,kind); nested=false end
                end
                inspect(env,admin,token); admin.ChatPrint=original
                eq(#lines,row,"old inspection stops at callback boundary")
                if kind=="relist" then
                    local fresh=next(state(env,"catalogInspections")[admin].targets)
                    say(env,admin,"!nextEventRef " .. fresh); eq(state(env,"pendingSelection").name,"Raid")
                elseif kind=="select reference" or kind=="select name" then eq(state(env,"pendingSelection").name,"Raid")
                elseif kind=="clear choice" then eq(state(env,"pendingSelection"),nil) end
            end)
        end
    end
    for _,now in ipairs({-1,60,math.huge,-math.huge,0/0}) do
        test("inspection refuses invalid time " .. tostring(now),function()
            local env,admin=setup(); local token=listed(env,admin); env.now=now
            noDetails(inspect(env,admin,token)); eq(state(env,"pendingSelection"),nil)
        end)
    end
    for _,field in ipairs({"activatorModel","npcPath","maxNPCs"}) do
        for _,kind in ipairs({"relist","select reference","select name","disconnect","demote","invalidate","expiry","duplicate","information"}) do
            test("inspection revalidates after " .. field .. " getter reenters " .. kind,function()
                local env,admin,info=setup(); local value=info[field]; info[field]=nil; local token=listed(env,admin); local once
                setmetatable(info,{__index=function(_,key)
                    if key==field then
                        if not once then once=true; change(env,admin,token,kind) end
                        return value
                    end
                end})
                local original=admin.ChatPrint; local lines={}; local nested=false
                -- Record only inspection output, excluding deliberate callback commands.
                local getter=getmetatable(info).__index
                getmetatable(info).__index=function(...) nested=true; local value=getter(...); nested=false; return value end
                admin.ChatPrint=function(self,text) original(self,text); if not nested then lines[#lines+1]=text end end
                inspect(env,admin,token); admin.ChatPrint=original
                for _,line in ipairs(lines) do assert(not line:find("Configuration snapshot",1,true),"no stale snapshot after config getter") end
                if kind=="relist" then assert(state(env,"catalogInspections")[admin],"new page survives") end
            end)
        end
    end
    for _,field in ipairs({"name","information"}) do
        test("inspection rejects inherited " .. field .. " changed by snapshot getter before first row",function()
            local env,admin,info=setup(); local inherited={name="Raid",information=info}
            env.NPCEdits={setmetatable({}, {__index=inherited})}
            local token=listed(env,admin); info.activatorModel=nil
            setmetatable(info,{__index=function(_,key)
                if key=="activatorModel" then
                    inherited[field]=field=="name" and "Other" or {}
                    return "models/alyx.mdl"
                end
            end})
            local _,lines=inspect(env,admin,token); eq(#lines,0,"fresh validation after snapshot lookup")
            eq(state(env,"pendingSelection"),nil)
        end)
    end
    test("inspection handles throwing fields privately without consuming the reference",function()
        local env,admin,info=setup(); local token=listed(env,admin); info.activatorModel=nil
        setmetatable(info,{__index=function() error("private sensitive details") end})
        local text=inspect(env,admin,token); noDetails(text); assert(not text:find("private sensitive details",1,true))
        setmetatable(info,nil); say(env,admin,"!nextEventRef " .. token); eq(state(env,"pendingSelection").name,"Raid")
    end)
    test("nested inspection owns the later reply stream without renewing the catalog",function()
        local env,admin=setup(); local token=listed(env,admin); local page=state(env,"catalogInspections")[admin]
        local original=admin.ChatPrint; local once; local outer=0; local nested=false
        admin.ChatPrint=function(self,text)
            original(self,text); if nested then return end; outer=outer+1
            if not once then once=true; nested=true; eq(#select(2,inspect(env,admin,token)),5); nested=false end
        end
        inspect(env,admin,token); admin.ChatPrint=original; eq(outer,1)
        assert(rawequal(state(env,"catalogInspections")[admin],page)); eq(page.expires,60)
    end)
    for _,who in ipairs({"same admin","another admin"}) do
        for _,operation in ipairs({"select then clear","clear only"}) do
            test("inspection stops for restored nil pending after " .. operation .. " by " .. who,function()
                local env,admin=setup(); local token=listed(env,admin)
                local other=admin
                if who=="another admin" then other=env.entity("player"); other.admin=true end
                local original=admin.ChatPrint; local outer,nested,once=0,false,false
                admin.ChatPrint=function(self,text)
                    original(self,text); if nested then return end; outer=outer+1
                    if not once then
                        once=true; nested=true
                        if operation=="select then clear" then say(env,other,"!nextEvent Raid") end
                        say(env,other,"!clearNextEvent"); nested=false
                    end
                end
                inspect(env,admin,token); admin.ChatPrint=original
                eq(state(env,"pendingSelection"),nil); eq(outer,1,"successful selection command retires old reply stream")
                say(env,admin,"!nextEventRef " .. token); eq(state(env,"pendingSelection").name,"Raid")
            end)
        end
    end
    for _,getter in ipairs({"GetMap","CurTime","IsAdmin","IsPlayer"}) do
        test("inspection revalidates after initial " .. getter .. " reentry",function()
            local env,admin=setup(); local token=listed(env,admin); local once
            local owner=getter=="GetMap" and env.game or (getter=="CurTime" and env or admin)
            local original=owner[getter]
            owner[getter]=function(...)
                if not once then once=true; listed(env,admin) end
                return original(...)
            end
            local _,lines=inspect(env,admin,token); owner[getter]=original
            for _,line in ipairs(lines) do assert(not line:find("Configuration snapshot",1,true)) end
        end)
    end
    for _,mode in ipairs({"pending","ready with interaction","active interrupted","paused"}) do
        test("inspection preserves gameplay data and traps side effects in " .. mode,function()
            local env,admin=setup(); say(env,admin,"!nextEvent Raid")
            if mode=="ready with interaction" then
                local _,actor=env.ready(); admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
            elseif mode=="active interrupted" then local _,enemies=env.start(); enemies[1]:Remove()
            elseif mode=="paused" then say(env,admin,"!pauseActivatorSpawns") end
            local token=listed(env,admin)
            local names={"pendingSelection","selectedBatchName","selectedBatchEntities","interactions","eventActive","eventInterrupted","activeEventName","initialEnemies","activeEnemies","automaticSpawnsPaused","spawnScheduleGeneration","catalogGeneration","catalogInspections"}
            local before={}; for _,name in ipairs(names) do before[name]=state(env,name) end
            local page=state(env,"catalogInspections")[admin]; local expires=page.expires
            local messages,total,count=#env.messages,env.totalEnemies,env.activatorCount
            local snapshot={}; local function capture(value)
                if type(value)~="table" or snapshot[value] then return end
                local record={}; snapshot[value]=record
                for key,item in pairs(value) do if key~="chats" then record[key]=item; capture(item) end end
            end
            local originals={}; local function forbid(owner,key)
                originals[#originals+1]={owner,key,owner[key]}; owner[key]=function() error("unexpected side effect " .. key) end
            end
            local oldMath=env.math; env.math=setmetatable({}, {__index=math})
            for _,key in ipairs({"random","randomseed"}) do forbid(env.math,key) end
            for _,key in ipairs({"Start","Stop","Create","Simple","Remove","Adjust"}) do forbid(env.timer,key) end
            for _,key in ipairs({"Read","Write","Append","Delete","CreateDir","Exists"}) do forbid(env.file,key) end
            for _,key in ipairs({"Start","Send","Broadcast","WriteString","WriteBool","WriteUInt","WriteEntity"}) do forbid(env.net,key) end
            for _,key in ipairs({"Create","FindByClass","FindByName"}) do forbid(env.ents,key) end
            for _,key in ipairs({"IsValidModel","IsValidProp","IsValidRagdoll","PrecacheModel"}) do forbid(env.util,key) end
            for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnEnemyHealth","destroyActivators","returnDelayBetweenEvents","returnMaxActivators","returnMinNumberOfPlayers"}) do forbid(env,key) end
            for _,ent in ipairs(env.entities) do for _,key in ipairs({"Remove","Spawn","SetName","SetModel","SetPos","SetHealth","GetModel","GetPhysicsObject"}) do forbid(ent,key) end end
            capture(before); capture(env.NPCEdits); capture(env.SpawnPositions); capture(env.entities); capture(env.timers)
            local text=inspect(env,admin,token); contains(text,"Configuration snapshot")
            for _,name in ipairs(names) do assert(rawequal(state(env,name),before[name]),"preserve " .. name) end
            for object,record in pairs(snapshot) do
                for key,value in pairs(record) do assert(rawequal(object[key],value),"preserve table field") end
                for key,value in pairs(object) do if key~="chats" then assert(rawequal(record[key],value),"no new table field") end end
            end
            eq(page.expires,expires); eq(#env.messages,messages); eq(env.totalEnemies,total); eq(env.activatorCount,count)
            for _,entry in ipairs(originals) do entry[1][entry[2]]=entry[3] end; env.math=oldMath
            say(env,admin,"!nextEventRef " .. token); eq(state(env,"pendingSelection").name,"Raid")
            if mode=="ready with interaction" then env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,5) end
        end)
    end
end
