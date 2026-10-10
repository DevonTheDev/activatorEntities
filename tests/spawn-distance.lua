-- Public list output is a server-side snapshot of configured bases. These
-- doubles exercise text and ownership, not native ChatPrint or world placement.
return function(gmod,test,eq)
    local kinds={
        {name="enemy",field="enemySpawnPositions",remove="!removeEnemySpawn",move="!moveEnemySpawn"},
        {name="activator",field="activatorSpawnPositions",remove="!removeActivatorSpawn",move="!moveActivatorSpawn"},
    }
    local function setup(kind)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local positions={[2]=env.Vector(3,4,12),[9]=env.Vector(0,0,-13)}
        env.SpawnPositions[1][kind.field]=positions
        return env,admin,positions
    end
    local function inspect(env,admin,kind,page)
        local before={}
        for _,player in ipairs(env.player.GetAll()) do before[player]=#player.chats end
        eq(env.fire("PlayerSay",admin,"!listSpawns " .. kind.name .. (page and " " .. page or "")),"","private command")
        local lines,rows={},{}
        for i=before[admin]+1,#admin.chats do
            local line=admin.chats[i]; assert(#line <= 255,"bounded ChatPrint bytes")
            lines[#lines+1]=line
            if line:match("^Key ") then
                local key,x,y,z,suffix=line:match("^Key ([^:]+): x=([^,]+), y=([^,]+), z=([^;]+); (.+)$")
                assert(key and suffix,"retain exact coordinates and add a distance suffix")
                rows[#rows+1]={key=key,x=x,y=y,z=z,suffix=suffix,line=line}
            end
        end
        assert(#lines <= 10,"at most eight rows and two framing lines")
        for player,count in pairs(before) do
            if player ~= admin then eq(#player.chats,count,"private output for requester only") end
        end
        return rows,lines
    end
    local function distance(row)
        local value=row.suffix:match("^~([^ ]+) units away$")
        assert(value,"approximate Source-unit distance: " .. row.suffix)
        local number=tonumber(value)
        assert(number and number == number and number >= 0 and number < math.huge,"finite display distance")
        return number
    end
    local function close(actual,expected)
        assert(math.abs(actual/expected-1) < 0.00001,"distance approximation differs from " .. tostring(expected))
    end

    for _,kind in ipairs(kinds) do
        test(kind.name .. " list shows 3D and vertical distances to stored bases at list time",function()
            local env,admin,positions=setup(kind)
            local rows,lines=inspect(env,admin,kind)
            eq(#rows,2); eq(rows[1].key,"2"); eq(rows[2].key,"9")
            eq(distance(rows[1]),13); eq(distance(rows[2]),13)
            eq(tonumber(rows[1].x),3); eq(tonumber(rows[1].y),4); eq(tonumber(rows[1].z),12)
            assert(lines[1]:find("stored bases",1,true),"identify base positions")
            assert(lines[1]:find("list time",1,true),"identify snapshot timing")
            assert(lines[1]:find("3D Source units",1,true),"identify distance dimension and unit")
            if kind.name == "enemy" then
                assert(lines[#lines]:find("cumulatively",1,true),"explain advancing enemy offset")
                assert(lines[#lines]:find("(30,30,0)",1,true),"name per-creation offset")
            end
            local original=positions[2]; admin:SetPos(env.Vector(3,4,12))
            local moved=inspect(env,admin,kind)
            eq(distance(moved[1]),0); close(distance(moved[2]),math.sqrt(650))
            for i,row in ipairs(rows) do
                for _,field in ipairs({"key","x","y","z"}) do eq(moved[i][field],row[field],"movement preserves exact token") end
            end
            assert(rawequal(positions[2],original)); eq(original.x,3); eq(original.y,4); eq(original.z,12)
            eq(env.fire("PlayerSay",admin,kind.remove .. " 2"),""); eq(positions[2],nil,"moving does not invalidate the list grant")
        end)
        test(kind.name .. " list captures one native position and copies its scalars for every row",function()
            local env,admin,positions=setup(kind); local origin=env.Vector(0,0,0)
            local calls,copies,mutated=0,0,false
            admin.GetPos=function() calls=calls+1; return origin end
            env.Vector=function() copies=copies+1; error("listing does not construct a Vector") end
            env.tostring=function(value)
                if calls == 1 and not mutated and value == 3 then origin.x=1000; mutated=true end
                return tostring(value)
            end
            local rows=inspect(env,admin,kind)
            eq(calls,1); eq(copies,0); eq(mutated,true,"mutate returned Vector after capture")
            eq(distance(rows[1]),13); eq(distance(rows[2]),13,"all rows use captured coordinates")
        end)
        test(kind.name .. " distances are private to two admins at different locations",function()
            local env,admin=setup(kind); local second=env.entity("player"); second.admin=true
            local observer=env.entity("player"); second:SetPos(env.Vector(3,4,12))
            local first=inspect(env,admin,kind); local other=inspect(env,second,kind)
            eq(distance(first[1]),13); eq(distance(other[1]),0); eq(#observer.chats,0)
            eq(first[1].key,other[1].key)
        end)
        test(kind.name .. " distance pagination retains sorted exact keys and page grants",function()
            local env,admin,positions=setup(kind)
            for i=1,10 do positions[i*10]=env.Vector(i,-i,i*2) end
            local keys={}; for key in pairs(positions) do keys[#keys+1]=key end; table.sort(keys)
            local rows=inspect(env,admin,kind); eq(#rows,8)
            for i=1,8 do eq(tonumber(rows[i].key),keys[i]); distance(rows[i]) end
            local last=inspect(env,admin,kind,2); eq(#last,4)
            for i=1,4 do eq(tonumber(last[i].key),keys[i+8]); distance(last[i]) end
            env.fire("PlayerSay",admin,kind.remove .. " " .. rows[1].key); assert(positions[keys[1]],"old page is stale")
            env.fire("PlayerSay",admin,kind.remove .. " " .. last[1].key); eq(positions[keys[9]],nil)
        end)
    end

    local kind=kinds[1]
    local cases={
        {"negative axes",{-3,-4,-12},13},
        {"small finite",{3e-200,4e-200,12e-200},13e-200},
        {"subnormal finite",{0,0,5e-324},5e-324},
        {"large finite",{3e200,4e200,12e200},13e200},
        {"largest finite axis",{1.7976931348623157e308,0,0},1.7976931348623157e308},
        {"norm overflow",{1.7976931348623157e308,1.7976931348623157e308,0}},
        {"subtraction overflow",{1.7976931348623157e308,0,0},nil,{-1.7976931348623157e308,0,0}},
    }
    for _,case in ipairs(cases) do
        test("base distance handles " .. case[1] .. " without invalidating inspection",function()
            local env,admin,positions=setup(kind)
            positions[2]=env.Vector((table.unpack or unpack)(case[2])); positions[9]=nil
            if case[4] then admin:SetPos(env.Vector((table.unpack or unpack)(case[4]))) end
            local rows=inspect(env,admin,kind); eq(#rows,1)
            if case[3] then close(distance(rows[1]),case[3]) else eq(rows[1].suffix,"distance unavailable") end
            env.fire("PlayerSay",admin,kind.remove .. " 2"); eq(positions[2],nil)
        end)
    end
    local invalid={
        {"missing method",function(_,admin) admin.GetPos=false end},
        {"throwing method",function(_,admin) admin.GetPos=function() error("GetPos failure") end end},
        {"nil",function(_,admin) admin.GetPos=function() return nil end end},
        {"false",function(_,admin) admin.GetPos=function() return false end end},
        {"plain coordinates",function(_,admin) admin.GetPos=function() return {x=1,y=2,z=3} end end},
        {"throwing coordinate",function(env,admin)
            local origin=env.Vector(0,0,0); origin.x=nil
            getmetatable(origin).__index=function() error("coordinate failure") end
            admin.GetPos=function() return origin end
        end},
    }
    for _,axis in ipairs({"x","y","z"}) do
        for _,value in ipairs({{name="NaN",value=0/0},{name="infinity",value=math.huge},
            {name="negative infinity",value=-math.huge},{name="nonnumeric",value="1"},{name="missing"}}) do
            invalid[#invalid+1]={axis .. " " .. value.name,function(env,admin)
                local origin=env.Vector(0,0,0); origin[axis]=value.value
                admin.GetPos=function() return origin end
            end}
        end
    end
    for _,case in ipairs(invalid) do
        test("unavailable base distance for " .. case[1] .. " preserves coordinates and a subsequent edit",function()
            local env,admin,positions=setup(kind); case[2](env,admin)
            local rows=inspect(env,admin,kind); eq(#rows,2)
            for _,row in ipairs(rows) do
                eq(row.suffix,"distance unavailable")
                local point=positions[tonumber(row.key)]
                eq(tonumber(row.x),point.x); eq(tonumber(row.y),point.y); eq(tonumber(row.z),point.z)
            end
            admin.GetPos=function() return env.Vector(1,2,3) end
            env.fire("PlayerSay",admin,kind.move .. " 2")
            eq(positions[2].x,1); eq(positions[2].y,2); eq(positions[2].z,3)
        end)
    end
    for _,reason in ipairs({"invalid sender","nonplayer","nonadmin","missing map","malformed list","bad syntax","bad page"}) do
        test("list never reads position before rejecting " .. reason,function()
            local env,admin=setup(kind); local calls=0; local command="!listSpawns enemy"
            admin.GetPos=function() calls=calls+1; error("rejected request read position") end
            if reason == "invalid sender" then admin.valid=false
            elseif reason == "nonplayer" then admin.class="worldspawn"
            elseif reason == "nonadmin" then admin.admin=false
            elseif reason == "missing map" then env.SpawnPositions={}
            elseif reason == "malformed list" then env.SpawnPositions[1].enemySpawnPositions=false
            elseif reason == "bad syntax" then command="!listSpawns wrong"
            else command="!listSpawns enemy 2" end
            eq(env.fire("PlayerSay",admin,command),""); eq(calls,0)
        end)
    end
end
