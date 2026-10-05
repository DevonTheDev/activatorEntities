AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")
if not returnNPCInformation then include("autorun/server/sv_config.lua") end

util.AddNetworkString("OpenInteractionMenu")
util.AddNetworkString("CloseInteractionMenu")
util.AddNetworkString("SendNPCInformation")
util.AddNetworkString("roundFinished")
util.AddNetworkString("ActivatorEventStatus")
util.AddNetworkString("RequestActivatorEventStatus")

activatorCount = 0
totalEnemies = 0

local interactions = {}
local activeEnemies = {}
local constructingEnemies
local eventActive = false
local eventInterrupted = false
local activeEventName
local initialEnemies = 0
local statusRequestAfter = {}
local interactionLifetime = 60
local interactionDistanceSquared = 200 * 200

-- Pending is a replaceable slot; a selected batch owns only its own activators.
local pendingSelection
local selectedBatchName
local selectedBatchEntities = {}

local function usableActivator(ent, removed)
    return ent ~= removed and IsValid(ent) and not ent:IsMarkedForDeletion()
end

local function selectedBatchAlive(removed)
    for ent in pairs(selectedBatchEntities) do
        if usableActivator(ent, removed) then return true end
    end
    return false
end

local function clearSelectedBatch()
    selectedBatchName = nil
    selectedBatchEntities = {}
end

local function refreshSelectedBatch(removed)
    for ent in pairs(selectedBatchEntities) do
        if not usableActivator(ent, removed) then selectedBatchEntities[ent] = nil end
    end
    if not next(selectedBatchEntities) then clearSelectedBatch() end
end

-- Selection requires one exact, currently configured name with information.
local function selectableEvent(name)
    local found
    for _, event in pairs(type(NPCEdits) == "table" and NPCEdits or {}) do
        if type(event) == "table" and event.name == name then
            if found then return nil, "duplicate configured name" end
            found = event
        end
    end
    if not found then return nil, "unknown configured name" end
    if type(found.information) ~= "table" then return nil, "missing event information" end
    return found.information
end

-- Reserve status metadata within ChatPrint's 255 bytes before shortening a name.
local function adminLine(ply, text, suffix)
    suffix = suffix or ""
    text = text:gsub("[%c]", " ")
    local limit = 255 - #suffix
    if #text > limit then
        local last = limit - 3
        -- Keep complete UTF-8 characters at the truncation boundary.
        while text:byte(last + 1) >= 128 and text:byte(last + 1) <= 191 do last = last - 1 end
        text = text:sub(1, last) .. "..."
    end
    ply:ChatPrint(text .. suffix)
end

local function selectionLine(ply, prefix, name)
    if not name then adminLine(ply, prefix .. "none.") return end
    adminLine(ply, prefix .. '"' .. name, '"' .. (selectableEvent(name) and "" or " (unavailable)") .. ".")
end

