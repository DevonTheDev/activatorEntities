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
-- Session-only control; timer stops for encounters/capacity are independent.
local automaticSpawnsPaused = false
local spawnScheduleGeneration = 0
-- Ordinary timer reentry remains allowed; only immediate requests refuse overlap.
local spawnAttemptDepth = 0
local eventInterrupted = false
local activeEventName
local initialEnemies = 0
local statusRequestAfter = {}
local enemyInspections = {}
local enemyHealthRequests = {}
local enemyRemovalRequests = {}
local enemyMarkerCaptures = {}
local enemyMarkerGrants = {}
local catalogInspections = {}
local catalogRequests = {}
local detailRequests = {}
local catalogGeneration = 0
local catalogMaxGeneration = 9007199254740991
local catalogLifetime = 60
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
    adminLine(ply, "Usage: !nextEvent <exact configured name> (case-sensitive). !clearNextEvent clears the pending choice. !listEvents [page] shows the full catalog.")
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

-- Fold only ASCII letters; preserve original bytes for exact reference admission.
local function foldCatalogName(name)
    return (name:gsub("[A-Z]", function(character)
        return string.char(character:byte() + 32)
    end))
end

local function catalogSearchQuery(text)
    if #text > 147 then return end
    local page, query = text:match("^!findEvents ([0-9]+) (.+)$")
    if not page or #page > 6 or tonumber(page) < 1 or #query > 128
        or query:sub(1, 1) == " " or query:sub(-1) == " "
        or query:find("[%z\1-\31\127]") or query:find("\194[\128-\159]")
        or query:find("\226\128[\168\169]") then return end
    return tonumber(page), foldCatalogName(query)
end

