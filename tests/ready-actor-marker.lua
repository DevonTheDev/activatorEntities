-- Actual server/client hooks in finite host-Lua doubles, not native engine QA.
return function(gmod, test, eq)
    local command, channel = "!markNearestActivator", "ActivatorSpawnMarker"
    local upvalue = dofile("tests/find-upvalue.lua")
    local function setup(count)
        local env = gmod.new(); local admin = env.entity("player"); admin.admin = true
        local actors = {}
        for i=1,count or 3 do
            local actor = env.entity("activatorent")
            actor.EventIdentifier="Raid"; actor:Spawn()
            actor.index, actor.pos = 100+i, env.Vector(i, 0, 0)
            actors[i] = actor
        end
        env.now = 100
        return env, admin, actors
    end
    local function mark(env, admin, text)
        eq(env.fire("PlayerSay", admin, text or command), "", "recognized command stays private")
    end
    local function packets(env)
        local messages = {}
        for _, message in ipairs(env.messages) do
            if message.name == channel then messages[#messages+1] = message end
        end
        return messages
    end
    local function sent(env, admin, index)
        local messages = packets(env); eq(#messages, 1, "one private packet")
        local message = messages[1]
        eq(message.player, admin); eq(message.broadcast, nil); eq(message.unreliable, false)
        eq(message.values[1], true); eq(message.values[2], env.map)
        eq(message.values[3], "ready_actor"); eq(message.values[4], tostring(index or 101))
        eq(message.values[8], 115); eq(#message.fields, 8)
        eq(env.packetBits(message), 1+8*(#env.map+11+#message.values[4]+3)+256)
        return message
    end
    local function refused(env, admin, text)
        local before = #packets(env)
        mark(env, admin, text); eq(#packets(env), before, "refusal preserves prior marker")
        for _, line in ipairs(admin and admin.chats or {}) do
            assert(#line <= 255 and not line:find("%c"), "bounded private feedback")
        end
    end
    local function once(object, key, callback)
        local original, entered = object[key], false
        object[key] = function(...)
            object[key], entered = original, true
            callback()
            return original(...)
        end
        return function() assert(entered, "controlled getter exercised: " .. key) end
    end
    local function state(env, name)
        for _, hooks in pairs(env.hooks) do
            for _, callback in pairs(hooks) do
                local ok, result = pcall(upvalue, callback, name)
                if ok then return result end
            end
        end
        error("missing state " .. name)
    end
    local function paint(env)
        env.drawCalls, env.projections = {}, {}
        env.fire("HUDPaint")
        local texts = {}
        for _, call in ipairs(env.drawCalls) do
            if call.kind == "text" then texts[#texts+1] = call.text end
        end
        return texts
    end
    local function client(server, message)
        local env = gmod.new(true); env.localPlayer = env.entity("player")
        env.localPlayer.admin, env.now, env.realNow = true, server.now, 1000
        env.deliver(message)
        return env
    end

    -- This is the sole pre-implementation red: absent production routing.
    test("ready actor marker exact request privately sends nearest actual point", function()
        local env, admin = setup(); mark(env, admin)
        local message = sent(env, admin); eq(message.values[5], 1)
        eq(message.values[6], 0); eq(message.values[7], 0)
    end)
    test("ready actor marker shared hook yields before requester getters", function()
        local env, admin = setup()
        admin.IsPlayer = function() error("shared hook must not call this") end
        eq(env.hooks.PlayerSay.setUpSpawnPoints(admin, command), nil)
        eq(env.hooks.PlayerSay.setUpSpawnPoints(admin, command .. " 1"), nil)
    end)
    test("ready actor marker near matches remain ordinary chat", function()
        local env, admin = setup()
        for _, text in ipairs({"!markNearestActivatorMore", "!marknearestactivator", " " .. command,
            "hello " .. command, "!MarkNearestActivator", "ordinary"}) do
            eq(env.fire("PlayerSay", admin, text), nil)
        end
        eq(#admin.chats, 0); eq(#packets(env), 0)
    end)
    for _, suffix in ipairs({" ", "\t", " 1", "\n", " extra", " 1 2"}) do
        test("ready actor marker malformed suffix " .. string.format("%q", suffix), function()
            local env, admin = setup()
            env.ents.FindByClass = function() error("malformed request scanned") end
            refused(env, admin, command .. suffix)
            eq(admin.chats[1], "Usage: !markNearestActivator (no arguments).")
        end)
    end
    for _, guard in ipairs({"invalid", "nonplayer", "nonadmin", "dead", "throwing admin", "throwing alive"}) do
        test("ready actor marker refuses requester " .. guard, function()
            local env, admin = setup()
            if guard == "invalid" then admin.valid=false
            elseif guard == "nonplayer" then admin.IsPlayer=function() return false end
            elseif guard == "nonadmin" then admin.admin=false
            elseif guard == "dead" then admin.alive=false
            elseif guard == "throwing admin" then admin.IsAdmin=function() error("private") end
            else admin.Alive=function() error("private") end end
            refused(env, admin)
        end)
    end
    test("ready actor marker nil requester is contained and private", function()
        local env = setup(); mark(env, nil); eq(#packets(env), 0)
    end)
    for _, bad in ipairs({"empty", "control", "long", "throw", "nan time", "infinite time", "unrepresentable expiry"}) do
        test("ready actor marker refuses map or expiry " .. bad, function()
            local env, admin = setup()
            if bad == "empty" then env.map=""
            elseif bad == "control" then env.map="gm_\n"
            elseif bad == "long" then env.map=string.rep("m",129)
            elseif bad == "throw" then env.game.GetMap=function() error("private") end
            elseif bad == "nan time" then env.now=0/0
            elseif bad == "infinite time" then env.now=math.huge
            else env.now=1e300 end
            refused(env, admin)
        end)
    end
    test("ready actor marker refuses active encounter without reading actors", function()
        local env = gmod.new(); local admin = env.start(); admin.admin=true
        env.ents.FindByClass=function() error("active encounter scanned") end
        refused(env, admin)
    end)
    test("ready actor marker captures fresh manual actors with no health or configuration claim", function()
        local env, admin, actors = setup()
        actors[2].pos=env.Vector(0,0,0); actors[2].NPCInfo=false
        env.NPCEdits, env.SpawnPositions, env.activatorCount=false, false, 987
        for _, actor in ipairs(actors) do actor.Health=function() error("health read") end end
        mark(env, admin); sent(env, admin, 102); eq(env.activatorCount, 987)
        env.messages={}; actors[3].pos=env.Vector(-0.1,0,0); actors[2].pos=env.Vector(100,0,0)
        mark(env,admin); sent(env,admin,103)
    end)
    test("ready actor marker uses unrounded 3D distance and numeric index ties", function()
        local env, admin, actors=setup()
        actors[1].pos=env.Vector(0.49,0,0); actors[2].pos=env.Vector(0,0,-0.41)
        actors[3].pos=env.Vector(0,0,0.41); actors[3].index=9
        mark(env,admin); local message=sent(env,admin,9); eq(message.values[7],0.41)
    end)
    test("ready actor marker copies list and reads each native position once", function()
        local env, admin, actors=setup(); local list={actors[1],actors[2],actors[3],actors[1]}
        env.ents.FindByClass=function() return list end
        local reads={}; local origin=admin.GetPos
        admin.GetPos=function(self) reads.origin=(reads.origin or 0)+1; return origin(self) end
        for i,actor in ipairs(actors) do
            local original=actor.GetPos
            actor.GetPos=function(self)
                reads[i]=(reads[i] or 0)+1
                if i==1 then list[2],list[3]=nil,nil; admin.pos=env.Vector(999,0,0) end
                return original(self)
            end
        end
        mark(env,admin); sent(env,admin)
        eq(reads.origin,1); for i=1,3 do eq(reads[i],1) end
    end)
    test("ready actor marker omits invalid deleting actors but refuses empty ready scan", function()
        local env,admin,actors=setup()
        actors[1].valid=false; actors[2].markedForDeletion=true
        env.ents.FindByClass=function() return actors end
        mark(env,admin); sent(env,admin,103)
        env.messages={}; actors[3].valid=false; refused(env,admin)
    end)
    for _, subject in ipairs({"requester", "nearest", "farther"}) do
        for _, bad in ipairs({"throw", "nonvector", "nan", "infinite"}) do
            test("ready actor marker refuses " .. subject .. " position " .. bad, function()
                local env,admin,actors=setup()
                local entity=subject=="requester" and admin or actors[subject=="nearest" and 1 or 3]
                if bad=="throw" then entity.GetPos=function() error("private") end
                elseif bad=="nonvector" then entity.GetPos=function() return {x=0,y=0,z=0} end
                else entity.pos=env.Vector(0,bad=="nan" and 0/0 or math.huge,0) end
                refused(env,admin)
            end)
        end
    end
    test("ready actor marker refuses unrepresentable distance rather than farther selection", function()
        local env,admin,actors=setup(); admin.pos=env.Vector(-1e308,0,0)
        actors[3].pos=env.Vector(1e308,0,0); refused(env,admin)
    end)
    test("ready actor marker stable scaled distance handles finite large coordinates", function()
        local env,admin,actors=setup(); actors[1].pos=env.Vector(1e200,1e200,0)
        actors[2].pos=env.Vector(2e200,0,0); actors[3].pos=env.Vector(3e200,0,0)
        mark(env,admin); sent(env,admin)
    end)
    for _, bad in ipairs({"zero", "fraction", "infinite", "throw", "changed"}) do
        test("ready actor marker refuses selected index " .. bad, function()
            local env,admin,actors=setup()
            if bad=="zero" then actors[1].index=0
            elseif bad=="fraction" then actors[1].index=1.5
            elseif bad=="infinite" then actors[1].index=math.huge
            elseif bad=="throw" then actors[1].EntIndex=function() error("private") end
            else once(actors[1],"GetPos",function() actors[1].index=999 end) end
            env.Entity=function() error("replacement lookup forbidden") end
            refused(env,admin)
        end)
    end
    for _, transition in ipairs({"map", "death", "admin", "selected invalid", "farther deleting", "start", "stop cycle"}) do
        test("ready actor marker refuses captured transition " .. transition, function()
            local env,admin,actors=setup()
            local exercised=once(actors[3],"GetPos",function()
                if transition=="map" then env.map="gm_other"
                elseif transition=="death" then admin.alive=false
                elseif transition=="admin" then admin.admin=false
                elseif transition=="selected invalid" then actors[1].valid=false
                elseif transition=="farther deleting" then actors[2].markedForDeletion=true
                else local player=env.start(); player.admin=true
                    if transition=="stop cycle" then env.fire("PlayerSay",player,"!stopEvent") end
                end
            end)
            refused(env,admin); exercised()
        end)
    end
    for _, where in ipairs({"IsAdmin", "GetPos", "actor position", "actor deletion", "actor index", "map", "clock"}) do
        test("ready actor marker newer mark wins during " .. where, function()
            local env,admin,actors=setup(); local object,key=admin,where
            if where=="actor position" then object,key=actors[1],"GetPos"
            elseif where=="actor deletion" then object,key=actors[1],"IsMarkedForDeletion"
            elseif where=="actor index" then object,key=actors[1],"EntIndex"
            elseif where=="map" then object,key=env.game,"GetMap"
            elseif where=="clock" then object,key=env,"CurTime" end
            local exercised=once(object,key,function() actors[3].pos=env.Vector(0,0,0); mark(env,admin) end)
            mark(env,admin); exercised(); sent(env,admin,103)
            eq(#admin.chats,1,"older request produces no feedback")
        end)
    end
    for _, action in ipairs({"!clearSpawnMarker", "!clearEventEnemyMarker", "!markSpawn enemy 1", "!markEventEnemy 1",
        "!listSpawns enemy", "!nearSpawns activator", "!listEventEnemies", "!nearEventEnemies", "disconnect", "initialize"}) do
        test("ready actor marker owner retirement by " .. action, function()
            local env,admin,actors=setup()
            local exercised=once(actors[1],"GetPos",function()
                if action=="disconnect" then env.fire("PlayerDisconnected",admin)
                elseif action=="initialize" then env.fire("Initialize")
                else env.fire("PlayerSay",admin,action) end
            end)
            mark(env,admin); exercised()
            for _,message in ipairs(packets(env)) do eq(message.values[1],false,"only newer clear may send") end
            for _,line in ipairs(admin.chats) do assert(not line:find("actor position snapshot",1,true)) end
        end)
    end
    test("ready actor marker does not replace a captured object by recycled index", function()
        local env,admin,actors=setup()
        once(actors[1],"GetPos",function()
            actors[1].valid=false; local replacement=env.entity("activatorent")
            replacement.index=101; replacement.pos=env.Vector(0,0,0)
        end)
        env.Entity=function() error("replacement lookup") end; refused(env,admin)
    end)
    test("ready actor marker leaves catalogue leases ready requests config and Use Start authority unchanged", function()
        local env,admin,actors=setup()
        env.fire("PlayerSay",admin,"!listSpawns activator")
        local inspections=state(env,"spawnInspections"); local lease=inspections[admin]
        local readyRequests=state(env,"readyActivatorRequests"); local sentinel={}; readyRequests[admin]=sentinel
        local config,positions,timers=env.NPCEdits,env.SpawnPositions,env.timers
        local schedule=timers.activatorSpawner
        mark(env,admin); sent(env,admin)
        eq(inspections[admin],lease); eq(readyRequests[admin],sentinel)
        eq(env.NPCEdits,config); eq(env.SpawnPositions,positions); eq(env.timers,timers)
        eq(timers.activatorSpawner,schedule); eq(#actors,3)
        env.receive("SendNPCInformation",admin,"Raid"); eq(env.totalEnemies,0,"marker is no interaction grant")
        local player,actor=env.ready(); actor:AcceptInput("Use",player,player)
        env.receive("SendNPCInformation",player,"Raid"); eq(env.totalEnemies,5,"ordinary Use Start still works")
    end)
    test("ready actor marker actual wire reaches truthful client label and detached point", function()
        local env,admin,actors=setup(); mark(env,admin); local message=sent(env,admin)
        local view=client(env,message); actors[1].pos=env.Vector(1000,0,0); actors[1].valid=false
        local texts=paint(view)
        eq(texts[1],"Activator actor index 101 - position snapshot")
        assert(texts[2]:find("actor may move or disappear",1,true))
        assert(texts[2]:find("!clearSpawnMarker",1,true)); eq(view.projections[1].x,1)
        eq(#view.messages,0); eq(next(view.timers),nil)
        refused(env,admin,command .. " 1"); eq(paint(view)[1],texts[1])
    end)
    for _, reason in ipairs({"expiry", "real expiry", "death", "admin", "map", "reload", "initialize", "clear"}) do
        test("ready actor marker client cleanup " .. reason, function()
            local env,admin=setup(); mark(env,admin); local view=client(env,sent(env,admin))
            if reason=="expiry" then view.now=115
            elseif reason=="real expiry" then view.realNow=1015
            elseif reason=="death" then view.localPlayer.alive=false
            elseif reason=="admin" then view.localPlayer.admin=false
            elseif reason=="map" then view.map="gm_other"
            elseif reason=="reload" then view.fire("OnReloaded")
            elseif reason=="initialize" then view.fire("Initialize")
            else env.fire("PlayerSay",admin,"!clearSpawnMarker"); local messages=packets(env)
                eq(env.packetBits(messages[2]),1); view.deliver(messages[2]) end
            eq(#paint(view),0)
        end)
    end
    test("ready actor marker uses unchanged envelope cap and rejects malformed packets", function()
        local env,admin=setup(); mark(env,admin); local message=sent(env,admin)
        local view=client(env,message); local label=paint(view)[1]
        for _,bits in ipairs({0,1906,1913,view.packetBits(message)-8}) do
            view.deliver(message,nil,bits,true); eq(paint(view)[1],label)
        end
        message.values[3]="ready_actor_extra"; view.deliver(message,nil,nil,true); eq(paint(view)[1],label)
        message.values[3]="ready_actor"; message.values[5]=math.huge
        view.deliver(message,nil,nil,true); eq(paint(view)[1],label)
        message.values[2],message.values[4],message.values[5]=string.rep("m",128),"1"..string.rep("0",63),1
        view.map=message.values[2]; eq(view.packetBits(message),1905)
        view.deliver(message); assert(paint(view)[1]:find("Activator actor index",1,true))
    end)
    test("ready actor marker shares slot while legacy base and enemy labels retain their bytes", function()
        local env,admin=setup(); mark(env,admin); local message=sent(env,admin); local view=client(env,message)
        for _,kind in ipairs({"enemy","activator","event_enemy"}) do
            message.values[3]=kind; view.deliver(message)
            local expected=kind=="event_enemy" and "Encounter enemy index 101 - position snapshot"
                or (kind=="enemy" and "Enemy" or "Activator") .. " spawn key 101 - snapshot"
            eq(paint(view)[1],expected)
            message.values[3]="ready_actor"; view.deliver(message)
            eq(paint(view)[1],"Activator actor index 101 - position snapshot")
        end
    end)
end
