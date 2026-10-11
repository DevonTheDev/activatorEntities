-- Actual PlayerSay callbacks with GMod doubles; native chat remains unverified.
return function(gmod,test,eq)
    local function contains(text,part) assert(text:find(part,1,true),"missing " .. part .. " in " .. text) end
    local function setup(names)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        if names then
            env.NPCEdits={}
            for i,name in ipairs(names) do env.NPCEdits[i*7]={name=name,information={}} end
        end
        return env,admin
    end
    local function say(env,admin,command)
        local first=#admin.chats+1
        eq(env.fire("PlayerSay",admin,command),"","recognized command stays private")
        local lines={}; for i=first,#admin.chats do lines[#lines+1]=admin.chats[i] end
        for _,line in ipairs(lines) do assert(#line<=255,"bounded private chat line"); assert(not line:find("[%c]"),"no raw ASCII controls") end
        return table.concat(lines,"\n"),lines
    end
    local function page(env,admin,query,number)
        local text,lines=say(env,admin,query and ("!findEvents " .. (number or 1) .. " " .. query)
            or ("!listEvents" .. (number and (" " .. number) or "")))
        assert(#lines>=3 and #lines<=10,"header, at most eight body lines, footer")
        contains(lines[1],"!nextEvent eligibility only; engine unchecked")
        local refs={}
        for _,line in ipairs(lines) do
            assert(#line<=240,"catalog preserves conservative line budget")
            local id,token=line:match("^Entry (%d+) part %d+/%d+ ref ([%w%-]+) ")
            if token then
                if refs[tonumber(id)] then eq(refs[tonumber(id)],token,"continuation token identity") end
                refs[tonumber(id)]=token
            end
        end
        return refs,text,lines
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
    local function refused(env,admin,token)
        local before=state(env,"pendingSelection")
        local text=say(env,admin,"!nextEventRef " .. token)
        contains(text,"unchanged"); assert(rawequal(before,state(env,"pendingSelection")),"refusal preserves pending")
        local details=say(env,admin,"!inspectEventRef " .. token)
        assert(not details:find("activatorModel:",1,true),"invalid reference cannot inspect")
    end

    test("search privately finds configured names with ASCII-insensitive literal substrings",function()
        local env,admin=setup({"Ambush","RAID north","Supply raid","Raid"}); local other=env.entity("player")
        local refs,text,lines=page(env,admin,"rAiD")
        contains(lines[1],"page 1/1 (3 matching names)"); eq(refs[1],nil)
        assert(refs[2] and refs[3] and refs[4]); assert(not text:find('"Ambush"',1,true))
        eq(#other.chats,0); eq(#env.messages,0); eq(state(env,"pendingSelection"),nil)
    end)
    for _,query in ipairs({"[a].%", "^$()*+-?", '"quoted"', "\\x00", "two  spaces", "!nextEvent", "1"}) do
        test("search treats punctuation literally: " .. query,function()
            local env,admin=setup({"Prefix " .. query .. " suffix","unrelated"})
            local refs,text=page(env,admin,query); assert(refs[1]); eq(refs[2],nil)
            contains(text,"1 matching names"); say(env,admin,"!nextEventRef " .. refs[1])
            eq(state(env,"pendingSelection").name,"Prefix " .. query .. " suffix")
        end)
    end
    test("search preserves non-ASCII bytes without Unicode case folding",function()
        local env,admin=setup({"ÉCLAIR 火 🚀","éclair 火 🚀"})
        local refs,text=page(env,admin,"éCLAIR"); eq(refs[1],nil); assert(refs[2]); contains(text,"1 matching names")
        local all=page(env,admin,"火 🚀"); assert(all[1] and all[2])
    end)
    test("search matches original names rather than escaped diagnostics",function()
        local env,admin=setup({"A\0Raid\\tail","A\\x00Raid\\tail"})
        local literal,text=page(env,admin,"\\x00"); eq(literal[1],nil); assert(literal[2]); contains(text,"1 matching names")
        local refs=page(env,admin,"a"); assert(refs[1] and refs[2])
        contains(say(env,admin,"!inspectEventRef " .. refs[1]),"escaped diagnostic")
        say(env,admin,"!nextEventRef " .. refs[1]); eq(state(env,"pendingSelection").name,"A\0Raid\\tail")
    end)
    test("search retains global duplicate and malformed-information eligibility",function()
        local env,admin=setup(); local info={}
        env.NPCEdits={false,{}, {name=42}, {name="Other",information={}},
            {name="Raid",information=info},setmetatable({}, {__index={name="Raid",information=info}}),
            {name="Raid"},{name="Raid",information=false},{name="Raid missing"},
            {name="Raid wrong",information=3},{name="Raid valid",information={}}}
        local refs,text,lines=page(env,admin,"RAID")
        contains(lines[1],"4 matching names"); contains(text,"duplicate name (4)")
        contains(text,"missing information: 1"); contains(text,"non-table information: 1")
        eq(refs[1],nil); eq(refs[2],nil); eq(refs[3],nil); assert(refs[4]); eq(refs[5],nil)
        contains(text,"Unfiltered pool diagnostics: Non-table records: 1; missing names: 1; non-string names: 1")
        local forged=refs[4]:gsub("%-%d+$","-2"); refused(env,admin,forged)
        say(env,admin,"!nextEventRef " .. refs[4]); eq(state(env,"pendingSelection").name,"Raid valid")
    end)
    for _,kind in ipairs({"named","malformed only","empty","missing","non-table"}) do
        test("zero-match search is explicit with honest diagnostics for " .. kind,function()
            local env,admin=setup()
            if kind=="malformed only" then env.NPCEdits={false,{}, {name=true}}
            elseif kind=="empty" then env.NPCEdits={}
            elseif kind=="missing" then env.NPCEdits=nil
            elseif kind=="non-table" then env.NPCEdits=false end
            local refs,text,lines=page(env,admin,"absent")
            eq(next(refs),nil); contains(lines[1],"page 1/1 (0 matching names)")
            contains(text,"No configured names match this literal search.")
            if kind=="malformed only" then contains(text,"Unfiltered pool diagnostics: Non-table records: 1; missing names: 1; non-string names: 1") end
            if kind=="missing" then contains(text,"missing pool") end
            if kind=="non-table" then contains(text,"Malformed encounter pool") end
            local bad=say(env,admin,"!findEvents 2 absent"); contains(bad,"1-1")
        end)
    end
    test("search accepts exactly bounded query bytes and zero-padded positive pages",function()
        local query=string.rep("火",42) .. "AB"; eq(#query,128)
        local env,admin=setup({query}); local refs=page(env,admin,query,"000001")
        assert(refs[1]); say(env,admin,"!nextEventRef " .. refs[1]); eq(state(env,"pendingSelection").name,query)
        local one=page(env,admin,"a","01"); assert(one[1])
    end)
    local invalid={"", " ", " 1", " Raid", " 1 ", "  1 Raid", "\t1 Raid", " 1\tRaid", " 1  Raid", " 1 Raid ",
        " 0 Raid", " 000000 Raid", " 0000001 Raid", " -1 Raid", " +1 Raid", " 1.0 Raid", " 1e0 Raid", " 0x1 Raid", " inf Raid", " NaN Raid",
        " 1 " .. string.rep("x",129), " " .. string.rep("1",200) .. " Raid", " 1 a\226\128\168b", " 1 a\226\128\169b"}
    for byte=0,31 do invalid[#invalid+1]=" 1 a" .. string.char(byte) .. "b" end
    invalid[#invalid+1]=" 1 a\127b"
    for byte=128,159 do invalid[#invalid+1]=" 1 a\194" .. string.char(byte) .. "b" end
    test("search rejects malformed grammar ASCII and Unicode controls before reading configuration",function()
        local env,admin=setup(); local old=page(env,admin); local reads=0
        env.NPCEdits[90]=setmetatable({}, {__index=function() reads=reads+1; error("private config error") end})
        for _,suffix in ipairs(invalid) do
            local text,lines=say(env,admin,"!findEvents" .. suffix)
            eq(#lines,1); contains(text,"Usage: !findEvents <page> <text>")
            assert(not text:find("private config error",1,true))
        end
        eq(reads,0,"bad query cannot inspect configuration")
        env.NPCEdits[90]=nil; say(env,admin,"!nextEventRef " .. old[1]); eq(state(env,"pendingSelection").name,"Raid")
    end)
    test("search authorizes valid admin players and ignores command lookalikes",function()
        local env,admin=setup(); local ordinary=env.entity("player"); local prop=env.entity("prop_physics"); prop.admin=true
        for _,command in ipairs({"!findEvents", "!findEvents 1 Raid", "!findEvents 0 Raid"}) do
            contains(say(env,ordinary,command),"Only admins")
            eq(env.fire("PlayerSay",prop,command),nil); eq(env.fire("PlayerSay",nil,command),nil)
            admin.valid=false; eq(env.fire("PlayerSay",admin,command),nil); admin.valid=true
        end
        for _,command in ipairs({"!findEventsMore 1 Raid","!findEvents1 Raid","!findEvents/1 Raid","!findevents 1 Raid"," !findEvents 1 Raid"}) do
            eq(env.fire("PlayerSay",admin,command),nil)
        end
        eq(#admin.chats,0); eq(#prop.chats,0)
    end)
    test("search paginates only matching names in stable global order with shown-page grants",function()
        local names={"A excluded"}; for i=1,19 do names[#names+1]=string.format("Match %02d",i) end
        names[#names+1]="Z excluded"; local env,admin=setup(names); local all={}
        for number=1,3 do
            local refs,text,lines=page(env,admin,"MATCH",number)
            contains(lines[1],"page " .. number .. "/3 (19 matching names)")
            assert(not text:find("excluded",1,true))
            for id,token in pairs(refs) do assert(not all[id]); all[id]=true
                contains(say(env,admin,"!inspectEventRef " .. token),"Configuration snapshot") end
            local token=select(2,next(refs)); local off=token:gsub("%-%d+$",number==1 and "-10" or "-2")
            refused(env,admin,off)
        end
        eq(all[1],nil); eq(all[21],nil); for id=2,20 do assert(all[id]) end
        local text=say(env,admin,"!findEvents 4 MATCH"); contains(text,"1-3")
    end)
    test("search continuation pages retain every escaped UTF-8 byte and exact selection identity",function()
        local raw="A" .. string.rep("火\n\\",700) .. "Tail"
        local env,admin=setup({raw,"Z excluded"}); local parts={}; local first,last
        local _,_,header=page(env,admin,"tail"); local pages=assert(tonumber(header[1]:match("page 1/(%d+)"))); assert(pages>2)
        for number=1,pages do
            local refs,_,lines=page(env,admin,"TAIL",number); first=first or refs[1]; last=refs[1]
            eq(refs[2],nil); assert(last)
            for _,line in ipairs(lines) do
                local part,value=line:match('^Entry 1 part (%d+)/%d+ ref [%w%-]+ %b[]: "(.*)"$')
                if part then assert(not parts[tonumber(part)]); parts[tonumber(part)]=value
                    assert(not value:gsub("火",""):find("[\128-\255]"),"UTF-8 remains intact") end
            end
        end
        eq(table.concat(parts),"A" .. string.rep("火\\x0A\\x5C",700) .. "Tail")
        refused(env,admin,first); say(env,admin,"!nextEventRef " .. last); eq(state(env,"pendingSelection").name,raw)
    end)
    test("successful list and search pages replace one another and zero results revoke old refs",function()
        local env,admin=setup({"Alpha","Beta"}); local listed=page(env,admin)
        local found=page(env,admin,"Beta"); refused(env,admin,listed[1])
        local newer=page(env,admin); refused(env,admin,found[2])
        page(env,admin,"missing"); refused(env,admin,newer[1])
        local last=page(env,admin,"Alpha"); say(env,admin,"!findEvents 99 Alpha")
        say(env,admin,"!nextEventRef " .. last[1]); eq(state(env,"pendingSelection").name,"Alpha")
    end)
    test("search refs are private and inspection preserves the original lifetime until selection",function()
        local env,admin=setup(); local other=env.entity("player"); other.admin=true; env.now=5
        local refs=page(env,admin,"raid"); local theirs=page(env,other,"raid")
        refused(env,other,refs[1]); refused(env,admin,theirs[1])
        local lease=state(env,"catalogInspections")[admin]; env.now=64.999
        contains(say(env,admin,"!inspectEventRef " .. refs[1]),"Configuration snapshot"); eq(lease.expires,65)
        say(env,admin,"!nextEventRef " .. refs[1]); eq(state(env,"pendingSelection").name,"Raid")
        refused(env,admin,refs[1])
    end)
    for _,kind in ipairs({"pool","record","information","rename","duplicate","moved key","removed","map","expired","backward time","invalid time","disconnect","initialize"}) do
        test("search refs retain existing identity and lifetime guard: " .. kind,function()
            local env,admin=setup({"Alpha","Beta"}); say(env,admin,"!nextEvent Beta")
            local refs=page(env,admin,"alpha"); local record=env.NPCEdits[7]
            if kind=="pool" then env.NPCEdits={[7]=record,[14]=env.NPCEdits[14]}
            elseif kind=="record" then env.NPCEdits[7]={name="Alpha",information=record.information}
            elseif kind=="information" then record.information={}
            elseif kind=="rename" then record.name="Other"
            elseif kind=="duplicate" then env.NPCEdits[90]=setmetatable({}, {__index={name="Alpha",information={}}})
            elseif kind=="moved key" then env.NPCEdits[90]=record; env.NPCEdits[7]=nil
            elseif kind=="removed" then env.NPCEdits[7]=nil
            elseif kind=="map" then env.map="gm_other"
            elseif kind=="expired" then env.now=60
            elseif kind=="backward time" then env.now=-1
            elseif kind=="invalid time" then env.now=0/0
            elseif kind=="disconnect" then env.fire("PlayerDisconnected",admin)
            else env.fire("Initialize") end
            refused(env,admin,refs[1]); eq(state(env,"pendingSelection").name,"Beta")
        end)
    end
    for _,newer in ipairs({"list","search"}) do for _,point in ipairs({"ChatPrint","IsAdmin","configuration"}) do
        test("search respects nested " .. newer .. " request during " .. point,function()
            local env,admin=setup({"Alpha","Beta"}); local once,latest; local owner,key,original
            local function nested()
                if not once then once=true; latest=page(env,admin,newer=="search" and "Beta" or nil) end
            end
            if point=="configuration" then
                env.NPCEdits[90]=setmetatable({}, {__index=function() nested(); return nil end})
            else
                owner,key=admin,point; original=owner[key]
                owner[key]=function(...) local value=original(...); nested(); return value end
            end
            -- The unrelated spawn hook also checks IsAdmin for every chat;
            -- trigger this request's actual initial authorization callback.
            if point=="IsAdmin" then eq(env.hooks.PlayerSay.selectNextActivatorEvent(admin,"!findEvents 1 Alpha"),"")
            else say(env,admin,"!findEvents 1 Alpha") end
            if original then owner[key]=original end
            say(env,admin,"!nextEventRef " .. latest[2]); eq(state(env,"pendingSelection").name,"Beta")
        end)
    end end
    test("a search entered during list output owns the shared request lease",function()
        local env,admin=setup({"Alpha","Beta"}); local original=admin.ChatPrint; local once,latest
        admin.ChatPrint=function(self,text) original(self,text); if not once then once=true; latest=page(env,admin,"Beta") end end
        say(env,admin,"!listEvents"); admin.ChatPrint=original
        say(env,admin,"!nextEventRef " .. latest[2]); eq(state(env,"pendingSelection").name,"Beta")
    end)
    test("disconnect during search output cannot restore its inspection",function()
        local env,admin=setup(); local original=admin.ChatPrint; local token
        admin.ChatPrint=function(self,text)
            original(self,text)
            if not token then token=next(state(env,"catalogInspections")[admin].targets); env.fire("PlayerDisconnected",admin) end
        end
        local _,lines=say(env,admin,"!findEvents 1 raid"); admin.ChatPrint=original
        eq(#lines,1); assert(token); refused(env,admin,token)
    end)
    test("search fails closed on unrelated configuration errors without dropping its previous lease",function()
        local env,admin=setup(); local refs=page(env,admin,"raid")
        env.NPCEdits[90]=setmetatable({name="Unrelated"}, {__index=function() error("private secret") end})
        local text=say(env,admin,"!findEvents 1 raid"); contains(text,"configuration could not be inspected")
        assert(not text:find("private secret",1,true)); env.NPCEdits[90]=nil
        say(env,admin,"!nextEventRef " .. refs[1]); eq(state(env,"pendingSelection").name,"Raid")
    end)
    for _,kind in ipairs({"empty map","throwing map","invalid time","negative time","overflow time"}) do
        test("search admission preserves an older lease after " .. kind,function()
            local env,admin=setup(); local refs=page(env,admin,"raid"); local old=state(env,"catalogInspections")[admin]
            local getMap=env.game.GetMap
            if kind=="empty map" then env.map=""
            elseif kind=="throwing map" then env.game.GetMap=function() error("private map failure") end
            elseif kind=="invalid time" then env.now=0/0
            elseif kind=="negative time" then env.now=-1
            else env.now=1e30 end
            local text,lines=say(env,admin,"!findEvents 1 raid")
            eq(#lines,1); contains(text,"server map/time could not be checked")
            assert(rawequal(state(env,"catalogInspections")[admin],old))
            env.map="gm_construct"; env.now=0; env.game.GetMap=getMap
            say(env,admin,"!nextEventRef " .. refs[1]); eq(state(env,"pendingSelection").name,"Raid")
        end)
    end
    test("search copies labels before output but refs reject a replaced pool",function()
        local env,admin=setup({"Alpha","Beta"}); local original=admin.ChatPrint; local once
        admin.ChatPrint=function(self,text)
            original(self,text)
            if not once then once=true; env.NPCEdits={{name="Changed",information={}}} end
        end
        local refs,text=page(env,admin,"alpha"); admin.ChatPrint=original
        contains(text,'"Alpha"'); assert(not text:find('"Changed"',1,true)); refused(env,admin,refs[1])
    end)
    test("search replacing a page stops an older detail reply stream",function()
        local env,admin=setup({"Alpha","Beta"}); local refs=page(env,admin,"alpha")
        local original=admin.ChatPrint; local once,latest; local oldDetails=0
        admin.ChatPrint=function(self,text)
            original(self,text)
            if text:find("activatorModel:",1,true) then oldDetails=oldDetails+1 end
            if not once then once=true; latest=page(env,admin,"Beta") end
        end
        say(env,admin,"!inspectEventRef " .. refs[1]); admin.ChatPrint=original
        eq(oldDetails,0); refused(env,admin,refs[1]); say(env,admin,"!nextEventRef " .. latest[2])
        eq(state(env,"pendingSelection").name,"Beta")
    end)
    test("search refuses exhausted generations and shares the existing counter",function()
        local env,admin=setup(); state(env,"catalogGeneration",9007199254740990)
        local refs=page(env,admin,"raid"); eq(refs[1],"r9007199254740991-1")
        contains(say(env,admin,"!listEvents"),"exhausted"); contains(say(env,admin,"!findEvents 1 raid"),"exhausted")
        say(env,admin,"!nextEventRef " .. refs[1]); eq(state(env,"pendingSelection").name,"Raid")
    end)
    for _,mode in ipairs({"pending","ready with interaction","active interrupted","paused","deferred removal"}) do
        test("search preserves non-catalog state and side-effect traps while " .. mode,function()
            local env,admin=setup(); say(env,admin,"!nextEvent Raid")
            if mode=="paused" then say(env,admin,"!pauseActivatorSpawns")
            elseif mode~="pending" then
                env.fireTimer("activatorSpawner"); local actor=env.ents.FindByClass("activatorent")[1]
                admin:SetPos(actor:GetPos()); actor:AcceptInput("Use",admin,admin)
                if mode=="active interrupted" then env.receive("SendNPCInformation",admin,"Raid"); env.ents.FindByName("devonsSpawnedEntity")[1]:Remove()
                elseif mode=="deferred removal" then env.deferRemoval=true; actor:Remove() end
            end
            local roots={NPCEdits=env.NPCEdits,SpawnPositions=env.SpawnPositions,entities=env.entities,timers=env.timers,
                messages=env.messages,activatorCount=env.activatorCount,totalEnemies=env.totalEnemies}
            for _,name in ipairs({"pendingSelection","selectedBatchName","selectedBatchEntities","interactions","eventActive","eventInterrupted",
                "activeEventName","initialEnemies","activeEnemies","constructingEnemies","automaticSpawnsPaused","spawnScheduleGeneration","statusRequestAfter"}) do roots[name]=state(env,name) end
            local records={}
            local function snapshot(value)
                if type(value)~="table" or records[value] then return end
                local record={}; records[value]=record
                for key,item in pairs(value) do if key~="chats" then record[key]=item; snapshot(key); snapshot(item) end end
            end
            snapshot(roots)
            local original={}
            local function forbid(owner,key) original[#original+1]={owner,key,owner[key]}; owner[key]=function() error("forbidden side effect " .. key) end end
            local oldMath=env.math; env.math=setmetatable({}, {__index=math}); forbid(env.math,"random"); forbid(env.math,"randomseed")
            for _,key in ipairs({"Start","Stop","Create","Simple","Remove","Adjust"}) do forbid(env.timer,key) end
            for _,key in ipairs({"Read","Write","Append","Delete","CreateDir","Exists"}) do forbid(env.file,key) end
            for _,key in ipairs({"Start","Send","Broadcast","WriteString","WriteBool","WriteUInt","WriteEntity"}) do forbid(env.net,key) end
            for _,key in ipairs({"Create","FindByClass","FindByName"}) do forbid(env.ents,key) end
            for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnActivatorSpawns","returnSpawnPositions","destroyActivators","returnDelayBetweenEvents"}) do forbid(env,key) end
            for _,ent in ipairs(env.entities) do for _,key in ipairs({"Remove","Spawn","SetName","SetModel","SetPos","SetHealth","SetMoveType","StopMoving"}) do forbid(ent,key) end end
            local ok,err=pcall(function()
                page(env,admin,"raid"); page(env,admin,"absent"); say(env,admin,"!findEvents 99 raid"); say(env,admin,"!findEvents")
            end)
            for _,entry in ipairs(original) do entry[1][entry[2]]=entry[3] end; env.math=oldMath; assert(ok,err)
            for object,record in pairs(records) do
                for key,value in pairs(record) do assert(rawequal(object[key],value),"preserve stored state " .. tostring(key)) end
                for key,value in pairs(object) do if key~="chats" then assert(rawequal(record[key],value),"no added state " .. tostring(key)) end end
            end
            for key,value in pairs(roots) do
                local actual=env[key]; if actual==nil then actual=state(env,key) end
                assert(rawequal(actual,value),"preserve root identity " .. key)
            end
            if mode=="ready with interaction" then env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,5) end
        end)
    end
end
