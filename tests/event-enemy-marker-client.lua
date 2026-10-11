-- API-input/decision checks; these do not exercise native engine packets or pixels.
return function(gmod, test, eq)
    local channel = "ActivatorSpawnMarker"
    local function client()
        local env = gmod.new(true)
        local owner = env.entity("player")
        owner.admin, env.localPlayer = true, owner
        env.now, env.realNow = 100, 1000
        assert(env.receivers[channel], "marker receiver is installed")
        return env, owner
    end
    local function packet(env, changes)
        local values = {true, env.map, "event_enemy", "7", 20000.25, -30000.5, 2.125, env.now + 15}
        for index, value in pairs(changes or {}) do values[index] = value end
        return {name=channel, values=values, fields={
            {kind="bool"}, {kind="string"}, {kind="string"}, {kind="string"},
            {kind="double"}, {kind="double"}, {kind="double"}, {kind="double"}}}
    end
    local function show(env, changes, bits)
        env.deliver(packet(env, changes), nil, bits, true)
    end
    local function clear(env, bits)
        env.deliver({name=channel, values={false}, fields={{kind="bool"}}}, nil, bits, true)
    end
    local function paint(env)
        env.drawCalls, env.projections, env.camCalls = {}, {}, {}
        env.fire("HUDPaint")
        eq(env.camDepth, 0, "3D projection closes before any other HUD hook")
        local texts, lines = {}, {}
        for _, call in ipairs(env.drawCalls) do
            if call.kind == "text" then texts[#texts+1] = call
            elseif call.kind == "line" then lines[#lines+1] = call end
        end
        return texts, lines
    end
    local function visible(env, key, kind)
        key, kind = key or "7", kind or "event_enemy"
        local texts, lines = paint(env)
        eq(#lines, 2, "one fixed snapshot cross")
        eq(#texts, 2, "truthful label and fixed help")
        local label = kind == "event_enemy" and "Encounter enemy index " .. key .. " - position snapshot"
            or (kind == "enemy" and "Enemy" or "Activator") .. " spawn key " .. key .. " - snapshot"
        eq(texts[1].text, label, "literal subtype and token label")
        if kind == "event_enemy" then
            assert(texts[2].text:find("enemy may move", 1, true), "help explains historical enemy position")
            assert(texts[2].text:find("!clearEventEnemyMarker", 1, true), "help uses truthful clear alias")
        else
            eq(texts[2].text, "15-second snapshot; turn toward the point; !clearSpawnMarker", "legacy help bytes")
        end
        assert(texts[2].text:find("15-second", 1, true), "help states bounded lifetime")
        eq(#env.messages, 0, "client has no request, acknowledgement, retry or broadcast")
        eq(#env.panels, 0, "marker creates no panel or input capture")
        eq(next(env.timers), nil, "marker adds no timer")
        return env.projections[1]
    end
    local function absent(env)
        local texts, lines = paint(env)
        eq(#texts, 0, "no stale label")
        eq(#lines, 0, "no stale cross")
        eq(#env.projections, 0, "no stale point projected")
    end

    test("event enemy marker accepts the actual receiver packet with a truthful label", function()
        local env = client()
        env.deliver(packet(env))
        local point = visible(env)
        eq(point.x, 20000.25); eq(point.y, -30000.5); eq(point.z, 2.125)
    end)

    test("event enemy marker accepts exact 385-bit minimum and 1905-bit maximum payloads", function()
        local env = client()
        env.map = "a"
        local message = packet(env, {[4]="1"})
        eq(env.packetBits(message), 385, "minimum event_enemy packet")
        env.deliver(message); visible(env, "1")
        env.map = string.rep("a", 128)
        local token = "1" .. string.rep("0", 63)
        message = packet(env, {[4]=token})
        eq(env.packetBits(message), 1905, "maximum event_enemy packet")
        env.deliver(message); visible(env, token)
    end)

    for _, kind in ipairs({"enemy", "activator"}) do
        test("event enemy marker shares one slot with unchanged " .. kind .. " packets", function()
            local env = client()
            local legacy = packet(env, {[3]=kind, [4]="2"})
            eq(env.packetBits(legacy), 1+8*(#env.map+#kind+1+3)+256, "legacy payload formula")
            env.deliver(legacy); visible(env, "2", kind)
            show(env); visible(env)
            env.deliver(legacy); visible(env, "2", kind)
            show(env, {[4]="9", [5]=-12.25}); eq(visible(env, "9").x, -12.25)
            clear(env); absent(env); clear(env); absent(env)
        end)
    end
    for _, token in ipairs({"9007199254740993", "1e+30", "0007"}) do
        test("event enemy marker retains literal index token " .. token, function()
            local env = client(); show(env, {[4]=token}); visible(env, token)
        end)
    end

    local invalid = {
        {"empty map", 2, ""}, {"overlong map", 2, string.rep("a",129)},
        {"wrong map", 2, "gm_other"}, {"map NUL", 2, "gm_construct\0"},
        {"map control", 2, "gm_construct\31"}, {"map DEL", 2, "gm_construct\127"},
        {"unknown kind", 3, "npc"}, {"empty kind", 3, ""},
        {"kind suffix", 3, "event_enemy_extra"}, {"kind control", 3, "event_enemy\n"},
        {"empty token", 4, ""}, {"overlong token", 4, string.rep("1",65)},
        {"zero token", 4, "0"}, {"negative token", 4, "-7"}, {"fraction token", 4, "7.5"},
        {"nonnumeric token", 4, "npc7"}, {"infinite token", 4, "1e999"},
        {"token space", 4, " 7"}, {"token tab", 4, "7\t"}, {"token newline", 4, "7\n"},
        {"token NUL", 4, "7\0"}, {"token DEL", 4, "7\127"},
        {"x NaN", 5, 0/0}, {"x infinity", 5, math.huge}, {"x negative infinity", 5, -math.huge},
        {"y NaN", 6, 0/0}, {"y infinity", 6, math.huge}, {"y negative infinity", 6, -math.huge},
        {"z NaN", 7, 0/0}, {"z infinity", 7, math.huge}, {"z negative infinity", 7, -math.huge},
        {"expiry NaN", 8, 0/0}, {"expiry infinity", 8, math.huge}, {"expiry negative infinity", 8, -math.huge},
        {"past expiry", 8, 99}, {"current expiry", 8, 100}, {"excess tolerance", 8, 116.0001},
    }
    for _, case in ipairs(invalid) do
        test("event enemy marker preserves the previous snapshot on " .. case[1], function()
            local env = client(); show(env)
            local changes = {[4]="9", [5]=-12.25}
            changes[case[2]] = case[3]
            show(env, changes)
            eq(visible(env).x, 20000.25, "rejected payload does not replace detached point")
        end)
    end
    for _, length in ipairs({-1, 0, 0.5, 1890, 1906, 1913, math.huge, -math.huge, 0/0}) do
        test("event enemy marker rejects impossible envelope before reading " .. tostring(length), function()
            local env = client(); show(env)
            local before = env.netReads
            show(env, {[4]="9"}, length)
            eq(env.netReads, before, "impossible length consumes no fields")
            visible(env)
        end)
    end
    for _, offset in ipairs({-256, -64, -8, -1, 1, 7, 8, 64}) do
        test("event enemy marker rejects truncated or trailing payload offset " .. offset, function()
            local env = client(); show(env)
            local message = packet(env, {[4]="9"})
            env.deliver(message, nil, env.packetBits(message)+offset, true)
            visible(env)
        end)
    end
    test("event enemy marker rejects below its minimum before double reads", function()
        local env = client(); env.map="a"; show(env)
        local reads = 0
        env.net.ReadDouble = function() reads=reads+1; return 0 end
        show(env, {[4]="9"}, 377)
        eq(reads, 0); visible(env)
    end)
    for _, length in ipairs({0, 2, 8, 65, 385, 1905}) do
        test("event enemy marker preserves snapshot on malformed clear " .. length, function()
            local env = client(); show(env); clear(env, length); visible(env)
        end)
    end
    for index=1,8 do
        test("event enemy marker contains typed field order violation at field " .. index, function()
            local env = client(); show(env)
            local message = packet(env, {[4]="9"})
            local length = env.packetBits(message)
            message.fields[index].kind = index == 1 and "string" or "bool"
            env.deliver(message, nil, length, true); visible(env)
        end)
    end
    for _, reader in ipairs({"ReadBool", "ReadString", "ReadDouble"}) do
        test("event enemy marker contains " .. reader .. " failure", function()
            local env = client(); show(env)
            env.net[reader] = function() error("synthetic reader failure") end
            show(env, {[4]="9"}); visible(env)
        end)
    end
    test("event enemy marker rejects missing fields with an otherwise valid declared length", function()
        local env = client(); show(env)
        local message = packet(env, {[4]="9"})
        local length = env.packetBits(message)
        message.values[8], message.fields[8] = nil, nil
        env.deliver(message, nil, length, true); visible(env)
    end)
    test("event enemy marker rejects truncated zero-returning double reads before consuming them", function()
        local env = client(); show(env)
        local count, message = 0, packet(env, {[4]="9"})
        env.net.ReadDouble = function() count=count+1; return 0 end
        env.deliver(message, nil, env.packetBits(message)-64, true)
        eq(count, 0); visible(env)
    end)
    for _, value in ipairs({1, "true"}) do
        test("event enemy marker rejects nonboolean discriminator " .. tostring(value), function()
            local env = client(); show(env)
            env.net.ReadBool = function() return value end
            show(env, {[4]="9"}); visible(env)
        end)
    end

    local admission = {
        {"missing player", function(env) env.localPlayer=nil end},
        {"invalid player", function(env, ply) ply.valid=false end},
        {"nonplayer", function(env, ply) ply.class="worldspawn" end},
        {"dead player", function(env, ply) ply.alive=false end},
        {"demoted player", function(env, ply) ply.admin=false end},
        {"nonfinite game time", function(env) env.now=0/0 end},
        {"nonfinite real time", function(env) env.realNow=math.huge end},
        {"nonincreasing real deadline", function(env) env.realNow=1e308 end},
        {"throwing player getter", function(env, ply) ply.IsAdmin=function() error("permission failure") end end},
    }
    for _, case in ipairs(admission) do
        test("event enemy marker declines receipt for " .. case[1], function()
            local env, ply = client()
            local message, admin = packet(env), ply.IsAdmin
            case[2](env, ply)
            env.deliver(message, nil, nil, true)
            env.localPlayer, ply.valid, ply.alive, ply.admin, ply.class = ply, true, true, true, "player"
            env.now, env.realNow, ply.IsAdmin = 100, 1000, admin
            absent(env)
        end)
    end
    for _, observation in ipairs({"Think", "HUDPaint"}) do
        local invalidations = {
            {"missing player", function(env) env.localPlayer=nil end},
            {"invalid player", function(env, ply) ply.valid=false end},
            {"replacement player", function(env) env.localPlayer=env.entity("player"); env.localPlayer.admin=true end},
            {"death", function(env, ply) ply.alive=false end},
            {"demotion", function(env, ply) ply.admin=false end},
            {"map change", function(env) env.map="gm_other" end},
            {"game expiry", function(env) env.now=115 end},
            {"real expiry", function(env) env.realNow=1015 end},
            {"invalid game clock", function(env) env.now=0/0 end},
            {"invalid real clock", function(env) env.realNow=-math.huge end},
            {"game clock rollback", function(env) env.now=99 end},
            {"real clock rollback", function(env) env.realNow=999 end},
            {"context getter exception", function(env) env.game.GetMap=function() error("map failure") end end},
        }
        for _, case in ipairs(invalidations) do
            test("event enemy marker " .. observation .. " permanently observes " .. case[1], function()
                local env, ply = client(); show(env)
                local mapGetter = env.game.GetMap
                case[2](env, ply); env.fire(observation)
                env.localPlayer, ply.valid, ply.alive, ply.admin = ply, true, true, true
                env.map, env.now, env.realNow, env.game.GetMap = "gm_construct", 100, 1000, mapGetter
                absent(env)
            end)
        end
    end
    test("event enemy marker keeps only remaining delayed-arrival lifetime", function()
        local env = client(); local message = packet(env)
        env.now = 113
        env.deliver(message); visible(env)
        env.realNow = 1001.999; visible(env)
        env.realNow = 1002; env.fire("Think"); absent(env)
    end)
    test("event enemy marker one-second receipt tolerance still caps local life at 15 seconds", function()
        local env = client(); show(env, {[8]=116}); visible(env)
        env.realNow=1014.999; visible(env)
        env.realNow=1015; absent(env)
    end)
    test("event enemy marker repeated Think and HUDPaint do not renew the game deadline", function()
        local env = client(); show(env)
        for second=1,14 do
            env.now, env.realNow=100+second,1000+second
            eq(env.fire("Think"), nil, "lifetime hook never suppresses other hooks")
            visible(env)
        end
        env.now=114.999; visible(env)
        env.now=115; absent(env)
    end)
    test("event enemy marker rollback is relative to the latest observation", function()
        for _, clock in ipairs({"now", "realNow"}) do
            local env = client(); show(env)
            env[clock]=env[clock]+4; env.fire("Think"); visible(env)
            env[clock]=env[clock]-1; env.fire("Think")
            env[clock]=env[clock]+1; absent(env)
        end
    end)
    for _, event in ipairs({"Initialize", "OnReloaded"}) do
        test("event enemy marker permanently clears on " .. event, function()
            local env = client(); show(env); env.fire(event); absent(env)
        end)
    end
    test("event enemy marker repeated autorun replaces callbacks with an empty slot", function()
        local env=client(); show(env)
        env.include("autorun/client/cl_activator_spawn_marker.lua")
        absent(env); show(env); visible(env)
    end)
    test("event enemy marker cannot observe changes wholly between client observations", function()
        local env, ply=client(); show(env)
        ply.alive=false; ply.alive=true
        env.map="gm_other"; env.map="gm_construct"
        visible(env)
    end)
    test("event enemy marker copies scalars and never follows or looks up entities", function()
        local env = client()
        local enemy=env.entity("npc_test"); enemy.index=7
        enemy.pos=env.Vector(20000.25,-30000.5,2.125)
        local message=packet(env)
        env.deliver(message)
        message.values[4],message.values[5],message.values[6]="9",999,888
        enemy.pos.x,enemy.pos.y,enemy.valid=999,888,false
        local function forbidden() error("client must not query an enemy, send or schedule work") end
        env.Entity,env.ents.FindByClass,env.ents.FindByName=forbidden,forbidden,forbidden
        env.net.Start,env.timer.Create,enemy.GetPos=forbidden,forbidden,forbidden
        for i=1,3 do
            env.fire("Think")
            local point=visible(env)
            eq(point.x,20000.25); eq(point.y,-30000.5); eq(point.z,2.125)
        end
    end)

    local vectorFailures = {
        {"throws", function() error("Vector constructor failure") end},
        {"rounds a scalar", function(x,y,z,make) return make(math.floor(x),y,z) end},
        {"returns nonfinite", function(x,y,z,make) return make(x,math.huge,z) end},
        {"omits a component", function(x,y,z,make) return make(x,y,nil) end},
        {"returns nil", function() end},
        {"returns a plain table", function(x,y,z) return {x=x,y=y,z=z} end},
    }
    for _, case in ipairs(vectorFailures) do
        test("event enemy marker preserves accepted point when native Vector " .. case[1], function()
            local env=client(); show(env)
            local make=env.Vector
            env.Vector=function(x,y,z) return case[2](x,y,z,make) end
            show(env,{[4]="9"}); visible(env)
        end)
    end
    test("event enemy marker contains native component getter failure", function()
        local env=client(); show(env)
        env.Vector=function() return setmetatable({}, {__index=function() error("component failure") end}) end
        env.isvector=function() return true end
        show(env,{[4]="9"}); visible(env)
    end)
    local projections = {
        {"behind", {x=100,y=100,visible=false}}, {"missing visibility", {x=100,y=100}},
        {"left", {x=-1,y=100,visible=true}}, {"right", {x=1920,y=100,visible=true}},
        {"above", {x=100,y=-1,visible=true}}, {"below", {x=100,y=1080,visible=true}},
        {"NaN coordinate", {x=0/0,y=100,visible=true}}, {"infinite coordinate", {x=100,y=math.huge,visible=true}},
        {"missing coordinate", {y=100,visible=true}}, {"nontable", 10},
    }
    for _, case in ipairs(projections) do
        test("event enemy marker retains fixed status for projection " .. case[1], function()
            local env=client(); show(env); env.projection=case[2]
            local texts,lines=paint(env)
            eq(#texts,2); eq(#lines,0); eq(#env.camCalls,2)
            env.projection=nil; visible(env)
        end)
    end
    test("event enemy marker closes projection context when ToScreen throws", function()
        local env=client(); show(env); env.projectionError=true
        local texts,lines=paint(env)
        eq(#texts,2); eq(#lines,0); eq(#env.camCalls,2)
        env.projectionError=false; visible(env)
    end)
    for _, method in ipairs({"Start3D","End3D"}) do
        test("event enemy marker contains camera " .. method .. " failure", function()
            local env=client(); show(env)
            local original=env.cam[method]
            env.cam[method]=function(...)
                if method == "End3D" then original(...) end
                error("camera failure")
            end
            local texts,lines=paint(env)
            eq(#texts,2); eq(#lines,0)
            env.cam[method]=original; visible(env)
        end)
    end
    test("event enemy marker ends 3D before fixed text or cross drawing", function()
        local env=client(); show(env)
        local line,text=env.surface.DrawLine,env.draw.SimpleText
        env.surface.DrawLine=function(...) eq(env.camDepth,0); line(...) end
        env.draw.SimpleText=function(...) eq(env.camDepth,0); text(...) end
        visible(env)
    end)
    test("event enemy marker bounds long labels and crosses through viewport resizes", function()
        local env=client(); show(env,{[4]="1" .. string.rep("0",63)})
        for _,size in ipairs({{0.5,0.5},{1,1},{7,16},{64,32},{240,120},{320,240},{600,1000},{3440,1440},{1920,1080}}) do
            env.screenWidth,env.screenHeight=size[1],size[2]
            for _,point in ipairs({{x=0,y=0,visible=true},{x=math.max(0,size[1]-1),y=math.max(0,size[2]-1),visible=true}}) do
                env.projection=point
                local texts,lines=paint(env)
                for _,text in ipairs(texts) do
                    local width,height=env.surface.GetTextSize(text.text)
                    assert(text.x>=0 and text.y>=0 and text.x+width<=size[1] and text.y+height<=size[2], "text fits viewport")
                    if size[1]==320 and size[2]==240 then assert(text.y>=136,"status clears encounter progress region") end
                end
                for _,line in ipairs(lines) do
                    assert(line.x1>=0 and line.x2>=0 and line.y1>=0 and line.y2>=0
                        and line.x1<size[1] and line.x2<size[1] and line.y1<size[2] and line.y2<size[2], "cross fits viewport")
                end
                assert(#lines<=2,"only one cross")
            end
        end
    end)
    for _,size in ipairs({{0,1080},{1920,0},{-1,1080},{1920,-1},{math.huge,1080},{1920,0/0}}) do
        test("event enemy marker skips unusable viewport " .. tostring(size[1]) .. "x" .. tostring(size[2]), function()
            local env=client(); show(env)
            env.screenWidth,env.screenHeight=size[1],size[2]
            eq(#paint(env),0); eq(#env.projections,0)
            env.screenWidth,env.screenHeight=1920,1080; visible(env)
        end)
    end

    -- Finite baseline receiver fixture from commit 2dbc37ab56e5aa39263083a817369c863dfd64cf.
    -- This frozen decoder/receiver prefix is intentionally independent of current
    -- production source and repository history. It captures old-client rejection,
    -- not native engine delivery, rendering, or multiplayer timing.
    local baselineReceiverSource = [=[
-- A private, temporary snapshot of a configured base, never a live spawn target.
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
    if not finite(bits) or bits % 1 ~= 0 or bits < 1 or bits > 1889 then return end
    local show = net.ReadBool()
    if show == false then
        if bits == 1 then return false end
        return
    end
    if show ~= true or bits < 337 then return end
    local map, kind, key = net.ReadString(), net.ReadString(), net.ReadString()
    if not boundedString(map, 128) or (kind ~= "enemy" and kind ~= "activator")
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
    -- Reject a lossy or unusable copy; never alter the configured coordinates.
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

return function()
    if not marker then return end
    return marker, (marker.kind == "enemy" and "Enemy" or "Activator") .. " spawn key " .. marker.key .. " - snapshot"
end
]=]
    test("event enemy marker finite old decoder retains its prior legacy marker without mislabeling", function()
        local env=client()
        local chunk
        if _VERSION == "Lua 5.1" then
            chunk=assert(loadstring(baselineReceiverSource,"@baseline-marker-receiver-fixture")); setfenv(chunk,env)
        else
            chunk=assert(load(baselineReceiverSource,"@baseline-marker-receiver-fixture","t",env))
        end
        local snapshot=chunk()
        for _,kind in ipairs({"enemy","activator"}) do
            env.deliver(packet(env,{[3]=kind,[4]="2"}))
            local old,label=snapshot()
            assert(old,"fixture accepts a legacy control packet")
            eq(old.kind,kind); eq(old.key,"2"); eq(old.position.x,20000.25)
            eq(label,(kind == "enemy" and "Enemy" or "Activator") .. " spawn key 2 - snapshot")
            local reads=env.netReads
            env.deliver(packet(env,{[4]="9",[5]=-99.5}),nil,nil,true)
            eq(env.netReads-reads,4,"old decoder stops at unknown event_enemy kind before doubles")
            local retained,retainedLabel=snapshot()
            eq(retained,old,"unknown kind cannot replace the prior marker")
            eq(retainedLabel,label,"unknown kind cannot be mislabeled as a configured base")
            clear(env)
            eq(snapshot(),nil,"unchanged one-bit clear also clears an old client")
        end
    end)
end