local function nameList(ply, names, prefix, counts)
    table.sort(names)
    for i = 1, math.min(#names, 8) do
        local name = names[i]
        adminLine(ply, prefix .. '"' .. name, '"' .. (counts and (" (" .. counts[name] .. ")") or ""))
    end
    if #names > 8 then adminLine(ply, (#names - 8) .. " additional names omitted.") end
end

local function selectionHelp(ply)
    adminLine(ply, "Usage: !nextEvent <exact configured name> (case-sensitive). !clearNextEvent clears the pending choice.")
    local names, seen = {}, {}
    for _, event in pairs(type(NPCEdits) == "table" and NPCEdits or {}) do
        if type(event) == "table" and type(event.name) == "string" and not seen[event.name] then
            names[#names + 1] = event.name
            seen[event.name] = true
        end
    end
    nameList(ply, names, "Configured event: ")
    if #names == 0 then adminLine(ply, "No event names are configured.") end
end

-- Status only inspects current inputs; it neither samples nor refreshes state.
local function finiteStatusNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function statusListIndex(value)
    return finiteStatusNumber(value) and value >= 1 and value == math.floor(value)
end

local function currentStatusMap()
    if type(SpawnPositions) ~= "table" then return nil, "malformed map data" end
    local found, matches = nil, 0
    local map = game.GetMap()
    for key, information in pairs(SpawnPositions) do
        if not statusListIndex(key) or type(information) ~= "table"
            or type(information.map) ~= "string" or information.map == "" then
            return nil, "malformed map data"
        end
        if information.map == map then found, matches = information, matches + 1 end
    end
    -- The spawner uses one record, so duplicates cannot be combined or chosen here.
    if matches > 1 then return nil, "ambiguous map records (" .. matches .. ")" end
    if not found then return nil, "missing map record" end
    return found
end

local function positionStatus(information, reason, field)
    if not information then return reason end
    local positions = information[field]
    if positions == nil then return "missing list" end
    if type(positions) ~= "table" then return "malformed list" end
    local count = 0
    for key, position in pairs(positions) do
        if not statusListIndex(key) or not isvector(position)
            or not finiteStatusNumber(position.x) or not finiteStatusNumber(position.y)
            or not finiteStatusNumber(position.z) then return "malformed list" end
        count = count + 1
    end
    return count == 0 and "empty list" or (count .. " available")
end

local function spawnDefinitionStatus(count, readyName)
    local name = readyName or (count == 0 and pendingSelection and pendingSelection.name)
    if name then
        local information, reason = selectableEvent(name)
        return (readyName and "selected batch: " or "pending selection: ")
            .. (information and "information present; engine unchecked" or reason)
    end
    if NPCEdits == nil then return "random: no configured pool" end
    if type(NPCEdits) ~= "table" then return "random: unassessable pool" end
    local seen, count = {}, 0
    for _, event in pairs(NPCEdits) do
        if type(event) ~= "table" or type(event.name) ~= "string" or event.name == ""
            or seen[event.name] or type(event.information) ~= "table" then
            return "random: unassessable pool"
        end
        seen[event.name], count = true, count + 1
    end
    return count == 0 and "random: no configured pool"
        or "random: pool present; event unchosen; engine unchecked"
end

local function printSpawnConditions(ply, count, readyName)
    local players, minimum = player.GetCount(), returnMinNumberOfPlayers()
    local playerCondition = "unavailable (invalid minimum)"
    if finiteStatusNumber(minimum) then
        playerCondition = minimum .. (players < minimum and " (below minimum)" or " (met)")
    end
    -- Match the existing fallback exactly: zero and negatives are truthy in Lua.
    local maximum = returnMaxActivators() or 1
    local capacityCondition = "unavailable (invalid capacity)"
    if finiteStatusNumber(maximum) then
        local condition
        if maximum < 0 then condition = "negative; no capacity"
        elseif maximum == 0 then condition = "no capacity"
        elseif maximum ~= math.floor(maximum) then condition = "fractional; unassessed"
        elseif count >= maximum then condition = "capacity reached"
        else condition = "space" end
        capacityCondition = maximum .. " (" .. condition .. ")"
    end
    adminLine(ply, "Automatic spawn, next normal attempt: "
        .. (eventActive and "active encounter (blocked)" or "no active encounter")
        .. "; players " .. players .. "/min " .. playerCondition
        .. "; activators " .. count .. "/cap " .. capacityCondition .. ".")
    local information, reason = currentStatusMap()
    adminLine(ply, "Spawn inputs: " .. spawnDefinitionStatus(count, readyName)
        .. "; current-map activator positions: " .. positionStatus(information, reason, "activatorSpawnPositions") .. ".")
    adminLine(ply, "Encounter start enemy positions: " .. positionStatus(information, reason, "enemySpawnPositions")
        .. " (required on use).")
end

local function printSelectionStatus(ply)
    if eventActive then
        adminLine(ply, 'Active event: "' .. activeEventName, '" (' .. totalEnemies .. "/" .. initialEnemies
            .. " enemies remaining" .. (eventInterrupted and "; interrupted" or "") .. ").")
    else adminLine(ply, "Active event: none.") end
    local count, names, counts = 0, {}, {}
    for _, ent in pairs(ents.FindByClass("activatorent")) do
        if usableActivator(ent) then
            count = count + 1
            local name = ent.EventIdentifier or "unknown"
            if not counts[name] then names[#names + 1] = name end
            counts[name] = (counts[name] or 0) + 1
        end
    end
    adminLine(ply, "Ready activators: " .. count .. ".")
    nameList(ply, names, "Ready event: ", counts)
    local readyName = selectedBatchAlive() and selectedBatchName or nil
    selectionLine(ply, "Selected ready batch: ", readyName)
    selectionLine(ply, "Pending next batch: ", pendingSelection and pendingSelection.name)
    printSpawnConditions(ply, count, readyName)
end

hook.Add("PlayerSay", "selectNextActivatorEvent", function(ply, text)
    local command = text:match("^(!%S+)")
    if command ~= "!nextEvent" and command ~= "!clearNextEvent" and command ~= "!eventStatus" then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ply:IsAdmin() then
        adminLine(ply, "Only admins can select or inspect encounters.")
        return ""
    end
    if command == "!nextEvent" then
        local name = text:match("^!nextEvent%s(.*)$")
        if not name or name == "" then selectionHelp(ply) return "" end
        local info, reason = selectableEvent(name)
        if not info then
            adminLine(ply, "Next event unchanged: " .. reason .. ". Use !nextEvent to list configured names.")
            return ""
        end
        pendingSelection = {name = name}
        adminLine(ply, 'Queued for the next fresh automatic batch: "' .. name, '".')
    elseif text ~= command then
        adminLine(ply, "Usage: " .. command)
    elseif command == "!clearNextEvent" then
        pendingSelection = nil
        adminLine(ply, "Pending next event cleared.")
    else
        printSelectionStatus(ply)
    end
    return ""
end)

-- Observers receive only this server's current encounter state.
local function sendEventStatus(recipient)
    local active = eventActive and totalEnemies > 0
    net.Start("ActivatorEventStatus")
        net.WriteBool(active)
        if active then
            net.WriteString(activeEventName)
            net.WriteUInt(totalEnemies, 32)
            net.WriteUInt(initialEnemies, 32)
            net.WriteBool(eventInterrupted)
        end
    net.Send(recipient or player.GetAll())
end

-- A ready-client handshake also covers players joining during an encounter.
net.Receive("RequestActivatorEventStatus", function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local now = CurTime()
    if statusRequestAfter[ply] and now < statusRequestAfter[ply] then return end
    statusRequestAfter[ply] = now + 1
    sendEventStatus(ply)
end)
hook.Add("PlayerDisconnected", "clearActivatorStatusRequest", function(ply)
    statusRequestAfter[ply] = nil
end)

local function canInteract(ply, ent)
    return IsValid(ply) and ply:IsPlayer() and ply:Alive()
        and IsValid(ent) and not ent:IsMarkedForDeletion() and ent:GetClass() == "activatorent"
        and ply:GetPos():DistToSqr(ent:GetPos()) <= interactionDistanceSquared
end

-- Set up the NPC, including entities spawned manually before the first timer.
function ENT:Initialize()
    self.EventIdentifier = self.EventIdentifier or determineRandomEvent()
    self.NPCInfo = returnNPCInformation(self.EventIdentifier)
    if not self.NPCInfo then self:Remove() return end

    self:SetModel(self.NPCInfo.activatorModel)
    self:SetHullType(HULL_HUMAN)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_SCRIPT)
    self:SetSolid(SOLID_BBOX)
    self:SetUseType(SIMPLE_USE)
    if returnNPCRoam() then self:CapabilitiesAdd(CAP_MOVE_GROUND) end
    self:DropToFloor()
end

function ENT:AcceptInput(name, activator, caller)
    if name ~= "Use" or eventActive or not canInteract(caller, self) or not self.NPCInfo then return end

    interactions[caller] = {entity = self, expires = CurTime() + interactionLifetime}
    net.Start("OpenInteractionMenu")
        net.WriteEntity(caller)
        net.WriteEntity(self)
        net.WriteString(self.EventIdentifier)
        net.WriteString(self.NPCInfo.dialogue)
    net.Send(caller)
    self:StopMoving()
end

net.Receive("CloseInteractionMenu", function(_, ply)
    local ent = net.ReadEntity()
    local interaction = interactions[ply]
    if not interaction or interaction.entity ~= ent then return end
    interactions[ply] = nil
    if IsValid(ent) then ent:SetMoveType(MOVETYPE_STEP) end
end)

local function clearInteraction(ply)
    interactions[ply] = nil
end
hook.Add("PlayerDisconnected", "clearActivatorInteraction", clearInteraction)
hook.Add("PlayerDeath", "clearActivatorInteraction", clearInteraction)
hook.Add("PlayerSpawn", "clearActivatorInteraction", clearInteraction)

function destroyActivators()
    interactions = {}
    for _, ent in pairs(ents.FindByClass("activatorent")) do ent:Remove() end
    activatorCount = 0
end

local function finishEvent(completed)
    constructingEnemies = nil
    eventActive = false
    activeEnemies = {}
    totalEnemies = 0
    initialEnemies = 0
    activeEventName = nil
    timer.Start("activatorSpawner")
    sendEventStatus()
    if completed then
        net.Start("roundFinished")
        net.Send(player.GetAll())
    end
end

-- Callback boundaries can retire this exact event and start a replacement.
-- The in-flight NPC is not yet tracked, so its old constructor must remove it.
local function ownsConstruction(enemies, enemy)
    if eventActive and activeEnemies == enemies then return true end
    if IsValid(enemy) then enemy:Remove() end
    return false
end

-- Used by the admin command; clear ownership before removal callbacks fire.
function stopActivatorEvent()
    if not eventActive then return false end
    local enemies = activeEnemies
    finishEvent(false)
    for enemy in pairs(enemies) do if IsValid(enemy) then enemy:Remove() end end
    return true
end

net.Receive("SendNPCInformation", function(_, ply)
    local identifier = net.ReadString()
    local interaction = interactions[ply]
    interactions[ply] = nil -- A reply consumes the interaction, including invalid replies.
    if eventActive or not interaction or interaction.expires < CurTime()
        or not canInteract(ply, interaction.entity) then return end

    local ent = interaction.entity
    if identifier ~= ent.EventIdentifier then return end
    local info = ent.NPCInfo
    local spawnPosition = returnSpawnPositions(game.GetMap())
    if not spawnPosition then
        ErrorNoHalt("ERROR - There are no enemy spawn positions set for " .. game.GetMap() .. "\n")
        return
    end
    if type(info.maxNPCs) ~= "number" or info.maxNPCs < 1 or info.maxNPCs == math.huge then return end

    clearSelectedBatch()
    local enemies = activeEnemies
    constructingEnemies = enemies
    eventActive = true
    eventInterrupted = false
    activeEventName = identifier
    timer.Stop("activatorSpawner")
    destroyActivators()
    if not ownsConstruction(enemies) then return end
    for i = 1, math.floor(info.maxNPCs) do
        local enemy = ents.Create(info.npcPath)
        if not ownsConstruction(enemies, enemy) then return end
        if IsValid(enemy) then
            spawnPosition = spawnPosition + Vector(30, 30, 0)
            enemy:SetPos(spawnPosition)
            if not ownsConstruction(enemies, enemy) then return end
            enemy:SetName("devonsSpawnedEntity")
            if not ownsConstruction(enemies, enemy) then return end
            enemy:Spawn()
            if not ownsConstruction(enemies, enemy) then return end
            if IsValid(enemy) then
                local health = returnEnemyHealth()
                if not ownsConstruction(enemies, enemy) then return end
                enemy:SetHealth(health)
                if not ownsConstruction(enemies, enemy) then return end
                if IsValid(enemy) then
                    enemies[enemy] = true
                    totalEnemies = totalEnemies + 1
                    initialEnemies = initialEnemies + 1
                end
            end
        end
    end
    constructingEnemies = nil
    if initialEnemies == 0 then
        finishEvent(false)
        ErrorNoHalt("ERROR - No event enemies could be spawned\n")
        return
    end
    if totalEnemies == 0 then finishEvent(not eventInterrupted) return end
    sendEventStatus()
    for _, player in pairs(player.GetAll()) do
        player:ChatPrint(initialEnemies .. " enemies have been spawned. Eliminate them.")
    end
end)

-- Spawn only the missing activators, never more than the configured cap.
timer.Create("activatorSpawner", returnDelayBetweenEvents(), 0, function()
    if eventActive or player.GetCount() < returnMinNumberOfPlayers() then return end
    refreshSelectedBatch()
    activatorCount = 0
    for _, ent in pairs(ents.FindByClass("activatorent")) do
        if usableActivator(ent) then activatorCount = activatorCount + 1 end
    end
    local admittedSelection = activatorCount == 0 and pendingSelection or nil
    local selectedName = selectedBatchName or (admittedSelection and admittedSelection.name)
    local identifier
    if selectedName then
        if not selectableEvent(selectedName) then return end
        identifier = selectedName
    else identifier = determineRandomEvent() end
    if not identifier or not returnNPCInformation(identifier) then return end
    local spawnPosition = returnActivatorSpawns(game.GetMap())
    if not spawnPosition then return end

    local maximum = returnMaxActivators() or 1
    for i = activatorCount + 1, maximum do
        local activator = ents.Create("activatorent")
        if IsValid(activator) then
            activator.EventIdentifier = identifier
            activator:SetPos(spawnPosition)
            activator:Spawn()
            if selectedName and usableActivator(activator) then
                selectedBatchName = selectedName
                selectedBatchEntities[activator] = true
                -- Spawn can run other addon callbacks that replace/clear pending.
                if pendingSelection == admittedSelection then pendingSelection = nil end
            end
            spawnPosition = returnActivatorSpawns(game.GetMap())
        end
    end
    activatorCount = 0
    for _, ent in pairs(ents.FindByClass("activatorent")) do
        if usableActivator(ent) then activatorCount = activatorCount + 1 end
    end
    if activatorCount >= maximum and activatorCount > 0 then timer.Stop("activatorSpawner") end
end)

hook.Add("OnNPCKilled", "checkForOurEntities", function(npc, attacker)
    if not eventActive or not activeEnemies[npc] then return end
    activeEnemies[npc] = nil
    totalEnemies = totalEnemies - 1
    -- A temporary zero during Spawn is not the end of this encounter.
    if constructingEnemies == activeEnemies then return end
    if totalEnemies == 0 then finishEvent(not eventInterrupted) return end
    sendEventStatus()

    local message = "An enemy was eliminated. "
    if IsValid(attacker) and attacker:IsPlayer() then
        message = attacker:Nick() .. " has eliminated an enemy. "
    end
    if totalEnemies == 1 then message = message .. "Only 1 enemy remains."
    else message = message .. totalEnemies .. " enemies remain." end
    for _, player in pairs(player.GetAll()) do player:ChatPrint(message) end
end)

-- Cleanup tools/map cleanup can remove NPCs without firing OnNPCKilled.
hook.Add("EntityRemoved", "clearRemovedEventEntities", function(ent)
    if activeEnemies[ent] then
        eventInterrupted = true
        activeEnemies[ent] = nil
        totalEnemies = totalEnemies - 1
        if constructingEnemies ~= activeEnemies then
            if totalEnemies == 0 then finishEvent(false)
            else sendEventStatus() end
        end
    elseif ent:GetClass() == "activatorent" and not eventActive then
        -- EntityRemoved fires before the departing entity becomes invalid.
        refreshSelectedBatch(ent)
        timer.Start("activatorSpawner")
    end
    for ply, interaction in pairs(interactions) do
        if interaction.entity == ent then interactions[ply] = nil end
    end
end)
