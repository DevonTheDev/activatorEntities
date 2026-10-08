-- Actual public hooks, real encounter/client handlers, and independent storage
-- boundaries. Token bytes identify immutable detached Vector snapshots; this is
-- not a native JSON codec or evidence of DATA durability or engine behavior.
return function(gmod, test, eq)
    local canonical = "devonsspawninfo.json"
    local legacy = "DevonsSpawnInfo.json"
    local backup = "devonsspawninfo.backup.json"
    local kinds = {
        {name="enemy", field="enemySpawnPositions", add="!setEnemySpawn", remove="!removeEnemySpawn", move="!moveEnemySpawn", first=2, key=10, last=27},
        {name="activator", field="activatorSpawnPositions", add="!setActivatorSpawn", remove="!removeActivatorSpawn", move="!moveActivatorSpawn", first=3, key=11, last=29},
    }
    local function contains(value, fragment)
        assert(value:find(fragment, 1, true), "missing " .. fragment .. " in " .. value)
    end
    local function tree(value)
        local result = {value=value}
        if type(value) == "table" then
            result.entries = {}
            for key, child in pairs(value) do result.entries[key] = tree(child) end
        end
        return result
    end
    local function sameTree(value, before)
        assert(rawequal(value, before.value), "existing reference or value changed")
        if before.entries then
            for key, child in pairs(before.entries) do sameTree(value[key], child) end
            for key in pairs(value) do assert(before.entries[key], "unexpected field: " .. tostring(key)) end
        end
    end
    local function clone(env, value)
        if env.isvector(value) then return env.Vector(value.x, value.y, value.z) end
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = clone(env, child) end
        return result
    end
    local function fingerprint(env, value)
        if env.isvector(value) then return "Vector(" .. value.x .. "," .. value.y .. "," .. value.z .. ")" end
        if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
        local keys, parts = {}, {}
        for key in pairs(value) do keys[#keys+1] = key end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) < type(b)
        end)
        for _, key in ipairs(keys) do parts[#parts+1] = fingerprint(env, key) .. "=" .. fingerprint(env, value[key]) end
        return "{" .. table.concat(parts, ";") .. "}"
    end
    local function storage(env)
        local state = {files={}, log={}, snapshots={}, tokens={}, serial=0, encodes=0,
            writeFaults={}, readFaults={}, prints={}}
        function state.register(bytes, snapshot)
            state.snapshots[bytes] = clone(env, snapshot)
            state.tokens[fingerprint(env, snapshot)] = bytes
            return bytes
        end
        function state.snapshot(bytes)
            return clone(env, assert(state.snapshots[bytes], "unregistered token bytes: " .. tostring(bytes)))
        end
        env.print = function(value) state.prints[#state.prints+1] = value end
        env.file.Exists = function(path, realm)
            eq(realm, "DATA"); state.log[#state.log+1] = {op="exists", path=path}
            return state.files[path] ~= nil
        end
        env.file.Read = function(path, realm)
            eq(realm, "DATA")
            local entry = {op="read", path=path, bytes=state.files[path]}
            state.log[#state.log+1] = entry
            local fault = state.readFaults[path]
            if fault == "throw" then entry.failure=fault; error("synthetic unreadable " .. path) end
            if fault == "nil" then entry.failure=fault; entry.bytes=nil; return nil end
            if fault == "wrong" then entry.bytes="wrong bytes"; return entry.bytes end
            return state.files[path]
        end
        env.file.Write = function(path, bytes)
            state.log[#state.log+1] = {op="write", path=path, bytes=bytes}
            local fault = state.writeFaults[path]
            if fault then
                -- Every failed write destroys prior contents, unlike a failed
                -- open that leaves canonical bytes recoverable by accident.
                state.files[path] = "partial:" .. bytes:sub(1, 6)
                if fault == "throw" then error("synthetic destructive write " .. path) end
                if fault == "false" then return false end
                if fault == "nil" then return nil end
                if fault == "truncated true" then return true end
                error("unknown write fault")
            end
            state.files[path] = bytes
            return true
        end
        env.util.TableToJSON = function(value)
            state.encodes = state.encodes+1
            state.log[#state.log+1] = {op="encode"}
            if state.encodeFault == "throw" then error("synthetic encode failure") end
            if state.encodeFault == "nil" then return nil end
            if state.encodeFault == "empty" then return "" end
            if state.encodeFault == "unknown token" then return "unknown candidate bytes" end
            if state.encodeFault == "bad schema" then
                return state.register("invalid candidate schema", {{map="gm_construct", enemySpawnPositions={}, activatorSpawnPositions={bad="position"}}})
            end
            local shape = fingerprint(env, value)
            local bytes = state.tokens[shape]
            if not bytes then
                state.serial=state.serial+1
                bytes='{"workflow_snapshot":' .. state.serial .. '}'
                state.register(bytes, value)
            end
            return bytes
        end
        env.util.JSONToTable = function(bytes, ignoreLimits, ignoreConversions)
            eq(ignoreLimits, nil, "default JSON limits preserved")
            eq(ignoreConversions, nil, "default numeric-key conversion preserved")
            state.log[#state.log+1] = {op="decode", bytes=bytes}
            return clone(env, state.snapshots[bytes])
        end
        return state
    end
    local function sparse(env, offset)
        offset=offset or 0
        return {[4]={map="gm_construct",
            enemySpawnPositions={[2]=env.Vector(102+offset,202,302), [10]=env.Vector(110+offset,210,310), [27]=env.Vector(127+offset,227,327)},
            activatorSpawnPositions={[3]=env.Vector(203+offset,303,403), [11]=env.Vector(211+offset,311,411), [29]=env.Vector(229+offset,329,429)}},
            [19]={map="other_map", enemySpawnPositions={[10]=env.Vector(6,7,8)}, activatorSpawnPositions={[11]=env.Vector(9,8,7)}}}
    end
    local function fixture(mode)
        local env=gmod.new(); local disk=storage(env)
        local old="{ loaded workflow snapshot A }\n"
        local initial=sparse(env)
        if mode == "empty root" then initial={}
        elseif mode == "empty lists" then initial[4].enemySpawnPositions={}; initial[4].activatorSpawnPositions={} end
        disk.register(old, initial)
        if mode == "legacy" then disk.files[legacy]=old
        elseif mode ~= "first" and mode ~= "orphan" then disk.files[canonical]=old end
        if mode == "both" then disk.files[legacy]=disk.register("{ older legacy snapshot }", sparse(env, 9000)) end
        if mode == "orphan" then disk.files[backup]="orphan recovery bytes" end
        env.fire("Initialize")
        local admin=env.entity("player"); admin.admin=true
        local second=env.entity("player"); second.admin=true
        local observer=env.entity("player")
        return env, disk, admin, second, observer, old
    end
    local function count(disk, op, path)
        local result=0
        for _,entry in ipairs(disk.log) do
            if entry.op == op and (not path or entry.path == path) then result=result+1 end
        end
        return result
    end
    local function say(env, player, text) return env.fire("PlayerSay", player, text) end
    local function privateSay(env, player, text)
        local chats={}
        for _,other in ipairs(env.player.GetAll()) do chats[other]=#other.chats end
        eq(say(env, player, text), "", "private command consumed")
        for i=chats[player]+1,#player.chats do
            assert(#player.chats[i] <= 255, "private response stays within ChatPrint's byte limit")
        end
        assert(#player.chats > chats[player], "private command supplies an explanation")
        for other, before in pairs(chats) do
            if other ~= player then eq(#other.chats, before, "bystander receives no private command text") end
        end
        return table.concat(player.chats, "\n", chats[player]+1)
    end
    local function inspect(env, player, kind)
        return privateSay(env, player, "!listSpawns " .. kind.name)
    end
    local function move(env, player, kind, key)
        return privateSay(env, player, kind.move .. " " .. tostring(key or kind.key))
    end
    local function edit(env, player, kind, operation)
        if operation == "move" then return move(env, player, kind)
        elseif operation == "indexed removal" then return privateSay(env, player, kind.remove .. " " .. kind.key)
        else
            local before=#player.chats
            eq(say(env, player, operation == "add" and kind.add or kind.remove), nil, "legacy command return unchanged")
            return table.concat(player.chats, "\n", before+1)
        end
    end
    local function noIO(disk, callback)
        local size=#disk.log; callback(); eq(#disk.log, size, "rejected command performs no persistence I/O or codec work")
    end
    local function staleBoth(env, disk, admin, second, kind)
        noIO(disk, function()
            for _,player in ipairs({admin, second}) do
                contains(move(env, player, kind, kind.first), "inspect")
                contains(privateSay(env, player, kind.remove .. " " .. kind.first), "inspect")
            end
        end)
    end
    local function verifiedOrder(disk, start, old, new)
        local backupWrite, backupRead, canonicalWrite, canonicalRead, candidateDecode
        for i=start+1,#disk.log do
            local e=disk.log[i]
            if e.op == "decode" and e.bytes == new then candidateDecode=candidateDecode or i end
            if e.op == "write" and e.path == backup and e.bytes == old then backupWrite=backupWrite or i end
            if e.op == "read" and e.path == backup and e.bytes == old and not e.failure then backupRead=i end
            if e.op == "write" and e.path == canonical and e.bytes == new then canonicalWrite=canonicalWrite or i end
            if e.op == "read" and e.path == canonical and e.bytes == new and not e.failure then canonicalRead=i end
        end
        assert(backupWrite, "exact loaded predecessor must be written to backup")
        assert(backupRead and backupRead > backupWrite, "backup must be read-verified after writing")
        assert(canonicalWrite and canonicalWrite > backupRead, "canonical write must follow verified backup")
        assert(canonicalRead and canonicalRead > canonicalWrite, "canonical must be read-verified after writing")
        assert(candidateDecode and candidateDecode < backupWrite, "candidate must be reload-validated before file mutation")
    end
    local function status(env, admin)
        local before=#admin.chats; eq(say(env, admin, "!eventStatus"), "")
        local lines={}
        for i=before+1,#admin.chats do
            local line=admin.chats[i]
            if line:find("^Active event:") or line:find("^Ready activators:") or line:find("^Ready event:")
                or line:find("^Selected ready batch:") or line:find("^Pending next batch:") then lines[#lines+1]=line end
        end
        return table.concat(lines, "\n")
    end
    local actorFields={"valid","markedForDeletion","pos","class","name","health","model","moveType","moveChanges","stopped","spawned","EventIdentifier","NPCInfo"}
    local function lifecycle(env, admin)
        local result={size=#env.entities, actors={}, timers=tree(env.timers), messages=#env.messages,
            receivers=tree(env.receivers), network=tree(env.networkStrings), enemies=env.totalEnemies,
            activators=env.activatorCount, status=status(env, admin)}
        for _,actor in ipairs(env.entities) do
            local fields={}
            for _,name in ipairs(actorFields) do fields[name]=tree(actor[name]) end
            result.actors[actor]=fields
        end
        return result
    end
    local function sameLifecycle(env, admin, before)
        eq(#env.entities, before.size, "storage path creates no actors")
        eq(#env.messages, before.messages, "storage path emits no encounter packets")
        eq(env.totalEnemies, before.enemies); eq(env.activatorCount, before.activators)
        sameTree(env.timers, before.timers); sameTree(env.receivers, before.receivers); sameTree(env.networkStrings, before.network)
        eq(status(env, admin), before.status, "round and selected/pending event state preserved")
        for _,actor in ipairs(env.entities) do
            for _,name in ipairs(actorFields) do sameTree(actor[name], before.actors[actor][name]) end
        end
    end
    local function readyDialogue(env, admin)
        local client=gmod.new(true)
        env.NPCEdits[7]={name="Ambush",information={activatorModel=env.NPCEdits[1].information.activatorModel,
            npcPath="npc_combine_s",maxNPCs=2,dialogue="An ambush awaits."}}
        eq(say(env, admin, "!nextEvent Ambush"), ""); env.fireTimer("activatorSpawner")
        eq(say(env, admin, "!nextEvent Raid"), "")
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
        for _,actor in ipairs(actors) do eq(actor.EventIdentifier, "Ambush") end
        local actor=actors[1]; admin:SetPos(actor:GetPos()); actor:AcceptInput("Use", admin, admin)
        local message=env.messages[#env.messages]; eq(message.name,"OpenInteractionMenu"); eq(message.player,admin)
        client.deliver(message)
        local menu={client=client}
        for _,panel in ipairs(client.panels) do
            if panel.class == "DFrame" then menu.frame=panel
            elseif panel.class == "DButton" and panel.text:find("Start",1,true) then menu.start=panel
            elseif panel.class == "DButton" and panel.text:find("Quit",1,true) then menu.quit=panel end
        end
        assert(menu.frame and menu.start and menu.quit, "actual dialogue controls required")
        return menu
    end
    local function startDialogue(env, admin, menu)
        eq(menu.frame.valid,true); menu.start:DoClick(); eq(menu.frame.valid,false)
        local request=menu.client.messages[#menu.client.messages]; eq(request.name,"SendNPCInformation")
        env.deliver(request,admin)
        eq(env.totalEnemies,2,"pre-edit real interaction still starts selected Ambush")
        return env.ents.FindByName("devonsSpawnedEntity")
    end
    local function finishRound(env, admin, enemies)
        for _,enemy in ipairs(enemies) do env.fire("OnNPCKilled",enemy,admin) end
        eq(env.totalEnemies,0); eq(env.messageCount("roundFinished"),1)
        eq(env.timers.activatorSpawner.stopped,false); env.fireTimer("activatorSpawner")
        local actors=env.ents.FindByClass("activatorent"); eq(#actors,3)
        for _,actor in ipairs(actors) do eq(actor.EventIdentifier,"Raid","pending next choice survived persistence") end
    end

    test("workflow codec tokens retain exact detached sparse Vector snapshots", function()
        local env,disk,_,_,_,old=fixture()
        local first=disk.snapshot(old); local second=disk.snapshot(old)
        assert(not rawequal(first,second)); assert(not rawequal(first[4].enemySpawnPositions[10],second[4].enemySpawnPositions[10]))
        assert(env.isvector(first[4].enemySpawnPositions[10])); eq(first[1],nil)
        env.SpawnPositions[4].enemySpawnPositions[10].x=999
        first[4].enemySpawnPositions[10].x=888
        eq(disk.snapshot(old)[4].enemySpawnPositions[10].x,110)
        eq(second[4].enemySpawnPositions[10].x,110)
    end)

    for _,kind in ipairs(kinds) do
        for _,operation in ipairs({"add","bare removal","indexed removal","move"}) do
            test("backup workflow " .. kind.name .. " " .. operation .. " preserves dialogue and rejects both stale inspections",function()
                local env,disk,admin,second,_,old=fixture()
                local menu=readyDialogue(env,admin); local current=env.SpawnPositions[4]
                local root,map,list=env.SpawnPositions,current,current[kind.field]
                inspect(env,admin,kind); inspect(env,second,kind); second:SetPos(env.Vector(601,602,603))
                local before=lifecycle(env,admin); local start=#disk.log
                local text=edit(env,second,kind,operation)
                assert(not text:find("remains in memory",1,true),"verified edit is acknowledged")
                eq(disk.files[backup],old,"backup preserves exact predecessor bytes")
                verifiedOrder(disk,start,old,disk.files[canonical])
                eq(disk.encodes,1); eq(count(disk,"write",backup),1); eq(count(disk,"write",canonical),1)
                assert(rawequal(root,env.SpawnPositions) and rawequal(map,current) and rawequal(list,current[kind.field]))
                if operation == "add" then eq(list[kind.last+1].x,601)
                elseif operation == "bare removal" then eq(list[kind.last],nil)
                elseif operation == "indexed removal" then eq(list[kind.key],nil)
                else eq(list[kind.key].x,601); assert(env.isvector(list[kind.key])) end
                eq(env.SpawnPositions[1],nil); eq(list[1],nil); eq(env.SpawnPositions[19].map,"other_map")
                local saved=disk.snapshot(disk.files[canonical]); local prior=disk.snapshot(disk.files[backup])
                eq(fingerprint(env,saved),fingerprint(env,env.SpawnPositions),"verified bytes encode actual edited state")
                eq(prior[4][kind.field][kind.key].x,kind.name == "enemy" and 110 or 211)
                sameLifecycle(env,admin,before); eq(menu.frame.valid,true); eq(menu.start.valid,true); eq(menu.quit.valid,true)
                staleBoth(env,disk,admin,second,kind)
                local enemies=startDialogue(env,admin,menu); finishRound(env,admin,enemies)
                eq(count(disk,"write",canonical),1,"encounter lifecycle does not save spawn data")
            end)
        end

        for _,operation in ipairs({"add","bare removal","indexed removal","move"}) do
            test("failed " .. kind.name .. " " .. operation .. " keeps accepted edits and prepared predecessor for shutdown retry",function()
                local env,disk,admin,second,_,old=fixture()
                inspect(env,admin,kind); inspect(env,second,kind); second:SetPos(env.Vector(601,602,603))
                disk.writeFaults[canonical]="false"
                contains(edit(env,second,kind,operation),"remains in memory")
                local pending=fingerprint(env,env.SpawnPositions)
                eq(disk.files[backup],old); contains(disk.files[canonical],"partial:")
                staleBoth(env,disk,admin,second,kind)
                eq(env.hooks.ShutDown.saveTheTables(),nil); eq(count(disk,"write",backup),1)
                eq(fingerprint(env,env.SpawnPositions),pending,"failed shutdown does not undo accepted edit")
                disk.writeFaults[canonical]=nil; eq(env.fire("ShutDown"),nil)
                eq(count(disk,"write",backup),1); eq(disk.files[backup],old)
                eq(fingerprint(env,disk.snapshot(disk.files[canonical])),pending)
            end)
        end

        test("returning " .. kind.name .. " to acknowledged coordinates repairs damaged canonical bytes using the prepared backup",function()
            local env,disk,admin,_,_,old=fixture()
            local original=clone(env,env.SpawnPositions[4][kind.field][kind.key])
            admin:SetPos(env.Vector(601,602,603)); inspect(env,admin,kind)
            disk.writeFaults[canonical]="false"; contains(move(env,admin,kind),"remains in memory")
            disk.writeFaults[canonical]=nil; inspect(env,admin,kind); admin:SetPos(original)
            move(env,admin,kind)
            eq(disk.files[canonical],old,"unchanged candidate still repairs a mismatched canonical file")
            eq(disk.files[backup],old); eq(count(disk,"write",backup),1); eq(count(disk,"write",canonical),2)
            eq(env.fire("ShutDown"),nil); eq(count(disk,"write",canonical),2)
        end)

        test("same-coordinate " .. kind.name .. " edit verifies unchanged bytes without rotating backup",function()
            local env,disk,admin,second,_,old=fixture(); disk.files[backup]="older recovery copy"
            local oldPoint=env.SpawnPositions[4][kind.field][kind.key]
            second:SetPos(oldPoint); inspect(env,admin,kind); inspect(env,second,kind)
            local start=#disk.log; move(env,second,kind)
            assert(not rawequal(env.SpawnPositions[4][kind.field][kind.key],oldPoint),"move remains accepted with detached Vector")
            eq(disk.encodes,1); eq(count(disk,"write"),0,"byte-identical move performs no write")
            eq(disk.files[canonical],old); eq(disk.files[backup],"older recovery copy")
            local canonicalRead=false
            for i=start+1,#disk.log do if disk.log[i].op == "read" and disk.log[i].path == canonical then canonicalRead=true end end
            assert(canonicalRead,"no-op checks actual canonical bytes")
            staleBoth(env,disk,admin,second,kind)
            eq(env.hooks.ShutDown.saveTheTables(),nil,"shutdown never returns status")
            eq(count(disk,"write"),0); eq(disk.files[backup],"older recovery copy")
        end)

        for _,mode in ipairs({"legacy","both"}) do
            test(kind.name .. " edit backs up the selected " .. mode .. " load without changing legacy bytes",function()
                local env,disk,admin,_,_,old=fixture(mode); local originalLegacy=disk.files[legacy]
                inspect(env,admin,kind); admin:SetPos(env.Vector(401,402,403)); local start=#disk.log
                move(env,admin,kind); eq(disk.files[backup],old)
                verifiedOrder(disk,start,old,disk.files[canonical]); eq(disk.files[legacy],originalLegacy)
                eq(count(disk,"write",legacy),0)
                if mode == "both" then eq(count(disk,"read",legacy),0,"canonical precedence does not read legacy") end
            end)
        end

        for _,mode in ipairs({"first","orphan"}) do
            test("first " .. kind.name .. " save with " .. mode .. " storage preserves unrelated backup through destructive failure",function()
                local env,disk,admin=fixture(mode); local originalBackup=disk.files[backup]
                admin:SetPos(env.Vector(701,702,703)); disk.writeFaults[canonical]="false"
                local text=edit(env,admin,kind,"add"); contains(text,"remains in memory")
                eq(count(disk,"write",backup),0); eq(disk.files[backup],originalBackup)
                disk.writeFaults[canonical]=nil
                eq(env.hooks.ShutDown.saveTheTables(),nil)
                eq(count(disk,"write",backup),0); eq(disk.files[backup],originalBackup)
                eq(fingerprint(env,disk.snapshot(disk.files[canonical])),fingerprint(env,env.SpawnPositions))
                local before=count(disk,"write"); eq(env.fire("ShutDown"),nil); eq(count(disk,"write"),before)
            end)
        end

        for _,failure in ipairs({"false","nil","throw","truncated true","read nil","read throw","read wrong"}) do
            test("active " .. kind.name .. " edits retain one prepared backup across destructive canonical " .. failure .. " and shutdown",function()
                local env,disk,admin,second,_,old=fixture()
                local menu=readyDialogue(env,admin); local enemies=startDialogue(env,admin,menu)
                second:SetPos(env.Vector(501,502,503)); inspect(env,admin,kind); inspect(env,second,kind)
                if failure:sub(1,5) == "read " then disk.readFaults[canonical]=failure:sub(6)
                else disk.writeFaults[canonical]=failure end
                local before=lifecycle(env,admin); local printed=#disk.prints
                contains(move(env,second,kind),"remains in memory")
                eq(env.SpawnPositions[4][kind.field][kind.key].x,501)
                eq(disk.files[backup],old); eq(count(disk,"write",backup),1)
                eq(#disk.prints,printed,"unverified save is not announced as successful")
                if failure:sub(1,5) == "read " then
                    eq(disk.snapshot(disk.files[canonical])[4][kind.field][kind.key].x,501,
                        "write may have stored candidate bytes even though verification failed")
                    assert(not second.chats[#second.chats]:find("in memory only",1,true),
                        "warning must not claim candidate bytes are absent from disk")
                else
                    contains(disk.files[canonical],"partial:")
                end
                sameLifecycle(env,admin,before); staleBoth(env,disk,admin,second,kind)
                second:SetPos(env.Vector(801,802,803)); inspect(env,second,kind)
                before=lifecycle(env,admin); contains(move(env,second,kind),"remains in memory")
                eq(env.hooks.ShutDown.saveTheTables(),nil)
                eq(count(disk,"write",backup),1,"retries do not rewrite sole prepared recovery copy")
                eq(count(disk,"write",canonical),3); eq(disk.files[backup],old)
                sameLifecycle(env,admin,before)
                disk.writeFaults[canonical]=nil; disk.readFaults[canonical]=nil
                eq(env.fire("ShutDown"),nil); eq(count(disk,"write",backup),1)
                eq(disk.snapshot(disk.files[canonical])[4][kind.field][kind.key].x,801)
                eq(disk.snapshot(disk.files[backup])[4][kind.field][kind.key].x,kind.name == "enemy" and 110 or 211)
                sameLifecycle(env,admin,before); finishRound(env,admin,enemies)
            end)
        end

        for _,damage in ipairs({"tampered","nil","throw"}) do
            test("prepared " .. kind.name .. " backup " .. damage .. " blocks repeated retries until exact bytes recover, then rotates next predecessor",function()
                local env,disk,admin,second,_,old=fixture()
                inspect(env,admin,kind); admin:SetPos(env.Vector(401,402,403)); disk.writeFaults[canonical]="false"
                contains(move(env,admin,kind),"remains in memory"); eq(disk.files[backup],old)
                disk.writeFaults[canonical]=nil
                if damage == "tampered" then disk.files[backup]="tampered recovery bytes"
                else disk.readFaults[backup]=damage end
                local damaged=disk.files[backup]; local brokenCanonical=disk.files[canonical]
                local writes=count(disk,"write")
                inspect(env,second,kind); second:SetPos(env.Vector(601,602,603))
                contains(move(env,second,kind),"remains in memory"); eq(env.fire("ShutDown"),nil)
                eq(count(disk,"write"),writes,"untrusted prepared copy blocks all writes")
                eq(disk.files[backup],damaged); eq(disk.files[canonical],brokenCanonical)
                eq(env.SpawnPositions[4][kind.field][kind.key].x,601)
                disk.files[backup]=old; disk.readFaults[backup]=nil
                eq(env.fire("ShutDown"),nil); eq(count(disk,"write",backup),1)
                local recovered=disk.files[canonical]; eq(disk.snapshot(recovered)[4][kind.field][kind.key].x,601)
                inspect(env,admin,kind); admin:SetPos(env.Vector(901,902,903)); local start=#disk.log
                move(env,admin,kind); eq(disk.files[backup],recovered)
                verifiedOrder(disk,start,recovered,disk.files[canonical]); eq(count(disk,"write",backup),2)
                eq(disk.snapshot(disk.files[backup])[4][kind.field][kind.key].x,601)
                eq(disk.snapshot(disk.files[canonical])[4][kind.field][kind.key].x,901)
                writes=count(disk,"write"); eq(env.fire("ShutDown"),nil); eq(count(disk,"write"),writes)
                eq(disk.files[backup],recovered,"byte-identical shutdown retains actual predecessor")
            end)
        end

        for _,failure in ipairs({"false","truncated true","read nil","read throw"}) do
            test(kind.name .. " backup preparation " .. failure .. " preserves canonical and open Start permission",function()
                local env,disk,admin,second,_,old=fixture(); local menu=readyDialogue(env,admin)
                inspect(env,admin,kind); inspect(env,second,kind); second:SetPos(env.Vector(301,302,303))
                if failure:sub(1,5) == "read " then disk.readFaults[backup]=failure:sub(6)
                else disk.writeFaults[backup]=failure end
                local before=lifecycle(env,admin); local printed=#disk.prints
                contains(move(env,second,kind),"remains in memory")
                eq(disk.files[canonical],old); eq(count(disk,"write",canonical),0)
                eq(env.SpawnPositions[4][kind.field][kind.key].x,301); eq(#disk.prints,printed)
                sameLifecycle(env,admin,before); staleBoth(env,disk,admin,second,kind)
                eq(menu.frame.valid,true); startDialogue(env,admin,menu)
            end)
        end

        test("empty sparse " .. kind.name .. " list is a valid predecessor and empty removal has no I/O",function()
            local env,disk,admin,_,observer,old=fixture("empty lists")
            noIO(disk,function()
                edit(env,admin,kind,"bare removal")
                privateSay(env,observer,kind.move .. " " .. kind.key)
                eq(say(env,observer,kind.add),nil); eq(say(env,observer,kind.remove),nil)
                privateSay(env,admin,kind.move .. " nonsense")
            end)
            admin:SetPos(env.Vector(101,102,103)); local start=#disk.log; edit(env,admin,kind,"add")
            eq(env.SpawnPositions[4][kind.field][1].x,101); eq(env.SpawnPositions[1],nil)
            eq(disk.files[backup],old); verifiedOrder(disk,start,old,disk.files[canonical])
            eq(next(disk.snapshot(old)[4][kind.field]),nil,"empty predecessor remains empty")
        end)
    end

    test("loaded empty map table remains an intentional choice until actual add creates its first record",function()
        local env,disk,admin,_,_,old=fixture("empty root")
        eq(next(env.SpawnPositions),nil); eq(env.fire("ShutDown"),nil); eq(count(disk,"write"),0)
        admin:SetPos(env.Vector(5,6,7)); local start=#disk.log; edit(env,admin,kinds[1],"add")
        eq(env.SpawnPositions[1].map,"gm_construct"); eq(env.SpawnPositions[1].enemySpawnPositions[1].x,5)
        eq(disk.files[backup],old); verifiedOrder(disk,start,old,disk.files[canonical])
        eq(next(disk.snapshot(old)),nil)
    end)

    for _,failure in ipairs({"throw","nil","empty","unknown token","bad schema"}) do
        test("accepted edit with candidate " .. failure .. " fails before file writes and invalidates inspections",function()
            local env,disk,admin,second,_,old=fixture()
            inspect(env,admin,kinds[1]); inspect(env,second,kinds[1]); second:SetPos(env.Vector(801,802,803))
            disk.encodeFault=failure
            contains(move(env,second,kinds[1]),"remains in memory")
            eq(count(disk,"write"),0); eq(disk.files[canonical],old); eq(disk.files[backup],nil)
            eq(env.SpawnPositions[4].enemySpawnPositions[10].x,801)
            staleBoth(env,disk,admin,second,kinds[1])
            disk.encodeFault=nil; eq(env.fire("ShutDown"),nil); eq(disk.files[backup],old)
        end)
    end

    for _,failure in ipairs({"corrupt","nil","throw"}) do
        test("canonical " .. failure .. " locks out edits and shutdown despite valid legacy and backup",function()
            local env=gmod.new(); local disk=storage(env)
            local valid=disk.register("{ valid alternate recovery }",sparse(env))
            disk.files[canonical]="unrecognized corrupt canonical"
            disk.files[legacy]=valid; disk.files[backup]=valid
            if failure ~= "corrupt" then disk.readFaults[canonical]=failure end
            local configured=env.SpawnPositions; env.fire("Initialize"); assert(rawequal(env.SpawnPositions,configured))
            local admin=env.entity("player"); admin.admin=true; admin:SetPos(env.Vector(4,5,6))
            local files=fingerprint(env,disk.files); local log=#disk.log
            for _,kind in ipairs(kinds) do contains(edit(env,admin,kind,"add"),"remains in memory") end
            eq(env.hooks.ShutDown.saveTheTables(),nil); eq(#disk.log,log,"lockout avoids all persistence I/O")
            eq(fingerprint(env,disk.files),files); eq(disk.encodes,0)
            eq(count(disk,"read",legacy),0); eq(count(disk,"read",backup),0)
        end)
    end
end
