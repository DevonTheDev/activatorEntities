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

-- The same finite sparse-list contract applies to persistence and inspection.
local function finiteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function listIndex(value)
    return finiteNumber(value) and value >= 1 and value == math.floor(value)
end

local function validPositionList(positions)
    if type(positions) ~= "table" then return false end
    for key, position in pairs(positions) do
        if not listIndex(key) or not isvector(position)
            or not finiteNumber(position.x) or not finiteNumber(position.y) or not finiteNumber(position.z) then
            return false
        end
    end
    return true
end

local spawnInspections = {}
local spawnKinds = {
    enemy = {field = "enemySpawnPositions", remove = "!removeEnemySpawn", move = "!moveEnemySpawn"},
    activator = {field = "activatorSpawnPositions", remove = "!removeActivatorSpawn", move = "!moveActivatorSpawn"},
}

-- Lua 5.3 integer tostring preserves int64 keys; %.17g alone can round them.
-- Lua 5.1/LuaJIT may need the fallback for integral doubles. Verify either form.
local function spawnNumberToken(value)
    local token = tostring(value)
    if tonumber(token) == value then return token end
    local formatted, precise = pcall(string.format, "%.17g", value)
    if formatted and tonumber(precise) == value then return precise end
end

local function inspectedSpawnList(kind)
    if type(SpawnPositions) ~= "table" then return nil, nil, "malformed map data" end
    local currentMap, information = game.GetMap(), nil
    for key, record in pairs(SpawnPositions) do
        if not listIndex(key) or type(record) ~= "table"
            or type(record.map) ~= "string" or record.map == "" then
            return nil, nil, "malformed map data"
        end
        if record.map == currentMap then
            if information then return nil, nil, "ambiguous current-map records" end
            information = record
        end
    end
    if not information then return nil, nil, "missing current-map record" end
    local positions = information[spawnKinds[kind].field]
    if positions == nil then return nil, nil, "missing " .. kind .. " list" end
    if not validPositionList(positions) then return nil, nil, "malformed " .. kind .. " list" end
    return information, positions
end

local function invalidateSpawnInspections(map, kind)
    for admin, inspection in pairs(spawnInspections) do
        if inspection.map == map and inspection.kind == kind then spawnInspections[admin] = nil end
    end
end

