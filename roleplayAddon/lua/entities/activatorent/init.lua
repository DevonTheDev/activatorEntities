AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")
if not returnNPCInformation then include("autorun/server/sv_config.lua") end

util.AddNetworkString("OpenInteractionMenu")
util.AddNetworkString("CloseInteractionMenu")
util.AddNetworkString("SendNPCInformation")
util.AddNetworkString("roundFinished")

activatorCount = 0
totalEnemies = 0

local interactions = {}
local activeEnemies = {}
local eventActive = false
local eventInterrupted = false
local interactionLifetime = 60
local interactionDistanceSquared = 200 * 200

local function canInteract(ply, ent)
    return IsValid(ply) and ply:IsPlayer() and ply:Alive()
        and IsValid(ent) and ent:GetClass() == "activatorent"
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
    eventActive = false
    activeEnemies = {}
    totalEnemies = 0
    timer.Start("activatorSpawner")
    if completed then
        net.Start("roundFinished")
        net.Send(player.GetAll())
    end
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

    eventActive = true
    eventInterrupted = false
    timer.Stop("activatorSpawner")
    destroyActivators()
    for i = 1, math.floor(info.maxNPCs) do
        local enemy = ents.Create(info.npcPath)
        if IsValid(enemy) then
            spawnPosition = spawnPosition + Vector(30, 30, 0)
            enemy:SetPos(spawnPosition)
            enemy:SetName("devonsSpawnedEntity")
            enemy:Spawn()
            if IsValid(enemy) then
                enemy:SetHealth(returnEnemyHealth())
                activeEnemies[enemy] = true
                totalEnemies = totalEnemies + 1
            end
        end
    end
    if totalEnemies == 0 then
        finishEvent(false)
        ErrorNoHalt("ERROR - No event enemies could be spawned\n")
        return
    end
    for _, player in pairs(player.GetAll()) do
        player:ChatPrint(totalEnemies .. " enemies have been spawned. Eliminate them.")
    end
end)

-- Spawn only the missing activators, never more than the configured cap.
timer.Create("activatorSpawner", returnDelayBetweenEvents(), 0, function()
    if eventActive or player.GetCount() < returnMinNumberOfPlayers() then return end
    local identifier = determineRandomEvent()
    if identifier ~= "Raid" or not returnNPCInformation(identifier) then return end
    local spawnPosition = returnActivatorSpawns(game.GetMap())
    if not spawnPosition then return end

    activatorCount = #ents.FindByClass("activatorent")
    local maximum = returnMaxActivators() or 1
    for i = activatorCount + 1, maximum do
        local activator = ents.Create("activatorent")
        if IsValid(activator) then
            activator.EventIdentifier = identifier
            activator:SetPos(spawnPosition)
            activator:Spawn()
            spawnPosition = returnActivatorSpawns(game.GetMap())
        end
    end
    activatorCount = #ents.FindByClass("activatorent")
    if activatorCount >= maximum and activatorCount > 0 then timer.Stop("activatorSpawner") end
end)

hook.Add("OnNPCKilled", "checkForOurEntities", function(npc, attacker)
    if not eventActive or not activeEnemies[npc] then return end
    activeEnemies[npc] = nil
    totalEnemies = totalEnemies - 1
    if totalEnemies == 0 then finishEvent(not eventInterrupted) return end

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
        if totalEnemies == 0 then finishEvent(false) end
    elseif ent:GetClass() == "activatorent" and not eventActive then
        timer.Start("activatorSpawner")
    end
    for ply, interaction in pairs(interactions) do
        if interaction.entity == ent then interactions[ply] = nil end
    end
end)
