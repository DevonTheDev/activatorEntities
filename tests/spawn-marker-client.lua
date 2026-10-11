-- These are API-input/decision checks, not native packet or pixel tests.
return function(gmod, test, eq)
    local channel = "ActivatorSpawnMarker"
    local function client()
        local env = gmod.new(true)
        assert(env.receivers[channel], "spawn marker client receiver is missing")
        local owner = env.entity("player")
        owner.admin = true
        env.localPlayer = owner
        env.now, env.realNow = 100, 1000
        return env, owner
    end
    local function packet(env, changes)
        local values = {true, env.map, "enemy", "2", 20000.25, -30000.5, 2.125, env.now+15}
        for key, value in pairs(changes or {}) do values[key] = value end
        local fields = {{kind="bool"}, {kind="string"}, {kind="string"}, {kind="string"},
            {kind="double"}, {kind="double"}, {kind="double"}, {kind="double"}}
        return {name=channel, values=values, fields=fields}
    end
    local function show(env, changes)
        env.deliver(packet(env, changes), nil, nil, true)
    end
    local function clear(env, bits)
        env.deliver({name=channel, values={false}, fields={{kind="bool"}}}, nil, bits, true)
    end
    local function paint(env)
        env.drawCalls, env.projections, env.camCalls = {}, {}, {}
        env.fire("HUDPaint")
        eq(env.camDepth, 0, "projection context closes before another HUD hook")
        local texts, lines = {}, {}
        for _, call in ipairs(env.drawCalls) do
            if call.kind == "text" then texts[#texts+1] = call
            elseif call.kind == "line" then lines[#lines+1] = call end
        end
        return texts, lines
    end
    local function visible(env, key, kind)
        local texts, lines = paint(env)
        eq(#lines, 2, "one cross has two strokes")
        assert(#texts >= 2, "snapshot label and fixed help are visible")
        local label = (kind == "activator" and "Activator" or "Enemy") .. " spawn key " .. (key or "2")
        assert(texts[1].text:find(label, 1, true), "literal key and kind identify the snapshot")
        assert(texts[1].text:find("snapshot", 1, true), "historical snapshot is labelled")
        assert(texts[2].text:find("15", 1, true) and texts[2].text:find("turn", 1, true)
            and texts[2].text:find("!clearSpawnMarker", 1, true), "fixed help explains lifetime, turning and clear")
        eq(#env.messages, 0, "client sends no network traffic")
        eq(#env.panels, 0, "marker creates no input or panel")
        return env.projections[1]
    end
    local function absent(env)
        local texts, lines = paint(env)
        eq(#texts, 0, "no marker labels remain")
        eq(#lines, 0, "no cross remains")
        eq(#env.projections, 0, "no obsolete position is projected")
    end

    test("spawn marker client loads quietly without a local player", function()
        local env = gmod.new(true)
        assert(env.receivers[channel], "spawn marker client receiver is missing")
        env.fire("Think"); absent(env)
        eq(#env.messages, 0); eq(#env.panels, 0); eq(next(env.timers), nil)
    end)

    for _, kind in ipairs({"enemy", "activator"}) do
        for _, key in ipairs({"2", "9007199254740993", "1e+30"}) do
            test("spawn marker client labels exact " .. kind .. " token " .. key, function()
                local env = client()
                show(env, {[3]=kind, [4]=key})
                local position = visible(env, key, kind)
                eq(position.x, 20000.25); eq(position.y, -30000.5); eq(position.z, 2.125)
                eq(#env.camCalls, 2); eq(env.camCalls[1].name, "Start3D")
                eq(#env.camCalls[1].args, 0, "uses default 3D projection")
                eq(env.camCalls[2].name, "End3D")
            end)
        end
    end

    test("spawn marker client replaces one snapshot and clear is idempotent", function()
        local env = client()
        show(env); visible(env)
        show(env, {[3]="activator", [4]="7", [5]=-12.25})
        eq(visible(env, "7", "activator").x, -12.25)
        show(env, {[3]="activator", [4]="7", [5]=-12.25})
        visible(env, "7", "activator")
        clear(env); absent(env); clear(env); absent(env)
        eq(#env.messages, 0)
    end)

    local invalid = {
        {"empty map", 2, ""}, {"map longer than 128 bytes", 2, string.rep("a",129)},
        {"map mismatch", 2, "gm_other"}, {"map newline", 2, "gm_construct\n"},
        {"map NUL", 2, "gm_construct\0"}, {"map DEL", 2, "gm_construct\127"},
        {"unknown kind", 3, "npc"}, {"kind control", 3, "enemy\n"},
        {"empty key", 4, ""}, {"key longer than 64 bytes", 4, string.rep("1",65)},
        {"nonnumeric key", 4, "key"}, {"zero key", 4, "0"}, {"negative key", 4, "-2"},
        {"fractional key", 4, "2.5"}, {"infinite key", 4, "1e999"},
        {"key whitespace", 4, " 2"}, {"key NUL", 4, "2\0"},
        {"key newline", 4, "2\n"}, {"key DEL", 4, "2\127"},
        {"x NaN", 5, 0/0}, {"x positive infinity", 5, math.huge},
        {"y negative infinity", 6, -math.huge}, {"z NaN", 7, 0/0},
        {"expiry NaN", 8, 0/0}, {"expiry positive infinity", 8, math.huge},
        {"expired", 8, 99}, {"expires now", 8, 100}, {"beyond clock tolerance", 8, 116.0001},
    }
    for _, case in ipairs(invalid) do
        test("spawn marker client preserves accepted marker on " .. case[1], function()
            local env = client(); show(env)
            show(env, {[case[2]]=case[3], [5]=case[2] == 5 and case[3] or 99})
            eq(visible(env).x, 20000.25)
        end)
    end

    test("spawn marker client accepts bounded map key and clock tolerance", function()
        local env = client()
        env.map = string.rep("a", 128)
        local key = "1" .. string.rep("0", 63)
        show(env, {[3]="activator", [4]=key, [8]=116})
        visible(env, key, "activator")
        env.now, env.realNow = 100, 1015
        env.fire("Think"); absent(env)
    end)

    for _, length in ipairs({-1, 0, 0.5, 1890, math.huge, -math.huge, 0/0}) do
        test("spawn marker client rejects invalid callback length " .. tostring(length) .. " before reading", function()
            local env = client(); show(env)
            local before = env.netReads
            env.deliver(packet(env, {[4]="7"}), nil, length, true)
            eq(env.netReads, before, "invalid envelope cannot consume any field")
            visible(env)
        end)
    end
    for _, offset in ipairs({-256, -64, -1, 1, 7, 8, 64}) do
        test("spawn marker client rejects truncated or trailing show length " .. offset, function()
            local env = client(); show(env)
            local message = packet(env, {[4]="7"})
            env.deliver(message, nil, env.packetBits(message)+offset, true)
            visible(env)
        end)
    end
    for _, length in ipairs({0, 2, 8, 65, 1889}) do
        test("spawn marker client rejects malformed clear length " .. length, function()
            local env = client(); show(env); clear(env, length); visible(env)
        end)
    end
    test("spawn marker client rejects missing double fields even when a reader returns zero", function()
        local env = client(); show(env)
        local message = packet(env, {[4]="7"})
        local doubles = 0
        env.net.ReadDouble = function() doubles=doubles+1; return 0 end
        env.deliver(message, nil, env.packetBits(message)-64, true)
        eq(doubles, 0, "payload size is checked before zero-returning truncated reads")
        visible(env)
    end)
    test("spawn marker client contains typed field order and reader errors", function()
        local env = client(); show(env)
        local message = packet(env, {[4]="7"})
        message.fields[5].kind = "string"
        env.deliver(message, nil, env.packetBits(packet(env)), true)
        visible(env)
        env.net.ReadString = function() error("synthetic decoder failure") end
        env.deliver(packet(env), nil, env.packetBits(packet(env)), true)
        visible(env)
    end)
    test("spawn marker client rejects nonboolean show discriminator", function()
        local env = client(); show(env)
        env.net.ReadBool = function() return 1 end
        env.deliver(packet(env, {[4]="7"}), nil, nil, true)
        visible(env)
    end)

    local admission = {
        {"missing local player", function(env) env.localPlayer=nil end},
        {"invalid local player", function(env, ply) ply.valid=false end},
        {"nonplayer local entity", function(env) env.localPlayer=env.entity("worldspawn"); env.localPlayer.admin=true end},
        {"dead local player", function(env, ply) ply.alive=false end},
        {"nonadmin local player", function(env, ply) ply.admin=false end},
        {"nonfinite CurTime", function(env) env.now=0/0 end},
        {"nonfinite RealTime", function(env) env.realNow=math.huge end},
        {"nonincreasing RealTime deadline", function(env) env.realNow=1e308 end},
    }
    for _, case in ipairs(admission) do
        test("spawn marker client declines admission for " .. case[1], function()
            local env, ply = client()
            local message = packet(env)
            case[2](env, ply)
            env.deliver(message, nil, nil, true)
            env.localPlayer, ply.valid, ply.alive, ply.admin = ply, true, true, true
            env.now, env.realNow = 100, 1000
            absent(env)
        end)
    end

    for _, event in ipairs({"Think", "HUDPaint"}) do
        local cleanup = {
            {"owner missing", function(env) env.localPlayer=nil end},
            {"owner invalid", function(env, ply) ply.valid=false end},
            {"owner replaced", function(env) env.localPlayer=env.entity("player"); env.localPlayer.admin=true end},
            {"owner dead", function(env, ply) ply.alive=false end},
            {"owner demoted", function(env, ply) ply.admin=false end},
            {"map changed", function(env) env.map="gm_other" end},
            {"game expiry", function(env) env.now=115 end},
            {"real expiry while server paused", function(env) env.realNow=1015 end},
            {"game clock invalid", function(env) env.now=0/0 end},
            {"real clock invalid", function(env) env.realNow=-math.huge end},
            {"game clock reversed", function(env) env.now=99 end},
            {"real clock reversed", function(env) env.realNow=999 end},
        }
        for _, case in ipairs(cleanup) do
            test("spawn marker client " .. event .. " permanently discards " .. case[1], function()
                local env, ply = client(); show(env)
                case[2](env, ply); env.fire(event)
                env.localPlayer, ply.valid, ply.alive, ply.admin = ply, true, true, true
                env.map, env.now, env.realNow = "gm_construct", 100, 1000
                env.fire("Think"); absent(env)
            end)
        end
    end
    test("spawn marker client delayed packet keeps only its remaining lifetime", function()
        local env = client(); local message = packet(env)
        env.now = 113
        env.deliver(message); visible(env)
        env.realNow = 1002
        env.fire("Think"); absent(env)
    end)
    test("spawn marker client rendering and Think never renew expiry", function()
        local env = client(); show(env)
        for second=1,14 do
            env.now, env.realNow = 100+second, 1000+second
            env.fire("Think"); visible(env)
        end
        env.now, env.realNow = 115, 1015
        env.fire("Think"); absent(env)
    end)
    test("spawn marker client Think does not override other hooks or the gamemode", function()
        local env = client(); show(env)
        for _, callback in pairs(env.hooks.Think) do
            eq(callback(), nil, "Think callbacks must not suppress unrelated hooks")
        end
        visible(env)
    end)
    for _, event in ipairs({"Initialize", "OnReloaded"}) do
        test("spawn marker client clears on " .. event, function()
            local env = client(); show(env); env.fire(event); absent(env)
        end)
    end
    test("spawn marker client repeated autorun load starts empty with one set of hooks", function()
        local env = client(); show(env)
        env.include("autorun/client/cl_activator_spawn_marker.lua")
        absent(env); show(env); visible(env)
    end)

    local vectorFailures = {
        {"throws", function() error("synthetic Vector construction failure") end},
        {"rounds a scalar", function(x,y,z,make) return make(math.floor(x),y,z) end},
        {"returns nonfinite", function(x,y,z,make) return make(x,math.huge,z) end},
        {"returns missing component", function(x,y,z,make) return make(x,y,nil) end},
        {"returns nil", function() end},
        {"throws on component read", function() return setmetatable({}, {__index=function() error("component failure") end}) end},
    }
    for _, case in ipairs(vectorFailures) do
        test("spawn marker client preserves accepted snapshot when Vector " .. case[1], function()
            local env = client(); show(env)
            local make = env.Vector
            env.Vector = function(x,y,z) return case[2](x,y,z,make) end
            show(env, {[4]="7"})
            visible(env)
        end)
    end
    test("spawn marker client keeps detached coordinates after packet mutation", function()
        local env = client(); local message = packet(env)
        env.deliver(message)
        message.values[4], message.values[5], message.values[6] = "7", 999, 888
        local point = visible(env)
        eq(point.x, 20000.25); eq(point.y, -30000.5)
    end)

    local projections = {
        {"behind", {x=100,y=100,visible=false}}, {"missing visibility", {x=100,y=100}},
        {"left", {x=-1,y=100,visible=true}}, {"right", {x=1920,y=100,visible=true}},
        {"above", {x=100,y=-1,visible=true}}, {"below", {x=100,y=1080,visible=true}},
        {"nonfinite x", {x=0/0,y=100,visible=true}}, {"nonfinite y", {x=100,y=math.huge,visible=true}},
        {"missing coordinate", {y=100,visible=true}}, {"nontable result", 10},
    }
    for _, case in ipairs(projections) do
        test("spawn marker client keeps fixed status without a cross for projection " .. case[1], function()
            local env = client(); show(env); env.projection=case[2]
            local texts, lines = paint(env)
            eq(#lines, 0); eq(#texts, 2); eq(#env.camCalls, 2)
            env.projection=nil; visible(env)
        end)
    end
    test("spawn marker client contains projection failures and closes the 3D context", function()
        local env = client(); show(env); env.projectionError=true
        local texts, lines = paint(env)
        eq(#texts, 2); eq(#lines, 0); eq(#env.camCalls, 2)
        env.projectionError=false; visible(env)
    end)
    test("spawn marker client ends projection context before any 2D drawing", function()
        local env = client(); show(env)
        local line, text = env.surface.DrawLine, env.draw.SimpleText
        env.surface.DrawLine = function(...) eq(env.camDepth,0); line(...) end
        env.draw.SimpleText = function(...) eq(env.camDepth,0); text(...) end
        visible(env)
    end)
    for _, dimensions in ipairs({{0,1080},{1920,0},{-1,1080},{1920,-1},{math.huge,1080},{1920,0/0}}) do
        test("spawn marker client skips invalid viewport " .. tostring(dimensions[1]) .. "x" .. tostring(dimensions[2]), function()
            local env = client(); show(env)
            env.screenWidth, env.screenHeight = dimensions[1], dimensions[2]
            eq(#paint(env), 0); eq(#env.projections, 0)
            env.screenWidth, env.screenHeight = 1920,1080
            visible(env)
        end)
    end
    test("spawn marker client keeps narrow-screen status below active progress", function()
        local env = client(); show(env)
        env.screenWidth, env.screenHeight = 320,240
        local texts = paint(env)
        eq(#texts, 2, "both compact status lines fit the narrow viewport")
        for _, text in ipairs(texts) do
            assert(text.y >= 136, "status clears existing progress region y16..136")
            local width,height = env.surface.GetTextSize(text.text)
            assert(text.x >= 0 and text.x+width <= 320 and text.y+height <= 240,
                "bottom status remains inside the narrow screen")
        end
    end)
    test("spawn marker client bounds text and cross across tiny narrow wide and resized screens", function()
        local env = client(); show(env, {[4]="1" .. string.rep("0",63)})
        for _, size in ipairs({{0.5,0.5},{1,1},{7,16},{64,32},{240,120},{320,240},{600,1000},{3440,1440},{1920,1080}}) do
            env.screenWidth, env.screenHeight = size[1],size[2]
            env.projection={x=0,y=0,visible=true}
            local texts, lines = paint(env)
            for _, text in ipairs(texts) do
                local width,height = env.surface.GetTextSize(text.text)
                assert(text.x >= 0 and text.y >= 0 and text.x+width <= size[1]
                    and text.y+height <= size[2], "measured status remains in viewport")
            end
            for _, line in ipairs(lines) do
                assert(line.x1 >= 0 and line.x2 >= 0 and line.y1 >= 0 and line.y2 >= 0
                    and line.x1 < size[1] and line.x2 < size[1]
                    and line.y1 < size[2] and line.y2 < size[2], "cross strokes remain in viewport")
            end
            assert(#lines <= 2, "at most one cross")
        end
        eq(#env.panels,0); eq(#env.messages,0)
    end)
end