local function printSpawnList(sender, text)
    spawnInspections[sender] = nil
    local kind, argument = text:match("^!listSpawns%s+(%S+)%s*(.-)%s*$")
    if not spawnKinds[kind] then
        sender:ChatPrint("Usage: !listSpawns enemy|activator [page].")
        return
    end
    local page = argument == "" and 1 or (argument:match("^%d+$") and tonumber(argument))
    if not page or not listIndex(page) then
        sender:ChatPrint("Usage: !listSpawns " .. kind .. " [page]; use a positive integer page.")
        return
    end
    local information, positions, reason = inspectedSpawnList(kind)
    if not information then
        sender:ChatPrint("Cannot inspect spawns: " .. reason .. ".")
        return
    end
    local keys = {}
    for key in pairs(positions) do
        if not spawnNumberToken(key) then
            sender:ChatPrint("Cannot inspect spawns: a key cannot be represented exactly.")
            return
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local pages = math.max(1, math.ceil(#keys / 8))
    if page > pages then
        sender:ChatPrint("Usage: !listSpawns " .. kind .. " [page]; page must be in 1-" .. pages .. ".")
        return
    end
    local shown, lines = {}, {}
    for i = (page - 1) * 8 + 1, math.min(page * 8, #keys) do
        local key, position = keys[i], positions[keys[i]]
        local token = spawnNumberToken(key)
        local x, y, z = spawnNumberToken(position.x), spawnNumberToken(position.y), spawnNumberToken(position.z)
        if not token or not x or not y or not z then
            sender:ChatPrint("Cannot inspect spawns: a value cannot be represented exactly.")
            return
        end
        local line = "Key " .. token .. ": x=" .. x .. ", y=" .. y .. ", z=" .. z
        if #line > 255 then
            sender:ChatPrint("Cannot inspect spawns: a position exceeds the chat line limit.")
            return
        end
        lines[#lines + 1] = line
        shown[token] = {key = key, x = position.x, y = position.y, z = position.z}
    end
    spawnInspections[sender] = {map = game.GetMap(), kind = kind, information = information,
        positions = positions, shown = shown}
    sender:ChatPrint("Current-map " .. kind .. " spawns, page " .. page .. "/" .. pages
        .. " (" .. #keys .. " positions" .. (#keys == 0 and "; empty list" or "") .. ").")
    for _, line in ipairs(lines) do sender:ChatPrint(line) end
    sender:ChatPrint("Shown key: " .. spawnKinds[kind].remove .. " <key> to remove; " .. spawnKinds[kind].move
        .. " <key> to move here. Copy the exact key; list again after any edit. Coordinates are not placement checks.")
end

local function inspectedSpawnTarget(sender, kind, token)
    local inspection = spawnInspections[sender]
    if not inspection or inspection.kind ~= kind or inspection.map ~= game.GetMap()
        or not inspection.shown[token] then return nil end
    local information, positions = inspectedSpawnList(kind)
    if not rawequal(information, inspection.information) or not rawequal(positions, inspection.positions) then return nil end
    for _, shown in pairs(inspection.shown) do
        local current = positions[shown.key]
        if not current or current.x ~= shown.x or current.y ~= shown.y or current.z ~= shown.z then return nil end
    end
    return positions, inspection.shown[token].key
end

-- Capture once and keep a detached, exact Vector without mutating either source.
local function copySpawnDestination(sender, previous)
    local ok, position = pcall(function()
        local destination = sender:GetPos()
        if not isvector(destination) then return end
        local x, y, z = destination.x, destination.y, destination.z
        if not finiteNumber(x) or not finiteNumber(y) or not finiteNumber(z) then return end
        local copy = Vector(x, y, z)
        if not isvector(copy) or rawequal(copy, destination) or rawequal(copy, previous)
            or copy.x ~= x or copy.y ~= y or copy.z ~= z then return end
        return copy
    end)
    if ok then return position end
end

hook.Add("PlayerDisconnected", "clearSpawnInspection", function(sender)
    spawnInspections[sender] = nil
end)

-- The save routine is assigned below before any chat command can run.
local saveSpawnPositions
local function confirmSpawnEdit(sender, message)
    if not saveSpawnPositions() then
        message = message .. " This change remains in memory; saving failed, is disabled or could not be verified. Check the server console."
    end
    sender:ChatPrint(message)
end

-- Function that allows admins to modify spawn positions in game.
hook.Add("PlayerSay", "setUpSpawnPoints", function(sender, text)
    if type(text) ~= "string" then return end
    local name = text:match("^(!%S+)")
    local moving = name == "!moveEnemySpawn" and "enemy" or (name == "!moveActivatorSpawn" and "activator")
    local kind = moving or (name == "!removeEnemySpawn" and "enemy" or (name == "!removeActivatorSpawn" and "activator"))
    local indexed = kind and (moving or text ~= name)
    if name == "!listSpawns" or indexed then
        if not IsValid(sender) or not sender:IsPlayer() then return "" end
        if not sender:IsAdmin() then
            sender:ChatPrint("Only admins can inspect or edit spawn positions.")
            return ""
        end
        if name == "!listSpawns" then
            printSpawnList(sender, text)
            return ""
        end
        local token = text:match("^!%S+%s+(%S+)%s*$")
        -- Match the literal inspected token, not tonumber(input): an unlisted
        -- decimal can round to another valid key on double-only runtimes.
        if not token then
            sender:ChatPrint("Usage: " .. name .. " <key>; copy an exact key from !listSpawns " .. kind .. ".")
            return ""
        end
        local positions, key = inspectedSpawnTarget(sender, kind, token)
        if not positions then
            sender:ChatPrint("Spawn unchanged: inspect a current key with !listSpawns " .. kind .. " and copy it exactly.")
            return ""
        end
        if moving then
            local position = copySpawnDestination(sender, positions[key])
            if not position then
                sender:ChatPrint("Spawn unchanged: your position could not be copied as a finite Vector. Try again from a valid position.")
                return ""
            end
            positions[key] = position
        else
            positions[key] = nil
        end
        invalidateSpawnInspections(game.GetMap(), kind)
        confirmSpawnEdit(sender, "The " .. kind .. " spawn at key " .. token .. " was successfully " .. (moving and "moved." or "removed."))
        return ""
    end
    if not IsValid(sender) or not sender:IsPlayer() or not sender:IsAdmin() then return end

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
        local maximum = table.maxn(positions)
        local nextKey = maximum + 1
        if not listIndex(nextKey) or nextKey <= maximum or positions[nextKey] ~= nil then
            sender:ChatPrint("Cannot add a spawn: no exact free key follows the current maximum. Existing positions are unchanged.")
            return ""
        end
        positions[nextKey] = sender:GetPos()
        invalidateSpawnInspections(game.GetMap(), command[1] == "enemySpawnPositions" and "enemy" or "activator")
        confirmSpawnEdit(sender, "New " .. command[2] .. " Spawn Successfully Set at " .. tostring(sender:GetPos()) .. ".")
    else
        local positions = information and information[command[1]]
        local last = positions and table.maxn(positions) or 0
        if last > 0 then
            positions[last] = nil
            invalidateSpawnInspections(game.GetMap(), command[1] == "enemySpawnPositions" and "enemy" or "activator")
            confirmSpawnEdit(sender, "The previous " .. command[2] .. " spawn was successfully removed.")
        else
            sender:ChatPrint("There are no more " .. command[2] .. " spawns to remove.")
        end
    end
end)

-- file.Write lowercases DATA paths; use the same name when reading on Linux.
local spawnDataFile = "devonsspawninfo.json"
local legacySpawnDataFile = "DevonsSpawnInfo.json"
local spawnBackupFile = "devonsspawninfo.backup.json"
local canSaveSpawnPositions = false
-- Only acknowledged, immutable bytes may become the next recovery copy.
local lastGoodSpawnBytes, preparedSpawnBackupBytes

-- Validate without rebuilding lists: preserve sparse keys and native Vectors
-- restored by util.JSONToTable from GMod's existing "[x y z]" representation.
local function validSpawnPositions(positions)
    if type(positions) ~= "table" then return false end
    for key, information in pairs(positions) do
        if not listIndex(key) or type(information) ~= "table"
            or type(information.map) ~= "string" or information.map == ""
            or not validPositionList(information.enemySpawnPositions)
            or not validPositionList(information.activatorSpawnPositions) then
            return false
        end
    end
    return true
end

-- Keep the loader and serialized-candidate checks on the same JSON defaults.
local function decodeSpawnPositions(bytes)
    local decoded, positions = pcall(util.JSONToTable, bytes)
    if decoded and validSpawnPositions(positions) then return positions end
end

local function spawnFileMatches(filename, bytes)
    local read, contents = pcall(file.Read, filename, "DATA")
    return read and contents == bytes
end

local function writeVerifiedSpawnFile(filename, bytes)
    local written, success = pcall(file.Write, filename, bytes)
    return written and success == true and spawnFileMatches(filename, bytes)
end

local function prepareSpawnBackup()
    if not lastGoodSpawnBytes then return true end
    if spawnFileMatches(spawnBackupFile, lastGoodSpawnBytes) then
        preparedSpawnBackupBytes = lastGoodSpawnBytes
        return true
    end
    -- A failed canonical write may leave this as the sole recovery copy.
    -- An unreadable or changed prepared copy is not permission to overwrite it.
    if preparedSpawnBackupBytes == lastGoodSpawnBytes then return false end
    if not writeVerifiedSpawnFile(spawnBackupFile, lastGoodSpawnBytes) then return false end
    preparedSpawnBackupBytes = lastGoodSpawnBytes
    return true
end

local function readSpawnData()
    local filename = spawnDataFile
    if not file.Exists(filename, "DATA") then
        filename = legacySpawnDataFile
        if not file.Exists(filename, "DATA") then return nil, nil end
    end
    return file.Read(filename, "DATA"), filename
end

-- Only save after initialization has established that existing data is safe.
saveSpawnPositions = function()
    if not canSaveSpawnPositions then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Spawn saving is disabled; existing data was left untouched.\n")
        return false
    end
    if not validSpawnPositions(SpawnPositions) then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Invalid current spawn positions; existing data was left untouched.\n")
        return false
    end
    local encoded, converted = pcall(util.TableToJSON, SpawnPositions)
    if not encoded or type(converted) ~= "string" or converted == "" then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not serialize spawn positions; existing data was left untouched.\n")
        return false
    end
    if not decodeSpawnPositions(converted) then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not validate serialized spawn positions for " .. spawnDataFile .. "; existing data was left untouched.\n")
        return false
    end
    -- Byte equality only: differently ordered/formatted JSON is a changed save.
    if converted == lastGoodSpawnBytes and spawnFileMatches(spawnDataFile, lastGoodSpawnBytes) then return true end
    if not prepareSpawnBackup() then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not prepare or verify spawn backup " .. spawnBackupFile .. "; " .. spawnDataFile .. " was left untouched.\n")
        return false
    end
    if not writeVerifiedSpawnFile(spawnDataFile, converted) then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not save and verify spawn positions in " .. spawnDataFile .. ".\n")
        return false
    end
    lastGoodSpawnBytes = converted
    print("DEVONS ROLEPLAY ADDON - The spawn positions table was successfully saved")
    return true
end

hook.Add("ShutDown", "saveTheTables", function()
    saveSpawnPositions() -- Do not return its status and stop other addons' hooks.
end)

hook.Add("Initialize", "loadTheTables", function()
    spawnInspections = {}
    canSaveSpawnPositions = false
    lastGoodSpawnBytes, preparedSpawnBackupBytes = nil, nil
    local read, JSONData, filename = pcall(readSpawnData)
    if not read or (filename and type(JSONData) ~= "string") then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not read saved spawn positions. Using configured positions; saving is disabled. Back up and repair the DATA file, then restart.\n")
        return
    end
    if not filename then
        canSaveSpawnPositions = true
        return
    end
    local positions = decodeSpawnPositions(JSONData)
    if not positions then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Invalid spawn positions in " .. filename .. ". Using configured positions; saving is disabled. Back up and repair the DATA file, then restart.\n")
        return
    end
    SpawnPositions = positions
    lastGoodSpawnBytes = JSONData
    canSaveSpawnPositions = true
    print("DEVONS ROLEPLAY ADDON - The spawn positions table was successfully loaded")
end)
