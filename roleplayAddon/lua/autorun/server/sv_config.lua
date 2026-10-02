--[[

────────────────────────────────────────────────────────────────────────────────────
─████████████───██████████████─██████──██████─██████████████─██████──────────██████─
─██░░░░░░░░████─██░░░░░░░░░░██─██░░██──██░░██─██░░░░░░░░░░██─██░░██████████──██░░██─
─██░░████░░░░██─██░░██████████─██░░██──██░░██─██░░██████░░██─██░░░░░░░░░░██──██░░██─
─██░░██──██░░██─██░░██─────────██░░██──██░░██─██░░██──██░░██─██░░██████░░██──██░░██─
─██░░██──██░░██─██░░██████████─██░░██──██░░██─██░░██──██░░██─██░░██──██░░██──██░░██─
─██░░██──██░░██─██░░░░░░░░░░██─██░░██──██░░██─██░░██──██░░██─██░░██──██░░██──██░░██─
─██░░██──██░░██─██░░██████████─██░░██──██░░██─██░░██──██░░██─██░░██──██░░██──██░░██─
─██░░██──██░░██─██░░██─────────██░░░░██░░░░██─██░░██──██░░██─██░░██──██░░██████░░██─
─██░░████░░░░██─██░░██████████─████░░░░░░████─██░░██████░░██─██░░██──██░░░░░░░░░░██─
─██░░░░░░░░████─██░░░░░░░░░░██───████░░████───██░░░░░░░░░░██─██░░██──██████████░░██─
─████████████───██████████████─────██████─────██████████████─██████──────────██████─
────────────────────────────────────────────────────────────────────────────────────

--]]

AddCSLuaFile("entities/activatorent/cl_init.lua")

--[[

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
───────────────────────────────██████████████─██████████████─██████████████─████████████████───██████████████───────────────────────────────
───────────────────────────────██░░░░░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░░░██───██░░░░░░░░░░██───────────────────────────────
───────────────────────────────██░░██████████─██████░░██████─██░░██████░░██─██░░████████░░██───██████░░██████───────────────────────────────
───────────────────────────────██░░██─────────────██░░██─────██░░██──██░░██─██░░██────██░░██───────██░░██───────────────────────────────────
─██████████████─██████████████─██░░██████████─────██░░██─────██░░██████░░██─██░░████████░░██───────██░░██─────██████████████─██████████████─
─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─────██░░██─────██░░░░░░░░░░██─██░░░░░░░░░░░░██───────██░░██─────██░░░░░░░░░░██─██░░░░░░░░░░██─
─██████████████─██████████████─██████████░░██─────██░░██─────██░░██████░░██─██░░██████░░████───────██░░██─────██████████████─██████████████─
───────────────────────────────────────██░░██─────██░░██─────██░░██──██░░██─██░░██──██░░██─────────██░░██───────────────────────────────────
───────────────────────────────██████████░░██─────██░░██─────██░░██──██░░██─██░░██──██░░██████─────██░░██───────────────────────────────────
───────────────────────────────██░░░░░░░░░░██─────██░░██─────██░░██──██░░██─██░░██──██░░░░░░██─────██░░██───────────────────────────────────
───────────────────────────────██████████████─────██████─────██████──██████─██████──██████████─────██████───────────────────────────────────
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
You can start editing values here. Make sure to follow the templates provided to ensure that the addon works.

--]]

delayBetweenEvents = 10 -- This value is in seconds, and determines how long there should be between two event entitites being spawned
multipleEntities = true -- This determines if there can be multiple activator entities on the map at the same time (NOTE: Once an event is activated, all entities on the map will despawn)
maxActivators = 3 -- This is the maximum number of activator entities that can exist on the map (NOTE: Changing this value will do nothing if multipleEntities is set to false)
minNumberOfPlayers = 0 -- This is the minimum number of players needed on the server for activators to be spawned
npcRoam = true -- This value determines if the activator entities will be able to move when they are spawned
enemyHealth = 100 -- The amount of health each spawned NPC will have

--[[
Below you are able to set spawn positions, but please note you are able to do this in-game to avoid working with the code directly
--]]


SpawnPositions = { -- The positions in here are where you want the enemies to spawn
    {
        map = "gm_construct", -- Set this to a valid map name
        enemySpawnPositions = 
        {
            [1] = Vector(746.589233, -32.137600, -79.968750), -- You can use getPos in your console to get the position, but make sure to add commas between each number
            [2] = Vector(175.183151, -1167.408447, -79.968750),
            [3] = Vector(-1825.940063, 949.154358, -83.910980),
        },
        activatorSpawnPositions = {
            [1] = Vector(1408.292847, 363.668182, 128.031250), -- You can use getPos in your console to get the position, but make sure to add commas between each number
            [2] = Vector(1462.423706, 677.650208, 128.031250),
            [3] = Vector(1724.513672, 1090.982666, 128.031250),
        },
    },
}

