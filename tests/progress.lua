-- These tests execute the actual addon with host doubles. They validate Lua
-- behavior and protocol fields, not native GMod networking or HUD rendering.
return function(gmod, test, eq)
    local statusName, requestName = "ActivatorEventStatus", "RequestActivatorEventStatus"
    local function snapshots(env)
        local found={}
        for _, message in ipairs(env.messages) do
            if message.name == statusName then found[#found+1]=message end
        end
        return found
    end
    local function lastSnapshot(env)
        local found=snapshots(env)
        return assert(found[#found], "expected an encounter status message")
    end
    local function active(message, identifier, remaining, initial, interrupted)
        eq(message.unreliable, false, "status is reliable")
        eq(#message.values, 5)
        eq(message.values[1], true)
        eq(message.values[2], identifier)
        eq(message.values[3], remaining)
        eq(message.values[4], initial)
        eq(message.values[5], interrupted)
        eq(message.fields[1].kind, "bool")
        eq(message.fields[2].kind, "string")
        for _, index in ipairs({3, 4}) do
            eq(message.fields[index].kind, "uint")
            eq(message.fields[index].bits, 32, "counts retain the complete configured range")
        end
        eq(message.fields[5].kind, "bool")
    end
    local function inactive(message)
        eq(message.unreliable, false)
        eq(#message.values, 1, "inactive messages contain no stale encounter fields")
        eq(message.values[1], false)
        eq(message.fields[1].kind, "bool")
    end
    local function broadcast(env, message)
        local recipients={}
        for _, recipient in ipairs(message.player) do recipients[recipient]=true end
        local players=env.player.GetAll()
        eq(#message.player, #players, "every connected player receives progress")
        for _, ply in ipairs(players) do eq(recipients[ply], true) end
    end
    local function roots(env, class)
        local found={}
        for _, panel in ipairs(env.panels) do
            if panel.valid and panel.class == class and not panel.parent then found[#found+1]=panel end
        end
        return found
    end
    local function hud(env)
        local found=roots(env, "DPanel")
        eq(#found, 1, "there is one encounter panel")
        return found[1]
    end
    local function checkHud(env, identifier, remaining, initial, interrupted)
        local panel=hud(env)
        local eventLabel, countLabel, bar, warning
        for _, child in ipairs(panel.children) do
            if child.class == "DProgress" then bar=child end
            if child.class == "DLabel" then
                local label=child.text or ""
                if label:find(identifier, 1, true) then eventLabel=child end
                local first, second=label:match("(%d+)%D+(%d+)")
                if tonumber(first) == remaining and tonumber(second) == initial then countLabel=child end
                if label:lower():find("interrupt", 1, true) or label:lower():find("cleanup", 1, true) then warning=child end
            end
            eq(child.popup, nil, "progress children never capture focus")
        end
        assert(eventLabel and eventLabel:IsVisible(), "event identifier is visible")
        assert(countLabel and countLabel:IsVisible(), "remaining and initial counts are visible")
        assert(bar and bar:IsVisible(), "remaining progress bar is visible")
        eq(bar.fraction, remaining / initial)
        if interrupted then assert(warning and warning:IsVisible(), "cleanup interruption is visibly explained")
        elseif warning then eq(warning:IsVisible(), false, "clean events show no cleanup warning") end
        eq(panel.popup, nil, "progress never calls MakePopup")
        eq(panel.mouseInput, false, "progress cannot intercept the mouse")
        eq(panel.keyboardInput, false, "progress cannot intercept the keyboard")
        assert(panel.width > 0 and panel.width <= 600 and panel.height > 0 and panel.height <= 200, "progress is compact")
        return panel
    end
    local function publish(env, identifier, remaining, initial, interrupted)
        env.receive(statusName, nil, true, identifier, remaining, initial, interrupted or false)
    end

    test("successful start broadcasts the actual encounter progress", function()
        local env=gmod.new(); local _, enemies=env.start()
        eq(env.messageCount(statusName), 1, "successful start publishes one progress snapshot")
        local snapshot=lastSnapshot(env)
        active(snapshot, "Raid", #enemies, #enemies, false)
        broadcast(env, snapshot)
        eq(env.networkStrings[statusName], true); eq(env.networkStrings[requestName], true)
    end)
    test("progress uses surviving spawned NPCs when creation and spawn both fail", function()
        local env=gmod.new(); local create=env.ents.Create; local attempts=0
        env.ents.Create=function(class)
            if class ~= "npc_stalker" then return create(class) end
            attempts=attempts+1
            if attempts == 1 or attempts == 3 then return {valid=false} end
            local enemy=create(class)
            if attempts == 5 then
                local spawn=enemy.Spawn
                function enemy:Spawn() spawn(self); self:Remove() end
            end
            return enemy
        end
        local ply, enemies=env.start()
        eq(attempts, 5); eq(#enemies, 2); eq(env.totalEnemies, 2)
        eq(env.messageCount(statusName), 1); active(lastSnapshot(env), "Raid", 2, 2, false)
        env.fire("OnNPCKilled", enemies[1], ply)
        active(lastSnapshot(env), "Raid", 1, 2, false)
    end)
    test("custom event identifier reaches progress independently of the Raid default", function()
        local env=gmod.new(); env.NPCEdits[1].name="Supply Raid"
        local ply, activator=env.ready(); activator:AcceptInput("Use", ply, ply)
        env.receive("SendNPCInformation", ply, "Supply Raid")
        active(lastSnapshot(env), "Supply Raid", 5, 5, false)
    end)
    test("owned kills publish each remaining count and one inactive completion", function()
        local env=gmod.new(); local _, enemies=env.start(); local world=env.entity("worldspawn")
        for i, enemy in ipairs(enemies) do
            env.fire("OnNPCKilled", enemy, world)
            eq(env.messageCount(statusName), i+1)
            broadcast(env, lastSnapshot(env))
            if i < #enemies then active(lastSnapshot(env), "Raid", #enemies-i, #enemies, false)
            else inactive(lastSnapshot(env)) end
        end
        eq(env.messageCount("roundFinished"), 1); eq(env.totalEnemies, 0)
        eq(env.timers.activatorSpawner.stopped, false)
    end)
    test("unrelated and repeated deaths or removals never publish progress", function()
        local env=gmod.new(); local ply, enemies=env.start(); local unrelated=env.entity("npc_stalker")
        unrelated:SetName("devonsSpawnedEntity")
        env.fire("OnNPCKilled", unrelated, ply); unrelated:Remove()
        eq(env.messageCount(statusName), 1)
        env.fire("OnNPCKilled", enemies[1], ply)
        env.fire("OnNPCKilled", enemies[1], ply); enemies[1]:Remove()
        eq(env.messageCount(statusName), 2); active(lastSnapshot(env), "Raid", 4, 5, false)
        for i=2,#enemies do env.fire("OnNPCKilled", enemies[i], ply) end
        local count=env.messageCount(statusName)
        env.fire("OnNPCKilled", enemies[5], ply); enemies[5]:Remove()
        env.fire("OnNPCKilled", env.entity("npc_stalker"), ply)
        eq(env.messageCount(statusName), count); eq(env.messageCount("roundFinished"), 1)
    end)
    test("owned removals publish interrupted counts and clear without victory", function()
        local env=gmod.new(); local _, enemies=env.start()
        for i, enemy in ipairs(enemies) do
            enemy:Remove(); eq(env.messageCount(statusName), i+1)
            if i < #enemies then active(lastSnapshot(env), "Raid", #enemies-i, #enemies, true)
            else inactive(lastSnapshot(env)) end
        end
        eq(env.messageCount("roundFinished"), 0); eq(env.totalEnemies, 0)
        eq(env.timers.activatorSpawner.stopped, false)
    end)
    test("cleanup interruption survives later kills and resets for the next event", function()
        local env=gmod.new(); local ply, enemies=env.start(); enemies[1]:Remove()
        env.fire("OnNPCKilled", enemies[2], ply)
        active(lastSnapshot(env), "Raid", 3, 5, true)
        for i=3,#enemies do env.fire("OnNPCKilled", enemies[i], ply) end
        inactive(lastSnapshot(env)); eq(env.messageCount("roundFinished"), 0)
        env.start(); active(lastSnapshot(env), "Raid", 5, 5, false)
    end)
    test("admin stop publishes only one clear before removing owned enemies", function()
        local env=gmod.new(); local ply=env.start(); ply.admin=true
        env.fire("PlayerSay", ply, "!stopEvent")
        eq(env.messageCount(statusName), 2); inactive(lastSnapshot(env))
        broadcast(env, lastSnapshot(env))
        eq(#env.ents.FindByName("devonsSpawnedEntity"), 0)
        eq(env.messageCount("entitiesDeleted"), 1); eq(env.messageCount("roundFinished"), 0)
        env.start(); active(lastSnapshot(env), "Raid", 5, 5, false)
    end)
    test("non-admin stop and rejected starts cannot publish or alter progress", function()
        local env=gmod.new(); local ply, activator=env.ready()
        env.receive("SendNPCInformation", ply, "Raid")
        eq(env.messageCount(statusName), 0)
        activator:AcceptInput("Use", ply, ply); env.receive("SendNPCInformation", ply, "Raid")
        env.fire("PlayerSay", ply, "!stopEvent")
        env.receive("SendNPCInformation", ply, "Forged")
        eq(env.messageCount(statusName), 1); active(lastSnapshot(env), "Raid", 5, 5, false)
    end)
    test("zero successful spawns publishes an inactive clear without victory", function()
        local env=gmod.new(); env.failClass="npc_stalker"; env.start()
        eq(env.messageCount(statusName), 1); inactive(lastSnapshot(env))
        broadcast(env, lastSnapshot(env))
        eq(env.totalEnemies, 0); eq(env.messageCount("roundFinished"), 0)
        eq(env.timers.activatorSpawner.stopped, false)
    end)
    test("a snapshot request returns current progress only to its actual sender", function()
        local env=gmod.new(); local ply, enemies=env.start(); enemies[1]:Remove()
        local late=env.entity("player"); env.receive(requestName, late)
        local message=lastSnapshot(env)
        active(message, "Raid", 4, 5, true)
        eq(message.player, late); eq(message.broadcast, nil)
        eq(env.messageCount(statusName), 3)
        eq(env.totalEnemies, 4); eq(env.messageCount("roundFinished"), 0)
        eq(ply.valid, true)
    end)
    test("idle and finished snapshot requests contain only the inactive flag", function()
        local env=gmod.new(); local late=env.entity("player")
        env.receive(requestName, late); inactive(lastSnapshot(env)); eq(lastSnapshot(env).player, late)
        local ply, enemies=env.start()
        for _, enemy in ipairs(enemies) do env.fire("OnNPCKilled", enemy, ply) end
        env.now=1; env.receive(requestName, late)
        inactive(lastSnapshot(env)); eq(lastSnapshot(env).player, late)
    end)
    test("snapshot payload is ignored and cannot forge state or consume start permission", function()
        local env=gmod.new(); local ply, activator=env.ready(); local victim=env.entity("player")
        activator:AcceptInput("Use", ply, ply)
        local reads=env.netReads or 0
        env.receive(requestName, ply, victim, true, "Forged", 999, 999, true)
        eq(env.netReads or 0, reads, "snapshot handler never reads client-owned state")
        eq(lastSnapshot(env).player, ply); inactive(lastSnapshot(env)); eq(env.totalEnemies, 0)
        env.receive("SendNPCInformation", ply, "Raid")
        active(lastSnapshot(env), "Raid", 5, 5, false)
        env.now=1; env.receive(requestName, ply, victim, false, "Forged", 0, 1, true)
        eq(lastSnapshot(env).player, ply); active(lastSnapshot(env), "Raid", 5, 5, false)
        eq(env.totalEnemies, 5); eq(env.messageCount("roundFinished"), 0)
    end)
    test("snapshot requests reject missing invalid and non-player senders", function()
        local env=gmod.new(); env.receive(requestName, nil)
        env.receive(requestName, {valid=false})
        env.receive(requestName, env.entity("npc_stalker"))
        eq(env.messageCount(statusName), 0)
        local ply=env.entity("player"); env.receive(requestName, ply)
        eq(env.messageCount(statusName), 1); eq(lastSnapshot(env).player, ply)
    end)
    test("snapshot throttle is per player with a one-second boundary", function()
        local env=gmod.new(); local first, second=env.entity("player"), env.entity("player")
        env.receive(requestName, first); env.receive(requestName, first)
        eq(env.messageCount(statusName), 1)
        env.receive(requestName, second); eq(env.messageCount(statusName), 2)
        env.now=0.999; env.receive(requestName, first); eq(env.messageCount(statusName), 2)
        env.now=1; env.receive(requestName, first); eq(env.messageCount(statusName), 3)
        eq(lastSnapshot(env).player, first)
    end)
    test("disconnect clears a player's snapshot throttle", function()
        local env=gmod.new(); local ply=env.entity("player")
        env.receive(requestName, ply); env.fire("PlayerDisconnected", ply)
        env.receive(requestName, ply)
        eq(env.messageCount(statusName), 2, "same synthetic sender object is no longer throttled")
    end)
    test("client requests an empty snapshot only after InitPostEntity readiness", function()
        local env=gmod.new(true); eq(env.messageCount(requestName), 0)
        env.fire("InitPostEntity")
        eq(env.messageCount(requestName), 1); eq(#env.messages[1].values, 0)
        eq(env.messages[1].player, "server"); eq(env.messages[1].unreliable, false)
        eq(#env.panels, 0)
    end)
    test("late-join handshake transfers actual server state to one passive HUD", function()
        local server=gmod.new(); local ply, enemies=server.start()
        server.fire("OnNPCKilled", enemies[1], ply)
        local late=server.entity("player"); local client=gmod.new(true)
        client.fire("InitPostEntity"); server.deliver(client.messages[1], late)
        local message=lastSnapshot(server); eq(message.player, late)
        client.deliver(message)
        checkHud(client, "Raid", 4, 5, false)
        eq(client.messageCount(requestName), 1); eq(#client.messages, 1)
        eq(#roots(client, "DFrame"), 0)
    end)
    test("progress updates reuse the panel and show interruption without network writes", function()
        local env=gmod.new(true); publish(env, "Supply Raid", 5, 5)
        local panel=checkHud(env, "Supply Raid", 5, 5, false); local count=#env.panels
        publish(env, "Supply Raid", 3, 5, true)
        eq(checkHud(env, "Supply Raid", 3, 5, true), panel); eq(#env.panels, count)
        publish(env, "Ambush", 2, 3, false)
        eq(checkHud(env, "Ambush", 2, 3, false), panel); eq(#env.panels, count)
        eq(#env.messages, 0)
    end)
    test("inactive status removes the HUD and permits a clean next encounter", function()
        local env=gmod.new(true); publish(env, "Raid", 5, 5); local panel=hud(env)
        env.receive(statusName, nil, false); eq(panel.valid, false); eq(#roots(env, "DPanel"), 0)
        for _, child in ipairs(panel.children) do eq(child.valid, false) end
        env.receive(statusName, nil, false); eq(#roots(env, "DPanel"), 0)
        publish(env, "Ambush", 1, 2); assert(checkHud(env, "Ambush", 1, 2, false) ~= panel)
        eq(#env.messages, 0)
    end)
    for _, counts in ipairs({{0,5}, {1,0}, {0,0}, {6,5}}) do
        test("invalid active counts " .. counts[1] .. "/" .. counts[2] .. " clear stale progress", function()
            local env=gmod.new(true); publish(env, "Raid", 5, 5); local panel=hud(env)
            publish(env, "Raid", counts[1], counts[2])
            eq(panel.valid, false); eq(#roots(env, "DPanel"), 0); eq(#env.messages, 0)
        end)
    end
    test("screen resize repositions the same HUD within the new viewport", function()
        local env=gmod.new(true); publish(env, "Raid", 3, 5, true)
        local panel=checkHud(env, "Raid", 3, 5, true)
        local positionChanges=panel.positionChanges or 0
        env.screenWidth, env.screenHeight=800, 600
        env.fire("OnScreenSizeChanged", 1920, 1080)
        eq(checkHud(env, "Raid", 3, 5, true), panel)
        assert((panel.positionChanges or 0) > positionChanges, "resize recomputes position")
        assert(panel.x >= 0 and panel.y >= 0 and panel.x+panel.width <= 800 and panel.y+panel.height <= 600, "HUD fits the resized screen")
        eq(#env.messages, 0)
    end)
    test("clearing progress leaves the interaction and completion popups independent", function()
        local env=gmod.new(true); publish(env, "Raid", 3, 5)
        local panel=hud(env); local ply, ent=env.entity("player"), env.entity("activatorent")
        ent.model="models/alyx.mdl"
        env.receive("OpenInteractionMenu", nil, ply, ent, "Raid", "Ready?")
        local interaction=roots(env, "DFrame")[1]; local start
        for _, child in ipairs(interaction.children) do
            if child.class == "DButton" and child.text:find("Start", 1, true) then start=child end
        end
        env.receive("roundFinished", nil); local alert=roots(env, "DFrame")[2]
        env.receive(statusName, nil, false)
        eq(panel.valid, false); eq(interaction.valid, true); eq(alert.valid, true)
        env.fireTimer("destroyAlertFrame")
        eq(alert.valid, false); eq(interaction.valid, true)
        assert(start):DoClick(); eq(env.messageCount("SendNPCInformation"), 1)
        eq(env.messageCount("CloseInteractionMenu"), 0)
    end)
    test("completion timer never destroys a new encounter HUD", function()
        local env=gmod.new(true); env.receive("roundFinished", nil)
        publish(env, "Ambush", 2, 4); local panel=hud(env)
        env.fireTimer("destroyAlertFrame")
        eq(checkHud(env, "Ambush", 2, 4, false), panel); eq(#roots(env, "DFrame"), 0)
    end)
    test("real server start kill cleanup and stop messages update then clear the client", function()
        local server, client=gmod.new(), gmod.new(true)
        local ply, enemies=server.start(); client.deliver(lastSnapshot(server))
        local panel=checkHud(client, "Raid", 5, 5, false)
        server.fire("OnNPCKilled", enemies[1], ply); client.deliver(lastSnapshot(server))
        eq(checkHud(client, "Raid", 4, 5, false), panel)
        enemies[2]:Remove(); client.deliver(lastSnapshot(server))
        eq(checkHud(client, "Raid", 3, 5, true), panel)
        ply.admin=true; server.fire("PlayerSay", ply, "!stopEvent")
        client.deliver(lastSnapshot(server)); eq(panel.valid, false); eq(#roots(client, "DPanel"), 0)
        eq(server.messageCount("roundFinished"), 0); eq(#client.messages, 0)
    end)
end
