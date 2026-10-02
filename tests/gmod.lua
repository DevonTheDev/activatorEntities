-- Minimal test doubles for the Garry's Mod APIs used by this addon.
local M = {}
local root = "roleplayAddon/lua/"

-- Translate only GLua operators/comments, preserving quoted strings and long
-- comments. This lets stock Lua execute the actual addon rather than a copy.
function M.source(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local out, i = {}, 1
    while i <= #source do
        local rest = source:sub(i)
        local quote = source:sub(i, i)
        local long = rest:match("^%-%-%[(=*)%[")
        if long ~= nil then
            local close = "]" .. long .. "]"
            local finish = assert(source:find(close, i + #long + 4, true), "unclosed comment") + #close - 1
            out[#out + 1], i = source:sub(i, finish), finish + 1
        elseif rest:sub(1, 2) == "--" or rest:sub(1, 2) == "//" then
            local finish = source:find("\n", i, true) or (#source + 1)
            out[#out + 1], i = "--" .. source:sub(i + 2, finish - 1), finish
        elseif quote == '"' or quote == "'" then
            local finish = i + 1
            while finish <= #source do
                if source:sub(finish, finish) == "\\" then
                    finish = finish + 2
                elseif source:sub(finish, finish) == quote then
                    break
                else
                    finish = finish + 1
                end
            end
            out[#out + 1], i = source:sub(i, finish), finish + 1
        elseif rest:sub(1, 2) == "!=" then
            out[#out + 1], i = "~=", i + 2
        elseif quote == "!" then
            out[#out + 1], i = "not ", i + 1
        else
            out[#out + 1], i = quote, i + 1
        end
    end
    return table.concat(out)
end

function M.new(client)
    local env = setmetatable({}, {__index = _G})
    env._G, env.ENT = env, {}
    env.entities, env.messages, env.receivers, env.hooks, env.timers = {}, {}, {}, {}, {}
    env.now, env.map, env.errors = 0, "gm_construct", {}
    env.IsValid = function(value) return type(value) == "table" and value.valid == true end
    env.CurTime = function() return env.now end
    env.AddCSLuaFile = function() end
    env.ErrorNoHalt = function(text) table.insert(env.errors, text) end
    env.Error = function(text) error(text) end
    env.PrintTable = function() end
    env.Color = function(...) return {...} end
    env.SCREENFADE, env.color_black = {IN = 1}, {}
    env.table = setmetatable({}, {__index = table})
    env.table.maxn = function(values)
        local max = 0
        for key in pairs(values) do if type(key) == "number" and key > max then max = key end end
        return max
    end
    local vector = {}
    vector.__index = vector
    function env.Vector(x, y, z) return setmetatable({x=x, y=y, z=z}, vector) end
    function vector.__add(a, b) return env.Vector(a.x+b.x, a.y+b.y, a.z+b.z) end
    function vector:DistToSqr(other) return (self.x-other.x)^2+(self.y-other.y)^2+(self.z-other.z)^2 end
    env.util = {AddNetworkString = function() end}
    env.file = {Read = function() end, Write = function() end}
    env.game = {GetMap = function() return env.map end}
    env.net = {}
    function env.net.Receive(name, callback) env.receivers[name] = callback end
    function env.net.Start(name) env.outgoing = {name = name, values = {}} end
    function env.net.WriteEntity(value) table.insert(env.outgoing.values, value) end
    env.net.WriteString = env.net.WriteEntity
    function env.net.Send(ply)
        env.outgoing.player = ply
        table.insert(env.messages, env.outgoing)
        env.outgoing = nil
    end
    function env.net.SendToServer() env.net.Send("server") end
    local function read() return table.remove(env.incoming, 1) end
    env.net.ReadEntity, env.net.ReadString = read, read
    function env.receive(name, sender, ...)
        env.incoming = {...}
        assert(env.receivers[name], "Missing receiver: " .. name)(0, sender)
    end
    function env.messageCount(name)
        local count = 0
        for _, message in ipairs(env.messages) do if message.name == name then count = count + 1 end end
        return count
    end
    env.hook = {}
    function env.hook.Add(event, name, callback)
        env.hooks[event] = env.hooks[event] or {}
        env.hooks[event][name] = callback
    end
    function env.fire(event, ...)
        for _, callback in pairs(env.hooks[event] or {}) do callback(...) end
    end
    env.timer = {}
    function env.timer.Create(name, delay, repetitions, callback)
        env.timers[name] = {delay=delay, repetitions=repetitions, callback=callback, stopped=false}
    end
    function env.timer.Start(name) if env.timers[name] then env.timers[name].stopped = false end end
    function env.timer.Stop(name) if env.timers[name] then env.timers[name].stopped = true end end
    function env.timer.Simple(delay, callback) env.timer.Create("simple" .. (#env.timers+1), delay, 1, callback) end
    function env.fireTimer(name)
        local timer = assert(env.timers[name], "Missing timer: " .. name)
        if timer.stopped then return end
        if timer.repetitions == 1 then env.timers[name] = nil end
        timer.callback()
    end
    env.ents = {}
    local function find(field, value)
        local result = {}
        for _, ent in ipairs(env.entities) do if ent.valid and ent[field] == value then table.insert(result, ent) end end
        return result
    end
    env.ents.FindByClass = function(class) return find("class", class) end
    env.ents.FindByName = function(name) return find("name", name) end
    function env.entity(class)
        local ent = {valid=true, class=class, name="", pos=env.Vector(0,0,0), chats={}}
        function ent:IsPlayer() return self.class == "player" end
        function ent:GetClass() return self.class end
        function ent:GetName() return self.name end
        function ent:SetName(value) self.name = value end
        function ent:GetPos() return self.pos end
        function ent:SetPos(value) assert(value, "missing position"); self.pos = value end
        function ent:SetModel(value) assert(value, "missing model"); self.model=value end
        function ent:GetModel() return self.model end
        function ent:SetHealth(value) self.health = value end
        function ent:SetMoveType(value) self.moveType = value; self.moveChanges=(self.moveChanges or 0)+1 end
        function ent:StopMoving() self.stopped = true end
        function ent:ChatPrint(text) table.insert(self.chats, text) end
        for _, method in ipairs({"SetHullType", "SetHullSizeNormal", "SetNPCState", "SetSolid", "SetUseType", "CapabilitiesAdd", "DropToFloor", "ScreenFade"}) do
            ent[method] = function() end
        end
        function ent:Spawn()
            if self.Initialize then self:Initialize() end
            self.spawned = true
        end
        function ent:Remove()
            if not self.valid then return end
            if self.OnRemove then self:OnRemove() end
            env.fire("EntityRemoved", self)
            self.valid = false
        end
        function ent:Alive() return self.alive ~= false end
        function ent:Nick() return "Test player" end
        function ent:IsAdmin() return self.admin == true end
        if class == "activatorent" then setmetatable(ent, {__index=env.ENT}) end
        table.insert(env.entities, ent)
        return ent
    end
    function env.ents.Create(class)
        if env.failClass == class then return {valid=false} end
        return env.entity(class)
    end
    env.player = {GetAll=function() return find("class", "player") end, GetCount=function() return #find("class", "player") end}
    function env.include(path)
        if client and path:match("^autorun/server/") then error("server-only file unavailable to client: " .. path) end
        if path == "shared.lua" then path = "entities/activatorent/shared.lua" end
        local source, chunk = M.source(root .. path)
        if _VERSION == "Lua 5.1" then chunk=assert(loadstring(source, "@" .. path)); setfenv(chunk, env)
        else chunk=assert(load(source, "@" .. path, "t", env)) end
        return chunk()
    end
    if client then
        env.panels = {}
        env.ScrW, env.ScrH = function() return 1920 end, function() return 1080 end
        env.vgui = {}
        function env.vgui.Create(class, parent)
            local panel = {valid=true, class=class, parent=parent, children={}}
            if parent then table.insert(parent.children, panel) end
            for _, method in ipairs({"SetVisible", "SetTitle", "SetSize", "Center", "MakePopup", "SetBackgroundBlur", "SetDeleteOnClose", "ShowCloseButton", "SetFont", "SetColor", "Dock", "DockMargin", "SetPos", "SetModel", "SetFOV", "SetCamPos", "SetPaintShadow"}) do panel[method]=function() end end
            function panel:SetText(value) self.text=value end
            function panel:GetTall() return 1080 end
            function panel:GetCamPos() return env.Vector(0,0,0) end
            function panel:IsValid() return self.valid end
            function panel:Close()
                if self.OnClose then self:OnClose() end
                self.valid=false
                for _, child in ipairs(self.children) do child.valid=false end
            end
            table.insert(env.panels, panel)
            return panel
        end
        env.include("entities/activatorent/cl_init.lua")
    else
        env.include("autorun/server/sv_config.lua")
        env.include("entities/activatorent/init.lua")
    end
    function env.ready()
        local ply=env.entity("player")
        env.fireTimer("activatorSpawner")
        local activator=assert(env.ents.FindByClass("activatorent")[1])
        ply:SetPos(activator:GetPos())
        return ply, activator
    end
    function env.start()
        local ply, activator=env.ready()
        activator:AcceptInput("Use", ply, ply)
        env.receive("SendNPCInformation", ply, "Raid")
        return ply, env.ents.FindByName("devonsSpawnedEntity")
    end
    return env
end
return M