NPCEdits = {
    {
        name = "Raid", -- The identifier for the type of activity
        information = 
        {
            activatorModel = "models/alyx.mdl", -- The model of the activator NPC
            npcPath = "npc_stalker", -- The model for the enemies
            maxNPCs = 5, -- This number is how many NPCs will spawn when the event is activated
            dialogue = "Ahh, an imperial scumbag. Just wait until reinforcements arrive...", -- This is the dialogue that is shown to the player when they interact with the NPC
        }
    },

}

--[[

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
───────────────────────────────██████████████─██████──────────██████─████████████─────────────────────────────────
───────────────────────────────██░░░░░░░░░░██─██░░██████████──██░░██─██░░░░░░░░████───────────────────────────────
───────────────────────────────██░░██████████─██░░░░░░░░░░██──██░░██─██░░████░░░░██───────────────────────────────
───────────────────────────────██░░██─────────██░░██████░░██──██░░██─██░░██──██░░██───────────────────────────────
─██████████████─██████████████─██░░██████████─██░░██──██░░██──██░░██─██░░██──██░░██─██████████████─██████████████─
─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░██──██░░██──██░░██─██░░██──██░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─
─██████████████─██████████████─██░░██████████─██░░██──██░░██──██░░██─██░░██──██░░██─██████████████─██████████████─
───────────────────────────────██░░██─────────██░░██──██░░██████░░██─██░░██──██░░██───────────────────────────────
───────────────────────────────██░░██████████─██░░██──██░░░░░░░░░░██─██░░████░░░░██───────────────────────────────
───────────────────────────────██░░░░░░░░░░██─██░░██──██████████░░██─██░░░░░░░░████───────────────────────────────
───────────────────────────────██████████████─██████──────────██████─████████████─────────────────────────────────
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
You can stop editing values here.

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
───────────────────────────────██████──────────██████─██████████████─████████████████───██████──────────██████─██████████─██████──────────██████─██████████████───────────────────────────────
───────────────────────────────██░░██──────────██░░██─██░░░░░░░░░░██─██░░░░░░░░░░░░██───██░░██████████──██░░██─██░░░░░░██─██░░██████████──██░░██─██░░░░░░░░░░██───────────────────────────────
───────────────────────────────██░░██──────────██░░██─██░░██████░░██─██░░████████░░██───██░░░░░░░░░░██──██░░██─████░░████─██░░░░░░░░░░██──██░░██─██░░██████████───────────────────────────────
───────────────────────────────██░░██──────────██░░██─██░░██──██░░██─██░░██────██░░██───██░░██████░░██──██░░██───██░░██───██░░██████░░██──██░░██─██░░██───────────────────────────────────────
─██████████████─██████████████─██░░██──██████──██░░██─██░░██████░░██─██░░████████░░██───██░░██──██░░██──██░░██───██░░██───██░░██──██░░██──██░░██─██░░██─────────██████████████─██████████████─
─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░██──██░░██──██░░██─██░░░░░░░░░░██─██░░░░░░░░░░░░██───██░░██──██░░██──██░░██───██░░██───██░░██──██░░██──██░░██─██░░██──██████─██░░░░░░░░░░██─██░░░░░░░░░░██─
─██████████████─██████████████─██░░██──██░░██──██░░██─██░░██████░░██─██░░██████░░████───██░░██──██░░██──██░░██───██░░██───██░░██──██░░██──██░░██─██░░██──██░░██─██████████████─██████████████─
───────────────────────────────██░░██████░░██████░░██─██░░██──██░░██─██░░██──██░░██─────██░░██──██░░██████░░██───██░░██───██░░██──██░░██████░░██─██░░██──██░░██───────────────────────────────
───────────────────────────────██░░░░░░░░░░░░░░░░░░██─██░░██──██░░██─██░░██──██░░██████─██░░██──██░░░░░░░░░░██─████░░████─██░░██──██░░░░░░░░░░██─██░░██████░░██───────────────────────────────
───────────────────────────────██░░██████░░██████░░██─██░░██──██░░██─██░░██──██░░░░░░██─██░░██──██████████░░██─██░░░░░░██─██░░██──██████████░░██─██░░░░░░░░░░██───────────────────────────────
───────────────────────────────██████──██████──██████─██████──██████─██████──██████████─██████──────────██████─██████████─██████──────────██████─██████████████───────────────────────────────
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
Below are all the functions needed to run the code. It is suggested that you do not edit these in any way, as this may break the addon.

--]]

