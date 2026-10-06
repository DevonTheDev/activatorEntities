-- Execute the real server hook with GMod doubles; native chat input/rendering
-- and NPC/model validity are deliberately outside this test suite's claims.
return function(gmod, test, eq)
    local function configured()
        local env=gmod.new()
        local admin=env.entity("player"); admin.admin=true
        return env,admin
    end
    local function contains(text, expected)
        assert(text:find(expected,1,true), "missing " .. expected .. " in " .. text)
    end
    local function say(env,admin,command)
        local before=#admin.chats
        eq(env.fire("PlayerSay",admin,command),"","recognized command is private")
        local lines={}
        for i=before+1,#admin.chats do lines[#lines+1]=admin.chats[i] end
        return lines,table.concat(lines,"\n")
    end
    local function catalog(env,admin,page)
        local lines,text=say(env,admin,"!listEvents" .. (page and (" " .. page) or ""))
        assert(#lines >= 3 and #lines <= 10,"catalog has header, at most eight body lines, and footer")
        for _,line in ipairs(lines) do
            assert(#line <= 240,"catalog exceeds conservative ChatPrint byte limit")
            assert(not line:find("[%c]"),"catalog emits a raw control byte")
        end
        contains(lines[1],"!nextEvent eligibility only; engine unchecked")
        contains(lines[#lines],"!listEvents")
        return lines,text
    end
    local function entries(env,admin)
        local lines=catalog(env,admin)
        local pages=assert(tonumber(lines[1]:match("page 1/(%d+)")),"page range in header")
        local found,diagnostics={},{}
        for page=1,pages do
            if page ~= 1 then lines=catalog(env,admin,page) end
            for i=2,#lines-1 do
                local id,part,total,status,kind,name=lines[i]:match('^Entry (%d+) part (%d+)/(%d+) %[(.*); (.-)%]: "(.*)"$')
                if id then
                    id,part,total=tonumber(id),tonumber(part),tonumber(total)
                    local entry=found[id] or {parts={},status=status,kind=kind,total=total}
                    eq(entry.status,status); eq(entry.kind,kind); eq(entry.total,total)
                    eq(entry.parts[part],nil,"no repeated part")
                    entry.parts[part]=name; found[id]=entry
                else diagnostics[#diagnostics+1]=lines[i] end
            end
        end
        for _,entry in ipairs(found) do
            eq(#entry.parts,entry.total,"all continuation parts reachable")
            entry.name=table.concat(entry.parts)
        end
        return found,table.concat(diagnostics,"\n"),pages
    end
    test("catalog privately lists the shipped definition with selection-only eligibility",function()
        local env,admin=configured(); local other=env.entity("player")
        local rows=entries(env,admin)
        eq(#rows,1); eq(rows[1].name,"Raid"); eq(rows[1].status,"eligible"); eq(rows[1].kind,"literal")
        eq(#other.chats,0); eq(#env.messages,0)
    end)
    test("catalog reaches every sparse name beyond eight in copied deterministic order",function()
        local env,admin=configured(); local info=env.NPCEdits[1].information
        local pool={}; env.NPCEdits=pool
        for i=19,1,-1 do pool[i*13]={name=string.format("Encounter %02d",i),information=info} end
        local rows,_,pages=entries(env,admin); eq(#rows,19); eq(pages,3)
        for i,row in ipairs(rows) do
            eq(row.name,string.format("Encounter %02d",i)); eq(pool[i*13].name,row.name)
        end
        local _,first=catalog(env,admin); local _,again=catalog(env,admin,1); eq(first,again)
        eq(env.NPCEdits,pool); eq(pool[1],nil,"configuration was not sorted in place")
    end)
    test("catalog preserves exact case spaces punctuation quotes and literal backslashes",function()
        local env,admin=configured()
        local names={"Raid","raid"," Raid","Raid ","Supply Raid: Alpha!",'A "quoted" raid',"  ","literal\\x0A"}
        env.NPCEdits={}
        for i,name in ipairs(names) do env.NPCEdits[i*7]={name=name,information={}} end
        table.sort(names)
        local rows=entries(env,admin); eq(#rows,#names)
        for i,name in ipairs(names) do
            eq(rows[i].name,name); eq(rows[i].status,"eligible"); eq(rows[i].kind,"literal")
            local _,response=say(env,admin,"!nextEvent " .. name)
            contains(response,"Queued for the next fresh automatic batch")
        end
    end)
    test("catalog groups duplicate names and counts missing or non-table information",function()
        local env,admin=configured()
        env.NPCEdits={ [9]={name="Duplicate",information={}}, [20]={name="Duplicate"},
            [31]={name="Duplicate",information=false}, [40]={name="Missing"},
            [50]={name="Wrong",information="bad"}, [60]={name="Empty info",information={}} }
        local rows=entries(env,admin); eq(#rows,4)
        eq(rows[1].name,"Duplicate")
        contains(rows[1].status,"duplicate name (3)")
        contains(rows[1].status,"missing information: 1")
        contains(rows[1].status,"non-table information: 1")
        eq(rows[2].status,"eligible","empty information table is selection eligible")
        contains(rows[3].status,"missing information: 1")
        contains(rows[4].status,"non-table information: 1")
        for _,row in ipairs(rows) do
            local _,response=say(env,admin,"!nextEvent " .. row.name)
            if row.status == "eligible" then contains(response,"Queued for the next fresh automatic batch")
            else contains(response,"Next event unchanged") end
        end
    end)
    test("catalog describes empty names and every malformed record without unstable addresses",function()
        local env,admin=configured()
        env.NPCEdits={false,17,"junk",{}, {name=false}, {name=42}, {name={}},
            {name="",information={}}, {name=""}, {name="Usable",information={}}}
        local rows,diagnostics=entries(env,admin); eq(#rows,2)
        eq(rows[1].name,""); contains(rows[1].status,"empty name")
        contains(rows[1].status,"duplicate name (2)"); contains(rows[1].status,"missing information: 1")
        contains(diagnostics,"Non-table records: 3; missing names: 1; non-string names: 3")
        assert(not diagnostics:find("table:",1,true),"diagnostics must not expose table addresses")
        local _,response=say(env,admin,"!nextEvent "); contains(response,"Usage:")
    end)
    for _,case in ipairs({"missing","empty","malformed"}) do
        test("catalog distinguishes " .. case .. " configuration",function()
            local env,admin=configured()
            if case == "missing" then env.NPCEdits=nil
            elseif case == "empty" then env.NPCEdits={}
            else env.NPCEdits=false end
            local _,diagnostics,pages=entries(env,admin); eq(pages,1)
            if case == "malformed" then contains(diagnostics,"Malformed encounter pool: expected table")
            else contains(diagnostics,"No configured encounters (" .. case .. " pool)") end
        end)
    end
    test("catalog reports malformed-only pools even without a named entry",function()
        local env,admin=configured(); env.NPCEdits={false,{}, {name=1}}
        local rows,diagnostics=entries(env,admin); eq(#rows,0)
        contains(diagnostics,"Non-table records: 1; missing names: 1; non-string names: 1")
    end)
    for _,character in ipairs({"x","é","火","🚀"}) do
        test("catalog continuation pages preserve every byte and UTF-8 boundary for " .. character,function()
            local env,admin=configured(); local name="A" .. string.rep(character,2000) .. " !tail  "
            env.NPCEdits={ [77]={name=name,information={}}, [900]={name="Z later name",information={}} }
            local rows,_,pages=entries(env,admin)
            assert(pages>1,"long entry consumes continuation pages")
            eq(#rows,2); eq(rows[1].name,name); eq(rows[2].name,"Z later name")
            for _,part in ipairs(rows[1].parts) do
                local remainder=part:gsub(character,"")
                assert(not remainder:find("[\128-\255]"),"split within a UTF-8 character")
            end
        end)
    end
    test("catalog marks control names as escaped diagnostics without colliding with literal escapes",function()
        local env,admin=configured(); local raw="A\\path\0\1\9\10\13\31\127火"
        env.NPCEdits={ {name=raw,information={}}, {name="A\\path\\x00\\x01\\x09\\x0A\\x0D\\x1F\\x7F火",information={}} }
        local rows=entries(env,admin); eq(#rows,2)
        eq(rows[1].kind,"escaped diagnostic"); eq(rows[1].status,"eligible")
        eq(rows[1].name,"A\\x5Cpath\\x00\\x01\\x09\\x0A\\x0D\\x1F\\x7F火")
        eq(rows[2].kind,"literal"); eq(rows[2].name,env.NPCEdits[2].name)
        eq(env.NPCEdits[1].name,raw,"catalog never renames configuration")
        local _,response=say(env,admin,"!nextEvent " .. raw)
        contains(response,"Queued for the next fresh automatic batch")
    end)
    test("catalog long escaped representations remain complete and bounded",function()
        local env,admin=configured(); local raw=string.rep("火\n\\",1800)
        env.NPCEdits={ {name=raw,information={}} }
        local rows,_,pages=entries(env,admin); assert(pages>8)
        eq(rows[1].kind,"escaped diagnostic")
        eq(rows[1].name,string.rep("火\\x0A\\x5C",1800))
    end)
    for _,argument in ipairs({"0","-1","+1","1.0","1e0","0x1","NaN","inf","2","9999999999999999999999999999999999999999","1 2","1\n2","page","1x"}) do
        test("catalog rejects invalid or out-of-range page " .. argument:gsub("%c"," "),function()
            local env,admin=configured()
            local lines,text=say(env,admin,"!listEvents " .. argument)
            eq(#lines,1); assert(#lines[1]<=240); contains(text,"Usage: !listEvents [page]")
            contains(text,"1-1"); assert(not text:find("Entry",1,true))
        end)
    end
    test("catalog accepts default and positive decimal pages with surrounding whitespace",function()
        local env,admin=configured(); local _,first=catalog(env,admin)
        for _,command in ipairs({"!listEvents 1","!listEvents 01","!listEvents ","!listEvents\t1 ","!listEvents   1  "}) do
            local _,text=say(env,admin,command); eq(text,first)
        end
    end)
    test("catalog checks valid players and admins and ignores lookalike command tokens",function()
        local env,admin=configured(); local ordinary=env.entity("player")
        local nonplayer=env.entity("prop_physics"); nonplayer.admin=true
        local invalid=env.entity("player"); invalid.valid=false; invalid.admin=true
        for _,command in ipairs({"!listEvents","!listEvents 1","!listEvents invalid"}) do
            local lines,text=say(env,ordinary,command); eq(#lines,1); contains(text,"Only admins")
            eq(env.fire("PlayerSay",nonplayer,command),nil); eq(#nonplayer.chats,0)
            eq(env.fire("PlayerSay",invalid,command),nil); eq(#invalid.chats,0)
        end
        for _,command in ipairs({"!listEventsExtra","!listEvents1","!listevents"," !listEvents","!listEvents/2","hello"}) do
            eq(env.fire("PlayerSay",admin,command),nil)
        end
        eq(#admin.chats,0)
    end)
    test("catalog snapshots each invocation before emitting any line",function()
        local env,admin=configured(); local original=admin.ChatPrint
        admin.ChatPrint=function(self,text)
            original(self,text)
            env.NPCEdits={ {name="New name",information={}}, {name="New name"} }
        end
        local rows=entries(env,admin); eq(rows[1].name,"Raid"); eq(rows[1].status,"eligible")
        admin.ChatPrint=original
        rows=entries(env,admin); eq(rows[1].name,"New name"); contains(rows[1].status,"duplicate name (2)")
        env.NPCEdits[2]=nil; env.NPCEdits[1].information=false
        rows=entries(env,admin); contains(rows[1].status,"non-table information: 1")
    end)
    test("bare nextEvent still lists names and points to the complete catalog",function()
        local env,admin=configured(); local _,text=say(env,admin,"!nextEvent")
        contains(text,'Configured event: "Raid"'); contains(text,"!listEvents")
    end)

    -- Capture real closure state and table identities, including entries whose
    -- deletion is deferred. ChatPrint output is the only expected mutation.
    local stateNames={pendingSelection=true,selectedBatchName=true,selectedBatchEntities=true,
        interactions=true,eventActive=true,eventInterrupted=true,activeEventName=true,
        initialEnemies=true,activeEnemies=true,constructingEnemies=true,statusRequestAfter=true}
    local function capture(env)
        local state={NPCEdits=env.NPCEdits,SpawnPositions=env.SpawnPositions,entities=env.entities,
            timers=env.timers,messages=env.messages,activatorCount=env.activatorCount,totalEnemies=env.totalEnemies}
        local seen={}
        local function visit(fn)
            if seen[fn] then return end; seen[fn]=true
            for i=1,100 do
                local name,value=debug.getupvalue(fn,i); if not name then break end
                if stateNames[name] then state[name]=value end
                if type(value)=="function" then visit(value) end
            end
        end
        for _,callbacks in pairs(env.hooks) do for _,fn in pairs(callbacks) do visit(fn) end end
        for _,fn in pairs(env.receivers) do visit(fn) end
        for _,timer in pairs(env.timers) do visit(timer.callback) end
        local records={}
        local function copy(value)
            if type(value)~="table" or records[value] then return end
            local record={}; records[value]=record
            for key,item in pairs(value) do
                if key~="chats" then record[key]=item; copy(key); copy(item) end
            end
        end
        copy(state)
        return state,records
    end
    local function unchanged(before,records,after)
        for key,value in pairs(before) do eq(after[key],value,"state identity " .. key) end
        for key,value in pairs(after) do eq(before[key],value,"state identity " .. key) end
        for object,record in pairs(records) do
            for key,value in pairs(record) do eq(object[key],value,"read-only snapshot key " .. tostring(key)) end
            for key,value in pairs(object) do
                if key~="chats" then eq(record[key],value,"no new state key " .. tostring(key)) end
            end
        end
    end
    local function readOnly(env,admin)
        local before,records=capture(env)
        local originals={}
        local function forbid(owner,key)
            originals[#originals+1]={owner,key,owner[key]}
            owner[key]=function() error("catalog called forbidden " .. key) end
        end
        local previousMath=env.math; env.math=setmetatable({}, {__index=math})
        for _,key in ipairs({"random","randomseed"}) do forbid(env.math,key) end
        for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnActivatorSpawns","returnSpawnPositions",
            "destroyActivators","returnDelayBetweenEvents","returnMaxActivators","returnMinNumberOfPlayers"}) do forbid(env,key) end
        for _,key in ipairs({"Start","Stop","Create","Simple","Remove","Adjust"}) do forbid(env.timer,key) end
        for _,key in ipairs({"Read","Write","Append","Delete","CreateDir","Exists"}) do forbid(env.file,key) end
        for _,key in ipairs({"Start","Send","Broadcast","WriteString","WriteBool","WriteUInt","WriteEntity"}) do forbid(env.net,key) end
        for _,key in ipairs({"Create","FindByClass","FindByName"}) do forbid(env.ents,key) end
        forbid(env.util,"AddNetworkString"); forbid(env.hook,"Add")
        for _,ent in ipairs(env.entities) do
            for _,key in ipairs({"Remove","Spawn","SetName","SetModel","SetPos","SetHealth","SetMoveType","StopMoving"}) do forbid(ent,key) end
        end
        local ok,err=pcall(function()
            catalog(env,admin); catalog(env,admin,1)
            say(env,admin,"!listEvents 0"); say(env,admin,"!listEvents 9999")
        end)
        for _,entry in ipairs(originals) do entry[1][entry[2]]=entry[3] end
        env.math=previousMath
        assert(ok,err)
        unchanged(before,records,capture(env))
    end
    for _,phase in ipairs({"pending","selected with interaction","active interrupted","deferred selected removal"}) do
        test("catalog preserves all state and side-effect traps during " .. phase,function()
            local env,admin=configured()
            env.NPCEdits[50]={name="Next",information=env.NPCEdits[1].information}
            say(env,admin,"!nextEvent Raid")
            if phase~="pending" then
                env.fireTimer("activatorSpawner")
                local ent=env.ents.FindByClass("activatorent")[1]
                admin:SetPos(ent:GetPos()); ent:AcceptInput("Use",admin,admin)
                say(env,admin,"!nextEvent Next")
                if phase=="active interrupted" then
                    env.receive("SendNPCInformation",admin,"Raid")
                    env.ents.FindByName("devonsSpawnedEntity")[1]:Remove()
                elseif phase=="deferred selected removal" then
                    env.deferRemoval=true
                    for _,actor in ipairs(env.ents.FindByClass("activatorent")) do actor:Remove() end
                end
            end
            readOnly(env,admin)
            if phase=="selected with interaction" then
                env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,5,"interaction still starts normally")
            elseif phase=="pending" then
                env.fireTimer("activatorSpawner")
                eq(env.ents.FindByClass("activatorent")[1].EventIdentifier,"Raid")
            end
        end)
    end
end