-- Copy text and exact configuration identities before sending private replies.
-- Continuation parts share a token; only entries on the shown page are granted.
local function catalogLines(pool, generation, query)
    local lines, names, groups, targets = {}, {}, {}, {}
    local nonTables, missingNames, nonStringNames = 0, 0, 0
    local noMatch = "No configured names match this literal search."
    if pool == nil then return query and {noMatch, "No configured encounters (missing pool)."}
        or {"No configured encounters (missing pool)."}, 0, targets end
    if type(pool) ~= "table" then return query and {noMatch, "Malformed encounter pool: expected table."}
        or {"Malformed encounter pool: expected table."}, 0, targets end
    for key, event in pairs(pool) do
        if type(event) ~= "table" then nonTables = nonTables + 1
        elseif event.name == nil then missingNames = missingNames + 1
        elseif type(event.name) ~= "string" then nonStringNames = nonStringNames + 1
        else
            local name = event.name
            if not groups[name] then
                names[#names + 1] = name
                groups[name] = {count = 0, missing = 0, nonTable = 0,
                    key = key, record = event, information = event.information}
            end
            local group = groups[name]
            group.count = group.count + 1
            if event.information == nil then group.missing = group.missing + 1
            elseif type(event.information) ~= "table" then group.nonTable = group.nonTable + 1 end
        end
    end
    table.sort(names)
    -- Eligibility groups always cover the complete pool. Filter original names,
    -- then preserve their global IDs and exact record/key identities.
    local shown = {}
    for id, name in ipairs(names) do
        if not query or foldCatalogName(name):find(query, 1, true) then shown[#shown + 1] = id end
    end
    for _, id in ipairs(shown) do
        local name = names[id]
        local group, reasons = groups[name], {}
        if name == "" then reasons[#reasons + 1] = "empty name" end
        if group.count > 1 then reasons[#reasons + 1] = "duplicate name (" .. group.count .. ")" end
        if group.missing > 0 then reasons[#reasons + 1] = "missing information: " .. group.missing end
        if group.nonTable > 0 then reasons[#reasons + 1] = "non-table information: " .. group.nonTable end
        local status = #reasons == 0 and "eligible" or ("unavailable: " .. table.concat(reasons, "; "))
        local escaped = name:find("[%c]") ~= nil
        local display = escaped and name:gsub("[%c\\]", function(char)
            return string.format("\\x%02X", char:byte())
        end) or name
        local token = #reasons == 0 and ("r" .. generation .. "-" .. id) or nil
        local reference = token and (" ref " .. token) or ""
        local suffix = reference .. " [" .. status .. "; " .. (escaped and "escaped diagnostic" or "literal") .. ']: "'
        -- Reserving the display length's digit count covers both part numbers,
        -- since no chunk can contain fewer than one byte. Never shorten a name.
        local digits = #tostring(math.max(#display, 1))
        local limit = 240 - #("Entry " .. id .. " part /" .. suffix .. '"') - 2 * digits
        local chunks, first = {}, 1
        repeat
            local last = math.min(first + limit - 1, #display)
            while last >= first and display:byte(last + 1) and display:byte(last + 1) >= 128
                and display:byte(last + 1) <= 191 do last = last - 1 end
            -- Malformed byte strings have no complete UTF-8 boundary here.
            -- Still make progress; native arbitrary-string input is unverified.
            if last < first and #display > 0 then last = first end
            chunks[#chunks + 1] = display:sub(first, last)
            first = last + 1
        until first > #display
        for part, chunk in ipairs(chunks) do
            lines[#lines + 1] = "Entry " .. id .. " part " .. part .. "/" .. #chunks .. suffix .. chunk .. '"'
            if token then targets[#lines] = {token = token, name = name,
                key = group.key, record = group.record, information = group.information} end
        end
    end
    if query and #shown == 0 then lines[1] = noMatch end
    if nonTables + missingNames + nonStringNames > 0 then
        lines[#lines + 1] = (query and "Unfiltered pool diagnostics: " or "")
            .. "Non-table records: " .. nonTables .. "; missing names: " .. missingNames
            .. "; non-string names: " .. nonStringNames .. "."
    end
    if #lines == 0 then lines[1] = "No configured encounters (empty pool)." end
    return lines, #shown, targets
end

local function catalogAdmin(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:IsAdmin() and IsValid(ply)
end

local function catalogTime(now)
    return type(now) == "number" and now == now and now >= 0 and now < math.huge
end

local function catalogContext()
    -- Native engine observations form the synchronous commit boundary. Read the
    -- clock first, then the map; neither normally invokes addon callbacks.
    local ok, map, now = pcall(function()
        local now = CurTime()
        return game.GetMap(), now
    end)
    if not ok or type(map) ~= "string" or map == "" or not catalogTime(now) then return end
    return map, now
end

local function catalogAdmission(ply)
    -- Configuration callbacks have finished. Do not invoke another permission
    -- getter after capturing the final native map/time observations.
    if not catalogAdmin(ply) then return end
    return catalogContext()
end

local function printEventCatalog(ply, text, request, search)
    local page, query
    if search then
        page, query = catalogSearchQuery(text)
        if not page then
            if catalogAdmin(ply) and rawequal(catalogRequests[ply], request) then
                adminLine(ply, "Usage: !findEvents <page> <text>; positive page: 1-6 digits; text: 1-128 bytes, no edge spaces or controls; command: at most 147 bytes.")
            end
            return
        end
    end
    local retry = search and "!findEvents <page> <text>" or "!listEvents"
    -- Refuse counter exhaustion rather than reuse a generation or touch RNG.
    if catalogGeneration >= catalogMaxGeneration then
        if catalogAdmin(ply) and rawequal(catalogRequests[ply], request) then
            adminLine(ply, "Catalog references exhausted for this server session; the last successful page is unchanged.")
        end
        return
    end
    local generation = catalogGeneration + 1
    catalogGeneration = generation
    local pool = NPCEdits
    -- Fixed token width keeps continuation boundaries stable across generations.
    local ok, lines, names, targets = pcall(catalogLines, pool, string.format("%016.0f", generation), query)
    if not ok then
        if catalogAdmin(ply) and rawequal(catalogRequests[ply], request) then
            adminLine(ply, "Catalog unavailable: configuration could not be inspected. Retry " .. retry .. ".")
        end
        return
    end
    local pages = math.max(1, math.ceil(#lines / 8))
    if not search then
        local argument = text:match("^!listEvents%s*(.-)%s*$")
        page = argument == "" and 1 or (argument:match("^%d+$") and tonumber(argument))
    end
    if not page or page < 1 or page > pages then
        if catalogAdmin(ply) and rawequal(catalogRequests[ply], request) then
            adminLine(ply, search and ("Usage: !findEvents <page> <text>; page must be in 1-" .. pages .. ".")
                or ("Usage: !listEvents [page]; page must be a positive integer in 1-" .. pages .. "."))
        end
        return
    end
    local map, issued = catalogAdmission(ply)
    local expires = issued and issued + catalogLifetime
    -- Engine/player getters can reenter. A newer request or disconnect wins.
    if not rawequal(catalogRequests[ply], request) then return end
    if not map or not expires or not catalogTime(expires) or expires <= issued then
        if IsValid(ply) and ply:IsPlayer() then
            adminLine(ply, "Catalog unavailable: server map/time could not be checked. Retry " .. retry .. ".")
        end
        return
    end
    local inspection = {pool = pool, map = map, issued = issued, expires = expires, targets = {}}
    local replies = {(search and "Configured encounter search, page " or "Configured encounters, page ")
        .. page .. "/" .. pages .. " (" .. names .. (search and " matching names" or " names")
        .. "). !nextEvent eligibility only; engine unchecked."}
    for i = (page - 1) * 8 + 1, math.min(page * 8, #lines) do
        replies[#replies + 1] = lines[i]
        local target = targets[i]
        if target then inspection.targets[target.token] = target end
    end
    replies[#replies + 1] = search and ("!findEvents <page> <text> (1-" .. pages
        .. "); new list/search pages replace refs. !nextEventRef <ref>: shown refs last 60s; one selection per page. Escaped text is diagnostic.")
        or ("!nextEventRef <ref>: shown refs last 60s; one selection per page. !listEvents [page] (1-"
            .. pages .. ") replaces refs. !nextEvent <exact name> still works; escaped text is diagnostic.")
    -- Install before ChatPrint. Never restore this page after nested callbacks.
    catalogInspections[ply] = inspection
    for _, reply in ipairs(replies) do
        if not catalogAdmin(ply) or not rawequal(catalogRequests[ply], request)
            or not rawequal(catalogInspections[ply], inspection) then return end
        ply:ChatPrint(reply)
    end
end

-- Both commands use the same live eligibility/identity admission. Inspection
-- may copy its fields inside the protected lookup phase, before final checks.
local function catalogReferenceTarget(ply, token, inspection, readSnapshot)
    local target = inspection and inspection.targets[token]
    local pool = inspection and inspection.pool
    -- Preserve ordinary configured property lookup, including inherited fields.
    -- Copy shallow raw membership/fields first so callbacks cannot add a duplicate
    -- or replace/rename a record after the eligibility scan and still commit.
    local records = {}
    if type(pool) == "table" then
        for key, record in next, pool do
            local captured = {record = record}
            if type(record) == "table" then
                captured.name = rawget(record, "name")
                captured.information = rawget(record, "information")
            end
            records[key] = captured
        end
    end
    local ok, eligible, snapshot = pcall(function()
        local eligible = target and target.record.name == target.name
            and rawequal(target.record.information, target.information)
            and rawequal(selectableEvent(target.name), target.information)
        return eligible, eligible and readSnapshot and readSnapshot(target)
    end)
    local map, now = catalogAdmission(ply)
    -- Final ownership and raw identity checks happen after all callbacks.
    local accepted = ok and eligible and target and map and now
        and rawequal(catalogInspections[ply], inspection)
        and map == inspection.map and now >= inspection.issued and now < inspection.expires
        and rawequal(NPCEdits, pool) and type(pool) == "table"
        and rawequal(rawget(pool, target.key), target.record)
        and type(target.information) == "table"
    if accepted then
        for key, record in next, pool do
            local captured = records[key]
            if not captured or not rawequal(captured.record, record)
                or (type(record) == "table" and (not rawequal(captured.name, rawget(record, "name"))
                    or not rawequal(captured.information, rawget(record, "information")))) then
                accepted = false
                break
            end
        end
        for key in next, records do
            if rawget(pool, key) == nil then accepted = false break end
        end
    end
    return accepted and target or nil, snapshot
end

local function selectEventReference(ply, text, inspection)
    local token = text:match("^!nextEventRef%s+(%S+)%s*$")
    if not token then
        adminLine(ply, "Usage: !nextEventRef <ref> from your latest catalog page (one reference, valid for 60 seconds).")
        return
    end
    local target = catalogReferenceTarget(ply, token, inspection)
    if not target then
        if IsValid(ply) and ply:IsPlayer() then
            adminLine(ply, "Next event unchanged: reference unavailable. Use !listEvents and copy one eligible ref from your latest page within 60 seconds.")
        end
        return
    end
    -- Consume before feedback can reenter; the ordinary pending-name path stays live.
    catalogInspections[ply] = nil
    pendingSelection = {name = target.name}
    detailRequests = {}
    adminLine(ply, 'Queued for the next fresh automatic batch: "' .. target.name, '".')
end

-- Only scalar diagnostics reach chat. Keep complete UTF-8 characters and reserve
-- explicit shortening/escaping notes rather than implying a complete path/name.
local function detailLabel(prefix, value)
    if value == nil then return prefix .. "missing" end
    if type(value) ~= "string" then return prefix .. "invalid " .. type(value) .. " (expected nonempty string)" end
    if value == "" then return prefix .. "invalid empty string" end
    local escaped = value:find("[%c]") ~= nil
    local display = escaped and value:gsub("[%c\\]", function(char)
        return string.format("\\x%02X", char:byte())
    end) or value
    local suffix = '"' .. (escaped and " [escaped diagnostic]" or "")
    prefix = prefix .. '"'
    if #prefix + #display + #suffix > 255 then
        suffix = suffix .. " [truncated]"
        local last = 255 - #prefix - #suffix
        while last > 0 and display:byte(last + 1) >= 128 and display:byte(last + 1) <= 191 do last = last - 1 end
        display = display:sub(1, last)
    end
    return prefix .. display .. suffix
end

-- Retain int64 spelling where available; fractional doubles may need 17
-- significant digits to avoid displaying a different requested/floored count.
local function detailNumber(value)
    local text = tostring(value)
    if tonumber(text) == value then return text end
    return string.format("%.17g", value)
end

local function detailSnapshot(target)
    -- Preserve ordinary inherited config properties, but never sample health,
    -- call engine/model validators, or serialize arbitrary configuration values.
    local info = target.information
    local model, class, count = info.activatorModel, info.npcPath, info.maxNPCs
    local countText = "missing; expected finite number >= 1"
    if count ~= nil then
        if type(count) == "number" and count == count and count >= 1 and count < math.huge then
            countText = detailNumber(count) .. "; finite >= 1; floor = " .. detailNumber(math.floor(count)) .. " creation attempts"
        else countText = "invalid " .. type(count) .. "; expected finite number >= 1" end
    end
    return {detailLabel("Configuration snapshot: ", target.name),
        detailLabel("activatorModel: ", model), detailLabel("npcPath (enemy class): ", class),
        "maxNPCs (requested count): " .. countText,
        "Configured base values only; engine unchecked. Data unchanged; reference not consumed or renewed. !nextEventRef <ref> can still select it."}
end

local function printEventInspection(ply, text, inspection, request, selection)
    local function ownsReply()
        return rawequal(detailRequests[ply], request) and rawequal(pendingSelection, selection)
            and rawequal(catalogInspections[ply], inspection)
    end
    local token = text:match("^!inspectEventRef%s+(%S+)%s*$")
    if not token then
        if catalogAdmin(ply) and ownsReply() then
            adminLine(ply, "Usage: !inspectEventRef <ref> from your latest catalog page (one reference, valid for 60 seconds).")
        end
        return
    end
    local target, replies = catalogReferenceTarget(ply, token, inspection, detailSnapshot)
    if not ownsReply() then return end
    if not target then
        if catalogAdmin(ply) and ownsReply() then
            adminLine(ply, "Inspection unavailable: reference or configuration could not be checked. Use !listEvents and copy one eligible ref from your latest page within 60 seconds. Data unchanged.")
        end
        return
    end
    for _, reply in ipairs(replies) do
        -- A reply callback may replace the page, select an event, revoke admin,
        -- disconnect, alter definitions or reach expiry. Never emit later rows
        -- for the old request or restore any state after such a callback.
        if not catalogReferenceTarget(ply, token, inspection) or not ownsReply() then return end
        ply:ChatPrint(reply)
    end
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
        .. (automaticSpawnsPaused and "paused; " or "enabled; ")
        .. (eventActive and "active encounter (blocked)" or "no active encounter")
        .. "; players " .. players .. "/min " .. playerCondition
        .. "; activators " .. count .. "/cap " .. capacityCondition .. ".")
    local information, reason = currentStatusMap()
    adminLine(ply, "Spawn inputs: " .. spawnDefinitionStatus(count, readyName)
        .. "; current-map activator positions: " .. positionStatus(information, reason, "activatorSpawnPositions") .. ".")
    adminLine(ply, "Encounter start enemy positions: " .. positionStatus(information, reason, "enemySpawnPositions")
        .. " (required on use).")
end

-- Ownership and all rendered text are copied before ChatPrint can reenter.
-- Indices describe this snapshot only; the engine can reuse them after deletion.
local function enemyLocationNumber(value)
    if math.abs(value) < 1000000000 then return string.format("%.0f", math.floor(value + 0.5)) end
    return string.format("%.3g", value)
end

local function enemyLocationPosition(enemy)
    local ok, text = pcall(function()
        local position = enemy:GetPos()
        if not isvector(position) or not finiteStatusNumber(position.x)
            or not finiteStatusNumber(position.y) or not finiteStatusNumber(position.z) then return nil end
        return "approx rounded world position (" .. enemyLocationNumber(position.x) .. ", "
            .. enemyLocationNumber(position.y) .. ", " .. enemyLocationNumber(position.z) .. ")"
    end)
    return ok and text or "world position unavailable"
end

local function enemyLocationName(name)
    local display = name:gsub("[%c]", " ")
    if #display > 160 then
        local last = 157
        while last > 0 and display:byte(last + 1) >= 128 and display:byte(last + 1) <= 191 do last = last - 1 end
        display = display:sub(1, last) .. "..."
    end
    return 'Active encounter: "' .. display .. '".'
end

local function enemyLocationIndex(enemy)
    local ok, index = pcall(function() return enemy:EntIndex() end)
    if not ok or not finiteStatusNumber(index) or index <= 0 or index ~= math.floor(index) then return nil end
    return index, string.format("%.17g", index)
end

local function enemyMarkerMap()
    local ok, mapName = pcall(game.GetMap)
    if ok and type(mapName) == "string" and #mapName > 0 and #mapName <= 128
        and not mapName:find("%c") then return mapName end
end

-- Nearest reads native coordinates once; only detached scalar fields reach sort.
local function enemyNearestCoordinates(entity)
    local ok, x, y, z = pcall(function()
        local position = entity:GetPos()
        if not isvector(position) then return end
        local px, py, pz = position.x, position.y, position.z
        if finiteStatusNumber(px) and finiteStatusNumber(py) and finiteStatusNumber(pz) then
            return px, py, pz
        end
    end)
    if ok then return x, y, z end
end

local function enemyNearestDistance(x, y, z, originX, originY, originZ)
    -- Native GLua uses floats; promote stock-Lua test integers before subtraction.
    local dx, dy, dz = x * 1.0 - originX * 1.0, y * 1.0 - originY * 1.0, z * 1.0 - originZ * 1.0
    if not finiteStatusNumber(dx) or not finiteStatusNumber(dy) or not finiteStatusNumber(dz) then return end
    local scale = math.max(math.abs(dx), math.abs(dy), math.abs(dz))
    if scale == 0 then return 0 end
    dx, dy, dz = dx / scale, dy / scale, dz / scale
    local distance = scale * math.sqrt(dx * dx + dy * dy + dz * dz)
    if finiteStatusNumber(distance) then return distance end
end

local function enemyNearestAdmitted(ply, alive)
    local ok, admitted = pcall(function()
        return IsValid(ply) and ply:IsPlayer() and ply:IsAdmin() and (not alive or ply:Alive())
    end)
    return ok and admitted
end

local function enemyNearestRejection(ply, capture, message)
    -- Recipient getters can supersede the request too; check identity afterward.
    if enemyNearestAdmitted(ply, false) and rawequal(enemyMarkerCaptures[ply], capture) then
        pcall(function() ply:ChatPrint(message) end)
    end
end

local function printEventEnemies(ply, text, capture, nearest)
    local command = nearest and "!nearEventEnemies" or "!listEventEnemies"
    local argument = text:match("^" .. command .. "%s*(.-)%s*$")
    local page = argument == "" and 1 or (argument:match("^%d+$") and tonumber(argument))
    local usage = "Usage: " .. command .. " [page]; page must be a positive integer"
    local function reject(message)
        if nearest then enemyNearestRejection(ply, capture, message)
        else ply:ChatPrint(message) end
    end
    local function current()
        return capture and rawequal(enemyMarkerCaptures[ply], capture)
            and rawequal(activeEnemies, capture.owners)
    end
    if nearest and not current() then return end
    if not finiteStatusNumber(page) or page < 1 or page ~= math.floor(page) then
        reject(usage .. ".")
        return
    end
    if not eventActive then reject("No active encounter.") return end

    local owners, copied = activeEnemies, {}
    local markerMap = enemyMarkerMap()
    local originX, originY, originZ
    if nearest then
        if not current() then return end
        if not markerMap then
            reject("Nearest inspection unavailable: current map is unavailable. Use !listEventEnemies [page].")
            return
        end
        originX, originY, originZ = enemyNearestCoordinates(ply)
        if not enemyNearestAdmitted(ply, true) or not current() or not eventActive then return end
        if originX == nil then
            reject("Nearest inspection unavailable: your current world position is unavailable. Use !listEventEnemies [page].")
            return
        end
    end
    local name, remaining, initial = activeEventName, totalEnemies, initialEnemies
    for enemy in pairs(owners) do copied[#copied + 1] = enemy end
    local rows, indexCounts, omitted = {}, {}, 0
    for _, enemy in ipairs(copied) do
        if not IsValid(enemy) or enemy:IsMarkedForDeletion() then omitted = omitted + 1
        else
            local index, token = enemyLocationIndex(enemy)
            if token then indexCounts[token] = (indexCounts[token] or 0) + 1 end
            local prefix = token and ("Entity index " .. token .. ": ") or "Unindexed: index unavailable; "
            if nearest then
                local x, y, z = enemyNearestCoordinates(enemy)
                local position, distance = "world position unavailable", nil
                if x ~= nil then
                    position = "approx rounded world position (" .. enemyLocationNumber(x) .. ", "
                        .. enemyLocationNumber(y) .. ", " .. enemyLocationNumber(z) .. ")"
                    distance = enemyNearestDistance(x, y, z, originX, originY, originZ)
                end
                local legacyText = prefix .. position .. "."
                local suffix = distance and ("; ~" .. string.format("%.6g", distance) .. " units away")
                    or "; distance unavailable"
                rows[#rows + 1] = {index = index, token = token, enemy = enemy, distance = distance,
                    legacyText = legacyText, text = prefix .. position .. suffix .. "."}
            else
                rows[#rows + 1] = {index = index, token = token, enemy = enemy,
                    text = prefix .. enemyLocationPosition(enemy) .. "."}
            end
        end
    end
    if nearest and not current() then return end
    if not eventActive or activeEnemies ~= owners then
        reject("Encounter changed during inspection. Retry " .. command .. " [page].")
        return
    end
    table.sort(rows, function(a, b)
        if nearest then
            if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
            if a.distance and not b.distance then return true end
            if b.distance and not a.distance then return false end
        end
        if a.index and b.index and a.index ~= b.index then return a.index < b.index end
        if a.index and not b.index then return true end
        if b.index and not a.index then return false end
        return (a.legacyText or a.text) < (b.legacyText or b.text)
    end)
    local pages = math.max(1, math.ceil(#rows / 8))
    if page > pages then reject(usage .. " in 1-" .. pages .. ".") return end
    local replies = {enemyLocationName(name), (nearest and "Nearest enemy locations, page " or "Enemy locations, page ") .. page .. "/" .. pages
        .. ": progress " .. remaining .. "/" .. initial .. "; listed " .. #rows
        .. "; omitted invalid/deleting " .. omitted .. "."}
    if nearest then
        replies[#replies + 1] = "Approx. distance from your captured position at request time, in 3D Source units; unknown distances last."
    end
    local targets = {}
    for i = (page - 1) * 8 + 1, math.min(page * 8, #rows) do
        local row = rows[i]
        replies[#replies + 1] = row.text
        if row.token and indexCounts[row.token] == 1 then targets[row.token] = row.enemy end
    end
    replies[#replies + 1] = "Temporary entity indices can be reused. " .. command .. " [page] (1-" .. pages
        .. (nearest and "); fresh snapshot; pages can move." or "); fresh snapshot.")
    replies[#replies + 1] = "!removeEventEnemy <index> requests one listed enemy's removal; interrupts the encounter (no victory). List again after each request."
    local currentMap
    if nearest then
        currentMap = enemyMarkerMap()
        if not enemyNearestAdmitted(ply, true) or not current() then return end
        if not eventActive or not rawequal(activeEnemies, owners) or currentMap ~= markerMap then
            reject("Nearest inspection context changed. Retry !nearEventEnemies [page].")
            return
        end
        -- Actor getters can change the map after the earlier observation. Keep
        -- that read's actor checks, then confirm once and recheck capture ownership.
        currentMap = enemyMarkerMap()
        if not current() then return end
        if not eventActive or not rawequal(activeEnemies, owners) or currentMap ~= markerMap then
            reject("Nearest inspection context changed. Retry !nearEventEnemies [page].")
            return
        end
    end
    -- Install before replies: nested inspection or retirement must win.
    local inspection = {owners = owners, targets = targets}
    enemyInspections[ply] = inspection
    -- A marker grant follows this exact page, never a reconstructed index.
    -- Older legacy getter captures may still install their removal page; fail
    -- closed if that page and a newer marker grant disagree, without cleanup changes.
    if not nearest then currentMap = enemyMarkerMap() end
    if capture and rawequal(enemyMarkerCaptures[ply], capture) and capture.stable
        and rawequal(capture.owners, owners) and eventActive and not constructingEnemies
        and rawequal(activeEnemies, owners) and rawequal(enemyInspections[ply], inspection)
        and markerMap and currentMap == markerMap then
        enemyMarkerGrants[ply] = {capture = capture, inspection = inspection, map = markerMap}
    end
    for _, reply in ipairs(replies) do ply:ChatPrint(reply) end
    -- Health inspection alone requires the complete server reply sequence. This
    -- does not acknowledge client delivery or delay existing marker/removal grants.
    local grant = enemyMarkerGrants[ply]
    if grant and rawequal(grant.inspection, inspection) and rawequal(grant.capture, capture)
        and rawequal(enemyMarkerCaptures[ply], capture) and rawequal(enemyInspections[ply], inspection)
        and rawequal(activeEnemies, owners) and eventActive and not constructingEnemies then
        inspection.healthReplyComplete = true
    end
end

-- Captured object and page identity are checked after callback-capable reads.
-- Sending a detached point grants no tracking or cleanup authority.
local function sendEventEnemyMarker(ply, text, clear)
    if ply == nil then return end
    local operation = ActivatorSnapshotMarker.Claim(ply)
    local grant = enemyMarkerGrants[ply]
    local capture = grant and grant.capture
    local inspection = grant and grant.inspection
    local owners = inspection and inspection.owners
    local token = text:match("^!markEventEnemy%s+(%S+)%s*$")
    local enemy = inspection and token and inspection.targets[token]
    local function current() return ActivatorSnapshotMarker.Current(ply, operation) end
    local function owned()
        return current() and grant and rawequal(enemyMarkerGrants[ply], grant)
            and rawequal(enemyMarkerCaptures[ply], capture)
            and rawequal(enemyInspections[ply], inspection) and rawequal(activeEnemies, owners)
            and eventActive and not constructingEnemies and enemy and owners[enemy]
            and rawequal(inspection.targets[token], enemy) and not enemyRemovalRequests[enemy]
    end
    local function permitted(alive)
        return IsValid(ply) and ply:IsPlayer() and ply:IsAdmin() and (not alive or ply:Alive())
    end
    local function targetCurrent()
        if not owned() or not IsValid(enemy) or enemy:IsMarkedForDeletion() then return false end
        local _, index = enemyLocationIndex(enemy)
        if index ~= token or not IsValid(enemy) or enemy:IsMarkedForDeletion() or not owned() then return false end
        local _, finalIndex = enemyLocationIndex(enemy)
        return finalIndex == token and owned()
    end
    local refused = "Enemy snapshot unchanged: inspect again with !listEventEnemies [page] and copy one unique current index."
    local ok, message = pcall(function()
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply:IsAdmin() then return "Only admins can mark encounter enemy snapshots." end
        if clear then
            if text ~= "!clearEventEnemyMarker" then return "Usage: !clearEventEnemyMarker." end
            if not permitted(false) or not current() then return end
            ActivatorSnapshotMarker.Send(ply)
            return "Enemy snapshot marker cleared."
        end
        if not ply:Alive() then return "Enemy snapshot unchanged: you must be alive." end
        if not token or #token > 64 or token:find("%c") then
            return "Usage: !markEventEnemy <index>; copy an exact index from !listEventEnemies."
        end
        if not owned() then return refused end
        local mapName, now = enemyMarkerMap(), CurTime()
        if not mapName or mapName ~= grant.map or not finiteStatusNumber(now)
            or not finiteStatusNumber(now + 15) or now + 15 <= now then return refused end
        if not permitted(true) or not targetCurrent() then return refused end
        local position = enemy:GetPos()
        if not isvector(position) then return refused end
        local x, y, z = position.x, position.y, position.z
        if not finiteStatusNumber(x) or not finiteStatusNumber(y) or not finiteStatusNumber(z) then return refused end
        if enemyMarkerMap() ~= mapName or not permitted(true) or not targetCurrent() or not owned() then return refused end
        ActivatorSnapshotMarker.Send(ply, mapName, "event_enemy", token, x, y, z, now + 15)
        return "15-second encounter enemy position snapshot sent; the enemy may move. !clearEventEnemyMarker to clear."
    end)
    -- Retire only our operation; a nested request owns its own feedback.
    if ActivatorSnapshotMarker.Retire(ply, operation) and ok and message then
        pcall(adminLine, ply, message)
    end
end

-- Observe the exact listed object; this command neither claims marker authority
-- nor consumes/renews a page. Every callback boundary keeps its own request token.
local function inspectEventEnemy(ply, text)
    if ply == nil then return end
    local request = {}
    enemyHealthRequests[ply] = request
    local grant = enemyMarkerGrants[ply]
    local capture = grant and grant.capture
    local inspection = grant and grant.inspection
    local owners = inspection and inspection.owners
    local token = text:match("^!inspectEventEnemy%s+(%S+)%s*$")
    local enemy = inspection and token and inspection.targets[token]
    local function current() return rawequal(enemyHealthRequests[ply], request) end
    local function owned()
        return current() and grant and rawequal(enemyMarkerGrants[ply], grant)
            and rawequal(enemyMarkerCaptures[ply], capture) and capture.stable
            and rawequal(enemyInspections[ply], inspection) and inspection.healthReplyComplete
            and rawequal(activeEnemies, owners) and eventActive and not constructingEnemies
            and enemy and owners[enemy] and rawequal(inspection.targets[token], enemy)
            and not enemyRemovalRequests[enemy]
    end
    local function targetCurrent()
        if not owned() or not IsValid(enemy) or enemy:IsMarkedForDeletion() then return false end
        local _, index = enemyLocationIndex(enemy)
        if index ~= token or not IsValid(enemy) or enemy:IsMarkedForDeletion() or not owned() then return false end
        local _, finalIndex = enemyLocationIndex(enemy)
        return finalIndex == token and owned()
    end
    local function eligible()
        if not owned() or not enemyNearestAdmitted(ply, false) or not owned() then return false end
        if enemyMarkerMap() ~= grant.map or not targetCurrent() then return false end
        -- Confirm actor and map after target getters; these checks are bounded,
        -- not a guarantee against arbitrary getters mutating unrelated state.
        if not enemyNearestAdmitted(ply, false) or not owned() then return false end
        return enemyMarkerMap() == grant.map and owned()
    end
    local function observed(method)
        local ok, value = pcall(function() return enemy[method](enemy) end)
        if not ok then return "unavailable" end
        if type(value) ~= "number" then return "invalid nonnumeric" end
        if not finiteStatusNumber(value) then return "invalid nonfinite" end
        return detailNumber(value)
    end
    local refused = "Health inspection refused: list again with !listEventEnemies or !nearEventEnemies and copy one exact current index."
    local ok, message, detail = pcall(function()
        if not enemyNearestAdmitted(ply, false) or not current() then return end
        if not token or #token > 64 or token:find("%c") then
            return "Usage: !inspectEventEnemy <index>; copy one exact index from your latest !listEventEnemies or !nearEventEnemies page."
        end
        if not eligible() then return refused end
        local health = observed("Health")
        if not eligible() then return refused end
        local maximum = observed("GetMaxHealth")
        if not eligible() then return refused end
        return "Encounter enemy index " .. token .. ": Health() = " .. health .. "; GetMaxHealth() = " .. maximum
            .. ". Observed game values; may change.", true
    end)
    -- Recipient checks may reenter too. Retire only this request before feedback;
    -- a nested feedback command keeps its newer state, with no later writes here.
    local admitted
    if ok and detail then
        local checked, eligibleNow = pcall(eligible)
        if checked and eligibleNow then admitted = true else message = refused end
    elseif not ok then message = refused end
    if not admitted then admitted = enemyNearestAdmitted(ply, false) end
    if not current() then return end
    enemyHealthRequests[ply] = nil
    if admitted and message then pcall(adminLine, ply, message) end
end

local function removeEventEnemy(ply, text)
    local token = text:match("^!removeEventEnemy%s+(%S+)%s*$")
    if not token then
        adminLine(ply, "Usage: !removeEventEnemy <index> from your latest !listEventEnemies page; interrupts the encounter (no victory).")
        return
    end
    local inspection = enemyInspections[ply]
    local enemy = inspection and inspection.targets[token]
    local owners = inspection and inspection.owners
    local function current()
        return IsValid(ply) and ply:IsPlayer() and ply:IsAdmin()
            and eventActive and activeEnemies == owners and owners[enemy]
            and enemyInspections[ply] == inspection and not enemyRemovalRequests[enemy]
    end
    local accepted = false
    if enemy and current() then
        -- Getters can reenter: revalidate permission and exact ownership afterward.
        local ok, usable = pcall(function()
            if not IsValid(enemy) or enemy:IsMarkedForDeletion() then return false end
            local _, currentToken = enemyLocationIndex(enemy)
            return currentToken == token and not enemy:IsMarkedForDeletion() and IsValid(enemy)
        end)
        accepted = ok and usable and current()
    end
    if not accepted then
        if IsValid(ply) and ply:IsPlayer() then
            adminLine(ply, "Enemy removal refused: inspect again with !listEventEnemies [page] and use one unique, unchanged index from your latest page.")
        end
        return
    end
    -- Consume before Remove can reenter, including from another admin's snapshot.
    -- Existing kill/removal hooks alone own accounting and encounter retirement.
    enemyInspections[ply] = nil
    enemyRemovalRequests[enemy] = true
    eventInterrupted = true
    enemy:Remove()
    if IsValid(ply) and ply:IsPlayer() then
        adminLine(ply, "Enemy " .. token .. " removal requested; encounter interrupted (no victory). Other enemies and the queued next event are unchanged.")
    end
end

local function printSelectionStatus(ply)
    if eventActive then
        adminLine(ply, 'Active event: "' .. activeEventName, '" (' .. totalEnemies .. "/" .. initialEnemies
            .. " enemies remaining" .. (eventInterrupted and "; interrupted" or "") .. ").")
        adminLine(ply, "!listEventEnemies [page] shows current owned enemy locations (approximate).")
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
    if type(text) ~= "string" then return end
    local command = text:match("^(!%S+)")
    if command == "!inspectEventEnemy" then
        inspectEventEnemy(ply, text)
        return ""
    end
    if command == "!markEventEnemy" or command == "!clearEventEnemyMarker" then
        sendEventEnemyMarker(ply, text, command == "!clearEventEnemyMarker")
        return ""
    end
    if command ~= "!nextEvent" and command ~= "!nextEventRef" and command ~= "!clearNextEvent" and command ~= "!eventStatus"
        and command ~= "!listEvents" and command ~= "!findEvents" and command ~= "!inspectEventRef" and command ~= "!listEventEnemies" and command ~= "!nearEventEnemies" and command ~= "!removeEventEnemy" then return end
    if ply == nil then return command == "!nearEventEnemies" and "" or nil end
    local request, inspection, selection, markerCapture
    if command == "!listEventEnemies" or command == "!nearEventEnemies" then
        markerCapture = {owners = activeEnemies, stable = not constructingEnemies}
        enemyMarkerCaptures[ply], enemyMarkerGrants[ply] = markerCapture, nil
        ActivatorSnapshotMarker.Cancel(ply)
    end
    if command == "!nearEventEnemies" then
        if not enemyNearestAdmitted(ply, true) then
            enemyNearestRejection(ply, markerCapture, "Nearest inspection requires a living admin.")
            return ""
        end
        local ok = pcall(printEventEnemies, ply, text, markerCapture, true)
        if not ok then
            enemyNearestRejection(ply, markerCapture, "Nearest inspection unavailable. Retry !nearEventEnemies [page] or use !listEventEnemies [page].")
        end
        return ""
    end
    if command == "!listEvents" or command == "!findEvents" then
        request = {}
        catalogRequests[ply] = request
    elseif command == "!inspectEventRef" then
        request, inspection, selection = {}, catalogInspections[ply], pendingSelection
        detailRequests[ply] = request
    elseif command == "!nextEventRef" then inspection = catalogInspections[ply] end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ply:IsAdmin() then
        adminLine(ply, "Only admins can select, inspect or clean up encounters.")
        return ""
    end
    if command == "!removeEventEnemy" then
        removeEventEnemy(ply, text)
    elseif command == "!listEventEnemies" then
        printEventEnemies(ply, text, markerCapture)
    elseif command == "!listEvents" or command == "!findEvents" then
        printEventCatalog(ply, text, request, command == "!findEvents")
    elseif command == "!inspectEventRef" then
        printEventInspection(ply, text, inspection, request, selection)
    elseif command == "!nextEventRef" then
        selectEventReference(ply, text, inspection)
    elseif command == "!nextEvent" then
        local name = text:match("^!nextEvent%s(.*)$")
        if not name or name == "" then selectionHelp(ply) return "" end
        local info, reason = selectableEvent(name)
        if not info then
            adminLine(ply, "Next event unchanged: " .. reason .. ". Use !nextEvent to list configured names.")
            return ""
        end
        pendingSelection = {name = name}
        detailRequests = {}
        adminLine(ply, 'Queued for the next fresh automatic batch: "' .. name, '".')
    elseif text ~= command then
        adminLine(ply, "Usage: " .. command)
    elseif command == "!clearNextEvent" then
        pendingSelection = nil
        detailRequests = {}
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
    enemyInspections[ply] = nil
    enemyHealthRequests[ply] = nil
    enemyMarkerCaptures[ply], enemyMarkerGrants[ply] = nil, nil
    ActivatorSnapshotMarker.Cancel(ply)
    catalogInspections[ply] = nil
    catalogRequests[ply] = nil
    detailRequests[ply] = nil
end)
hook.Add("Initialize", "clearActivatorCatalogReferences", function()
    enemyHealthRequests = {}
    enemyMarkerCaptures, enemyMarkerGrants = {}, {}
    catalogInspections = {}
    catalogRequests = {}
    detailRequests = {}
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

-- Pause only automatic admissions; existing encounters and Use grants stay live.
hook.Add("PlayerSay", "controlAutomaticActivatorSpawns", function(ply, text)
    local command = text:match("^(!%S+)")
    if command ~= "!pauseActivatorSpawns" and command ~= "!resumeActivatorSpawns" then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ply:IsAdmin() then
        adminLine(ply, "Only admins can pause or resume automatic activator spawning.")
        return ""
    end
    if text ~= command then
        adminLine(ply, "Usage: " .. command)
        return ""
    end
    local pause = command == "!pauseActivatorSpawns"
    if automaticSpawnsPaused == pause then
        adminLine(ply, pause and "Automatic activator spawning is already paused."
            or "Automatic activator spawning is already enabled.")
        return ""
    end
    automaticSpawnsPaused = pause
    -- Invalidate an attempt even if a Spawn callback pauses and resumes at once.
    spawnScheduleGeneration = spawnScheduleGeneration + 1
    if pause then
        timer.Stop("activatorSpawner")
        adminLine(ply, "Automatic activator spawning paused. Existing activators and encounters remain usable.")
    elseif eventActive then
        adminLine(ply, "Automatic activator spawning enabled. The normal spawn delay starts after the active encounter ends.")
    else
        timer.Start("activatorSpawner")
        adminLine(ply, "Automatic activator spawning enabled. Normal spawn delay restarted; ordinary spawn conditions still apply.")
    end
    return ""
end)

-- Retire ready authority before removal callbacks; the normal timer owns replacement.
hook.Add("PlayerSay", "refreshReadyActivators", function(ply, text)
    if text:match("^(!%S+)") ~= "!refreshActivators" then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ply:IsAdmin() then
        adminLine(ply, "Only admins can refresh activators.")
        return ""
    end
    if text ~= "!refreshActivators" then
        adminLine(ply, "Usage: !refreshActivators")
        return ""
    end
    if eventActive then
        adminLine(ply, "Cannot refresh activators during an active encounter. Finish it or use !stopEvent first.")
        return ""
    end
    -- Retire in-flight automatic work before invoking removal callbacks.
    spawnScheduleGeneration = spawnScheduleGeneration + 1
    clearSelectedBatch()
    destroyActivators()
    if automaticSpawnsPaused then
        adminLine(ply, "Ready activator removal requested (including manual activators). Automatic spawning remains paused; use !resumeActivatorSpawns when ready.")
    else
        timer.Start("activatorSpawner")
        adminLine(ply, "Ready activator removal requested (including manual activators). Normal spawn delay restarted; the next attempt still requires ordinary spawn conditions.")
    end
    return ""
end)

local function finishEvent(completed)
    enemyHealthRequests = {}
    enemyMarkerCaptures, enemyMarkerGrants = {}, {}
    enemyInspections = {}
    enemyRemovalRequests = {}
    constructingEnemies = nil
    eventActive = false
    activeEnemies = {}
    totalEnemies = 0
    initialEnemies = 0
    activeEventName = nil
    if not automaticSpawnsPaused then timer.Start("activatorSpawner") end
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
    if eventActive or not interaction or not canInteract(ply, interaction.entity) then return end

    local ent = interaction.entity
    if identifier ~= ent.EventIdentifier then return end
    if interaction.expires < CurTime() then
        ply:ChatPrint("This interaction expired. Use the activator again.")
        return
    end
    local info = ent.NPCInfo
    local spawnPosition = returnSpawnPositions(game.GetMap())
    if not spawnPosition then
        ErrorNoHalt("ERROR - There are no enemy spawn positions set for " .. game.GetMap() .. "\n")
        ply:ChatPrint("No enemy spawn position is available. Ask an admin to fix it, then use the activator again.")
        return
    end
    if type(info.maxNPCs) ~= "number" or info.maxNPCs ~= info.maxNPCs or info.maxNPCs < 1 or info.maxNPCs == math.huge then
        ply:ChatPrint("This encounter has an invalid enemy count. Ask an admin to correct the configuration and restart the server.")
        return
    end

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
            if IsValid(enemy) and not enemy:IsMarkedForDeletion() then
                local health = returnEnemyHealth()
                if not ownsConstruction(enemies, enemy) then return end
                if type(health) ~= "number" then
                    stopActivatorEvent()
                    if IsValid(enemy) then enemy:Remove() end
                    if IsValid(ply) and ply:IsPlayer() then
                        ply:ChatPrint("Your encounter start was cancelled because the configured enemy health is not a number. Ask an admin to correct the configuration and restart the server.")
                    end
                    return
                end
                enemy:SetHealth(health)
                if not ownsConstruction(enemies, enemy) then return end
                if IsValid(enemy) and not enemy:IsMarkedForDeletion() then
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
        if IsValid(ply) and ply:IsPlayer() then
            ply:ChatPrint("No enemies could be spawned for your encounter. Ask an admin to check the server console.")
        end
        return
    end
    if totalEnemies == 0 then finishEvent(not eventInterrupted) return end
    sendEventStatus()
    for _, player in pairs(player.GetAll()) do
        player:ChatPrint(initialEnemies .. " enemies have been spawned. Eliminate them.")
    end
end)

-- One ordinary ready-batch attempt. Keep configuration, RNG and API order shared.
local function attemptReadyBatch(immediate)
    if automaticSpawnsPaused then return "Immediate activator attempt blocked: automatic spawning is paused." end
    if eventActive then return "Immediate activator attempt blocked: an encounter is active." end
    if player.GetCount() < returnMinNumberOfPlayers() then return "Immediate activator attempt blocked: not enough players." end
    local generation = spawnScheduleGeneration
    refreshSelectedBatch()
    activatorCount = 0
    for _, ent in pairs(ents.FindByClass("activatorent")) do
        if usableActivator(ent) then activatorCount = activatorCount + 1 end
    end
    if not hasActivatorSpawns(game.GetMap()) then return "Immediate activator attempt blocked: no activator positions are available." end
    local admittedSelection = activatorCount == 0 and pendingSelection or nil
    local selectedName = selectedBatchName or (admittedSelection and admittedSelection.name)
    local identifier
    if selectedName then
        if not selectableEvent(selectedName) then return "Immediate activator attempt blocked: the selected event is unavailable." end
        identifier = selectedName
    else identifier = determineRandomEvent() end
    if not identifier or not returnNPCInformation(identifier) then return "Immediate activator attempt blocked: event information is unavailable." end
    local spawnPosition = returnActivatorSpawns(game.GetMap())
    if not spawnPosition then return "Immediate activator attempt blocked: no position was sampled." end

    local maximum = returnMaxActivators() or 1
    if not finiteStatusNumber(maximum) then return "Immediate activator attempt blocked: configured capacity is invalid." end
    for i = activatorCount + 1, maximum do
        -- A previous Spawn callback may have made the next sample unavailable.
        if automaticSpawnsPaused or generation ~= spawnScheduleGeneration or (immediate and eventActive) then
            return "Immediate activator attempt interrupted by a spawn control or encounter change; actors may remain. No retry was scheduled."
        end
        if not spawnPosition then break end
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
            -- Finish ownership for the admitted actor, then retire a paused or
            -- superseded attempt before further RNG, admissions or timer.Stop.
            if automaticSpawnsPaused or generation ~= spawnScheduleGeneration or (immediate and eventActive) then
                return "Immediate activator attempt interrupted by a spawn control or encounter change; actors may remain. No retry was scheduled."
            end
            spawnPosition = returnActivatorSpawns(game.GetMap())
        end
    end
    if automaticSpawnsPaused or generation ~= spawnScheduleGeneration or (immediate and eventActive) then
        return "Immediate activator attempt interrupted by a spawn control or encounter change; actors may remain. No retry was scheduled."
    end
    activatorCount = 0
    for _, ent in pairs(ents.FindByClass("activatorent")) do
        if usableActivator(ent) then activatorCount = activatorCount + 1 end
    end
    local observedCount = activatorCount
    if activatorCount >= maximum and activatorCount > 0 then timer.Stop("activatorSpawner") end
    if immediate then
        return "Immediate activator attempt finished. Ready activators: " .. observedCount .. " / " .. maximum .. ". No retry was scheduled."
    end
end

-- Claim before the ready scan, and release before either feedback or rethrow.
local function runSpawnAttempt(immediate)
    spawnAttemptDepth = spawnAttemptDepth + 1
    local ok, result = pcall(function()
        if immediate then
            if automaticSpawnsPaused then return "Immediate activator spawn refused: automatic spawning is paused." end
            if eventActive then return "Immediate activator spawn refused: an encounter is active." end
            for _, ent in pairs(ents.FindByClass("activatorent")) do
                if usableActivator(ent) then return "Immediate activator spawn refused: a ready activator already exists (including manual actors)." end
            end
        end
        return attemptReadyBatch(immediate)
    end)
    spawnAttemptDepth = spawnAttemptDepth - 1
    return ok, result
end

-- Spawn only the missing activators, never more than the configured cap.
timer.Create("activatorSpawner", returnDelayBetweenEvents(), 0, function()
    local ok, result = runSpawnAttempt(false)
    if not ok then error(result, 0) end
end)

hook.Add("PlayerSay", "spawnReadyActivatorsNow", function(ply, text)
    if type(text) ~= "string" or text:match("^(!%S+)") ~= "!spawnActivatorsNow" then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local failure = "Immediate activator attempt stopped with an error; actors may remain and the pending choice may have changed. No retry was scheduled."
    local ok, message = pcall(function()
        if not ply:IsAdmin() then return "Only admins can spawn activators now." end
        if text ~= "!spawnActivatorsNow" then return "Usage: !spawnActivatorsNow" end
        if spawnAttemptDepth > 0 then return "Immediate activator spawn refused: another spawn attempt is in flight." end
        local succeeded, result = runSpawnAttempt(true)
        if not succeeded then return failure end
        return result
    end)
    -- Native reply callbacks can reenter, throw or disconnect. All state work
    -- has finished; never serialize an arbitrary error or write after feedback.
    pcall(function()
        if IsValid(ply) and ply:IsPlayer() then adminLine(ply, ok and message or failure) end
    end)
    return ""
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
        if not automaticSpawnsPaused then timer.Start("activatorSpawner") end
    end
    for ply, interaction in pairs(interactions) do
        if interaction.entity == ent then interactions[ply] = nil end
    end
end)
