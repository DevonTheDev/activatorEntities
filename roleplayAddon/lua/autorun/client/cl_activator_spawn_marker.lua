-- A private, temporary position snapshot, never a live target or tracking request.
local marker
local lifetime, clockTolerance = 15, 1
local font = "DermaDefault"
local markerColor = Color(255, 210, 80, 255)
local textColor = Color(255, 255, 255, 255)

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function boundedString(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum
        and not value:find("[%z\1-\31\127]")
end

local function context()
    local owner = LocalPlayer()
    if not IsValid(owner) or not owner:IsPlayer() or not owner:IsAdmin() or not owner:Alive() then return end
    local map, now, realNow = game.GetMap(), CurTime(), RealTime()
    if not boundedString(map, 128) or not finite(now) or not finite(realNow) then return end
    return owner, map, now, realNow
end

local function decode(bits)
    -- net.Receive gives payload bits, excluding the message-name header. Bound
    -- before reads: truncated engine reads can return zero instead of throwing.
    if not finite(bits) or bits % 8 ~= 1 or bits < 1 or bits > 1905 then return end
    local show = net.ReadBool()
    if show == false then
        if bits == 1 then return false end
        return
    end
    if show ~= true or bits < 337 then return end
    local map, kind, key = net.ReadString(), net.ReadString(), net.ReadString()
    if not boundedString(map, 128) or (kind ~= "enemy" and kind ~= "activator" and kind ~= "event_enemy" and kind ~= "ready_actor")
        or not boundedString(key, 64) or key:find("%s") then return end
    local number = tonumber(key)
    if not finite(number) or number <= 0 or number % 1 ~= 0 then return end
    -- Three NUL-terminated strings and four 64-bit doubles follow the bool.
    if bits ~= 1 + 8 * (#map + #kind + #key + 3) + 256 then return end
    local x, y, z, expires = net.ReadDouble(), net.ReadDouble(), net.ReadDouble(), net.ReadDouble()
    if not finite(x) or not finite(y) or not finite(z) or not finite(expires) then return end
    local owner, currentMap, now, realNow = context()
    if not owner or map ~= currentMap then return end
    local remaining = expires - now
    if not finite(remaining) or remaining <= 0 or remaining > lifetime + clockTolerance then return end
    local realExpires = realNow + math.min(lifetime, remaining)
    if not finite(realExpires) or realExpires <= realNow then return end
    -- Vector can have a narrower native representation than a network double.
    -- Reject a lossy or unusable copy; never alter the received coordinates.
    local position = Vector(x, y, z)
    if not isvector(position) or not finite(position.x) or not finite(position.y) or not finite(position.z)
        or position.x ~= x or position.y ~= y or position.z ~= z then return end
    return {owner=owner, map=map, kind=kind, key=key, position=position,
        expires=expires, realExpires=realExpires, lastNow=now, lastReal=realNow}
end

net.Receive("ActivatorSpawnMarker", function(bits)
    local ok, candidate = pcall(decode, bits)
    if not ok or candidate == nil then return end
    marker = candidate or nil
end)

local function currentMarker()
    if not marker then return end
    local ok, owner, map, now, realNow = pcall(context)
    if not ok or owner ~= marker.owner or map ~= marker.map or not finite(now) or not finite(realNow)
        or now < marker.lastNow or realNow < marker.lastReal
        or now >= marker.expires or realNow >= marker.realExpires then
        marker = nil
        return
    end
    marker.lastNow, marker.lastReal = now, realNow
    return marker
end

local function clearMarker()
    marker = nil
end

hook.Add("Think", "ActivatorSpawnMarkerLifetime", function()
    currentMarker()
end)
hook.Add("Initialize", "ActivatorSpawnMarkerInitialize", clearMarker)
hook.Add("OnReloaded", "ActivatorSpawnMarkerReload", clearMarker)

local function project(position)
    local started = false
    local ok, x, y, visible = pcall(function()
        cam.Start3D()
        started = true
        local screen = position:ToScreen()
        if type(screen) ~= "table" then return end
        return screen.x, screen.y, screen.visible
    end)
    if started then
        local ended = pcall(cam.End3D)
        if not ended then return end
    end
    if ok and visible == true and finite(x) and finite(y) then return x, y end
end

local function statusLine(text, x, y, width, height)
    local textWidth, textHeight = surface.GetTextSize(text)
    if not finite(textWidth) or not finite(textHeight) or textHeight <= 0 or y + textHeight > height then return end
    if textWidth > width then
        -- Labels are bounded ASCII; no partial multibyte characters are cut.
        local suffix = "..."
        while #text > 0 do
            text = text:sub(1, -2)
            textWidth = surface.GetTextSize(text .. suffix)
            if textWidth <= width then text = text .. suffix; break end
        end
        if #text == 0 then return end
    end
    draw.SimpleText(text, font, x, y, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    return textHeight
end

hook.Add("HUDPaint", "ActivatorSpawnMarkerHUD", function()
    local current = currentMarker()
    if not current then return end
    local width, height = ScrW(), ScrH()
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then return end
    local x, y = project(current.position)
    if x and x >= 0 and y >= 0 and x < width and y < height then
        surface.SetDrawColor(markerColor)
        surface.DrawLine(math.max(0, x - 6), y, math.min(math.max(0, width - 1), x + 6), y)
        surface.DrawLine(x, math.max(0, y - 6), x, math.min(math.max(0, height - 1), y + 6))
    end
    surface.SetFont(font)
    local left, top = math.min(8, width / 4), math.min(8, height / 4)
    local _, fontHeight = surface.GetTextSize("M")
    if finite(fontHeight) and fontHeight > 0 and height >= 2 * fontHeight + 2 then
        -- Keep the fixed status below the encounter progress panel, including
        -- narrow viewports where its top-right panel spans almost the width.
        top = math.max(0, height - 2 * fontHeight - 2 - top)
    end
    local available = math.max(0, width - 2 * left)
    local label = (current.kind == "enemy" and "Enemy" or "Activator") .. " spawn key " .. current.key .. " - snapshot"
    local help = "15-second snapshot; turn toward the point; !clearSpawnMarker"
    if current.kind == "event_enemy" then
        label = "Encounter enemy index " .. current.key .. " - position snapshot"
        help = "15-second snapshot; enemy may move; !clearEventEnemyMarker"
    elseif current.kind == "ready_actor" then
        label = "Activator actor index " .. current.key .. " - position snapshot"
        help = "15-second snapshot; actor may move or disappear; !clearSpawnMarker"
    end
    local lineHeight = statusLine(label, left, top, available, height)
    if lineHeight then
        statusLine(help, left, top + lineHeight + 2, available, height)
    end
end)
