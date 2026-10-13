-- Fixed help contract through actual PlayerSay handlers; no native delivery claim.
return function(gmod, test, eq)
    local expected = {
        [""] = {
            "Activator admin help (private): !activatorHelp <topic>",
            "events - browse, inspect and choose configured encounters",
            "spawns - inspect and edit saved spawn bases",
            "enemies - inspect or remove tracked encounter enemies",
            "markers - temporary private position snapshots",
            "control - status, pause/resume, stop, refresh and spawn now",
            "All listed commands require admin. Help changes nothing and never renews a page or ref.",
        },
        ["events"] = {
            "Activator help: events (admin commands).",
            "!listEvents [page] - all names/diagnostics; !eligibleEvents [page] - only names passing !nextEvent checks.",
            "!findEvents / !findEligibleEvents <page> <text> - literal names / eligible names; positive page: 1-6 digits; text: 1-128 bytes, no edge spaces or controls; use single separators.",
            "!nextEvent <exact name> - queue a case-sensitive name. Bare !nextEvent shows configured-name help.",
            "!inspectEventRef <ref> - inspect configured model, enemy class and requested count.",
            "!nextEventRef <ref> - queue the exact eligible entry from your current list/search/eligible page.",
            "!clearNextEvent - clear the pending future choice.",
            "Refs: your latest successful list/search/eligible page, 60s, one selection. New successful pages replace refs; inspect/help never renew them.",
            "Queue/clear affects only the future fresh automatic batch; it preserves ready actors and the active encounter.",
            "Eligible means selectable configuration; models and NPC classes remain engine unchecked.",
        },
        ["spawns"] = {
            "Activator help: spawns (admin commands).",
            "!listSpawns enemy|activator [page] / !nearSpawns enemy|activator [page] - inspect this map's configured bases.",
            "!setEnemySpawn / !setActivatorSpawn - add your current position.",
            "!moveEnemySpawn <key> / !moveActivatorSpawn <key> - move one inspected base to your current position.",
            "!removeEnemySpawn [key] / !removeActivatorSpawn [key] - remove one base; omitting the key removes the highest stored key.",
            "Indexed edits require a current inspected page. Copy shown stored keys, never row ranks or enemy indices.",
            "New pages, accepted edits or lifecycle/identity changes can invalidate permission. Configured pages have no timed or death expiry.",
            "!nearSpawns requires a living admin; !listSpawns also works when dead.",
            "Accepted edits attempt saving immediately; failure can leave changes in memory.",
            "!saveSpawns - retry verified saving for all maps; !spawnSaveStatus - cached session/save history (also when dead).",
        },
        ["enemies"] = {
            "Activator help: enemies (admin commands).",
            "!listEventEnemies [page] - inspect tracked enemies in the active encounter.",
            "!nearEventEnemies [page] - list nearest first; requires a living admin with a usable position.",
            "!inspectEventEnemy <index> - observe Health(), GetMaxHealth() and GetClass() on an eligible page; also works when dead.",
            "!removeEventEnemy <index> - request removal of one owned enemy from your inspected page.",
            "Copy an exact unique shown index, never a rank or stored spawn key. Indices are temporary and never authorize a replacement entity.",
            "New listing attempts invalidate health/marker permission. Removal keeps its existing latest-successful-page rules.",
            "Accepted removal consumes your page and interrupts the encounter, preventing its ordinary victory notice.",
            "Enemy pages have no timed expiry; lifecycle and target changes can still invalidate them. List again when refused.",
            "Observed health is not a promised configured maximum. Removal requests may complete later.",
        },
        ["markers"] = {
            "Activator help: markers (admin commands).",
            "!markSpawn enemy|activator <key> - mark one inspected configured base.",
            "!markEventEnemy <index> - mark one inspected remaining enemy's position at mark time.",
            "!clearSpawnMarker / !clearEventEnemyMarker - clear the same shared snapshot slot.",
            "Marking requires a living admin and an eligible inspected target. Clearing also works when dead.",
            "One private HUD slot; each accepted mark replaces it and lasts at most 15 seconds.",
            "Marks are historical position snapshots, not tracking, navigation, visibility or reachability guarantees.",
            "An enemy spawn-base mark shows the configured base before enemy placement offsets.",
            "Marking, clearing and help do not consume or renew the page used for edit/removal authority.",
        },
        ["control"] = {
            "Activator help: control (admin commands).",
            "!eventStatus - inspect automatic spawning, the active encounter, ready actors, pending choice and current spawn conditions.",
            "!pauseActivatorSpawns - pause new automatic batches for this session; ready actors and active fights remain usable.",
            "!resumeActivatorSpawns - resume with the full normal delay, or start that delay after the active fight; never spawn immediately.",
            "!stopEvent - remove current encounter enemies; restart the normal delay unless paused.",
            "!refreshActivators - retire ready addon actors, including manual ones; refused during an active encounter.",
            "Stop/refresh preserve the pending choice. Refresh restarts the normal delay unless paused.",
            "!spawnActivatorsNow - one ordinary ready-batch attempt now; refused while paused, fighting, spawning or any ready actor exists.",
            "Spawn now keeps player/position/event/capacity checks, may consume the queued choice, and never schedules a retry.",
            "These control commands take no extra arguments. A fresh session starts with automatic spawning enabled.",
        },
    }
    local topics = {"", "events", "spawns", "enemies", "markers", "control"}
    local usage = "Usage: !activatorHelp [events|spawns|enemies|markers|control]; use one lowercase topic and single spaces, with no extra arguments."
    local denial = "Only admins can use Activator command help."
    local function setup()
        local env = gmod.new(); local admin = env.entity("player"); admin.admin = true
        return env, admin
    end
    local function command(topic) return "!activatorHelp" .. (topic == "" and "" or " " .. topic) end
    local function capture(env, admin, text)
        local first = #admin.chats + 1
        eq(env.fire("PlayerSay", admin, text), "", "recognized help stays private")
        local lines = {}; for i = first, #admin.chats do lines[#lines + 1] = admin.chats[i] end
        return lines
    end
    local function help(env, admin, topic)
        local lines = capture(env, admin, command(topic or ""))
        eq(#lines, #expected[topic or ""], "fixed line count")
        assert(#lines <= 10)
        for i, line in ipairs(lines) do
            eq(line, expected[topic or ""][i], "fixed line " .. i)
            assert(#line <= 240 and not line:find("%c"), "bounded control-free help")
        end
        return lines
    end
    local function allHelp(env, admin) for _, topic in ipairs(topics) do help(env, admin, topic) end end
    local function state(env, name)
        local seen = {}
        local function visit(fn)
            if seen[fn] then return end; seen[fn] = true
            for i = 1, 100 do
                local key, value = debug.getupvalue(fn, i); if not key then break end
                if key == name then return value, true end
                if type(value) == "function" then
                    local found, ok = visit(value); if ok then return found, true end
                end
            end
        end
        for _, callbacks in pairs(env.hooks) do for _, fn in pairs(callbacks) do
            local value, found = visit(fn); if found then return value end
        end end
    end
    local function once(object, name, callback)
        local original, entered = object[name], false
        object[name] = function(...)
            if not entered then entered = true; callback() end
            return original(...)
        end
        return function() object[name] = original; assert(entered, "injection must run") end
    end
    local function catalog(env, admin, search)
        local lines = capture(env, admin, search and "!findEvents 1 raid" or "!listEvents")
        return assert(table.concat(lines, "\n"):match(" ref ([%w%-]+) "), "eligible catalog ref")
    end
    local function enemies(nearest)
        local env = gmod.new(); local admin, actors = env.start(); admin.admin = true
        for i, actor in ipairs(actors) do
            actor.index = 100 + i
            actor.Health = function(self) return self.health end
            actor.GetMaxHealth = function() return 100 end
        end
        capture(env, admin, nearest and "!nearEventEnemies" or "!listEventEnemies")
        return env, admin, actors
    end
    for _, topic in ipairs(topics) do
        test("command help exact private response: " .. (topic == "" and "index" or topic), function()
            local env, admin = setup(); local other = env.entity("player"); other.admin = true
            help(env, admin, topic); eq(#other.chats, 0); eq(#env.messages, 0)
        end)
    end
    local bad = {" other", " EVENTS", " ", "  events", "\tevents", "\nevents", " events spawns",
        " '[%w].*'", " \195\169v\195\169nements", " events\0secret", " " .. string.rep("x", 4096)}
    for i, suffix in ipairs(bad) do
        test("command help fixed malformed reply " .. i, function()
            local env, admin = setup(); local lines = capture(env, admin, "!activatorHelp" .. suffix)
            eq(#lines, 1); eq(lines[1], usage)
        end)
    end
    test("command help preserves unclaimed tokens and owning nonstring guard", function()
        local env, admin = setup()
        for _, text in ipairs({"ordinary chat", "!activatorHelper", "!activatorHelpX", "!ActivatorHelp", " !activatorHelp"}) do
            eq(env.fire("PlayerSay", admin, text), nil)
        end
        local handler = env.hooks.PlayerSay.setUpSpawnPoints
        eq(handler(admin, nil), nil); eq(handler(admin, false), nil); eq(handler(admin, {}), nil)
        eq(#admin.chats, 0)
    end)
    for _, kind in ipairs({"dead", "nonadmin", "invalid", "nonplayer", "nil"}) do
        test("command help admission: " .. kind, function()
            local env, admin = setup()
            if kind == "dead" then admin.alive = false; allHelp(env, admin); return end
            if kind == "nonadmin" then admin.admin = false
            elseif kind == "invalid" then admin.valid = false
            elseif kind == "nonplayer" then admin.class = "worldspawn" end
            local sender = admin; if kind == "nil" then sender = nil end
            eq(env.fire("PlayerSay", sender, "!activatorHelp"), "")
            eq(#admin.chats, kind == "nonadmin" and 1 or 0)
            if kind == "nonadmin" then eq(admin.chats[1], denial) end
        end)
    end
    test("command help coexists with all 120 PlayerSay hook orders", function()
        local names = {"setUpSpawnPoints", "selectNextActivatorEvent", "controlAutomaticActivatorSpawns", "refreshReadyActivators", "spawnReadyActivatorsNow"}
        local count = 0
        local function visit(order, used)
            if #order == 5 then
                local env, admin = setup(); local result
                for _, name in ipairs(order) do
                    result = env.hooks.PlayerSay[name](admin, "!activatorHelp")
                    if result ~= nil then break end
                end
                eq(result, ""); eq(table.concat(admin.chats, "\n"), table.concat(expected[""], "\n"))
                eq(#env.messages, 0); count = count + 1; return
            end
            for _, name in ipairs(names) do if not used[name] then
                used[name] = true; order[#order + 1] = name; visit(order, used)
                order[#order] = nil; used[name] = nil
            end end
        end
        visit({}, {}); eq(count, 120)
    end)
    local names = {"interactions", "activeEnemies", "constructingEnemies", "eventActive", "automaticSpawnsPaused",
        "spawnScheduleGeneration", "spawnAttemptDepth", "pendingSelection", "selectedBatchName", "selectedBatchEntities", "catalogInspections",
        "catalogRequests", "detailRequests", "catalogGeneration", "enemyInspections", "enemyHealthRequests",
        "enemyRemovalRequests", "enemyMarkerCaptures", "enemyMarkerGrants", "spawnInspections", "spawnMarkerOperations",
        "spawnCatalogueRequests"}
    for _, mode in ipairs({"idle", "ready", "active", "paused"}) do
        test("command help leaves " .. mode .. " state and external APIs untouched", function()
            local env, admin = setup()
            if mode == "ready" then env.ready()
            elseif mode == "active" then env.start()
            elseif mode == "paused" then env.fire("PlayerSay", admin, "!pauseActivatorSpawns") end
            local before = {}; for _, name in ipairs(names) do before[name] = state(env, name) end
            local positions, definitions = env.SpawnPositions, env.NPCEdits
            local actorCount, packets, total = #env.entities, #env.messages, env.totalEnemies
            local timer, stopped = env.timers.activatorSpawner, env.timers.activatorSpawner.stopped
            local calls = {}
            local function forbidden(name) return function() calls[#calls + 1] = name; error("PRIVATE " .. name) end end
            for _, name in ipairs({"Read", "Write", "Exists"}) do env.file[name] = forbidden("file." .. name) end
            for _, name in ipairs({"TableToJSON", "JSONToTable"}) do env.util[name] = forbidden(name) end
            for _, name in ipairs({"Create", "Start", "Stop", "Simple", "Remove", "Adjust"}) do env.timer[name] = forbidden("timer." .. name) end
            for _, name in ipairs({"Start", "Send", "Broadcast"}) do env.net[name] = forbidden("net." .. name) end
            for _, name in ipairs({"Create", "FindByClass", "FindByName"}) do env.ents[name] = forbidden("ents." .. name) end
            env.player.GetAll, env.player.GetCount = forbidden("GetAll"), forbidden("GetCount")
            env.math = setmetatable({random = forbidden("random"), randomseed = forbidden("randomseed")}, {__index = math})
            env.CurTime, env.game.GetMap = forbidden("CurTime"), forbidden("GetMap")
            admin.GetPos, admin.Alive = forbidden("GetPos"), forbidden("Alive")
            env.returnNPCInformation, env.returnSpawnPositions, env.returnActivatorSpawns = forbidden("definition"), forbidden("enemy base"), forbidden("activator base")
            local poison = {__index = forbidden("configuration index"), __pairs = forbidden("configuration traversal")}
            env.SpawnPositions, env.NPCEdits = setmetatable({}, poison), setmetatable({}, poison)
            allHelp(env, admin); eq(capture(env, admin, "!activatorHelp other")[1], usage)
            eq(#calls, 0); eq(#env.entities, actorCount); eq(#env.messages, packets); eq(env.totalEnemies, total)
            eq(env.timers.activatorSpawner, timer); eq(timer.stopped, stopped)
            for _, name in ipairs(names) do eq(state(env, name), before[name], name) end
            env.SpawnPositions, env.NPCEdits = positions, definitions
        end)
    end
    for _, nearest in ipairs({false, true}) do
        test("command help preserves configured page and actual actions: " .. tostring(nearest), function()
            local env, admin = setup(); local positions = {[7] = env.Vector(1, 2, 3)}
            env.SpawnPositions[1].enemySpawnPositions = positions
            capture(env, admin, nearest and "!nearSpawns enemy" or "!listSpawns enemy")
            local page = state(env, "spawnInspections")[admin]; local shown = page.shown
            allHelp(env, admin); eq(state(env, "spawnInspections")[admin], page); eq(page.shown, shown)
            capture(env, admin, "!markSpawn enemy 7"); eq(#env.messages, 1)
            capture(env, admin, "!moveEnemySpawn 7"); eq(positions[7].x, admin.pos.x)
            allHelp(env, admin); capture(env, admin, "!removeEnemySpawn 7"); assert(positions[7], "help cannot restore invalidated page")
        end)
        test("command help preserves event reference lifetime: " .. tostring(nearest), function()
            local env, admin = setup(); local ref = catalog(env, admin, nearest)
            local page = state(env, "catalogInspections")[admin]; local expires = page.expires
            local generation = state(env, "catalogGeneration")
            allHelp(env, admin); eq(state(env, "catalogInspections")[admin], page); eq(page.expires, expires)
            eq(state(env, "catalogGeneration"), generation)
            capture(env, admin, "!nextEventRef " .. ref); eq(state(env, "pendingSelection").name, "Raid")
            local pending = state(env, "pendingSelection"); allHelp(env, admin)
            capture(env, admin, "!nextEventRef " .. ref); eq(state(env, "pendingSelection"), pending, "consumed ref remains consumed")
            ref = catalog(env, admin, nearest); env.now = state(env, "catalogInspections")[admin].expires
            allHelp(env, admin); capture(env, admin, "!nextEventRef " .. ref); eq(state(env, "pendingSelection"), pending, "expired ref remains expired")
        end)
        test("command help preserves enemy page and real health marker removal: " .. tostring(nearest), function()
            local env, admin, actors = enemies(nearest); local page = state(env, "enemyInspections")[admin]
            local grant = state(env, "enemyMarkerGrants")[admin]; allHelp(env, admin)
            eq(state(env, "enemyInspections")[admin], page); eq(state(env, "enemyMarkerGrants")[admin], grant)
            local lines = capture(env, admin, "!inspectEventEnemy 101"); assert(lines[1]:find("Health() =", 1, true))
            assert(lines[1]:find('GetClass() = "npc_stalker"', 1, true))
            local packets = #env.messages; capture(env, admin, "!markEventEnemy 101"); eq(#env.messages, packets + 1)
            capture(env, admin, "!removeEventEnemy 101"); eq(actors[1].valid, false)
            allHelp(env, admin); capture(env, admin, "!removeEventEnemy 102"); eq(actors[2].valid, true)
        end)
    end
    test("command help never creates configured or enemy inspection authority", function()
        local env, admin = setup(); local positions = {[7] = env.Vector(1, 2, 3)}
        env.SpawnPositions[1].enemySpawnPositions = positions
        allHelp(env, admin); capture(env, admin, "!removeEnemySpawn 7"); assert(positions[7])
        local other, actors = env.start(); other.admin = true
        allHelp(env, other); capture(env, other, "!removeEventEnemy " .. actors[1]:EntIndex()); eq(actors[1].valid, true)
    end)
    for _, kind in ipairs({"configured", "catalog", "enemy", "marker"}) do
        test("command help preserves pending " .. kind .. " operation", function()
            local env, admin = setup(); local trigger, object, method
            env.SpawnPositions[1].enemySpawnPositions = {[7] = env.Vector(1, 2, 3)}
            if kind == "enemy" then
                admin = env.start(); admin.admin = true; trigger = "!listEventEnemies"
            elseif kind == "catalog" then trigger = "!listEvents"
            elseif kind == "marker" then
                capture(env, admin, "!listSpawns enemy"); trigger = "!markSpawn enemy 7"
                object, method = admin, "Alive"
            else trigger = "!listSpawns enemy" end
            object, method = object or admin, method or "ChatPrint"
            local restore = once(object, method, function() help(env, admin, "events") end)
            capture(env, admin, trigger); restore()
            if kind == "configured" then capture(env, admin, "!removeEnemySpawn 7"); eq(env.SpawnPositions[1].enemySpawnPositions[7], nil)
            elseif kind == "catalog" then
                local ref = assert(table.concat(admin.chats, "\n"):match(" ref ([%w%-]+) "))
                capture(env, admin, "!nextEventRef " .. ref); eq(state(env, "pendingSelection").name, "Raid")
            elseif kind == "enemy" then
                local actor = env.ents.FindByName("devonsSpawnedEntity")[1]
                capture(env, admin, "!markEventEnemy " .. actor:EntIndex()); eq(env.messages[#env.messages].name, "ActivatorSpawnMarker")
            else eq(env.messages[#env.messages].name, "ActivatorSpawnMarker") end
        end)
    end
    for _, action in ipairs({"new page", "selection", "clear marker", "disconnect"}) do
        test("command help never restores state after nested " .. action, function()
            local env, admin = setup(); capture(env, admin, "!listSpawns enemy")
            local resulting
            local restore = once(admin, "ChatPrint", function()
                if action == "new page" then capture(env, admin, "!listSpawns activator")
                elseif action == "selection" then capture(env, admin, "!nextEvent Raid")
                elseif action == "clear marker" then capture(env, admin, "!clearSpawnMarker")
                else env.fire("PlayerDisconnected", admin) end
                resulting = state(env, action == "selection" and "pendingSelection" or "spawnInspections")[action == "selection" and "name" or admin]
            end)
            capture(env, admin, "!activatorHelp"); restore()
            eq(state(env, action == "selection" and "pendingSelection" or "spawnInspections")[action == "selection" and "name" or admin], resulting)
            if action == "clear marker" then eq(#env.messages, 1); eq(env.messages[1].values[1], false) end
        end)
    end
    for _, method in ipairs({"IsValid", "IsPlayer", "IsAdmin", "ChatPrint"}) do
        test("command help suppresses throwing " .. method, function()
            local env, admin = setup(); local calls = 0
            local function throwing() calls = calls + 1; error("PRIVATE ADMISSION DETAIL") end
            if method == "IsValid" then env.IsValid = throwing else admin[method] = throwing end
            eq(env.fire("PlayerSay", admin, "!activatorHelp"), ""); eq(#admin.chats, 0); eq(calls, 1)
        end)
    end
    test("command help ends a response when later ChatPrint throws", function()
        local env, admin = setup(); local original, calls = admin.ChatPrint, 0
        admin.ChatPrint = function(self, line)
            calls = calls + 1; if calls == 2 then error("PRIVATE CHAT DETAIL") end; original(self, line)
        end
        eq(env.fire("PlayerSay", admin, "!activatorHelp"), ""); eq(calls, 2); eq(#admin.chats, 1)
        eq(admin.chats[1], expected[""][1])
    end)
    test("command help preserves existing bare next-event help and legacy returns", function()
        local env, admin = setup(); local lines = capture(env, admin, "!nextEvent")
        eq(lines[1], "Usage: !nextEvent <exact configured name> (case-sensitive). !clearNextEvent clears the pending choice. !listEvents [page] shows the full catalog.")
        eq(env.fire("PlayerSay", admin, "!stopEvent"), nil); eq(admin.chats[#admin.chats], "There is no event running")
        eq(env.fire("PlayerSay", admin, "!setEnemySpawn"), nil)
        capture(env, admin, "!pauseActivatorSpawns")
        eq(admin.chats[#admin.chats], "Automatic activator spawning paused. Existing activators and encounters remain usable.")
    end)
    local statusExpected={
        "Spawn initialization (this session): pending.",
        "Spawn saving permission (this session): disabled.",
        "Last completed spawn save attempt (historical): none completed.",
    }
    local statusUsage="Usage: !spawnSaveStatus (cached session and historical save status)."
    local statusDenial="Only admins can inspect spawn saving status."
    for _,alive in ipairs({true,false}) do
        test("spawn save status privately replies while alive: " .. tostring(alive),function()
            local env,admin=setup(); local other=env.entity("player"); other.admin=true; admin.alive=alive
            local lines=capture(env,admin,"!spawnSaveStatus"); eq(#lines,3)
            for i,line in ipairs(lines) do eq(line,statusExpected[i]); assert(#line <= 255 and not line:find("%c")) end
            eq(#other.chats,0); eq(#env.messages,0)
        end)
    end
    local statusBad={" force"," restore"," other_map"," now please"," ","\t","\n"," \0secret"," " .. string.rep("x",4096)}
    for i,suffix in ipairs(statusBad) do
        test("spawn save status privately rejects extra input " .. i,function()
            local env,admin=setup(); local lines=capture(env,admin,"!spawnSaveStatus" .. suffix)
            eq(#lines,1); eq(lines[1],statusUsage)
            admin.admin=false; lines=capture(env,admin,"!spawnSaveStatus" .. suffix)
            eq(#lines,1); eq(lines[1],statusDenial)
        end)
    end
    test("spawn save status preserves unclaimed tokens and the nonstring guard",function()
        local env,admin=setup()
        for _,text in ipairs({"ordinary chat","!spawnSaveStatusX","!spawnsavestatus","!SpawnSaveStatus"," !spawnSaveStatus","!spawnSaveStatus!"}) do
            eq(env.fire("PlayerSay",admin,text),nil)
        end
        local handler=env.hooks.PlayerSay.setUpSpawnPoints
        eq(handler(admin,nil),nil); eq(handler(admin,false),nil); eq(handler(admin,{}),nil); eq(#admin.chats,0)
    end)
    for _,kind in ipairs({"nonadmin","invalid","nonplayer","nil"}) do
        test("spawn save status admission: " .. kind,function()
            local env,admin=setup(); local sender=admin
            if kind == "nonadmin" then admin.admin=false
            elseif kind == "invalid" then admin.valid=false
            elseif kind == "nonplayer" then admin.class="worldspawn"
            else sender=nil end
            eq(env.fire("PlayerSay",sender,"!spawnSaveStatus"),"")
            eq(#admin.chats,kind == "nonadmin" and 1 or 0)
            if kind == "nonadmin" then eq(admin.chats[1],statusDenial) end
        end)
    end
    for _,method in ipairs({"IsValid","IsPlayer","IsAdmin"}) do
        test("spawn save status contains throwing admission: " .. method,function()
            local env,admin=setup(); local calls=0
            local function throwing() calls=calls+1; error("PRIVATE admission error") end
            if method == "IsValid" then env.IsValid=throwing else admin[method]=throwing end
            eq(env.fire("PlayerSay",admin,"!spawnSaveStatus"),""); eq(calls,1); eq(#admin.chats,0)
        end)
    end
    for _,at in ipairs({1,2,3}) do
        test("spawn save status contains throwing reply line " .. at,function()
            local env,admin=setup(); local calls=0; local reply=admin.ChatPrint
            admin.ChatPrint=function(self,line)
                calls=calls+1; if calls == at then error("PRIVATE reply error") end; reply(self,line)
            end
            eq(env.fire("PlayerSay",admin,"!spawnSaveStatus"),""); eq(calls,at); eq(#admin.chats,at-1)
            for i,line in ipairs(admin.chats) do eq(line,statusExpected[i]) end
        end)
    end
    test("spawn save status coexists with all 120 PlayerSay hook orders",function()
        local hooks={"setUpSpawnPoints","selectNextActivatorEvent","controlAutomaticActivatorSpawns","refreshReadyActivators","spawnReadyActivatorsNow"}
        local visited=0
        local function visit(order,used)
            if #order == #hooks then
                local env,admin=setup(); local result
                for _,name in ipairs(order) do
                    result=env.hooks.PlayerSay[name](admin,"!spawnSaveStatus"); if result ~= nil then break end
                end
                eq(result,""); eq(table.concat(admin.chats,"\n"),table.concat(statusExpected,"\n")); visited=visited+1; return
            end
            for _,name in ipairs(hooks) do if not used[name] then
                used[name]=true; order[#order+1]=name; visit(order,used); order[#order]=nil; used[name]=nil
            end end
        end
        visit({},{}); eq(visited,120)
    end)
    for _,mode in ipairs({"idle","ready","active","paused"}) do
        test("spawn save status touches no external API or authority in " .. mode,function()
            local env,admin=setup()
            if mode == "ready" then env.ready()
            elseif mode == "active" then env.start()
            elseif mode == "paused" then capture(env,admin,"!pauseActivatorSpawns") end
            capture(env,admin,"!nextEvent Raid"); capture(env,admin,"!listSpawns enemy")
            local before={}; for _,name in ipairs(names) do before[name]=state(env,name) end
            local positions,definitions=env.SpawnPositions,env.NPCEdits
            local actors,packets,total=#env.entities,#env.messages,env.totalEnemies
            local timer,stopped=env.timers.activatorSpawner,env.timers.activatorSpawner.stopped
            local calls={}
            local function forbidden(name) return function() calls[#calls+1]=name; error("PRIVATE " .. name) end end
            for _,name in ipairs({"Read","Write","Exists"}) do env.file[name]=forbidden("file." .. name) end
            for _,name in ipairs({"TableToJSON","JSONToTable"}) do env.util[name]=forbidden(name) end
            for _,name in ipairs({"Create","Start","Stop","Simple","Remove","Adjust"}) do env.timer[name]=forbidden("timer." .. name) end
            for _,name in ipairs({"Start","Send","Broadcast"}) do env.net[name]=forbidden("net." .. name) end
            for _,name in ipairs({"Create","FindByClass","FindByName"}) do env.ents[name]=forbidden("ents." .. name) end
            env.player.GetAll,env.player.GetCount=forbidden("GetAll"),forbidden("GetCount")
            env.CurTime,env.RealTime,env.game.GetMap=forbidden("CurTime"),forbidden("RealTime"),forbidden("GetMap")
            admin.GetPos,admin.Alive=forbidden("GetPos"),forbidden("Alive")
            env.isvector=forbidden("isvector")
            env.returnNPCInformation,env.returnSpawnPositions,env.returnActivatorSpawns=forbidden("definition"),forbidden("enemy base"),forbidden("activator base")
            env.print,env.ErrorNoHalt=forbidden("console"),forbidden("diagnostic")
            env.math=setmetatable({random=forbidden("random"),randomseed=forbidden("randomseed")},{__index=math})
            local poison={__index=forbidden("configuration index"),__pairs=forbidden("configuration traversal")}
            env.SpawnPositions,env.NPCEdits=setmetatable({},poison),setmetatable({},poison)
            local lines=capture(env,admin,"!spawnSaveStatus"); eq(table.concat(lines,"\n"),table.concat(statusExpected,"\n"))
            eq(capture(env,admin,"!spawnSaveStatus extra")[1],statusUsage)
            eq(#calls,0); eq(#env.entities,actors); eq(#env.messages,packets); eq(env.totalEnemies,total)
            eq(env.timers.activatorSpawner,timer); eq(timer.stopped,stopped)
            for _,name in ipairs(names) do eq(state(env,name),before[name],name) end
            env.SpawnPositions,env.NPCEdits=positions,definitions
        end)
    end
    for _,nearest in ipairs({false,true}) do
        test("spawn save status preserves catalog reference lifetime: " .. tostring(nearest),function()
            local env,admin=setup(); local ref=catalog(env,admin,nearest)
            local page=state(env,"catalogInspections")[admin]; local expires=page.expires
            capture(env,admin,"!spawnSaveStatus"); eq(state(env,"catalogInspections")[admin],page); eq(page.expires,expires)
            capture(env,admin,"!nextEventRef " .. ref); local pending=state(env,"pendingSelection"); eq(pending.name,"Raid")
            capture(env,admin,"!spawnSaveStatus"); capture(env,admin,"!nextEventRef " .. ref); eq(state(env,"pendingSelection"),pending)
            ref=catalog(env,admin,nearest); env.now=state(env,"catalogInspections")[admin].expires
            capture(env,admin,"!spawnSaveStatus"); capture(env,admin,"!nextEventRef " .. ref); eq(state(env,"pendingSelection"),pending)
        end)
        test("spawn save status preserves enemy health marker and removal page: " .. tostring(nearest),function()
            local env,admin,actors=enemies(nearest); local page=state(env,"enemyInspections")[admin]
            local grant=state(env,"enemyMarkerGrants")[admin]; capture(env,admin,"!spawnSaveStatus")
            eq(state(env,"enemyInspections")[admin],page); eq(state(env,"enemyMarkerGrants")[admin],grant)
            local lines=capture(env,admin,"!inspectEventEnemy 101"); assert(lines[1]:find("Health() =",1,true))
            assert(lines[1]:find('GetClass() = "npc_stalker"',1,true))
            local packets=#env.messages; capture(env,admin,"!markEventEnemy 101"); eq(#env.messages,packets+1)
            capture(env,admin,"!removeEventEnemy 101"); eq(actors[1].valid,false)
            capture(env,admin,"!spawnSaveStatus"); capture(env,admin,"!removeEventEnemy 102"); eq(actors[2].valid,true)
        end)
    end
    test("spawn save status never creates configured or enemy inspection authority",function()
        local env,admin=setup(); local positions={[7]=env.Vector(1,2,3)}; env.SpawnPositions[1].enemySpawnPositions=positions
        capture(env,admin,"!spawnSaveStatus"); capture(env,admin,"!removeEnemySpawn 7"); assert(positions[7])
        local other,actors=env.start(); other.admin=true
        capture(env,other,"!spawnSaveStatus"); capture(env,other,"!removeEventEnemy " .. actors[1]:EntIndex()); eq(actors[1].valid,true)
    end)
end
