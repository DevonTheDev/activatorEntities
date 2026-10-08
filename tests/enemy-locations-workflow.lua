-- Independent workflows run the actual server hooks with engine doubles.
-- They verify ownership and lifecycle outcomes, not native GMod placement,
-- entity-index reuse, chat delivery, collision, navigation or timer timing.
return function(gmod, test, eq)
    local longestReply, largestPage = 0, 0
    local function contains(text, wanted)
        assert(text:find(wanted, 1, true), "expected " .. wanted .. " in " .. text)
    end
    local function bounded(lines)
        for _, line in ipairs(lines) do
            assert(type(line) == "string" and #line > 0 and #line <= 255, "each private reply fits ChatPrint's byte limit")
            assert(not line:find("[%c]"), "configured control characters cannot enter chat output")
            longestReply = math.max(longestReply, #line)
        end
    end
    local function say(env, player, command)
        local first, lines = #player.chats + 1, {}
        local result = env.fire("PlayerSay", player, command)
        for i = first, #player.chats do lines[#lines + 1] = player.chats[i] end
        bounded(lines)
        return result, lines, table.concat(lines, "\n")
    end
    local function inspect(env, admin, page)
        local result, lines, text = say(env, admin, "!listEventEnemies" .. (page and (" " .. page) or ""))
        eq(result, "", "actual enemy lookup command is handled privately after reaching encounter state")
        assert(#lines > 0, "inspection explains current encounter state")
        return lines, text
    end
    local function rowIndex(line)
        return tonumber(line:lower():match("entity%s+index%s+(%d+)"))
    end
    local function rows(lines)
        local result = {}
        for _, line in ipairs(lines) do
            if rowIndex(line) or line:lower():find("unindexed", 1, true) then result[#result + 1] = line end
        end
        assert(#result <= 8, "every captured page contains at most eight body rows")
        largestPage = math.max(largestPage, #result)
        return result
    end
    local function coordinates(line)
        local x, y, z = line:match("%(([^,()]+),%s*([^,()]+),%s*([^,()]+)%)")
        return tonumber(x), tonumber(y), tonumber(z)
    end
    local function coordinateFacts(line, x, y, z)
        local low = line:lower()
        assert(low:find("approx", 1, true) or low:find("round", 1, true), "world coordinates explicitly describe their precision")
        local actualX, actualY, actualZ = coordinates(line)
        eq(actualX, x, "reported current world x"); eq(actualY, y, "reported current world y"); eq(actualZ, z, "reported current world z")
    end
    local function countFacts(text, remaining, initial, listed, omitted)
        contains(text, remaining .. "/" .. initial)
        local low = text:lower()
        assert(low:find("listed", 1, true), "location-row count is labeled independently from progress")
        assert(low:find("omitted", 1, true), "omitted invalid/deleting entries are labeled")
        assert(low:match("listed[^%d]*" .. listed .. "%D") or low:match(listed .. "[^%d\n]*listed"), "actual listed count is visible")
        assert(low:match("omitted[^%d]*" .. omitted .. "%D") or low:match(omitted .. "[^%d\n]*omitted"), "actual omitted count is visible")
    end
    local function inactive(text)
        local low = text:lower()
        assert(low:find("no active", 1, true) or low:find("active encounter: none", 1, true), "idle reply has no stale active encounter")
    end
    local function fixture(number, name)
        local env = gmod.new()
        local info = env.NPCEdits[1].information
        env.NPCEdits[1].name = name or "Raid"
        info.maxNPCs = number or 5
        env.NPCEdits[23] = {name="After inspection", information={activatorModel=info.activatorModel,
            npcPath="npc_combine_s", maxNPCs=2, dialogue="Continue normally."}}
        env.determineRandomEvent = function() return name or "Raid" end
        local admin, observer = env.entity("player"), env.entity("player")
        admin.admin = true
        return env, admin, observer
    end
    local function start(env, admin)
        env.fireTimer("activatorSpawner")
        local actor = assert(env.ents.FindByClass("activatorent")[1], "ordinary timer made a ready activator")
        admin:SetPos(actor:GetPos())
        actor:AcceptInput("Use", admin, admin)
        env.receive("SendNPCInformation", admin, actor.EventIdentifier)
        local result = {}
        for _, ent in ipairs(env.entities) do
            if ent.valid and ent.name == "devonsSpawnedEntity" and not ent.killed then result[#result + 1] = ent end
        end
        eq(env.totalEnemies, #result, "real admitted enemies define encounter progress")
        for i, enemy in ipairs(result) do
            -- Independent indices also keep baseline missing-command reds from
            -- depending on the later minimal shared-harness addition.
            enemy.index = 100 + i
            enemy.EntIndex = function(self) return self.index end
        end
        return result
    end
    local function kill(env, admin, enemy)
        env.fire("OnNPCKilled", enemy, admin)
        enemy.killed = true
    end
    local function finish(env, admin, enemies, victories)
        for _, enemy in ipairs(enemies) do if enemy.valid and not enemy.killed then kill(env, admin, enemy) end end
        eq(env.totalEnemies, 0)
        eq(env.messageCount("roundFinished"), victories, "fight reaches the intended exact victory outcome")
        eq(env.timers.activatorSpawner.stopped, false, "normal delay resumes after the real encounter ends")
        for _, enemy in ipairs(enemies) do env.fire("OnNPCKilled", enemy, admin) end
        eq(env.messageCount("roundFinished"), victories, "repeated kill callbacks cannot award another victory")
    end
    local names = {interactions=true, activeEnemies=true, constructingEnemies=true, eventActive=true,
        eventInterrupted=true, activeEventName=true, initialEnemies=true, pendingSelection=true,
        selectedBatchName=true, selectedBatchEntities=true, statusRequestAfter=true}
    local function capture(env)
        local state = {entities=env.entities, messages=env.messages, timers=env.timers,
            SpawnPositions=env.SpawnPositions, NPCEdits=env.NPCEdits, networkStrings=env.networkStrings,
            hooks=env.hooks, receivers=env.receivers, errors=env.errors,
            totalEnemies=env.totalEnemies, activatorCount=env.activatorCount}
        local seen = {}
        local function visit(fn)
            if seen[fn] then return end
            seen[fn] = true
            for i=1,100 do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                if names[name] then state[name] = value end
                if type(value) == "function" then visit(value) end
            end
        end
        for _, callbacks in pairs(env.hooks) do for _, fn in pairs(callbacks) do visit(fn) end end
        for _, fn in pairs(env.receivers) do visit(fn) end
        for _, timer in pairs(env.timers) do visit(timer.callback) end
        local records = {}
        local function record(value)
            if type(value) ~= "table" or records[value] then return end
            local contents = {}
            records[value] = contents
            for key, item in pairs(value) do
                if key ~= "chats" then contents[key] = item; record(key); record(item) end
            end
        end
        record(state)
        return state, records
    end
    local function readOnly(env, callback, allowedChat)
        local before, records = capture(env)
        local originals, attempts, privateCounts = {}, {}, {}
        local allowed = {}
        if allowedChat then
            for _, player in ipairs(allowedChat) do allowed[player] = true end
        else
            for _, player in ipairs(env.entities) do if player.admin then allowed[player] = true end end
        end
        for _, player in ipairs(env.entities) do
            if player.class == "player" and not allowed[player] then privateCounts[player] = #player.chats end
        end
        local function forbid(owner, key)
            originals[#originals + 1] = {owner, key, rawget(owner, key)}
            owner[key] = function()
                attempts[#attempts + 1] = key
                error("enemy lookup called forbidden " .. key)
            end
        end
        local previousMath = rawget(env, "math")
        env.math = setmetatable({}, {__index=math})
        for _, key in ipairs({"random", "randomseed"}) do forbid(env.math, key) end
        for _, key in ipairs({"determineRandomEvent", "returnNPCInformation", "returnSpawnPositions", "returnActivatorSpawns",
            "returnDelayBetweenEvents", "returnMaxActivators", "returnMinNumberOfPlayers", "destroyActivators", "stopActivatorEvent"}) do forbid(env, key) end
        for _, key in ipairs({"Start", "Stop", "Create", "Simple", "Remove", "Adjust"}) do forbid(env.timer, key) end
        for _, key in ipairs({"Read", "Write", "Append", "Delete", "Exists", "CreateDir"}) do forbid(env.file, key) end
        for _, key in ipairs({"Start", "Send", "Broadcast", "WriteEntity", "WriteString", "WriteBool", "WriteUInt"}) do forbid(env.net, key) end
        for _, key in ipairs({"Create", "FindByClass", "FindByName"}) do forbid(env.ents, key) end
        forbid(env.util, "AddNetworkString"); forbid(env.hook, "Add")
        for _, enemy in ipairs(env.entities) do
            for _, key in ipairs({"Remove", "FinishRemoval", "Spawn", "SetPos", "SetName", "SetHealth", "SetModel",
                "SetMoveType", "StopMoving", "TakeDamage", "TakeDamageInfo", "Fire", "AcceptInput"}) do forbid(enemy, key) end
        end
        local ok, err = pcall(callback)
        for _, original in ipairs(originals) do original[1][original[2]] = original[3] end
        env.math = previousMath
        assert(ok, err)
        eq(#attempts, 0, "no forbidden mutation/read attempt is hidden by a protected getter")
        for player, count in pairs(privateCounts) do eq(#player.chats, count, "command replies stay private to actual requester") end
        local after = capture(env)
        local function same(actual, expected, context)
            if type(actual) == "number" and type(expected) == "number" and actual ~= actual and expected ~= expected then return end
            eq(actual, expected, context)
        end
        for key, value in pairs(before) do eq(after[key], value, "inspection retains state identity " .. key) end
        for key, value in pairs(after) do eq(before[key], value, "inspection adds no private state " .. key) end
        for object, contents in pairs(records) do
            for key, value in pairs(contents) do same(object[key], value, "inspection preserves nested state " .. tostring(key)) end
            for key, value in pairs(object) do if key ~= "chats" then same(contents[key], value, "inspection adds no nested state " .. tostring(key)) end end
        end
    end

    test("enemy lookup privately follows moved owned hostiles and preserves clean completion and the queued next batch", function()
        local env, admin, observer = fixture()
        local enemies = start(env, admin)
        eq(#enemies, 5, "baseline reaches a real active encounter before lookup")
        local outsider = env.entity(enemies[1].class)
        outsider:SetName("devonsSpawnedEntity"); outsider:SetPos(env.Vector(919191, 929292, 939393))
        outsider.EntIndex = function() return 919 end
        enemies[2]:SetPos(env.Vector(1234, -5678, 9012))
        enemies[3]:SetName("another-addon-name")
        eq(env.fire("PlayerSay", admin, "!nextEvent After inspection"), "")
        local observerChats = #observer.chats
        readOnly(env, function()
            local lines, text = inspect(env, admin)
            eq(#rows(lines), 5); countFacts(text, 5, 5, 5, 0)
            local moved
            for _, line in ipairs(rows(lines)) do if rowIndex(line) == enemies[2].index then moved = line end end
            coordinateFacts(assert(moved, "moved owned enemy still appears"), 1234, -5678, 9012)
            assert(not text:find("919191", 1, true), "same-name/class outsider is never discovered")
            local again = inspect(env, admin)
            eq(table.concat(again, "\n"), text, "unchanged encounter yields deterministic fresh pages")
        end)
        eq(#observer.chats, observerChats, "inspection stays private")
        finish(env, admin, enemies, 1)
        eq(outsider.valid, true, "lookup and victory leave unrelated NPC alone")
        env.fireTimer("activatorSpawner")
        local actors = env.ents.FindByClass("activatorent")
        eq(#actors, env.returnMaxActivators())
        for _, actor in ipairs(actors) do eq(actor.EventIdentifier, "After inspection", "future ordinary batch retains queued choice") end
    end)

    test("enemy lookup refuses unauthorized players without exposing locations or consuming a ready interaction", function()
        local env, admin, observer = fixture()
        env.fireTimer("activatorSpawner")
        local actor = env.ents.FindByClass("activatorent")[1]
        admin:SetPos(actor:GetPos()); actor:AcceptInput("Use", admin, admin)
        local invalid, prop = {valid=false}, env.entity("prop_physics")
        readOnly(env, function()
            local _, text = inspect(env, admin); inactive(text)
            local result, _, denial = say(env, observer, "!listEventEnemies")
            eq(result, ""); contains(denial:lower(), "admin")
            for _, player in ipairs({invalid, prop}) do
                eq(env.fire("PlayerSay", player, "!listEventEnemies"), nil)
            end
            for _, command in ipairs({"hello", "!listEventEnemiesExtra", "prefix !listEventEnemies", "!listeventenemies"}) do
                eq(env.fire("PlayerSay", admin, command), nil, "unrelated chat is not claimed")
            end
        end, {admin, observer})
        env.receive("SendNPCInformation", admin, actor.EventIdentifier)
        eq(env.totalEnemies, 5, "inspection preserves the original interaction grant")
        local enemies = env.ents.FindByName("devonsSpawnedEntity")
        finish(env, admin, enemies, 1)
    end)

    test("enemy lookup reaches every owned hostile in numerical index order across fresh eight-row pages", function()
        local env, admin = fixture(19)
        local enemies = start(env, admin)
        local expected = {}
        for i, enemy in ipairs(enemies) do
            enemy.index = (20 - i) * 11
            enemy:SetPos(env.Vector(10000 + i, 20000 + i, -30000 - i))
            expected[#expected + 1] = enemy.index
        end
        table.sort(expected)
        local actual = {}
        readOnly(env, function()
            for page = 1, 3 do
                local lines, text = inspect(env, admin, page)
                countFacts(text, 19, 19, 19, 0)
                contains(text:lower(), "page " .. page .. "/3")
                local body = rows(lines)
                eq(#body, page < 3 and 8 or 3, "at most eight body rows per page")
                for _, line in ipairs(body) do actual[#actual + 1] = assert(rowIndex(line)) end
            end
            local leading = inspect(env, admin, "0001")
            eq(#rows(leading), 8, "leading-zero positive decimal page is accepted")
            for _, argument in ipairs({"0", "-1", "1.5", "+1", "1e0", "one", "1 two", "4", "999999999999999999999999999999999999999999999999999999999999"}) do
                local lines, text = inspect(env, admin, argument)
                contains(text:lower(), "usage"); eq(#rows(lines), 0, "invalid pages cannot silently become page one")
            end
        end)
        eq(#actual, #expected)
        for i, index in ipairs(expected) do eq(actual[i], index, "each owned enemy appears once in numerical order") end
        finish(env, admin, enemies, 1)
    end)

    test("fresh lookup follows live movement and authoritative kill retirement without trusting enemy names", function()
        local env, admin = fixture(3)
        local enemies = start(env, admin)
        local first = inspect(env, admin)
        eq(#rows(first), 3)
        enemies[1]:SetPos(env.Vector(-14141, 25252, -36363))
        enemies[1]:SetName("renamed owned hostile")
        kill(env, admin, enemies[2])
        readOnly(env, function()
            local lines, text = inspect(env, admin)
            eq(#rows(lines), 2); countFacts(text, 2, 3, 2, 0)
            for _, line in ipairs(rows(lines)) do
                assert(rowIndex(line) ~= enemies[2].index, "dead owned enemy is retired by the actual kill hook")
                if rowIndex(line) == enemies[1].index then coordinateFacts(line, -14141, 25252, -36363) end
            end
        end)
        local result, _, status = say(env, admin, "!eventStatus")
        eq(result, ""); contains(status, "2/3"); contains(status, "!listEventEnemies")
        finish(env, admin, enemies, 1)
        local _, text = inspect(env, admin); inactive(text)
    end)

    test("pending removal and invalid owned entries stay in progress while their location rows are explicitly omitted", function()
        local env, admin = fixture(5)
        local enemies = start(env, admin)
        env.deferRemoval = true
        enemies[1]:Remove()
        eq(enemies[1].valid, true, "Remove remains pending before the engine-style removal callback")
        enemies[2].valid = false
        readOnly(env, function()
            local lines, text = inspect(env, admin)
            eq(#rows(lines), 3); countFacts(text, 5, 5, 3, 2)
        end)
        eq(env.totalEnemies, 5, "inspection never repairs progress by pruning omitted entries")
        enemies[2].valid = true
        env.flushRemovals()
        eq(env.totalEnemies, 4)
        readOnly(env, function()
            local lines, text = inspect(env, admin)
            eq(#rows(lines), 4); countFacts(text, 4, 5, 4, 0)
        end)
        local _, _, status = say(env, admin, "!eventStatus"); contains(status:lower(), "interrupt")
        finish(env, admin, enemies, 0)
        local _, text = inspect(env, admin); inactive(text)
    end)

    test("temporary index failures retain useful coordinates and duplicate indices never collapse ownership rows", function()
        local env, admin = fixture(12)
        local enemies = start(env, admin)
        local bad = {0, -1, false, 1.5, math.huge, 0/0}
        enemies[1].index, enemies[2].index = 18, 2
        enemies[3].index = 2
        for i, value in ipairs(bad) do enemies[i + 3].index = value end
        enemies[10].EntIndex = function() error("unreadable native index") end
        enemies[11].EntIndex = false
        enemies[12].index = nil
        for i, enemy in ipairs(enemies) do enemy:SetPos(env.Vector(41000 + i, -52000 - i, 63000 + i)) end
        readOnly(env, function()
            local lines, text = inspect(env, admin)
            local second, secondText = inspect(env, admin, 2)
            countFacts(text, 12, 12, 12, 0); countFacts(secondText, 12, 12, 12, 0)
            local combined = rows(lines)
            for _, line in ipairs(rows(second)) do combined[#combined + 1] = line end
            eq(#combined, 12, "index diagnostics remain rows instead of changing actual progress")
            eq(rowIndex(combined[1]), 2); eq(rowIndex(combined[2]), 2); eq(rowIndex(combined[3]), 18)
            for i=4,#combined do contains(combined[i]:lower(), "unindexed") end
            local seen = {}
            for _, line in ipairs(combined) do
                local x, y, z = coordinates(line)
                assert(x, "unindexed location diagnostic retains readable world coordinates")
                local number = x - 41000
                assert(number >= 1 and number <= 12 and number % 1 == 0 and not seen[number], "each actual owned coordinate tuple appears once")
                seen[number] = true
                eq(y, -52000 - number); eq(z, 63000 + number)
            end
            local again = inspect(env, admin)
            eq(table.concat(again, "\n"), text, "copied unindexed diagnostics keep consistent display order")
            contains(text:lower(), "temporar")
        end)
        finish(env, admin, enemies, 1)
    end)

    for _, position in ipairs({"missing method", "throwing method", "non-vector", "missing component", "throwing component", "nan", "infinity"}) do
        test("unavailable world position remains an owned diagnostic during " .. position, function()
            local env, admin = fixture(2)
            local enemies = start(env, admin)
            local enemy = enemies[1]
            if position == "missing method" then enemy.GetPos = false
            elseif position == "throwing method" then enemy.GetPos = function() error("unreadable position") end
            elseif position == "non-vector" then enemy.GetPos = function() return {x=0,y=0,z=0} end
            elseif position == "missing component" then enemy.pos.x = nil
            elseif position == "throwing component" then
                enemy.pos.x = nil
                getmetatable(enemy.pos).__index = function(_, key) if key == "x" then error("unreadable component") end end
            elseif position == "nan" then enemy.pos.x = 0/0
            else enemy.pos.y = math.huge end
            readOnly(env, function()
                local lines, text = inspect(env, admin)
                countFacts(text, 2, 2, 2, 0)
                local diagnostic
                for _, line in ipairs(rows(lines)) do if rowIndex(line) == enemy.index then diagnostic = line end end
                assert(diagnostic, "owned hostile retains its own row")
                contains(diagnostic:lower(), "unavailable")
                assert(not diagnostic:find("0, 0, 0", 1, true), "bad coordinates never fabricate an origin")
            end)
            finish(env, admin, enemies, 1)
        end)
    end

    test("all pending owned removals produce an active zero-row page until authoritative removal hooks end the interrupted fight", function()
        local env, admin = fixture(5)
        local enemies = start(env, admin)
        env.deferRemoval = true
        for _, enemy in ipairs(enemies) do enemy:Remove() end
        readOnly(env, function()
            local lines, text = inspect(env, admin)
            eq(#rows(lines), 0); countFacts(text, 5, 5, 0, 5); contains(text:lower(), "page 1/1")
            local invalid, message = inspect(env, admin, 2)
            eq(#rows(invalid), 0); contains(message:lower(), "usage")
        end)
        eq(env.totalEnemies, 5)
        env.flushRemovals()
        eq(env.totalEnemies, 0); eq(env.messageCount("roundFinished"), 0)
        local _, text = inspect(env, admin); inactive(text)
        finish(env, admin, enemies, 0)
    end)

    test("active lookup denies a non-admin before attempting any owned position or index method", function()
        local env, admin, observer = fixture(2)
        local enemies = start(env, admin)
        for _, enemy in ipairs(enemies) do
            enemy.GetPos = function() error("unauthorized position access") end
            enemy.EntIndex = function() error("unauthorized index access") end
        end
        local before = #admin.chats
        readOnly(env, function()
            local result, lines, text = say(env, observer, "!listEventEnemies 1")
            eq(result, ""); contains(text:lower(), "admin"); eq(#rows(lines), 0)
        end, {observer})
        eq(#admin.chats, before, "denial is private to its requester")
        finish(env, admin, enemies, 1)
    end)

    test("huge finite world coordinates and long Unicode encounter names preserve counts, rows and chat byte bounds", function()
        local name = string.rep("界", 160) .. "\n\t\0end"
        local env, admin = fixture(9, name)
        local enemies = start(env, admin)
        enemies[1]:SetPos(env.Vector(1e308, -1e308, 1e-300))
        local function validUtf8(text)
            local i = 1
            while i <= #text do
                local byte = text:byte(i)
                local width = byte < 128 and 1 or (byte >= 194 and byte <= 223 and 2 or (byte >= 224 and byte <= 239 and 3 or (byte >= 240 and byte <= 244 and 4)))
                assert(width and i + width - 1 <= #text, "truncated chat ends on a full UTF-8 character")
                for j=i+1,i+width-1 do assert(text:byte(j) >= 128 and text:byte(j) <= 191, "UTF-8 continuation remains intact") end
                i = i + width
            end
        end
        readOnly(env, function()
            for page=1,2 do
                local lines, text = inspect(env, admin, page)
                countFacts(text, 9, 9, 9, 0)
                eq(#rows(lines), page == 1 and 8 or 1)
                for _, line in ipairs(lines) do validUtf8(line) end
                if page == 1 then
                    local huge
                    for _, line in ipairs(rows(lines)) do if rowIndex(line) == enemies[1].index then huge = line end end
                    assert(huge and not huge:lower():find("unavailable", 1, true), "finite huge coordinates remain readable with a bounded representation")
                    contains(huge, "308")
                end
            end
        end)
        finish(env, admin, enemies, 1)
    end)

    test("lookup during a partial real constructor reports only admitted ownership and cannot change later spawn attempts", function()
        local env, admin = fixture(5)
        local create, attempts, during = env.ents.Create, 0, nil
        env.ents.Create = function(class)
            if class ~= "npc_stalker" then return create(class) end
            attempts = attempts + 1
            if attempts == 1 then return {valid=false} end
            local enemy = create(class)
            local spawn = enemy.Spawn
            local attempt = attempts
            enemy.Spawn = function(self)
                spawn(self)
                if attempt == 3 then self:Remove()
                elseif attempt == 4 then
                    readOnly(env, function() local lines, text = inspect(env, admin); during = {lines=lines, text=text} end)
                end
            end
            return enemy
        end
        local enemies = start(env, admin)
        eq(attempts, 5); eq(#enemies, 3); eq(env.totalEnemies, 3)
        assert(during, "actual Spawn callback reached inspection during construction")
        countFacts(during.text, 1, 1, 1, 0); eq(#rows(during.lines), 1)
        readOnly(env, function() local lines, text = inspect(env, admin); countFacts(text, 3, 3, 3, 0); eq(#rows(lines), 3) end)
        finish(env, admin, enemies, 1)
    end)

    for _, phase in ipairs({"pending choice", "ready interaction", "stopped"}) do
        test("idle lookup preserves ordinary selection and interaction during " .. phase, function()
            local env, admin = fixture()
            eq(env.fire("PlayerSay", admin, "!nextEvent After inspection"), "")
            local actor
            if phase == "ready interaction" then
                env.fireTimer("activatorSpawner")
                actor = env.ents.FindByClass("activatorent")[1]
                admin:SetPos(actor:GetPos()); actor:AcceptInput("Use", admin, admin)
            elseif phase == "stopped" then
                local enemies = start(env, admin)
                env.fire("PlayerSay", admin, "!stopEvent")
                eq(env.totalEnemies, 0); eq(env.messageCount("roundFinished"), 0)
                for _, enemy in ipairs(enemies) do eq(enemy.valid, false, "real stop removed each owned hostile") end
                eq(env.fire("PlayerSay", admin, "!nextEvent After inspection"), "")
            end
            readOnly(env, function() local _, text = inspect(env, admin); inactive(text) end)
            if actor then
                env.receive("SendNPCInformation", admin, actor.EventIdentifier)
                eq(env.totalEnemies, 2, "idle inspection keeps the already admitted interaction")
                finish(env, admin, env.ents.FindByName("devonsSpawnedEntity"), 1)
            else
                env.fireTimer("activatorSpawner")
                for _, ready in ipairs(env.ents.FindByClass("activatorent")) do eq(ready.EventIdentifier, "After inspection") end
            end
        end)
    end

    for _, boundary in ipairs({"GetPos", "EntIndex", "IsMarkedForDeletion"}) do
        test("capture rejects actual encounter replacement inside owned " .. boundary .. " callback", function()
            local env, admin = fixture(3)
            local enemies = start(env, admin)
            local old = enemies[1][boundary]
            local changed, replacement = false, nil
            enemies[1][boundary] = function(self)
                if not changed then
                    changed = true
                    eq(env.stopActivatorEvent(), true)
                    eq(env.fire("PlayerSay", admin, "!nextEvent After inspection"), "")
                    replacement = start(env, admin)
                end
                return old(self)
            end
            local lines, text = inspect(env, admin)
            assert(changed and replacement, "real owned callback replaced the encounter during capture")
            assert(text:lower():find("changed", 1, true) or text:lower():find("replac", 1, true), "mixed capture is explicitly refused")
            eq(#rows(lines), 0, "no stale or replacement rows escape the rejected capture")
            local fresh, current = inspect(env, admin)
            eq(#rows(fresh), 2); countFacts(current, 2, 2, 2, 0); contains(current, "After inspection")
            finish(env, admin, replacement, 1)
        end)
    end

    for _, change in ipairs({"movement and kill", "completion", "stop and replacement"}) do
        test("all replies retain the captured page when first ChatPrint reenters with " .. change, function()
            local env, admin = fixture(9)
            local enemies = start(env, admin)
            for i, enemy in ipairs(enemies) do enemy:SetPos(env.Vector(71000 + i, 82000 + i, -93000 - i)) end
            local expected = inspect(env, admin)
            local original, output, fired, replacement = admin.ChatPrint, {}, false, nil
            local wrapper
            wrapper = function(self, line)
                output[#output + 1] = line
                original(self, line)
                if fired then return end
                fired = true
                -- Other real hooks can print while this callback runs. Keep
                -- those messages separate from the inspected command's replies.
                admin.ChatPrint = original
                if change == "movement and kill" then
                    for _, enemy in ipairs(enemies) do enemy:SetPos(env.Vector(999001, 999002, 999003)) end
                    kill(env, admin, enemies[1])
                elseif change == "completion" then finish(env, admin, enemies, 1)
                else
                    eq(env.stopActivatorEvent(), true)
                    eq(env.fire("PlayerSay", admin, "!nextEvent After inspection"), "")
                    replacement = start(env, admin)
                end
                admin.ChatPrint = wrapper
            end
            admin.ChatPrint = wrapper
            eq(env.fire("PlayerSay", admin, "!listEventEnemies"), "")
            admin.ChatPrint = original
            assert(fired, "first actual private reply invoked the reentry callback")
            bounded(output)
            eq(#output, #expected)
            for i, line in ipairs(expected) do eq(output[i], line, "all output was rendered before the first reply callback") end
            if change == "movement and kill" then
                local fresh, text = inspect(env, admin)
                eq(#rows(fresh), 8); countFacts(text, 8, 9, 8, 0); contains(text, "999001")
                finish(env, admin, enemies, 1)
            elseif change == "completion" then
                local _, text = inspect(env, admin); inactive(text); eq(env.messageCount("roundFinished"), 1)
            else
                local fresh, text = inspect(env, admin)
                eq(#rows(fresh), 2); countFacts(text, 2, 2, 2, 0)
                finish(env, admin, replacement, 1)
            end
        end)
    end
    return {chat_byte_limit=255, maximum_observed_reply_bytes=longestReply,
        body_rows_per_page_limit=8, maximum_observed_page_rows=largestPage}
end