-- Return nil for missing/empty lists, and support sparse spawn-position tables.
local function randomValue(values)
    local choices = {}
    for _, value in pairs(values or {}) do
        choices[#choices + 1] = value
    end
    if #choices == 0 then return nil end
    return choices[math.random(1, #choices)]
end

local function mapInformation(mapName)
    for _, information in pairs(SpawnPositions) do
        if information.map == mapName then return information end
    end
end

-- Returns one configured enemy/activator position for this map.
function returnSpawnPositions(mapName)
    local information = mapInformation(mapName)
    return information and randomValue(information.enemySpawnPositions)
end

function returnActivatorSpawns(mapName)
    local information = mapInformation(mapName)
    return information and randomValue(information.activatorSpawnPositions)
end

function determineRandomEvent()
    local event = randomValue(NPCEdits)
    return event and event.name
end

function returnNPCInformation(NPCName)
    for _, event in pairs(NPCEdits or {}) do
        if event.name == NPCName then return event.information end
    end
end

-- Returns the delayBetweenEvents variable
function returnDelayBetweenEvents()
    return delayBetweenEvents
end

-- Returns the multipleEntities variable
function returnMultipleEntities()
    return multipleEntities
end

-- Returns the maxActivators variable
function returnMaxActivators()
    if(multipleEntities == true) then
        return maxActivators
    end
end

-- Returns the minNumberOfPlayers variable
function returnMinNumberOfPlayers()
    return minNumberOfPlayers
end

-- Returns the npcRoam boolean
function returnNPCRoam()
    return npcRoam
end

function returnEnemyHealth()
    return enemyHealth
end

util.AddNetworkString("entitiesDeleted")

-- Function that allows admins to modify spawn positions in game.
hook.Add("PlayerSay", "setUpSpawnPoints", function(sender, text)
    if not sender:IsAdmin() then return end

    if text == "!stopEvent" then
        if stopActivatorEvent and stopActivatorEvent() then
            net.Start("entitiesDeleted")
            net.Send(player.GetAll())
        else
            sender:ChatPrint("There is no event running")
        end
        return
    end

    local commands = {
        ["!setActivatorSpawn"] = {"activatorSpawnPositions", "Activator", true},
        ["!setEnemySpawn"] = {"enemySpawnPositions", "Enemy", true},
        ["!removeActivatorSpawn"] = {"activatorSpawnPositions", "activator", false},
        ["!removeEnemySpawn"] = {"enemySpawnPositions", "enemy", false},
    }
    local command = commands[text]
    if not command then return end

    local information = mapInformation(game.GetMap())
    if command[3] then
        if not information then
            information = {map = game.GetMap(), enemySpawnPositions = {}, activatorSpawnPositions = {}}
            table.insert(SpawnPositions, information)
        end
        local positions = information[command[1]]
        positions[table.maxn(positions) + 1] = sender:GetPos()
        sender:ChatPrint("New " .. command[2] .. " Spawn Successfully Set at " .. tostring(sender:GetPos()) .. ".")
    else
        local positions = information and information[command[1]]
        local last = positions and table.maxn(positions) or 0
        if last > 0 then
            positions[last] = nil
            sender:ChatPrint("The previous " .. command[2] .. " spawn was successfully removed.")
        else
            sender:ChatPrint("There are no more " .. command[2] .. " spawns to remove.")
        end
    end
end)

-- Saves the table of info when the lua environment closes
hook.Add("ShutDown", "saveTheTables", function()

    converted = util.TableToJSON(SpawnPositions) -- Converts the spawnpositions table into a JSON file
    file.Write("DevonsSpawnInfo.json", converted) -- Writes the file
    print("DEVONS ROLEPLAY ADDON - The spawn positions table was successfully saved")

end)

-- Loads the file when the gamemode initializes
hook.Add("Initialize", "loadTheTables", function()

    if(file.Read("DevonsSpawnInfo.json", "DATA") != nil) then -- Checks to see if the file exists before attempting to read it
        local JSONData = file.Read("DevonsSpawnInfo.json", "DATA") -- Reads the JSON file
        SpawnPositions = util.JSONToTable(JSONData)  -- Sets the spawn positons table = to the data inside the file
        print("DEVONS ROLEPLAY ADDON - The spawn positions table was successfully loaded")
    end

end)