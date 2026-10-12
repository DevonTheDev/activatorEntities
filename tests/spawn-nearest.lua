-- Actual configured catalogue/edit/marker handlers with finite callback injection.
-- API doubles cannot establish native Vector precision, delivery or world placement.
return function(gmod,test,eq)
    local kinds={
        {name="enemy",field="enemySpawnPositions",remove="!removeEnemySpawn",move="!moveEnemySpawn"},
        {name="activator",field="activatorSpawnPositions",remove="!removeActivatorSpawn",move="!moveActivatorSpawn"},
    }
    local function setup(kind)
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local positions={[2]=env.Vector(0,0,30),[9]=env.Vector(3,4,0),[31]=env.Vector(0,0,0)}
        env.SpawnPositions[1][kind.field]=positions
        return env,admin,positions
    end
    local function say(env,admin,text) return env.fire("PlayerSay",admin,text) end
    local function capture(env,admin,text)
        local first=#admin.chats+1; eq(say(env,admin,text),"","recognized command stays private")
        local rows,lines={},{}
        for i=first,#admin.chats do
            local line=admin.chats[i]; assert(#line <= 255,"255-byte chat limit")
            lines[#lines+1]=line
            local key,x,y,z,suffix=line:match("^Key ([^:]+): x=([^,]+), y=([^,]+), z=([^;]+); (.+)$")
            if key then rows[#rows+1]={key=key,x=x,y=y,z=z,suffix=suffix,line=line} end
        end
        assert(#lines <= 10,"eight rows plus two framing lines")
        return rows,lines
    end
    local function near(env,admin,kind,page)
        return capture(env,admin,"!nearSpawns "..kind.name..(page and " "..page or ""))
    end
    local function ordinary(env,admin,kind) return capture(env,admin,"!listSpawns "..kind.name) end
    local function mark(env,admin,kind,token)
        local before=#env.messages
        eq(say(env,admin,"!markSpawn "..kind.name.." "..token),"")
        return #env.messages-before
    end
    local function keys(rows)
        local result={}; for _,row in ipairs(rows) do result[#result+1]=row.key end
        return table.concat(result,",")
    end
    local function once(object,name,callback)
        local original=object[name]; local entered=false
        object[name]=function(...)
            if not entered then entered=true; callback() end
            return original(...)
        end
        return function() object[name]=original end
    end
    for _,kind in ipairs(kinds) do
        test("nearby "..kind.name.." sorts 3D distances before exact keys and retains ordinary bytes",function()
            local env,admin=setup(kind)
            local rows,lines=ordinary(env,admin,kind)
            eq(keys(rows),"2,9,31")
            eq(lines[1],"Current-map "..kind.name.." spawns, page 1/1 (3 positions). Approx. distance from you to stored bases at list time, in 3D Source units.")
            eq(rows[1].line,"Key 2: x=0, y=0, z=30; ~30 units away")
            eq(rows[2].line,"Key 9: x=3, y=4, z=0; ~5 units away")
            eq(rows[3].line,"Key 31: x=0, y=0, z=0; ~0 units away")
            local nearest,frames=near(env,admin,kind)
            eq(keys(nearest),"31,9,2"); eq(nearest[1].suffix,"~0 units away")
            assert(frames[1]:find("Nearest current-map",1,true)); assert(frames[1]:find("3D Source units",1,true))
            assert(frames[1]:find("unavailable last",1,true)); assert(frames[1]:find("fresh",1,true))
            eq(frames[#frames],lines[#lines],"existing exact-key footer")
            admin.pos=env.Vector(0,0,30); eq(keys(near(env,admin,kind)),"2,31,9","fresh origin reorders")
        end)
        for _,count in ipairs({0,8,9,17}) do
            test("nearby "..kind.name.." paginates "..count.." distance-sorted rows",function()
                local env,admin=setup(kind); local positions={}; env.SpawnPositions[1][kind.field]=positions
                for i=1,count do positions[i*10]=env.Vector(count-i,0,0) end
                local total=math.max(1,math.ceil(count/8)); local seen={}
                for page=1,total do
                    local rows,lines=near(env,admin,kind,page)
                    eq(#rows,math.min(8,math.max(0,count-(page-1)*8)))
                    assert(lines[1]:find("page "..page.."/"..total,1,true))
                    for j,row in ipairs(rows) do
                        local rank=(page-1)*8+j; eq(tonumber(row.key),(count-rank+1)*10)
                        assert(not seen[row.key]); seen[row.key]=true
                    end
                end
            end)
        end
        test("nearby "..kind.name.." sorts numeric distances before identical rounded suffixes",function()
            local env,admin=setup(kind)
            env.SpawnPositions[1][kind.field]={[2]=env.Vector(1.0000002,0,0),[9]=env.Vector(1.0000001,0,0),[31]=env.Vector(-1.0000001,0,0)}
            local rows=near(env,admin,kind); eq(keys(rows),"9,31,2"); eq(rows[1].suffix,rows[3].suffix)
        end)
        test("nearby "..kind.name.." exact tie ordering includes separate int64 and scientific keys",function()
            local env,admin=setup(kind); local positions={}; env.SpawnPositions[1][kind.field]=positions
            local lower,upper=tonumber("9223372036854775806"),tonumber("9223372036854775807")
            local expected={2,9,lower}; if lower ~= upper then expected[#expected+1]=upper end
            expected[#expected+1]=1e100
            for _,key in ipairs(expected) do positions[key]=env.Vector(3,4,12) end
            local rows=near(env,admin,kind); eq(#rows,#expected)
            for i,row in ipairs(rows) do eq(tonumber(row.key),expected[i]); eq(row.suffix,"~13 units away") end
            eq(mark(env,admin,kind,rows[#rows].key),1)
            eq(env.messages[#env.messages].values[4],rows[#rows].key)
            say(env,admin,kind.remove.." "..rows[#rows].key); eq(positions[1e100],nil)
        end)
        for _,action in ipairs({"move","remove","mark"}) do
            test("nearby "..kind.name.." grants real "..action.." by shown key, never rank or alias",function()
                local env,admin,positions=setup(kind); local rows=near(env,admin,kind)
                for _,bad in ipairs({"1","031","31.0","+31","0x1f","3.1e1","99"}) do
                    if action=="mark" then eq(mark(env,admin,kind,bad),0)
                    else say(env,admin,kind[action].." "..bad); eq(positions[31].x,0) end
                end
                local other=env.entity("player"); other.admin=true
                if action=="mark" then
                    eq(mark(env,other,kind,rows[1].key),0); eq(mark(env,admin,kind,rows[1].key),1)
                    eq(env.messages[#env.messages].values[4],"31")
                else
                    say(env,other,kind[action].." "..rows[1].key); eq(positions[31].x,0)
                    admin.pos=env.Vector(20,30,40); say(env,admin,kind[action].." "..rows[1].key)
                    if action=="remove" then eq(positions[31],nil) else eq(positions[31].x,20); eq(positions[31].y,30); eq(positions[31].z,40) end
                end
            end)
        end
        test("nearby "..kind.name.." page and kind replacement preserve literal grant scope",function()
            local env,admin,positions=setup(kind)
            for i=40,47 do positions[i]=env.Vector(i,0,0) end
            local first=near(env,admin,kind); local last=near(env,admin,kind,2)
            eq(mark(env,admin,kind,first[1].key),0); eq(mark(env,admin,kind,last[1].key),1)
            say(env,admin,"!listSpawns "..(kind.name=="enemy" and "activator" or "enemy"))
            eq(mark(env,admin,kind,last[1].key),0)
        end)
        test("nearby "..kind.name.." captures one origin, copies scalars and allocates no Vector",function()
            local env,admin,positions=setup(kind); local origin=env.Vector(0,0,0); local calls=0
            admin.GetPos=function() calls=calls+1; return origin end
            env.Vector=function() error("catalogue allocated Vector") end
            local changed=false
            env.tostring=function(value)
                if calls==1 and not changed then changed=true; origin.x=100 end
                return tostring(value)
            end
            local rows=near(env,admin,kind); eq(calls,1); eq(changed,true); eq(keys(rows),"31,9,2")
            eq(rows[1].suffix,"~0 units away"); eq(rows[2].suffix,"~5 units away"); eq(positions[9].x,3)
        end)
    end
    local kind=kinds[1]
    for _,case in ipairs({
        {"tiny",{3e-200,4e-200,12e-200}}, {"subnormal",{0,0,5e-324}},
        {"huge",{3e200,4e200,12e200}}, {"largest axis",{1.7976931348623157e308,0,0}},
    }) do
        test("nearby numeric norm handles "..case[1],function()
            local env,admin=setup(kind); local p=env.Vector((table.unpack or unpack)(case[2]))
            env.SpawnPositions[1][kind.field]={[2]=p,[9]=env.Vector(0,0,0)}
            local rows=near(env,admin,kind); eq(keys(rows),"9,2")
            local d=tonumber(rows[2].suffix:match("^~(%S+) units away$")); assert(d and d>0 and d<math.huge)
        end)
    end
    for _,overflow in ipairs({"norm","subtraction"}) do
        test("nearby "..overflow.." overflow sorts unavailable distances last with exact actionable keys",function()
            local env,admin=setup(kind); local huge=1.7976931348623157e308
            local positions={[2]=env.Vector(huge,huge,0),[9]=env.Vector(huge,huge,0),[31]=env.Vector(0,0,0)}
            if overflow=="subtraction" then admin.pos=env.Vector(-huge,0,0); positions[31]=env.Vector(-huge,0,0) end
            env.SpawnPositions[1][kind.field]=positions
            local rows=near(env,admin,kind); eq(keys(rows),"31,2,9"); eq(rows[2].suffix,"distance unavailable"); eq(rows[3].suffix,"distance unavailable")
            say(env,admin,kind.remove.." "..rows[2].key); eq(positions[2],nil)
        end)
    end
    local invalidOrigins={
        {"missing method",function(_,a) a.GetPos=false end},
        {"throwing",function(_,a) a.GetPos=function() error("PRIVATE FAILURE") end end},
        {"nil",function(_,a) a.GetPos=function() end end},
        {"nonvector",function(_,a) a.GetPos=function() return {x=0,y=0,z=0} end end},
    }
    for _,axis in ipairs({"x","y","z"}) do
        for _,case in ipairs({{"NaN",0/0},{"infinity",math.huge},{"negative infinity",-math.huge},{"string","0"},{"missing"}}) do
            invalidOrigins[#invalidOrigins+1]={axis.." "..case[1],function(_,a) a.pos[axis]=case[2] end}
        end
    end
    for _,case in ipairs(invalidOrigins) do
        test("nearby refuses "..case[1].." origin and clears old grant; ordinary retains unknown-distance grant",function()
            local env,admin=setup(kind); ordinary(env,admin,kind); case[2](env,admin)
            local rows,lines=near(env,admin,kind); eq(#rows,0); eq(#lines,1)
            assert(lines[1]:find("!listSpawns",1,true)); assert(not lines[1]:find("PRIVATE FAILURE",1,true))
            eq(mark(env,admin,kind,"2"),0)
            rows=ordinary(env,admin,kind); eq(rows[1].suffix,"distance unavailable")
            eq(mark(env,admin,kind,"2"),1)
        end)
    end
    for _,text in ipairs({"!nearSpawns","!nearSpawns Enemy","!nearSpawns bad","!nearSpawns enemy 0","!nearSpawns enemy -1",
        "!nearSpawns enemy 1.0","!nearSpawns enemy 1e1","!nearSpawns enemy 1 extra","!nearSpawns enemy "..string.rep("9",400),"!nearSpawns enemy 2"}) do
        test("nearby admitted invalid request clears page without reading origin: "..text:sub(1,60),function()
            local env,admin=setup(kind); ordinary(env,admin,kind); local calls=0
            admin.GetPos=function() calls=calls+1; error("must not read origin") end
            local rows,lines=capture(env,admin,text); eq(#rows,0); eq(calls,0); eq(#lines,1)
            eq(mark(env,admin,kind,"2"),0)
        end)
    end
    for _,case in ipairs({"nil","invalid","nonplayer","nonadmin","dead"}) do
        test("nearby actor rejection distinguishes "..case.." from admitted failure",function()
            local env,admin=setup(kind); ordinary(env,admin,kind); local actor=admin; local calls=0
            admin.GetPos=function() calls=calls+1; error("early origin") end
            if case=="nil" then actor=nil elseif case=="invalid" then admin.valid=false elseif case=="nonplayer" then admin.class="worldspawn"
            elseif case=="nonadmin" then admin.admin=false else admin.alive=false end
            eq(say(env,actor,"!nearSpawns enemy"),""); eq(calls,0)
            admin.valid=true; admin.class="player"; admin.admin=true; admin.alive=true
            eq(mark(env,admin,kind,"2"),case=="dead" and 0 or 1)
        end)
    end
    test("nearby exact recognition leaves unrelated chat and page unchanged",function()
        local env,admin=setup(kind); ordinary(env,admin,kind)
        for _,text in ipairs({"!nearSpawnsSuffix enemy","!NearSpawns enemy","hello !nearSpawns enemy"," !nearSpawns enemy"}) do eq(say(env,admin,text),nil) end
        eq(mark(env,admin,kind,"2"),1)
    end)
    for _,case in ipairs({"missing map","duplicate map","malformed map","missing list","string key","nonvector","nonfinite","unrepresentable key","unrepresentable coordinate","overlong row"}) do
        test("nearby rejects "..case.." without repairing data",function()
            local env,admin,positions=setup(kind); ordinary(env,admin,kind)
            if case=="missing map" then env.SpawnPositions={}
            elseif case=="duplicate map" then env.SpawnPositions[2]=env.SpawnPositions[1]
            elseif case=="malformed map" then env.SpawnPositions[1].map=false
            elseif case=="missing list" then env.SpawnPositions[1][kind.field]=nil
            elseif case=="string key" then positions.bad=env.Vector(0,0,0)
            elseif case=="nonvector" then positions[2]={x=0,y=0,z=0}
            elseif case=="nonfinite" then positions[2].z=math.huge
            elseif case=="unrepresentable key" or case=="unrepresentable coordinate" then
                local selected=case=="unrepresentable key" and 31 or 30
                env.tostring=function(v) if v==selected then return "bad" end return tostring(v) end
                env.string=setmetatable({format=function(f,v) if v==selected then return "bad" end return string.format(f,v) end},{__index=string})
            else
                env.tostring=function(v) if v==30 then return string.rep("0",260).."30" end return tostring(v) end
            end
            local before=positions[2]; local rows,lines=near(env,admin,kind)
            eq(#rows,0); eq(#lines,1); assert(lines[1]:find("Cannot inspect spawns",1,true)); eq(positions[2],before)
            eq(mark(env,admin,kind,"9"),0)
        end)
    end
    test("nearest empty list still requires one origin and a living admin",function()
        local env,admin=setup(kind); env.SpawnPositions[1][kind.field]={}; local calls=0
        admin.GetPos=function() calls=calls+1; return admin.pos end
        local rows,lines=near(env,admin,kind); eq(#rows,0); eq(#lines,2); eq(calls,1)
        admin.GetPos=function() calls=calls+1 end; rows,lines=near(env,admin,kind); eq(#rows,0); eq(#lines,1); eq(calls,2)
    end)
    test("ordinary dead admission and configured page lifetime remain unchanged",function()
        local env,admin,positions=setup(kind); admin.alive=false; ordinary(env,admin,kind)
        env.now=1e6; env.fire("PlayerDeath",admin); env.fire("PlayerSpawn",admin)
        say(env,admin,kind.remove.." 2"); eq(positions[2],nil)
        admin.alive=true; near(env,admin,kind); admin.alive=false
        env.now=2e6; env.fire("PlayerDeath",admin); env.fire("PlayerSpawn",admin)
        say(env,admin,kind.remove.." 9"); eq(positions[9],nil)
    end)
    for _,outer in ipairs({"!listSpawns enemy","!nearSpawns enemy"}) do
        for _,read in ipairs({"IsPlayer","IsAdmin","GetMap","GetPos"}) do
            for _,inner in ipairs({"!listSpawns activator","!nearSpawns activator","!listSpawns bad","!nearSpawns bad"}) do
                test("catalogue capture "..outer.." yields to "..inner.." in "..read,function()
                    local env,admin=setup(kind); env.SpawnPositions[1].activatorSpawnPositions={[77]=env.Vector(0,0,0)}
                    local object=read=="GetMap" and env.game or admin
                    local restore=once(object,read,function() eq(say(env,admin,inner),"") end)
                    eq(say(env,admin,outer),""); restore()
                    eq(mark(env,admin,kind,"2"),0)
                    eq(mark(env,admin,kinds[2],"77"),inner:find("bad",1,true) and 0 or 1)
                    local headers=0
                    for _,line in ipairs(admin.chats) do if line:find("current-map",1,true) or line:find("Current-map",1,true) then headers=headers+1 end end
                    eq(headers,inner:find("bad",1,true) and 0 or 1,"obsolete output suppressed")
                end)
            end
        end
    end
    for _,read in ipairs({"IsPlayer","IsAdmin","Alive","GetMap"}) do
        for _,inner in ipairs({"!listSpawns activator","!nearSpawns activator","!nearSpawns bad","disconnect","initialize"}) do
            test("nearest final "..read.." read yields to "..inner,function()
                local env,admin=setup(kind); env.SpawnPositions[1].activatorSpawnPositions={[77]=env.Vector(0,0,0)}
                local object=read=="GetMap" and env.game or admin; local original=object[read]; local calls=0
                object[read]=function(...)
                    calls=calls+1
                    if calls==2 then
                        if inner=="disconnect" then env.fire("PlayerDisconnected",admin)
                        elseif inner=="initialize" then env.file.Exists=function() return false end; env.fire("Initialize")
                        else eq(say(env,admin,inner),"") end
                    end
                    return original(...)
                end
                local rows=near(env,admin,kind); object[read]=original
                assert(calls>=2,"injected final read"); eq(mark(env,admin,kind,"31"),0)
                local success=inner=="!listSpawns activator" or inner=="!nearSpawns activator"
                eq(#rows,success and 1 or 0); eq(mark(env,admin,kinds[2],"77"),success and 1 or 0)
            end)
        end
        for _,nth in ipairs({1,2}) do
            test("nearest guarded "..read.." exception at read "..nth,function()
                local env,admin=setup(kind); ordinary(env,admin,kind)
                local object=read=="GetMap" and env.game or admin; local original=object[read]; local calls=0
                object[read]=function(...)
                    calls=calls+1; if calls==nth then error("PRIVATE GETTER FAILURE") end
                    return original(...)
                end
                local rows,lines=near(env,admin,kind); object[read]=original
                eq(#rows,0); eq(calls,nth)
                for _,line in ipairs(lines) do assert(not line:find("PRIVATE GETTER FAILURE",1,true)) end
                local beforeClear=nth==1 and (read=="IsPlayer" or read=="IsAdmin")
                eq(mark(env,admin,kind,"2"),beforeClear and 1 or 0)
            end)
        end
    end
    test("nearest first Alive callback retains a nested ordinary page",function()
        local env,admin=setup(kind); env.SpawnPositions[1].activatorSpawnPositions={[77]=env.Vector(0,0,0)}
        local restore=once(admin,"Alive",function() say(env,admin,"!listSpawns activator") end)
        local rows=near(env,admin,kind); restore(); eq(#rows,1); eq(rows[1].key,"77")
        eq(mark(env,admin,kinds[2],"77"),1); eq(mark(env,admin,kind,"31"),0)
    end)
    for _,case in ipairs({"dead","demoted","invalid","map changed","list replaced","record replaced","changed unshown","removed unshown","added key","same-coordinate edit","reused key","disconnect","initialize"}) do
        test("nearest capture refuses obsolete "..case.." snapshot",function()
            local env,admin,positions=setup(kind)
            for i=40,50 do positions[i]=env.Vector(i,0,0) end
            local other=env.entity("player"); other.admin=true; ordinary(env,other,kind)
            local restore=once(admin,"GetPos",function()
                if case=="dead" then admin.alive=false
                elseif case=="demoted" then admin.admin=false
                elseif case=="invalid" then admin.valid=false
                elseif case=="map changed" then env.map="other_map"
                elseif case=="list replaced" then local clone={}; for k,v in pairs(positions) do clone[k]=v end; env.SpawnPositions[1][kind.field]=clone
                elseif case=="record replaced" then local old=env.SpawnPositions[1]; env.SpawnPositions[1]={map=old.map,enemySpawnPositions=old.enemySpawnPositions,activatorSpawnPositions=old.activatorSpawnPositions}
                elseif case=="changed unshown" then positions[50].z=1
                elseif case=="removed unshown" then positions[50]=nil
                elseif case=="added key" then positions[51]=env.Vector(0,0,0)
                elseif case=="same-coordinate edit" then other.pos=positions[2]; say(env,other,kind.move.." 2")
                elseif case=="reused key" then say(env,other,kind.remove.." 2"); positions[2]=env.Vector(0,0,30)
                elseif case=="disconnect" then env.fire("PlayerDisconnected",admin)
                else env.file.Exists=function() return false end; env.fire("Initialize") end
            end)
            local rows=near(env,admin,kind); eq(#rows,0); restore()
            admin.alive=true; admin.admin=true; admin.valid=true; env.map="gm_construct"
            eq(mark(env,admin,kind,"31"),0)
        end)
    end
    test("nearest pending capture invalidation is scoped to edited map and kind",function()
        local env,admin=setup(kind); local other=env.entity("player"); other.admin=true
        say(env,other,"!listSpawns activator")
        local restore=once(admin,"GetPos",function() say(env,other,"!removeActivatorSpawn") end)
        local rows=near(env,admin,kind); restore(); eq(keys(rows),"31,9,2"); eq(mark(env,admin,kind,"31"),1)
    end)
    for _,mode in ipairs({"ordinary","nearest"}) do
        for _,when in ipairs({"header","row"}) do
            for _,action in ipairs({"ordinary","nearest","failed list","edit","disconnect","initialize","mark","clear","throw"}) do
                test(mode.." reply "..when.." reentry "..action.." never restores authority",function()
                    local env,admin,positions=setup(kind); local original=admin.ChatPrint; local entered=false
                    env.SpawnPositions[1].activatorSpawnPositions={[77]=env.Vector(7,7,7)}
                    admin.ChatPrint=function(self,line)
                        original(self,line)
                        if not entered and (when=="header" or line:match("^Key ")) then
                            entered=true
                            if action=="ordinary" then say(env,admin,"!listSpawns activator")
                            elseif action=="nearest" then say(env,admin,"!nearSpawns activator")
                            elseif action=="failed list" then say(env,admin,"!nearSpawns bad")
                            elseif action=="edit" then say(env,admin,kind.remove.." 31")
                            elseif action=="disconnect" then env.fire("PlayerDisconnected",admin)
                            elseif action=="initialize" then env.file.Exists=function() return false end; env.fire("Initialize")
                            elseif action=="mark" then say(env,admin,"!markSpawn enemy 31")
                            elseif action=="clear" then say(env,admin,"!clearSpawnMarker")
                            else error("reply interrupted") end
                        end
                    end
                    pcall(say,env,admin,mode=="ordinary" and "!listSpawns enemy" or "!nearSpawns enemy")
                    admin.ChatPrint=original; eq(entered,true)
                    if action=="ordinary" or action=="nearest" then
                        eq(mark(env,admin,kinds[2],"77"),1); eq(mark(env,admin,kind,"31"),0)
                    elseif action=="mark" or action=="clear" then
                        eq(#env.messages,1); eq(env.messages[1].values[1],action=="mark"); eq(mark(env,admin,kind,"31"),1)
                    elseif action=="throw" then eq(mark(env,admin,kind,"31"),1,"installed before feedback")
                    else eq(mark(env,admin,kind,"31"),0) end
                    if action=="edit" then eq(positions[31],nil) end
                end)
            end
        end
    end
    for _,case in ipairs({"map","list identity","record identity","shown coordinate","shown missing","same-coordinate move","failed-save remove","remove and reuse","disconnect","initialize"}) do
        test("nearest grant rejects stale "..case.." through real marker",function()
            local env,admin,positions=setup(kind); near(env,admin,kind)
            if case=="map" then env.map="other_map"
            elseif case=="list identity" then local mt={__eq=function() return true end}; setmetatable(positions,mt); env.SpawnPositions[1][kind.field]=setmetatable({[2]=positions[2],[9]=positions[9],[31]=positions[31]},mt)
            elseif case=="record identity" then local old=env.SpawnPositions[1]; local mt={__eq=function() return true end}; setmetatable(old,mt); env.SpawnPositions[1]=setmetatable({map=old.map,enemySpawnPositions=positions,activatorSpawnPositions=old.activatorSpawnPositions},mt)
            elseif case=="shown coordinate" then positions[2].x=9
            elseif case=="shown missing" then positions[2]=nil
            elseif case=="same-coordinate move" or case=="failed-save remove" or case=="remove and reuse" then
                local other=env.entity("player"); other.admin=true; other.pos=positions[2]; ordinary(env,other,kind)
                say(env,other,(case=="same-coordinate move" and kind.move or kind.remove).." 2")
                if case=="remove and reuse" then positions[2]=env.Vector(0,0,30) end
                if case=="failed-save remove" then assert(other.chats[#other.chats]:find("remains in memory",1,true)) end
            elseif case=="disconnect" then env.fire("PlayerDisconnected",admin)
            else env.file.Exists=function() return false end; env.fire("Initialize") end
            eq(mark(env,admin,kind,"31"),0)
        end)
    end
    test("nearest action grants do not require unshown rows or origin to remain unchanged",function()
        local env,admin,positions=setup(kind); for i=40,50 do positions[i]=env.Vector(i,0,0) end
        near(env,admin,kind); positions[50].x=100; admin.pos=env.Vector(1000,0,0)
        eq(mark(env,admin,kind,"31"),1); say(env,admin,kind.remove.." 31"); eq(positions[31],nil)
    end)
    for _,source in ipairs({"configured","encounter"}) do
        for _,text in ipairs({"!nearSpawns enemy","!nearSpawns bad"}) do
            test("nearest attempt cancels pending "..source.." marker: "..text,function()
                local env,admin=setup(kind); ordinary(env,admin,kind); local command="!markSpawn enemy 2"
                if source=="encounter" then
                    local ply,enemies=env.start(); admin=ply; admin.admin=true
                    say(env,admin,"!listEventEnemies"); command="!markEventEnemy "..enemies[1]:EntIndex()
                end
                local before=#env.messages; local restore=once(admin,"Alive",function() say(env,admin,text) end)
                eq(say(env,admin,command),""); restore(); eq(#env.messages,before,"no late marker packet")
            end)
        end
    end
    for _,state in ipairs({"idle","ready","active","paused"}) do
        test("nearest viewing in "..state.." leaves configuration, encounter, timers, RNG and packets untouched",function()
            local env,admin,positions=setup(kind)
            if state=="ready" then env.ready()
            elseif state=="active" then env.start()
            elseif state=="paused" then say(env,admin,"!pauseActivatorSpawns") end
            ordinary(env,admin,kind); eq(mark(env,admin,kind,"2"),1)
            local previous=env.messages[#env.messages]; local packetCount=#env.messages
            local entities=#env.entities; local total=env.totalEnemies; local timer=env.timers.activatorSpawner; local stopped=timer.stopped
            local original={}; for key,p in pairs(positions) do original[key]={object=p,x=p.x,y=p.y,z=p.z} end
            local calls={}; local function forbidden(name) return function() calls[#calls+1]=name; error("view called "..name) end end
            env.math=setmetatable({random=forbidden("random"),randomseed=forbidden("randomseed")},{__index=math})
            for _,name in ipairs({"Read","Write","Exists"}) do env.file[name]=forbidden("file."..name) end
            for _,name in ipairs({"TableToJSON","JSONToTable"}) do env.util[name]=forbidden(name) end
            for _,name in ipairs({"Create","Start","Stop","Simple","Remove","Adjust"}) do env.timer[name]=forbidden("timer."..name) end
            for _,name in ipairs({"Create","FindByClass","FindByName"}) do env.ents[name]=forbidden("ents."..name) end
            for _,name in ipairs({"Start","Send","Broadcast"}) do env.net[name]=forbidden("net."..name) end
            env.returnSpawnPositions=forbidden("spawn sample"); env.returnActivatorSpawns=forbidden("activator sample")
            env.Vector=forbidden("Vector")
            for _,actor in ipairs(env.entities) do
                for _,name in ipairs({"SetPos","Remove","Spawn","SetHealth","SetModel","SetMoveType"}) do actor[name]=forbidden(name) end
            end
            local rows=near(env,admin,kind); eq(#rows,3); capture(env,admin,"!nearSpawns bad")
            eq(#calls,0); eq(#env.entities,entities); eq(env.totalEnemies,total); eq(env.timers.activatorSpawner,timer); eq(timer.stopped,stopped)
            eq(#env.messages,packetCount); eq(env.messages[#env.messages],previous)
            for key,p in pairs(original) do eq(positions[key],p.object); eq(positions[key].x,p.x); eq(positions[key].y,p.y); eq(positions[key].z,p.z) end
        end)
    end
end
