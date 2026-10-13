-- Real PlayerSay callbacks with the existing GMod doubles; no native claim.
return function(gmod, test, eq)
    local private = dofile("tests/find-upvalue.lua")
    local function state(env, name)
        for _, callbacks in pairs(env.hooks) do for _, callback in pairs(callbacks) do
            local ok, value = pcall(private, callback, name)
            if ok then return value end
        end end
        error("missing observed state " .. name)
    end
    local function contains(text, part) assert(text:find(part, 1, true), "missing " .. part .. " in " .. text) end
    local function setup(names)
        local env = gmod.new(); local admin = env.entity("player"); admin.admin = true
        if names then
            env.NPCEdits = {}
            for i, name in ipairs(names) do env.NPCEdits[i * 7] = {name=name, information={}} end
        end
        return env, admin
    end
    local function say(env, admin, command)
        local first = #admin.chats + 1
        eq(env.fire("PlayerSay", admin, command), "", "recognized command stays private")
        local lines = {}; for i=first,#admin.chats do lines[#lines+1] = admin.chats[i] end
        for _, line in ipairs(lines) do assert(#line <= 255 and not line:find("[%c]"), "bounded private output") end
        return table.concat(lines, "\n"), lines
    end
    local function page(env, admin, command)
        local text, lines = say(env, admin, command or "!eligibleEvents")
        assert(#lines >= 3 and #lines <= 10, "header, at most eight body lines, footer")
        contains(lines[1], "!nextEvent eligibility only; engine unchecked")
        local refs = {}
        for _, line in ipairs(lines) do
            assert(#line <= 240, "conservative catalogue line bound")
            local id, token = line:match("^Entry (%d+) part %d+/%d+ ref ([%w%-]+) ")
            if token then
                if refs[tonumber(id)] then eq(refs[tonumber(id)], token) end
                refs[tonumber(id)] = token
            end
        end
        return refs, text, lines
    end
    local function refused(env, admin, token)
        local pending = state(env, "pendingSelection")
        contains(say(env, admin, "!nextEventRef " .. token), "reference unavailable")
        assert(rawequal(state(env, "pendingSelection"), pending))
    end
    test("eligible literal search intersects complete-pool eligibility and original names", function()
        local env, admin = setup(); local other = env.entity("player"); other.admin = true
        local info = {}; local inherited = {name="Raid valid", information={npcPath=false, maxNPCs=-1}}
        env.NPCEdits = {false, {}, {name=23}, {name="", information={}},
            {name="A outside", information={}}, {name="Raid duplicate", information=info},
            setmetatable({}, {__index={name="Raid duplicate", information=info}}),
            {name="Raid missing"}, {name="Raid wrong", information=false},
            setmetatable({}, {__index=inherited})}
        local refs, text, lines = page(env, admin, "!findEligibleEvents 1 rAiD")
        contains(lines[1], "Eligible configured encounter search, page 1/1 (1 matching eligible names)")
        assert(refs[5]); eq(refs[2], nil); eq(refs[3], nil); eq(refs[4], nil); eq(refs[6], nil)
        for _, hidden in ipairs({"A outside", "Raid duplicate", "Raid missing", "Raid wrong", "Non-table records"}) do
            assert(not text:find(hidden, 1, true), "excluded rows stay hidden")
        end
        contains(lines[#lines], "!findEligibleEvents <page> <text>"); contains(lines[#lines], "repeat same text")
        contains(lines[#lines], "!findEvents/!listEvents"); eq(#other.chats, 0); eq(#env.messages, 0)
        local invalid = say(env, admin, "!findEligibleEvents 2 rAiD")
        contains(invalid, "Usage: !findEligibleEvents <page> <text>; page must be in 1-1; repeat the same text.")
        say(env, admin, "!nextEventRef " .. refs[5]); eq(state(env, "pendingSelection").name, "Raid valid")
        refs = page(env, admin, "!findEligibleEvents 1 raid")
        local empty, noMatch = page(env, admin, "!findEligibleEvents 1 absent")
        eq(next(empty), nil); contains(noMatch, "No eligible configured names match this literal search.")
        refused(env, admin, refs[5])
    end)
    test("eligible literal search preserves Unicode bytes and literal escaped-name matching", function()
        local env, admin = setup({"A\0Raid", "A\\x00Raid", "ÉCLAIR 火 🚀", "éclair 火 🚀"})
        local refs = page(env, admin, "!findEligibleEvents 1 éCLAIR"); assert(refs[4]); eq(refs[3], nil)
        refs = page(env, admin, "!findEligibleEvents 1 火 🚀"); assert(refs[3] and refs[4])
        refs = page(env, admin, "!findEligibleEvents 1 \\x00"); assert(refs[2]); eq(refs[1], nil)
        refs = page(env, admin, "!findEligibleEvents 1 raid"); assert(refs[1] and refs[2])
        contains(say(env, admin, "!inspectEventRef " .. refs[1]), "escaped diagnostic")
        say(env, admin, "!nextEventRef " .. refs[1]); eq(state(env, "pendingSelection").name, "A\0Raid")
    end)
    test("eligible literal search paginates matching eligible names with global page-only grants", function()
        local env, admin = setup({"A excluded"}); env.NPCEdits[7].information = false
        for i=1,19 do env.NPCEdits[100+i] = {name=string.format("Match %02d", i), information={}} end
        env.NPCEdits[150] = {name="Match 00 excluded"}; env.NPCEdits[151] = {name="Z outside", information={}}
        local all = {}; local previous
        for number=1,3 do
            local refs, _, lines = page(env, admin, "!findEligibleEvents " .. number .. " MATCH")
            contains(lines[1], "page " .. number .. "/3 (19 matching eligible names)")
            contains(lines[#lines], "repeat same text")
            for id, token in pairs(refs) do assert(not all[id]); all[id] = true
                contains(say(env, admin, "!inspectEventRef " .. token), "Configuration snapshot") end
            if previous then refused(env, admin, previous) end
            local token = select(2, next(refs)); refused(env, admin, token:gsub("%-%d+$", number == 1 and "-11" or "-3"))
            previous = token
        end
        eq(all[1], nil); eq(all[2], nil); eq(all[22], nil); for id=3,21 do assert(all[id]) end
        contains(say(env, admin, "!findEligibleEvents 4 MATCH"), "1-3; repeat the same text")
        say(env, admin, "!nextEventRef " .. previous); assert(state(env, "pendingSelection"))
    end)
    test("eligible literal search yields to newer catalogue requests at callback boundaries", function()
        for _, newer in ipairs({"!listEvents", "!findEvents 1 Beta", "!eligibleEvents", "!findEligibleEvents 1 Beta"}) do
            for _, point in ipairs({"ChatPrint", "IsAdmin", "configuration"}) do
                local env, admin = setup({"Alpha", "Beta"}); local once, latest, original
                local function nested() if not once then once = true; latest = page(env, admin, newer) end end
                if point == "configuration" then env.NPCEdits[90] = setmetatable({}, {__index=function() nested(); return nil end})
                else original = admin[point]; admin[point] = function(...) local value = original(...); nested(); return value end end
                eq(env.hooks.PlayerSay.selectNextActivatorEvent(admin, "!findEligibleEvents 1 Alpha"), "")
                if original then admin[point] = original end
                say(env, admin, "!nextEventRef " .. assert(latest[2])); eq(state(env, "pendingSelection").name, "Beta")
            end
        end
    end)
    test("eligible literal page stops older catalogue and detail replies", function()
        for _, earlier in ipairs({"!listEvents", "!findEvents 1 Alpha", "!eligibleEvents", "!inspectEventRef"}) do
            local env, admin = setup({"Alpha", "Beta"}); local refs = page(env, admin)
            local original, once, latest, nested, outerLines = admin.ChatPrint, false, nil, false, 0
            admin.ChatPrint = function(self, line)
                original(self, line); if not nested then outerLines = outerLines + 1 end
                if not once then once = true; nested = true; latest = page(env, admin, "!findEligibleEvents 1 Beta"); nested = false end
            end
            say(env, admin, earlier == "!inspectEventRef" and (earlier .. " " .. refs[1]) or earlier)
            admin.ChatPrint = original; eq(outerLines, 1); refused(env, admin, refs[1])
            say(env, admin, "!nextEventRef " .. latest[2]); eq(state(env, "pendingSelection").name, "Beta")
        end
    end)
    test("eligible catalogue claims its exact command privately", function()
        local env, admin = setup(); local other = env.entity("player"); other.admin = true
        local refs, text = page(env, admin)
        contains(text, "Eligible configured encounters, page 1/1 (1 eligible names)")
        contains(text, "Excluded entries: !listEvents")
        assert(refs[1]); eq(#other.chats, 0); eq(#env.messages, 0)
    end)
    test("eligible catalogue filters after complete grouping and keeps exact global IDs", function()
        local env, admin = setup(); local info = {}
        env.NPCEdits = {false, {}, {name=23}, {name="", information={}},
            {name="A duplicate", information=info}, setmetatable({}, {__index={name="A duplicate", information=info}}),
            {name="B missing"}, {name="C malformed", information=false}, {name="D inherited"},
            {name="E valid", information={npcPath=false, maxNPCs=-1, activatorModel=false}}}
        setmetatable(env.NPCEdits[9], {__index={information={}}})
        local refs, text = page(env, admin)
        contains(text, "2 eligible names"); assert(refs[5] and refs[6]); eq(refs[1], nil)
        for _, hidden in ipairs({"A duplicate", "B missing", "C malformed", "Non-table records"}) do
            assert(not text:find(hidden, 1, true), "excluded rows are absent")
        end
        local _, full = page(env, admin, "!listEvents")
        contains(full, "duplicate name (2)"); contains(full, "missing information: 1")
        contains(full, "non-table information: 1"); contains(full, "Non-table records: 1")
        refs = page(env, admin); say(env, admin, "!nextEventRef " .. refs[6])
        eq(state(env, "pendingSelection").name, "E valid")
    end)
    test("eligible catalogue uses the same configured getter read trace as the full catalogue", function()
        local env, admin = setup(); local reads = {}; local info = {}
        env.NPCEdits = {[9]=setmetatable({}, {__index=function(_, key)
            reads[#reads+1] = key; if key == "name" then return "Inherited" end; return info
        end})}
        page(env, admin, "!listEvents"); local expected = table.concat(reads, ","); reads = {}
        page(env, admin); eq(table.concat(reads, ","), expected); reads = {}
        page(env, admin, "!findEligibleEvents 1 inherited"); eq(table.concat(reads, ","), expected)
    end)
    for _, command in ipairs({"!eligibleEvents", "!findEligibleEvents 1 raid"}) do
    for _, kind in ipairs({"empty", "missing", "malformed", "all excluded"}) do
        test("eligible zero page replaces earlier references: " .. kind .. ": " .. command, function()
            local env, admin = setup(); local old = page(env, admin, "!listEvents")
            local saved = env.NPCEdits
            if kind == "empty" then env.NPCEdits = {}
            elseif kind == "missing" then env.NPCEdits = nil
            elseif kind == "malformed" then env.NPCEdits = false
            else env.NPCEdits = {{name="Raid"}, {name="", information={}}} end
            local refs, text, lines = page(env, admin, command)
            eq(next(refs), nil); contains(lines[1], command == "!eligibleEvents" and "page 1/1 (0 eligible names)" or "page 1/1 (0 matching eligible names)")
            contains(text, "!listEvents")
            if kind == "empty" or kind == "all excluded" then contains(text, command == "!eligibleEvents" and "No configured names pass" or "No eligible configured names match this literal search.")
            elseif kind == "missing" then contains(text, "missing pool") else contains(text, "expected table") end
            if command ~= "!eligibleEvents" then contains(text, "No eligible configured names match this literal search.") end
            env.NPCEdits = saved; refused(env, admin, old[1])
        end)
    end
    end
    test("eligible catalogue preserves list page grammar and leaves invalid requests non-consuming", function()
        local env, admin = setup(); local refs
        for _, command in ipairs({"!eligibleEvents", "!eligibleEvents ", "!eligibleEvents 01", "!eligibleEvents\t1 ", "!eligibleEvents   1  "}) do
            refs = page(env, admin, command)
        end
        for _, argument in ipairs({"0", "-1", "1.0", "1e0", "+1", "99", "1 raid", "foo"}) do
            local text, lines = say(env, admin, "!eligibleEvents " .. argument)
            eq(#lines, 1); contains(text, "Usage: !eligibleEvents [page]")
        end
        say(env, admin, "!nextEventRef " .. refs[1]); eq(state(env, "pendingSelection").name, "Raid")
    end)
    test("eligible catalogue authorizes players and leaves command lookalikes unclaimed", function()
        local env, admin = setup(); local ordinary = env.entity("player"); local prop = env.entity("prop_physics"); prop.admin = true
        contains(say(env, ordinary, "!eligibleEvents"), "Only admins")
        eq(env.fire("PlayerSay", prop, "!eligibleEvents"), nil); eq(env.fire("PlayerSay", nil, "!eligibleEvents"), nil)
        admin.valid = false; eq(env.fire("PlayerSay", admin, "!eligibleEvents"), nil); admin.valid = true
        for _, command in ipairs({"!eligibleEventsMore", "!eligibleEvents1", "!eligibleEvents/1", "!eligibleevents", " !eligibleEvents"}) do
            eq(env.fire("PlayerSay", admin, command), nil)
        end
        eq(#admin.chats, 0); eq(#prop.chats, 0); admin.alive = false; page(env, admin)
    end)
    test("eligible pages preserve sorted global IDs and grant only displayed entries", function()
        local env, admin = setup({"A excluded"}); env.NPCEdits[7].information = false
        for i=1,19 do env.NPCEdits[100+i] = {name=string.format("Match %02d", i), information={}} end
        local all = {}
        for number=1,3 do
            local refs, _, lines = page(env, admin, "!eligibleEvents " .. number)
            contains(lines[1], "page " .. number .. "/3 (19 eligible names)")
            for id, token in pairs(refs) do assert(not all[id]); all[id] = true
                contains(say(env, admin, "!inspectEventRef " .. token), "Configuration snapshot") end
            local token = select(2, next(refs)); refused(env, admin, token:gsub("%-%d+$", number == 1 and "-10" or "-2"))
        end
        eq(all[1], nil); for id=2,20 do assert(all[id]) end
    end)
    for _, command in ipairs({"!eligibleEvents", "!findEligibleEvents 1 tail"}) do
    test("eligible continuations preserve every escaped Unicode byte and exact selection name: " .. command, function()
        local name = "A" .. string.rep("火\n\\", 250) .. "Tail"
        local env, admin = setup({"", name}); local parts = {}; local first, last
        local _, _, header = page(env, admin, command); local pages = assert(tonumber(header[1]:match("page 1/(%d+)"))); assert(pages > 2)
        for number=1,pages do
            local refs, _, lines = page(env, admin, (command == "!eligibleEvents" and "!eligibleEvents " .. number or "!findEligibleEvents " .. number .. " tail")); first = first or refs[2]; last = assert(refs[2])
            for _, line in ipairs(lines) do
                local part, value = line:match('^Entry 2 part (%d+)/%d+ ref [%w%-]+ %b[]: "(.*)"$')
                if part then assert(not parts[tonumber(part)]); parts[tonumber(part)] = value
                    assert(not value:gsub("火", ""):find("[\128-\255]")) end
            end
        end
        eq(table.concat(parts), "A" .. string.rep("火\\x0A\\x5C", 250) .. "Tail")
        refused(env, admin, first); say(env, admin, "!nextEventRef " .. last); eq(state(env, "pendingSelection").name, name)
    end)
    end
    test("all catalogue modes replace the same latest-page reference set", function()
        local env, admin = setup({"Alpha", "Beta"})
        for _, command in ipairs({"!listEvents", "!findEvents 1 Beta", "!findEligibleEvents 1 Beta"}) do
            local old = page(env, admin, command); local eligible = page(env, admin)
            refused(env, admin, assert(old[2])); local latest = page(env, admin, command)
            refused(env, admin, eligible[1]); assert(latest[2])
        end
    end)
    for _, command in ipairs({"!eligibleEvents", "!findEligibleEvents 1 a"}) do
    test("eligible references are requester-private and inspect does not renew or consume them: " .. command, function()
        local env, admin = setup(); local other = env.entity("player"); other.admin = true; env.now = 5
        local refs = page(env, admin, command); local theirs = page(env, other, command)
        refused(env, other, refs[1]); refused(env, admin, theirs[1]); env.now = 64.999
        contains(say(env, admin, "!inspectEventRef " .. refs[1]), "Configuration snapshot")
        eq(state(env, "catalogInspections")[admin].expires, 65)
        say(env, admin, "!nextEventRef " .. refs[1]); eq(state(env, "pendingSelection").name, "Raid")
        refused(env, admin, refs[1])
    end)
    for _, kind in ipairs({"pool", "record", "information", "rename", "duplicate", "moved key", "removed", "map", "expired", "backward time", "invalid time", "disconnect", "initialize"}) do
        test("eligible reference retains live identity and lifetime guard: " .. kind .. ": " .. command, function()
            local env, admin = setup({"Alpha", "Beta"}); say(env, admin, "!nextEvent Beta")
            local refs = page(env, admin, command); local record = env.NPCEdits[7]
            if kind == "pool" then env.NPCEdits = {[7]=record, [14]=env.NPCEdits[14]}
            elseif kind == "record" then env.NPCEdits[7] = {name="Alpha", information=record.information}
            elseif kind == "information" then record.information = {}
            elseif kind == "rename" then record.name = "Changed"
            elseif kind == "duplicate" then env.NPCEdits[90] = setmetatable({}, {__index={name="Alpha", information={}}})
            elseif kind == "moved key" then env.NPCEdits[90] = record; env.NPCEdits[7] = nil
            elseif kind == "removed" then env.NPCEdits[7] = nil
            elseif kind == "map" then env.map = "gm_other"
            elseif kind == "expired" then env.now = 60
            elseif kind == "backward time" then env.now = -1
            elseif kind == "invalid time" then env.now = 0/0
            elseif kind == "disconnect" then env.fire("PlayerDisconnected", admin)
            else env.fire("Initialize") end
            refused(env, admin, refs[1]); eq(state(env, "pendingSelection").name, "Beta")
        end)
    end
    end
    for _, newer in ipairs({"!listEvents", "!findEvents 1 Beta", "!eligibleEvents", "!findEligibleEvents 1 Beta"}) do
        for _, point in ipairs({"ChatPrint", "IsAdmin", "configuration"}) do
            test("eligible output yields to nested " .. newer .. " during " .. point, function()
                local env, admin = setup({"Alpha", "Beta"}); local once, latest, original
                local function nested() if not once then once = true; latest = page(env, admin, newer) end end
                if point == "configuration" then env.NPCEdits[90] = setmetatable({}, {__index=function() nested(); return nil end})
                else original = admin[point]; admin[point] = function(...) local value = original(...); nested(); return value end end
                eq(env.hooks.PlayerSay.selectNextActivatorEvent(admin, "!eligibleEvents"), "")
                if original then admin[point] = original end
                say(env, admin, "!nextEventRef " .. assert(latest[2])); eq(state(env, "pendingSelection").name, "Beta")
            end)
        end
    end
    for _, earlier in ipairs({"!listEvents", "!findEvents 1 Alpha", "!findEligibleEvents 1 Alpha", "!inspectEventRef"}) do
        test("eligible page stops an older catalogue or detail reply stream: " .. earlier, function()
            local env, admin = setup({"Alpha", "Beta"}); local refs = page(env, admin)
            local original, once, latest = admin.ChatPrint
            admin.ChatPrint = function(self, line)
                original(self, line); if not once then once = true; latest = page(env, admin) end
            end
            say(env, admin, earlier == "!inspectEventRef" and (earlier .. " " .. refs[1]) or earlier)
            admin.ChatPrint = original; refused(env, admin, refs[1])
            say(env, admin, "!nextEventRef " .. latest[2]); eq(state(env, "pendingSelection").name, "Beta")
        end)
    end
    for _, command in ipairs({"!eligibleEvents", "!findEligibleEvents 1 raid"}) do
    test("eligible disconnect during output cannot restore page authority: " .. command, function()
        local env, admin = setup(); local original, token = admin.ChatPrint
        admin.ChatPrint = function(self, line)
            original(self, line); token = token or next(state(env, "catalogInspections")[admin].targets)
            env.fire("PlayerDisconnected", admin)
        end
        local _, lines = say(env, admin, command); admin.ChatPrint = original
        eq(#lines, 1); refused(env, admin, assert(token))
    end)
    end
    for _, kind in ipairs({"configuration", "empty map", "throwing map", "invalid time", "negative time", "overflow time"}) do
        test("unavailable eligible request preserves the prior successful page: " .. kind, function()
            local env, admin = setup(); local refs = page(env, admin); local old = state(env, "catalogInspections")[admin]
            local getMap = env.game.GetMap
            if kind == "configuration" then env.NPCEdits[90] = setmetatable({name="Excluded"}, {__index=function() error("PRIVATE FAILURE") end})
            elseif kind == "empty map" then env.map = ""
            elseif kind == "throwing map" then env.game.GetMap = function() error("PRIVATE FAILURE") end
            elseif kind == "invalid time" then env.now = 0/0
            elseif kind == "negative time" then env.now = -1 else env.now = 1e30 end
            local text, lines = say(env, admin, "!eligibleEvents"); eq(#lines, 1); contains(text, "Catalog unavailable")
            contains(text, "Retry !eligibleEvents"); assert(not text:find("PRIVATE FAILURE", 1, true))
            assert(rawequal(state(env, "catalogInspections")[admin], old))
            local combined, combinedLines = say(env, admin, "!findEligibleEvents 1 raid")
            eq(#combinedLines, 1); contains(combined, "Retry !findEligibleEvents <page> <text> with the same text")
            assert(not combined:find("PRIVATE FAILURE", 1, true)); assert(#combinedLines[1] <= 240)
            assert(rawequal(state(env, "catalogInspections")[admin], old))
            env.NPCEdits[90] = nil; env.map = "gm_construct"; env.now = 0; env.game.GetMap = getMap
            say(env, admin, "!nextEventRef " .. refs[1]); eq(state(env, "pendingSelection").name, "Raid")
        end)
    end
    test("eligible browsing never reads information fields or samples health", function()
        local env, admin = setup({"Inherited"}); local reads = 0
        env.NPCEdits[7].information = setmetatable({}, {__index=function() reads = reads + 1; error("forbidden info read") end})
        env.returnEnemyHealth = function() error("forbidden health sample") end
        local refs = page(env, admin); eq(reads, 0)
        refs = page(env, admin, "!findEligibleEvents 1 inherited"); eq(reads, 0)
        say(env, admin, "!nextEventRef " .. refs[1]); eq(reads, 0); eq(state(env, "pendingSelection").name, "Inherited")
    end)
    for _,mode in ipairs({"pending","ready with interaction","active interrupted","paused","deferred removal"}) do
        test("eligible catalogue preserves lifecycle state and side-effect traps while " .. mode,function()
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
            for _,key in ipairs({"determineRandomEvent","returnNPCInformation","returnActivatorSpawns","returnSpawnPositions","destroyActivators","returnDelayBetweenEvents","returnEnemyHealth"}) do forbid(env,key) end
            for _,ent in ipairs(env.entities) do for _,key in ipairs({"Remove","Spawn","SetName","SetModel","SetPos","SetHealth","SetMoveType","StopMoving"}) do forbid(ent,key) end end
            local ok,err=pcall(function()
                page(env,admin); say(env,admin,"!eligibleEvents 99"); say(env,admin,"!eligibleEvents wrong")
                page(env,admin,"!findEligibleEvents 1 raid"); page(env,admin,"!findEligibleEvents 1 absent")
                say(env,admin,"!findEligibleEvents 99 raid"); say(env,admin,"!findEligibleEvents")
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
