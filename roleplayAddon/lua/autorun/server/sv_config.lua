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

-- Return nil for non-table/empty lists, and support sparse spawn-position tables.
local function randomValue(values)
    if type(values) ~= "table" then return nil end
    local choices = {}
    for _, value in pairs(values) do
        choices[#choices + 1] = value
    end
    if #choices == 0 then return nil end
    return choices[math.random(1, #choices)]
end

function determineRandomEvent()
    local event = randomValue(NPCEdits)
    if type(event) ~= "table" then return nil end
    return event.name
end

function returnNPCInformation(NPCName)
    if type(NPCEdits) ~= "table" then return nil end
    for _, event in pairs(NPCEdits) do
        if type(event) == "table" and event.name == NPCName then
            return type(event.information) == "table" and event.information or nil
        end
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

-- The same finite sparse-list contract applies to persistence, editing and spawning.
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
-- Ownership covers pending configured-catalogue capture, not a new edit grant.
local spawnCatalogueRequests = {}
local function currentSpawnCatalogue(sender, request)
    return rawequal(spawnCatalogueRequests[sender], request)
end
local spawnMarkerOperations = {}
util.AddNetworkString("ActivatorSpawnMarker")
-- Snapshot kinds occupy one client slot and share only operation/transport.
ActivatorSnapshotMarker = {}
function ActivatorSnapshotMarker.Claim(sender)
    local operation = {}
    spawnMarkerOperations[sender] = operation
    return operation
end
function ActivatorSnapshotMarker.Current(sender, operation)
    return rawequal(spawnMarkerOperations[sender], operation)
end
function ActivatorSnapshotMarker.Cancel(sender)
    spawnMarkerOperations[sender] = nil
end
function ActivatorSnapshotMarker.Retire(sender, operation)
    if not ActivatorSnapshotMarker.Current(sender, operation) then return false end
    spawnMarkerOperations[sender] = nil
    return true
end
function ActivatorSnapshotMarker.Send(sender, mapName, kind, token, x, y, z, expires)
    net.Start("ActivatorSpawnMarker")
    net.WriteBool(mapName ~= nil)
    if mapName ~= nil then
        net.WriteString(mapName)
        net.WriteString(kind)
        net.WriteString(token)
        net.WriteDouble(x)
        net.WriteDouble(y)
        net.WriteDouble(z)
        net.WriteDouble(expires)
    end
    net.Send(sender)
end
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

-- Validate the requested list without sampling or changing either position kind.
local function validatedSpawnList(mapName, kind, allowMissingMap)
    if type(SpawnPositions) ~= "table" then return nil, nil, "malformed map data" end
    local information
    for key, record in pairs(SpawnPositions) do
        if not listIndex(key) or type(record) ~= "table"
            or type(record.map) ~= "string" or record.map == "" then
            return nil, nil, "malformed map data"
        end
        if record.map == mapName then
            if information then return nil, nil, "ambiguous current-map records" end
            information = record
        end
    end
    if not information then
        if allowMissingMap then return end
        return nil, nil, "missing current-map record"
    end
    local positions = information[spawnKinds[kind].field]
    if positions == nil then return nil, nil, "missing " .. kind .. " list" end
    if not validPositionList(positions) then return nil, nil, "malformed " .. kind .. " list" end
    return information, positions
end

local function editableSpawnList(kind, allowMissingMap)
    return validatedSpawnList(game.GetMap(), kind, allowMissingMap)
end

-- Unavailable or ambiguous input has the same nil contract as an empty list.
function returnSpawnPositions(mapName)
    local _, positions = validatedSpawnList(mapName, "enemy")
    return positions and randomValue(positions)
end

function returnActivatorSpawns(mapName)
    local _, positions = validatedSpawnList(mapName, "activator")
    return positions and randomValue(positions)
end

-- Timed spawning checks availability before its ordinary event-first RNG draws.
function hasActivatorSpawns(mapName)
    local _, positions = validatedSpawnList(mapName, "activator")
    return positions ~= nil and next(positions) ~= nil
end

local function invalidateSpawnInspections(map, kind)
    for admin, request in pairs(spawnCatalogueRequests) do
        if request.map == map and request.kind == kind then spawnCatalogueRequests[admin] = nil end
    end
    for admin, inspection in pairs(spawnInspections) do
        if inspection.map == map and inspection.kind == kind then
            spawnInspections[admin], spawnMarkerOperations[admin] = nil, nil
        end
    end
end

-- Copy scalars once so every row uses the same server-side position snapshot.
local function spawnListOrigin(sender)
    local ok, x, y, z = pcall(function()
        local position = sender:GetPos()
        if not isvector(position) then return end
        local px, py, pz = position.x, position.y, position.z
        if finiteNumber(px) and finiteNumber(py) and finiteNumber(pz) then return px, py, pz end
    end)
    if ok then return x, y, z end
end

local function spawnDistance(px, py, pz, x, y, z)
    if x == nil then return end
    -- Use floating subtraction and a scaled norm, avoiding integer wrap and
    -- intermediate square overflow when the final distance is representable.
    local dx, dy, dz = px * 1.0 - x, py * 1.0 - y, pz * 1.0 - z
    if not finiteNumber(dx) or not finiteNumber(dy) or not finiteNumber(dz) then return end
    local scale = math.max(math.abs(dx), math.abs(dy), math.abs(dz))
    local distance = 0
    if scale > 0 then
        dx, dy, dz = dx / scale, dy / scale, dz / scale
        distance = scale * math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    if finiteNumber(distance) then return distance end
end

local function spawnDistanceText(distance)
    if distance == nil then return "distance unavailable" end
    return "~" .. string.format("%.6g", distance) .. " units away"
end

local function spawnBaseDistance(position, x, y, z)
    if x == nil then return "distance unavailable" end
    return spawnDistanceText(spawnDistance(position.x, position.y, position.z, x, y, z))
end

local function printSpawnList(sender, text, request)
    if not currentSpawnCatalogue(sender, request) then return end
    local function fail(message)
        if currentSpawnCatalogue(sender, request) then sender:ChatPrint(message) end
    end
    spawnInspections[sender], spawnMarkerOperations[sender] = nil, nil
    local kind, argument = text:match("^!listSpawns%s+(%S+)%s*(.-)%s*$")
    if not spawnKinds[kind] then
        fail("Usage: !listSpawns enemy|activator [page].")
        return
    end
    local page = argument == "" and 1 or (argument:match("^%d+$") and tonumber(argument))
    if not page or not listIndex(page) then
        fail("Usage: !listSpawns " .. kind .. " [page]; use a positive integer page.")
        return
    end
    local mapName = game.GetMap()
    if not currentSpawnCatalogue(sender, request) then return end
    request.map, request.kind = mapName, kind
    local information, positions, reason = validatedSpawnList(mapName, kind)
    if not information then
        fail("Cannot inspect spawns: " .. reason .. ".")
        return
    end
    local keys = {}
    for key in pairs(positions) do
        if not spawnNumberToken(key) then
            fail("Cannot inspect spawns: a key cannot be represented exactly.")
            return
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local pages = math.max(1, math.ceil(#keys / 8))
    if page > pages then
        fail("Usage: !listSpawns " .. kind .. " [page]; page must be in 1-" .. pages .. ".")
        return
    end
    local originX, originY, originZ = spawnListOrigin(sender)
    local shown, lines = {}, {}
    for i = (page - 1) * 8 + 1, math.min(page * 8, #keys) do
        local key, position = keys[i], positions[keys[i]]
        local token = spawnNumberToken(key)
        local x, y, z = spawnNumberToken(position.x), spawnNumberToken(position.y), spawnNumberToken(position.z)
        if not token or not x or not y or not z then
            fail("Cannot inspect spawns: a value cannot be represented exactly.")
            return
        end
        local line = "Key " .. token .. ": x=" .. x .. ", y=" .. y .. ", z=" .. z
            .. "; " .. spawnBaseDistance(position, originX, originY, originZ)
        if #line > 255 then
            fail("Cannot inspect spawns: a position exceeds the chat line limit.")
            return
        end
        lines[#lines + 1] = line
        shown[token] = {key = key, x = position.x, y = position.y, z = position.z}
    end
    mapName = game.GetMap()
    if not currentSpawnCatalogue(sender, request) then return end
    spawnInspections[sender] = {map = mapName, kind = kind, information = information,
        positions = positions, shown = shown}
    sender:ChatPrint("Current-map " .. kind .. " spawns, page " .. page .. "/" .. pages
        .. " (" .. #keys .. " positions" .. (#keys == 0 and "; empty list" or "") .. ")."
        .. " Approx. distance from you to stored bases at list time, in 3D Source units.")
    for _, line in ipairs(lines) do sender:ChatPrint(line) end
    sender:ChatPrint("Shown key: " .. spawnKinds[kind].remove .. " <key> to remove; " .. spawnKinds[kind].move
        .. " <key> to move here. Copy the exact key; list again after any edit. Coordinates are not placement checks."
        .. (kind == "enemy" and " Enemy placement adds (30,30,0) cumulatively per valid creation." or ""))
end

-- Separate distance ordering; reuse the ordinary literal-key inspection shape.
local function printNearestSpawns(sender, text, request)
    if not currentSpawnCatalogue(sender, request) then return end
    local function fail(message)
        if currentSpawnCatalogue(sender, request) then sender:ChatPrint(message) end
    end
    spawnInspections[sender], spawnMarkerOperations[sender] = nil, nil
    if not sender:Alive() then
        fail("Cannot inspect nearby spawns: you must be alive. Use !listSpawns for stored-key order.")
        return
    end
    local kind, argument = text:match("^!nearSpawns%s+(%S+)%s*(.-)%s*$")
    if not spawnKinds[kind] then fail("Usage: !nearSpawns enemy|activator [page]."); return end
    local page = argument == "" and 1 or (argument:match("^%d+$") and tonumber(argument))
    if not page or not listIndex(page) then
        fail("Usage: !nearSpawns " .. kind .. " [page]; use a positive integer page.")
        return
    end
    local mapName = game.GetMap()
    if not currentSpawnCatalogue(sender, request) then return end
    request.map, request.kind = mapName, kind
    local information, positions, reason = validatedSpawnList(mapName, kind)
    if not information then fail("Cannot inspect spawns: " .. reason .. "."); return end
    local rows, captured = {}, {}
    for key, position in pairs(positions) do
        local token = spawnNumberToken(key)
        if not token then fail("Cannot inspect spawns: a key cannot be represented exactly."); return end
        local x, y, z = position.x, position.y, position.z
        if not finiteNumber(x) or not finiteNumber(y) or not finiteNumber(z) then
            fail("Cannot inspect spawns: malformed " .. kind .. " list."); return
        end
        local row = {key = key, token = token, x = x, y = y, z = z}
        rows[#rows + 1], captured[key] = row, row
    end
    local pages = math.max(1, math.ceil(#rows / 8))
    if page > pages then
        fail("Usage: !nearSpawns " .. kind .. " [page]; page must be in 1-" .. pages .. ".")
        return
    end
    if not currentSpawnCatalogue(sender, request) then return end
    local originX, originY, originZ = spawnListOrigin(sender)
    if not currentSpawnCatalogue(sender, request) then return end
    if originX == nil then
        fail("Cannot inspect nearby spawns: your position is unavailable. Retry from a valid position or use !listSpawns.")
        return
    end
    for _, row in ipairs(rows) do
        row.distance = spawnDistance(row.x, row.y, row.z, originX, originY, originZ)
    end
    table.sort(rows, function(a, b)
        if a.distance == nil and b.distance ~= nil then return false end
        if b.distance == nil and a.distance ~= nil then return true end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.key < b.key
    end)
    local shown, lines = {}, {}
    for i = (page - 1) * 8 + 1, math.min(page * 8, #rows) do
        local row = rows[i]
        local x, y, z = spawnNumberToken(row.x), spawnNumberToken(row.y), spawnNumberToken(row.z)
        if not x or not y or not z then
            fail("Cannot inspect spawns: a value cannot be represented exactly."); return
        end
        local line = "Key " .. row.token .. ": x=" .. x .. ", y=" .. y .. ", z=" .. z
            .. "; " .. spawnDistanceText(row.distance)
        if #line > 255 then fail("Cannot inspect spawns: a position exceeds the chat line limit."); return end
        lines[#lines + 1] = line
        shown[row.token] = {key = row.key, x = row.x, y = row.y, z = row.z}
    end
    local header = "Nearest current-map " .. kind .. " stored bases, page " .. page .. "/" .. pages
        .. " (" .. #rows .. " positions" .. (#rows == 0 and "; empty list" or "") .. ")."
        .. " Approx. 3D Source units from you; distance unavailable last; each page is a fresh snapshot."
    local footer = "Shown key: " .. spawnKinds[kind].remove .. " <key> to remove; " .. spawnKinds[kind].move
        .. " <key> to move here. Copy the exact key; list again after any edit. Coordinates are not placement checks."
        .. (kind == "enemy" and " Enemy placement adds (30,30,0) cumulatively per valid creation." or "")
    if #header > 255 or #footer > 255 then fail("Cannot inspect spawns: a reply exceeds the chat line limit."); return end
    if not currentSpawnCatalogue(sender, request) then return end
    if not IsValid(sender) or not sender:IsPlayer() or not sender:IsAdmin() or not sender:Alive()
        or game.GetMap() ~= mapName then return end
    if not currentSpawnCatalogue(sender, request) then return end
    local currentInformation, currentPositions = validatedSpawnList(mapName, kind)
    local same = rawequal(information, currentInformation) and rawequal(positions, currentPositions)
    local count = 0
    if same then
        for key, position in pairs(currentPositions) do
            count = count + 1
            local row = captured[key]
            if not row or position.x ~= row.x or position.y ~= row.y or position.z ~= row.z then same = false; break end
        end
    end
    if not currentSpawnCatalogue(sender, request) then return end
    if not same or count ~= #rows then fail("Cannot inspect spawns: configuration changed; list again."); return end
    -- Install once before feedback. Reentrant replies never restore this grant.
    spawnInspections[sender] = {map = mapName, kind = kind, information = information,
        positions = positions, shown = shown}
    sender:ChatPrint(header)
    for _, line in ipairs(lines) do sender:ChatPrint(line) end
    sender:ChatPrint(footer)
end

local function inspectedSpawnTarget(sender, kind, token, mapName)
    local inspection = spawnInspections[sender]
    if not inspection or inspection.kind ~= kind or inspection.map ~= (mapName or game.GetMap())
        or not inspection.shown[token] then return nil end
    local information, positions
    if mapName then information, positions = validatedSpawnList(mapName, kind)
    else information, positions = editableSpawnList(kind) end
    if not rawequal(information, inspection.information) or not rawequal(positions, inspection.positions) then return nil end
    for _, shown in pairs(inspection.shown) do
        local current = positions[shown.key]
        if not current or current.x ~= shown.x or current.y ~= shown.y or current.z ~= shown.z then return nil end
    end
    return positions, inspection.shown[token].key
end

-- A request owns only its current stack operation, never the displayed snapshot.
-- Engine reads can reenter PlayerSay; a newer mark, clear or list wins.
local function sendSpawnMarker(sender, text, clear)
    if sender == nil then return end
    local operation, expected = ActivatorSnapshotMarker.Claim(sender), spawnInspections[sender]
    local function current() return ActivatorSnapshotMarker.Current(sender, operation) end
    local ok, message = pcall(function()
        if not IsValid(sender) or not sender:IsPlayer() then return end
        if not sender:IsAdmin() then return "Only admins can mark spawn snapshots." end
        if clear then
            if text ~= "!clearSpawnMarker" then return "Usage: !clearSpawnMarker." end
            if not current() then return end
            ActivatorSnapshotMarker.Send(sender)
            return "Spawn snapshot marker cleared."
        end
        if not sender:Alive() then return "Spawn snapshot unchanged: you must be alive." end
        local kind, token = text:match("^!markSpawn%s+(%S+)%s+(%S+)%s*$")
        if not spawnKinds[kind] or not token or #token > 64 then
            return "Usage: !markSpawn enemy|activator <key>; copy an exact key from !listSpawns."
        end
        local mapName, now = game.GetMap(), CurTime()
        if type(mapName) ~= "string" or #mapName == 0 or #mapName > 128 or mapName:find("%c")
            or not finiteNumber(now) or not finiteNumber(now + 15) or now + 15 <= now then
            return "Spawn snapshot unchanged: map or time is unavailable."
        end
        if not IsValid(sender) or not sender:IsPlayer() or not sender:IsAdmin() or not sender:Alive()
            or game.GetMap() ~= mapName then return end
        if not current() or not rawequal(spawnInspections[sender], expected) then return end
        if not expected then return "Spawn snapshot unchanged: inspect a current key with !listSpawns and copy it exactly." end
        local positions, key = inspectedSpawnTarget(sender, kind, token, mapName)
        if not positions then
            return "Spawn snapshot unchanged: inspect a current key with !listSpawns " .. kind .. " and copy it exactly."
        end
        local position = positions[key]
        local x, y, z = position.x, position.y, position.z
        if not finiteNumber(x) or not finiteNumber(y) or not finiteNumber(z)
            or not current() or not rawequal(spawnInspections[sender], expected) then return end
        ActivatorSnapshotMarker.Send(sender, mapName, kind, token, x, y, z, now + 15)
        return "15-second " .. kind .. " stored-base snapshot sent; !clearSpawnMarker to clear."
    end)
    -- Never retire a nested request's ownership, or print success before Send.
    if ActivatorSnapshotMarker.Retire(sender, operation) then
        if ok and message then sender:ChatPrint(message) end
    end
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
    spawnInspections[sender], spawnMarkerOperations[sender], spawnCatalogueRequests[sender] = nil, nil, nil
end)

-- The save routine is assigned below before any chat command can run.
local saveSpawnPositions
local canSaveSpawnPositions = false
-- Fixed session history only; inquiry never probes files or configuration.
local spawnLoadDecision = "pending"
local lastSpawnSaveResult = "none completed"
local function confirmSpawnEdit(sender, message)
    if not saveSpawnPositions() then
        message = message .. " This change remains in memory; saving failed, is disabled or could not be verified. Retry: !saveSpawns; check the server console."
    end
    sender:ChatPrint(message)
end

-- Literal help never reads configuration or changes inspection/marker authority.
local activatorHelp = {
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
        "!markNearestActivator - mark the nearest ready actor from a fresh scan; no arguments or active encounter.",
        "!clearSpawnMarker / !clearEventEnemyMarker - clear the same shared snapshot slot.",
        "Marking requires a living admin. Stored-base/enemy marks need an inspected target; nearest-ready marks use a fresh scan. Clearing also works when dead.",
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
        "!refreshActivators - retire ready actors, including manual ones; refused during combat; restart normal delay unless paused. Stop/refresh preserve the queued choice.",
        "!nearActivators [page] - locate existing ready actors, including manual ones; living admin, no active encounter; no action permission.",
        "!spawnActivatorsNow - one ordinary ready-batch attempt now; refused while paused, fighting, spawning or any ready actor exists.",
        "Spawn now keeps player/position/event/capacity checks, may consume the queued choice, and never schedules a retry.",
        "Only !nearActivators accepts an optional page here; other control commands take no arguments. Fresh sessions enable automatic spawning.",
    },
}

-- Function that allows admins to modify spawn positions in game.
hook.Add("PlayerSay", "setUpSpawnPoints", function(sender, text)
    if type(text) ~= "string" then return end
    local name = text:match("^(!%S+)")
    if name == "!spawnSaveStatus" then
        -- Contain native admission/reply errors and keep recognized chat private.
        pcall(function()
            if not IsValid(sender) or not sender:IsPlayer() then return end
            if not sender:IsAdmin() then
                sender:ChatPrint("Only admins can inspect spawn saving status.")
                return
            end
            if text ~= name then
                sender:ChatPrint("Usage: !spawnSaveStatus (cached session and historical save status).")
                return
            end
            -- Copy all fixed labels before ChatPrint can reenter load/save hooks.
            local lines = {
                "Spawn initialization (this session): " .. spawnLoadDecision .. ".",
                "Spawn saving permission (this session): " .. (canSaveSpawnPositions and "enabled" or "disabled") .. ".",
                "Last completed spawn save attempt (historical): " .. lastSpawnSaveResult .. ".",
            }
            for _, line in ipairs(lines) do sender:ChatPrint(line) end
        end)
        return ""
    end
    if name == "!activatorHelp" then
        -- Even rejected input and native reply failures remain requester-private.
        pcall(function()
            if not IsValid(sender) or not sender:IsPlayer() then return end
            if not sender:IsAdmin() then
                sender:ChatPrint("Only admins can use Activator command help.")
                return
            end
            local lines = text == name and activatorHelp[""]
            if not lines and #text <= 22 then
                local topic = text:match("^!activatorHelp ([a-z]+)$")
                lines = topic and activatorHelp[topic]
            end
            if not lines then
                sender:ChatPrint("Usage: !activatorHelp [events|spawns|enemies|markers|control]; use one lowercase topic and single spaces, with no extra arguments.")
                return
            end
            for _, line in ipairs(lines) do sender:ChatPrint(line) end
        end)
        return ""
    end
    -- Encounter commands claim their own capture/operation before any guards.
    if name == "!markNearestActivator" or name == "!nearActivators" or name == "!inspectEventEnemy" or name == "!markEventEnemy" or name == "!clearEventEnemyMarker" or name == "!listEventEnemies" or name == "!nearEventEnemies" then return end
    if name == "!markSpawn" or name == "!clearSpawnMarker" then
        sendSpawnMarker(sender, text, name == "!clearSpawnMarker")
        return ""
    end
    if name == "!listSpawns" or name == "!nearSpawns" then
        if sender == nil then return "" end
        local request = {}
        spawnCatalogueRequests[sender], spawnMarkerOperations[sender] = request, nil
        -- Native admission/position/reply errors must not leak exception text.
        pcall(function()
            if not IsValid(sender) or not sender:IsPlayer() then return end
            if not sender:IsAdmin() then
                if currentSpawnCatalogue(sender, request) then sender:ChatPrint("Only admins can inspect or edit spawn positions.") end
                return
            end
            if name == "!nearSpawns" then printNearestSpawns(sender, text, request)
            else printSpawnList(sender, text, request) end
        end)
        return ""
    end
    if name == "!saveSpawns" then
        if not IsValid(sender) or not sender:IsPlayer() then return "" end
        if not sender:IsAdmin() then
            sender:ChatPrint("Only admins can save spawn positions.")
            return ""
        end
        if text ~= name then
            sender:ChatPrint("Usage: !saveSpawns (save spawn positions for all maps).")
        elseif saveSpawnPositions() then
            sender:ChatPrint("Spawn save verified for all maps.")
        else
            sender:ChatPrint("Spawn saving could not be verified. Check the server console.")
        end
        return ""
    end
    local moving = name == "!moveEnemySpawn" and "enemy" or (name == "!moveActivatorSpawn" and "activator")
    local kind = moving or (name == "!removeEnemySpawn" and "enemy" or (name == "!removeActivatorSpawn" and "activator"))
    local indexed = kind and (moving or text ~= name)
    if indexed then
        if not IsValid(sender) or not sender:IsPlayer() then return "" end
        if not sender:IsAdmin() then
            sender:ChatPrint("Only admins can inspect or edit spawn positions.")
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

    local kind = command[1] == "enemySpawnPositions" and "enemy" or "activator"
    local information, positions, reason = editableSpawnList(kind, true)
    if reason then
        sender:ChatPrint("Spawn unchanged: " .. reason .. ".")
        return
    end
    if command[3] then
        if not information then
            information = {map = game.GetMap(), enemySpawnPositions = {}, activatorSpawnPositions = {}}
            table.insert(SpawnPositions, information)
            positions = information[command[1]]
        end
        local maximum = table.maxn(positions)
        local nextKey = maximum + 1
        if not listIndex(nextKey) or nextKey <= maximum or positions[nextKey] ~= nil then
            sender:ChatPrint("Cannot add a spawn: no exact free key follows the current maximum. Existing positions are unchanged.")
            return ""
        end
        positions[nextKey] = sender:GetPos()
        invalidateSpawnInspections(game.GetMap(), kind)
        confirmSpawnEdit(sender, "New " .. command[2] .. " Spawn Successfully Set at " .. tostring(sender:GetPos()) .. ".")
    else
        local last = positions and table.maxn(positions) or 0
        if last > 0 then
            positions[last] = nil
            invalidateSpawnInspections(game.GetMap(), kind)
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
        lastSpawnSaveResult = "disabled"
        return false
    end
    if not validSpawnPositions(SpawnPositions) then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Invalid current spawn positions; existing data was left untouched.\n")
        lastSpawnSaveResult = "invalid current positions"
        return false
    end
    local encoded, converted = pcall(util.TableToJSON, SpawnPositions)
    if not encoded or type(converted) ~= "string" or converted == "" then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not serialize spawn positions; existing data was left untouched.\n")
        lastSpawnSaveResult = "serialization failure"
        return false
    end
    if not decodeSpawnPositions(converted) then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not validate serialized spawn positions for " .. spawnDataFile .. "; existing data was left untouched.\n")
        lastSpawnSaveResult = "serialized validation failure"
        return false
    end
    -- Byte equality only: differently ordered/formatted JSON is a changed save.
    if converted == lastGoodSpawnBytes and spawnFileMatches(spawnDataFile, lastGoodSpawnBytes) then
        lastSpawnSaveResult = "verified success"
        return true
    end
    if not prepareSpawnBackup() then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not prepare or verify spawn backup " .. spawnBackupFile .. "; " .. spawnDataFile .. " was left untouched.\n")
        lastSpawnSaveResult = "backup verification failure"
        return false
    end
    if not writeVerifiedSpawnFile(spawnDataFile, converted) then
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not save and verify spawn positions in " .. spawnDataFile .. ".\n")
        lastSpawnSaveResult = "canonical verification failure"
        return false
    end
    lastGoodSpawnBytes = converted
    print("DEVONS ROLEPLAY ADDON - The spawn positions table was successfully saved")
    lastSpawnSaveResult = "verified success"
    return true
end

hook.Add("ShutDown", "saveTheTables", function()
    saveSpawnPositions() -- Do not return its status and stop other addons' hooks.
end)

hook.Add("Initialize", "loadTheTables", function()
    spawnInspections, spawnMarkerOperations, spawnCatalogueRequests = {}, {}, {}
    canSaveSpawnPositions = false
    spawnLoadDecision, lastSpawnSaveResult = "pending", "none completed"
    lastGoodSpawnBytes, preparedSpawnBackupBytes = nil, nil
    local read, JSONData, filename = pcall(readSpawnData)
    if not read or (filename and type(JSONData) ~= "string") then
        spawnLoadDecision = "read failure"
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Could not read saved spawn positions. Using configured positions; saving is disabled. Back up and repair the DATA file, then restart.\n")
        return
    end
    if not filename then
        spawnLoadDecision = "no file"
        canSaveSpawnPositions = true
        return
    end
    local positions = decodeSpawnPositions(JSONData)
    if not positions then
        spawnLoadDecision = "invalid file"
        ErrorNoHalt("DEVONS ROLEPLAY ADDON - Invalid spawn positions in " .. filename .. ". Using configured positions; saving is disabled. Back up and repair the DATA file, then restart.\n")
        return
    end
    SpawnPositions = positions
    lastGoodSpawnBytes = JSONData
    spawnLoadDecision = "loaded"
    canSaveSpawnPositions = true
    print("DEVONS ROLEPLAY ADDON - The spawn positions table was successfully loaded")
end)
