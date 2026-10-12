-- Finite production-hook coverage. Native GMod delivery and timing are unverified.
return function(gmod,test,eq)
    local function contains(text,wanted) assert(text:find(wanted,1,true),'missing '..wanted..' in '..text) end
    local function state(env)
        local found,seen={},{}
        local wanted={enemyInspections=true,enemyMarkerCaptures=true,enemyMarkerGrants=true,enemyRemovalRequests=true,
            activeEnemies=true,constructingEnemies=true,eventActive=true,eventInterrupted=true,activeEventName=true,
            initialEnemies=true,pendingSelection=true,selectedBatchName=true,selectedBatchEntities=true,
            interactions=true,statusRequestAfter=true,automaticSpawnsPaused=true}
        local function visit(fn)
            if seen[fn] then return end; seen[fn]=true
            for i=1,100 do
                local name,value=debug.getupvalue(fn,i); if not name then break end
                if wanted[name] then found[name]=value end
                if type(value)=='function' then visit(value) end
            end
        end
        for _,hooks in pairs(env.hooks) do for _,fn in pairs(hooks) do visit(fn) end end
        for _,fn in pairs(env.receivers) do visit(fn) end
        for _,timer in pairs(env.timers) do visit(timer.callback) end
        return found
    end
    local function setup(count,name)
        local env=gmod.new(); env.NPCEdits[1].information.maxNPCs=count or 3
        if name then env.NPCEdits[1].name=name; env.determineRandomEvent=function() return name end end
        local admin,actor=env.ready(); admin.admin=true
        actor:AcceptInput('Use',admin,admin); env.receive('SendNPCInformation',admin,name or 'Raid')
        local enemies=env.ents.FindByName('devonsSpawnedEntity'); eq(#enemies,count or 3)
        admin.pos=env.Vector(0,0,0); admin.chats={}
        for i,enemy in ipairs(enemies) do enemy.index=100+i; enemy.pos=env.Vector(i,0,0) end
        return env,admin,enemies
    end
    local function say(env,admin,command)
        local before=admin and #admin.chats or 0
        local result=env.fire('PlayerSay',admin,command or '!nearEventEnemies')
        local lines={}
        if admin then for i=before+1,#admin.chats do
            local line=admin.chats[i]; assert(#line<=255,'private chat byte limit'); assert(not line:find('%c'),'no control bytes')
            lines[#lines+1]=line
        end end
        return result,lines,table.concat(lines,'\n')
    end
    local function near(env,admin,page)
        local result,lines,text=say(env,admin,'!nearEventEnemies'..(page and ' '..page or ''))
        eq(result,'','nearest command consumed privately'); return lines,text
    end
    local function rows(lines)
        local found={}
        for _,line in ipairs(lines) do if line:match('^Entity index ') or line:match('^Unindexed:') then found[#found+1]=line end end
        assert(#found<=8,'eight rows per page'); return found
    end
    local function indices(lines)
        local found={}; for _,line in ipairs(rows(lines)) do found[#found+1]=tonumber(line:match('^Entity index (%S+):')) or 0 end
        return found
    end
    local function order(lines,expected)
        local actual=indices(lines); eq(#actual,#expected)
        for i,value in ipairs(expected) do eq(actual[i],value,'geometric row '..i) end
    end
    local function packets(env)
        local all={}; for _,out in ipairs(env.messages) do if out.name=='ActivatorSpawnMarker' then all[#all+1]=out end end
        return all
    end
    local function mark(env,admin,token)
        eq(env.fire('PlayerSay',admin,'!markEventEnemy '..token),''); return packets(env)
    end
    local function remove(env,admin,token) eq(env.fire('PlayerSay',admin,'!removeEventEnemy '..token),'') end
    local function inspection(env,admin) return state(env).enemyInspections[admin] end
    local function install(env,admin,mode,page)
        local result,lines,text=say(env,admin,(mode or '!nearEventEnemies')..(page and ' '..page or ''))
        eq(result,'','listing mode consumed privately'); return result,lines,text
    end

    -- 1: Exact routing and the finite grammar.
    test('nearest exact routing yields before shared player guards',function()
        local env,admin=setup(); local shared=env.hooks.PlayerSay.devonsCommands
        -- Locate the shared hook without relying on an incidental hook name.
        for name,fn in pairs(env.hooks.PlayerSay) do if name~='selectNextActivatorEvent' then shared=fn end end
        assert(shared,'shared command handler present')
        admin.IsPlayer=function() error('shared hook must yield before guards') end
        eq(shared(admin,'!nearEventEnemies'),nil)
        admin.IsPlayer=function() return true end
        for _,command in ipairs({'!nearEventEnemiesOther','hello !nearEventEnemies','ordinary chat'}) do eq(env.fire('PlayerSay',admin,command),nil) end
        local lines,text=near(env,admin); contains(text,'Nearest enemy locations, page 1/1')
        local _,again=near(env,admin,'01'); eq(again,text)
        contains(text,'Approx. distance from your captured position at request time, in 3D Source units; unknown distances last.')
        contains(text,'!nearEventEnemies [page]'); contains(text,'pages can move'); eq(#rows(lines),3)
    end)
    for _,argument in ipairs({'0','-1','+1','1.0','1e1','two','1 2','2 extra',string.rep('9',400)}) do
        test('nearest malformed page '..argument:sub(1,20),function()
            local env,admin=setup(); local lines,text=near(env,admin,argument)
            eq(#lines,1); contains(text,'Usage: !nearEventEnemies [page]'); eq(inspection(env,admin),nil)
        end)
    end
    test('nearest out-of-range idle and active zero-row cases',function()
        local env,admin,enemies=setup(2); local lines,text=near(env,admin,2)
        eq(#lines,1); contains(text,'1-1'); eq(inspection(env,admin),nil)
        for _,enemy in ipairs(enemies) do enemy.valid=false end
        lines,text=near(env,admin); contains(text,'listed 0'); contains(text,'omitted invalid/deleting 2'); eq(#rows(lines),0)
        env.stopActivatorEvent(); lines,text=near(env,admin,2); contains(text,'No active encounter')
        local idle=gmod.new(); local other=idle.entity('player'); other.admin=true
        lines,text=near(idle,other); contains(text,'No active encounter')
    end)

    -- 2: Actual ownership, independent origins and all three fresh pages.
    test('nearest owns 19 rows across three pages with two independent admins',function()
        local env,admin,enemies=setup(19,string.rep('雪',100)..'\n\0tail')
        local other=env.entity('player'); other.admin=true; other.pos=env.Vector(20,0,0)
        local stranger=env.entity(enemies[1].class); stranger.name=enemies[1].name; stranger.index=999
        stranger.pos=env.Vector(0,0,0)
        local all={}; local messages=#env.messages
        for page=1,3 do
            local lines,text=near(env,admin,page); contains(text,'page '..page..'/3'); contains(text,'progress 19/19')
            contains(text,'listed 19'); contains(text,'omitted invalid/deleting 0')
            eq(#rows(lines),page==3 and 3 or 8)
            for _,token in ipairs(indices(lines)) do all[#all+1]=token; assert(token~=999) end
        end
        for i=1,19 do eq(all[i],100+i) end
        local lines=near(env,other); order(lines,{119,118,117,116,115,114,113,112})
        eq(#env.messages,messages,'listing publishes no network'); eq(stranger.valid,true)
        local owners=state(env).activeEnemies
        enemies[1].valid=false; enemies[2].markedForDeletion=true
        local _,text=near(env,admin); contains(text,'progress 19/19'); contains(text,'listed 17'); contains(text,'omitted invalid/deleting 2')
        eq(owners[enemies[1]],true); eq(owners[enemies[2]],true); eq(state(env).activeEnemies,owners)
    end)

    -- 3: Unrounded 3D geometry, legacy ties, unknowns and movement.
    test('nearest ranks unrounded vertical negative zero and equal distances',function()
        local env,admin,enemies=setup(8)
        local points={{0,0,0},{0.49,0,0},{0.41,0,0},{0,0,-2},{-2,0,0},{0,3,0},{9,0,0},{4,0,0}}
        for i,p in ipairs(points) do enemies[i].pos=env.Vector(p[1],p[2],p[3]) end
        enemies[7].GetPos=function() return nil end
        order(near(env,admin),{101,103,102,104,105,106,108,107})
        local body=rows(near(env,admin)); contains(body[2],'(0, 0, 0); ~0.41 units away.')
        contains(body[4],'~2 units away'); contains(body[8],'world position unavailable; distance unavailable.')
        admin.pos=env.Vector(4,0,0); enemies[1].pos=env.Vector(50,0,0)
        order(near(env,admin),{108,102,103,104,106,105,101,107})
    end)
    test('nearest equal unindexed and unknown rows use legacy text ties',function()
        local env,admin,enemies=setup(5)
        enemies[1].index=0; enemies[1].pos=env.Vector(-1,0,0)
        enemies[2].index=0; enemies[2].pos=env.Vector(1,0,0)
        enemies[3].pos=env.Vector(1,0,0); enemies[3].index=9
        enemies[4].GetPos=function() return nil end; enemies[4].index=4
        enemies[5].GetPos=function() return nil end; enemies[5].index=2
        local body=rows(near(env,admin)); order(body,{9,0,0,2,4})
        contains(body[2],'(-1, 0, 0)'); contains(body[3],'(1, 0, 0)')
    end)

    -- 4: Capture once and compare only detached fields.
    test('nearest reads each native scalar once including off-page rows',function()
        local env,admin,enemies=setup(11); enemies[10].valid=false; enemies[11].markedForDeletion=true
        local calls,components={},{}
        local native=env.isvector
        env.isvector=function(p) return native(p) or p.__native==true end
        local function point(key,x,y,z)
            components[key]={x=0,y=0,z=0}
            local values={x=x,y=y,z=z}
            return setmetatable({__native=true},{__index=function(_,axis)
                components[key][axis]=components[key][axis]+1; return values[axis]
            end})
        end
        admin.GetPos=function() calls.actor=(calls.actor or 0)+1; return point('actor',0,0,0) end
        for i,enemy in ipairs(enemies) do enemy.GetPos=function()
            calls[i]=(calls[i] or 0)+1; return point(i,i,0,0)
        end end
        env.Vector=function() error('no vector allocation') end
        env.Entity=function() error('no lookup') end
        local sort=table.sort; local comparisons=0
        env.table.sort=function(list,less)
            return sort(list,function(a,b)
                comparisons=comparisons+1
                local total=0; for _,n in pairs(calls) do total=total+n end
                local value=less(a,b)
                local after=0; for _,n in pairs(calls) do after=after+n end
                eq(after,total,'comparator reads no entity'); return value
            end)
        end
        near(env,admin); eq(calls.actor,1); assert(comparisons>0)
        for i=1,9 do eq(calls[i],1); for _,axis in ipairs({'x','y','z'}) do eq(components[i][axis],1) end end
        eq(calls[10],nil); eq(calls[11],nil)
        for _,axis in ipairs({'x','y','z'}) do eq(components.actor[axis],1) end
    end)
    test('nearest detaches requester and enemy vectors before later mutation',function()
        local env,admin,enemies=setup(3); local origin=admin.pos; local captured={}
        for i,enemy in ipairs(enemies) do
            enemy.GetPos=function(self)
                origin.x=999
                for _,p in ipairs(captured) do p.x=999 end
                captured[#captured+1]=self.pos; return self.pos
            end
        end
        local lines=near(env,admin); order(lines,{101,102,103})
        for i,line in ipairs(rows(lines)) do contains(line,'('..i..', 0, 0); ~'..i..' units away.') end
    end)

    -- 5: Complete finite native-position failures for actor and enemy.
    local failures={
        {'missing getter',function(env,obj) obj.GetPos=false end},
        {'throwing getter',function(env,obj) obj.GetPos=function() error('position failed') end end},
        {'nil',function(env,obj) obj.GetPos=function() return nil end end},
        {'plain table',function(env,obj) obj.pos={x=1,y=2,z=3} end},
        {'throwing component',function(env,obj)
            obj.pos=setmetatable({__native=true},{__index=function() error('scalar failed') end})
            local old=env.isvector; env.isvector=function(p) return p.__native==true or old(p) end
        end},
    }
    for _,axis in ipairs({'x','y','z'}) do
        for _,variant in ipairs({'missing','string','NaN','+infinity','-infinity'}) do
            failures[#failures+1]={axis..' '..variant,function(env,obj)
                obj.pos=env.Vector(1,2,3)
                if variant=='missing' then obj.pos[axis]=nil elseif variant=='string' then obj.pos[axis]='3'
                elseif variant=='NaN' then obj.pos[axis]=0/0 elseif variant=='+infinity' then obj.pos[axis]=math.huge
                else obj.pos[axis]=-math.huge end
            end}
        end
    end
    for _,case in ipairs(failures) do
        test('nearest origin rejects '..case[1]..' without enemy reads',function()
            local env,admin,enemies=setup(); local previous=inspection(env,admin)
            for _,enemy in ipairs(enemies) do enemy.GetPos=function() error('origin rejection read enemy') end end
            case[2](env,admin); local lines,text=near(env,admin)
            eq(#lines,1); contains(text,'current world position is unavailable'); contains(text,'!listEventEnemies [page]')
            eq(inspection(env,admin),previous); eq(env.totalEnemies,3)
        end)
        test('nearest enemy retains unknown row for '..case[1],function()
            local env,admin,enemies=setup(2); case[2](env,enemies[1])
            local lines,text=near(env,admin); order(lines,{102,101}); contains(text,'listed 2')
            contains(rows(lines)[2],'world position unavailable; distance unavailable.')
            mark(env,admin,'102'); eq(#packets(env),1)
            remove(env,admin,'101'); eq(enemies[1].valid,false,'unknown row remains removable')
        end)
    end

    -- 6: Scaled norm, float arithmetic, representable extremes and overflows.
    local arithmetic={
        {'triangle',{3,4,12},13}, {'tiny triangle',{3e-200,4e-200,12e-200},13e-200},
        {'subnormal',{tonumber('4.9406564584124654e-324'),0,0},tonumber('4.9406564584124654e-324')},
        {'large triangle',{3e200,4e200,12e200},13e200},
        {'largest axis',{tonumber('1.7976931348623157e308'),0,0},tonumber('1.7976931348623157e308')},
        {'final norm overflow',{1.7e308,1.7e308,0},false},
        {'subtraction overflow',{1.7e308,0,0},false,{-1.7e308,0,0}},
        {'integer delta avoids wrapping',{9223372036854775807,0,0},9223372036854775807.0,{-9223372036854775807,0,0},1.8446744073709552e19},
    }
    for _,case in ipairs(arithmetic) do
        test('nearest arithmetic '..case[1],function()
            local env,admin,enemies=setup(2); local p=case[2]
            enemies[1].pos=env.Vector(p[1],p[2],p[3]); enemies[2].pos=env.Vector(0,0,0)
            if case[4] then local o=case[4]; admin.pos=env.Vector(o[1],o[2],o[3]); enemies[2].pos=env.Vector(o[1],o[2],o[3]) end
            local body=rows(near(env,admin)); order(body,{102,101})
            if case[3] then
                contains(body[2],'; ~'..string.format('%.6g',case[5] or case[3])..' units away.')
                local printed=tonumber(body[2]:match('; ~(%S+) units away%.')); assert(printed and printed>0,'positive finite distance cannot become zero or negative')
            else contains(body[2],'; distance unavailable.') end
        end)
    end

    -- 7: Actor and map refusal happens before positions and contains getters.
    for _,variant in ipairs({'nil','invalid','nonplayer','nonadmin','dead','throwing IsPlayer','throwing IsAdmin','throwing Alive'}) do
        test('nearest actor admission '..variant,function()
            local env,admin,enemies=setup(); local actor=admin; local reads=0
            admin.GetPos=function() reads=reads+1; error('forbidden origin read') end
            for _,enemy in ipairs(enemies) do enemy.GetPos=function() reads=reads+1; error('forbidden enemy read') end end
            if variant=='nil' then actor=nil elseif variant=='invalid' then admin.valid=false
            elseif variant=='nonplayer' then admin.class='worldspawn' elseif variant=='nonadmin' then admin.admin=false
            elseif variant=='dead' then admin.alive=false
            else local getter=variant:match('throwing (.+)'); admin[getter]=function() error('admission failed') end end
            eq(env.fire('PlayerSay',actor,'!nearEventEnemies'),''); eq(reads,0); eq(inspection(env,admin),nil); eq(env.totalEnemies,3)
        end)
    end
    for _,variant in ipairs({'empty','long','control','throwing'}) do
        test('nearest initial map '..variant,function()
            local env,admin,enemies=setup(); local reads=0
            admin.GetPos=function() reads=reads+1; error('unusable map read origin') end
            for _,enemy in ipairs(enemies) do enemy.GetPos=function() reads=reads+1; error('unusable map read enemy') end end
            if variant=='empty' then env.map='' elseif variant=='long' then env.map=string.rep('a',129)
            elseif variant=='control' then env.map='bad\nmap' else env.game.GetMap=function() error('map failed') end end
            local lines,text=near(env,admin); eq(#lines,1); contains(text,'map'); contains(text,'!listEventEnemies [page]')
            eq(reads,0); eq(inspection(env,admin),nil)
        end)
    end

    -- 8: Complete getter × capture-retirement matrix, plus both cross-mode directions.
    local boundaries={'IsPlayer','IsAdmin','Alive','GetMap','actor GetPos','enemy IsMarkedForDeletion','enemy EntIndex','enemy GetPos'}
    local actions={'new legacy page','new nearest page','new failed listing','disconnect','finish','replacement'}
    for _,boundary in ipairs(boundaries) do for _,action in ipairs(actions) do
        test('nearest capture '..boundary..' / '..action,function()
            local env,admin,enemies=setup(10); install(env,admin,'!listEventEnemies',1)
            local previous=inspection(env,admin); local inner; local triggered=false
            local object=boundary=='GetMap' and env.game or boundary:match('^enemy ') and enemies[1] or admin
            local getter=boundary:match(' (%S+)$') or boundary; local original=object[getter]
            object[getter]=function(...)
                object[getter]=original; triggered=true
                if action=='new legacy page' then install(env,admin,'!listEventEnemies',2); inner=inspection(env,admin)
                elseif action=='new nearest page' then install(env,admin,'!nearEventEnemies',2); inner=inspection(env,admin)
                elseif action=='new failed listing' then install(env,admin,'!nearEventEnemies',99); inner=previous
                elseif action=='disconnect' then env.fire('PlayerDisconnected',admin)
                elseif action=='finish' then for _,enemy in ipairs(enemies) do env.fire('OnNPCKilled',enemy,admin) end
                else
                    env.stopActivatorEvent(); local other=env.start(); other.admin=true
                end
                return original(...)
            end
            local result,lines,text=say(env,admin,'!nearEventEnemies')
            eq(result,'','outer nearest command consumed privately')
            assert(triggered,'actual callback boundary exercised')
            eq(inspection(env,admin),inner,'superseded nearest cannot overwrite removal authority')
            local grant=state(env).enemyMarkerGrants[admin]
            if action=='new legacy page' or action=='new nearest page' then
                assert(grant and grant.inspection==inner,'inner marker grant retained')
                eq(#rows(lines),2); contains(text,'page 2/2')
            else eq(grant,nil); eq(#rows(lines),0); assert(not text:find('Encounter changed during inspection',1,true),'obsolete rejection suppressed') end
        end)
    end end
    for _,source in ipairs({'actor','enemy'}) do for _,change in ipairs({'demotion','death','invalidation','map change','unavailable map'}) do
        test('nearest final admission after '..source..' position / '..change,function()
            local env,admin,enemies=setup(); install(env,admin,'!listEventEnemies'); local previous=inspection(env,admin)
            local obj=source=='actor' and admin or enemies[1]; local original=obj.GetPos
            obj.GetPos=function(self)
                obj.GetPos=original; local value=original(self)
                if change=='demotion' then admin.admin=false elseif change=='death' then admin.alive=false
                elseif change=='invalidation' then admin.valid=false elseif change=='map change' then env.map='gm_other'
                else env.map='' end; return value
            end
            near(env,admin); eq(inspection(env,admin),previous,'failed nearest retains removal page'); eq(state(env).enemyMarkerGrants[admin],nil)
        end)
    end end
    for _,getter in ipairs({'IsMarkedForDeletion','EntIndex','GetPos'}) do
        test('nearest outer superseded by legacy getter page '..getter,function()
            local env,admin,enemies=setup(10); local original=enemies[1][getter]
            enemies[1][getter]=function(...)
                enemies[1][getter]=original; install(env,admin,'!listEventEnemies',2); return original(...)
            end
            near(env,admin); mark(env,admin,'109'); eq(#packets(env),1)
            remove(env,admin,'101'); eq(enemies[1].valid,true)
            remove(env,admin,'109'); eq(enemies[9].valid,false)
        end)
        test('legacy outer preserves intentional removal exception after nearest getter page '..getter,function()
            local env,admin,enemies=setup(10); local original=enemies[1][getter]
            enemies[1][getter]=function(...)
                enemies[1][getter]=original; near(env,admin,2); return original(...)
            end
            install(env,admin,'!listEventEnemies'); mark(env,admin,'109'); mark(env,admin,'101'); eq(#packets(env),0)
            remove(env,admin,'101'); eq(enemies[1].valid,false,'legacy outer removal remains intentional')
        end)
    end
    test('nearest suppresses obsolete origin rejection after newer failed attempt',function()
        local env,admin=setup(); local original=admin.GetPos
        admin.GetPos=function(self) admin.GetPos=original; near(env,admin,'nope'); return nil end
        local _,lines,text=say(env,admin,'!nearEventEnemies'); eq(#lines,1); contains(text,'Usage:')
        assert(not text:find('current world position',1,true))
    end)

    for _,change in ipairs({'demotion','death','invalidation'}) do
        test('nearest rechecks admission immediately after origin '..change,function()
            local env,admin,enemies=setup(); local read=admin.GetPos; local enemyReads=0
            admin.GetPos=function(self)
                local point=read(self)
                if change=='demotion' then self.admin=false elseif change=='death' then self.alive=false else self.valid=false end
                return point
            end
            for _,enemy in ipairs(enemies) do enemy.GetPos=function(self) enemyReads=enemyReads+1; return self.pos end end
            near(env,admin); eq(enemyReads,0,'rejected origin context cannot read enemies'); eq(inspection(env,admin),nil)
        end)
    end

    for _,getter in ipairs({'IsPlayer','IsAdmin','Alive'}) do
        for _,change in ipairs({'changed','unavailable'}) do
            test('nearest final actor '..getter..' map '..change..' retains prior removal page',function()
                local env,admin,enemies=setup(10); install(env,admin,'!listEventEnemies',2)
                local previous=inspection(env,admin); local original=admin[getter]; local calls=0
                admin[getter]=function(self)
                    calls=calls+1
                    if calls==3 then
                        env.map=change=='changed' and 'gm_other' or ''; self[getter]=original
                    end
                    return original(self)
                end
                local lines=near(env,admin)
                eq(calls,3,'exercise final preinstall actor getter rather than initial admission')
                eq(inspection(env,admin),previous,'map loss during final actor getter must preserve prior removal identity')
                eq(#rows(lines),0,'refused nearest cannot print its page'); eq(state(env).enemyMarkerGrants[admin],nil)
                mark(env,admin,'109'); eq(#packets(env),0,'recognized failed nearest retires previous marker')
                remove(env,admin,'101'); eq(enemies[1].valid,true,'stale nearest row must not become removable')
                remove(env,admin,'109'); eq(enemies[9].valid,false,'old removal page retains its existing lack of map lease')
            end)
        end
    end
    test('nearest final actor getter with throwing map preserves prior removal page',function()
        local env,admin,enemies=setup(10); install(env,admin,'!listEventEnemies',2)
        local previous=inspection(env,admin); local original=admin.Alive; local calls=0
        admin.Alive=function(self)
            calls=calls+1
            if calls==3 then env.game.GetMap=function() error('final map unavailable') end; self.Alive=original end
            return original(self)
        end
        local lines=near(env,admin); eq(calls,3); eq(inspection(env,admin),previous)
        eq(#rows(lines),0); eq(state(env).enemyMarkerGrants[admin],nil)
        remove(env,admin,'101'); eq(enemies[1].valid,true); remove(env,admin,'109'); eq(enemies[9].valid,false)
    end)

    for _,change in ipairs({'demotion','death','invalidation'}) do
        test('nearest retained preinstall map read still validates actor '..change,function()
            local env,admin,enemies=setup(); install(env,admin,'!listEventEnemies'); local previous=inspection(env,admin)
            local original=env.game.GetMap; local calls=0
            env.game.GetMap=function()
                calls=calls+1
                if calls==2 then
                    env.game.GetMap=original
                    if change=='demotion' then admin.admin=false elseif change=='death' then admin.alive=false else admin.valid=false end
                end
                return original()
            end
            local lines=near(env,admin); eq(calls,2,'exercise retained preinstall map read')
            eq(inspection(env,admin),previous); eq(#rows(lines),0); eq(state(env).enemyMarkerGrants[admin],nil)
        end)
    end
    for _,action in ipairs({'new legacy page','new nearest page','new failed listing','disconnect','finish','replacement'}) do
        test('nearest final map confirmation respects '..action,function()
            local env,admin,enemies=setup(10); install(env,admin,'!listEventEnemies',2)
            local previous=inspection(env,admin); local inner; local original=env.game.GetMap; local calls=0
            env.game.GetMap=function()
                calls=calls+1
                if calls==3 then
                    env.game.GetMap=original
                    if action=='new legacy page' then install(env,admin,'!listEventEnemies',2); inner=inspection(env,admin)
                    elseif action=='new nearest page' then near(env,admin,2); inner=inspection(env,admin)
                    elseif action=='new failed listing' then near(env,admin,99); inner=previous
                    elseif action=='disconnect' then env.fire('PlayerDisconnected',admin)
                    elseif action=='finish' then for _,enemy in ipairs(enemies) do env.fire('OnNPCKilled',enemy,admin) end
                    else env.stopActivatorEvent(); local other=env.start(); other.admin=true end
                end
                return original()
            end
            local lines,text=near(env,admin)
            eq(calls,3,'exercise new final map confirmation rather than earlier map reads')
            eq(inspection(env,admin),inner,'newer page or retirement wins final map callback')
            local grant=state(env).enemyMarkerGrants[admin]
            if action=='new legacy page' or action=='new nearest page' then
                eq(#rows(lines),2); contains(text,'page 2/2'); assert(grant and grant.inspection==inner)
                mark(env,admin,'109'); eq(#packets(env),1)
            else eq(#rows(lines),0); eq(grant,nil); assert(not text:find('Nearest inspection context changed',1,true),'obsolete feedback suppressed') end
        end)
    end

    -- 9: Reply reentry retains all frozen output and never reinstalls outer authority.
    for _,action in ipairs({'new legacy page','new nearest page','movement and kill','completion','stop and replacement'}) do
        test('nearest first ChatPrint reentry '..action,function()
            local env,admin,enemies=setup(10); local _,frozen=near(env,admin); admin.chats={}
            local original=admin.ChatPrint; local outerLines={}; local inner
            admin.ChatPrint=function(self,line)
                outerLines[#outerLines+1]=line; original(self,line)
                if #outerLines==1 then
                    admin.ChatPrint=original
                    if action=='new legacy page' then install(env,admin,'!listEventEnemies',2); inner=inspection(env,admin)
                    elseif action=='new nearest page' then near(env,admin,2); inner=inspection(env,admin)
                    elseif action=='movement and kill' then enemies[1].pos.x=999; admin.pos.x=888; env.fire('OnNPCKilled',enemies[1],admin); inner=inspection(env,admin)
                    elseif action=='completion' then for _,enemy in ipairs(enemies) do env.fire('OnNPCKilled',enemy,admin) end
                    else env.stopActivatorEvent(); local other=env.start(); other.admin=true end
                    admin.ChatPrint=function(self,nextLine) outerLines[#outerLines+1]=nextLine; original(self,nextLine) end
                end
            end
            near(env,admin); eq(table.concat(outerLines,'\n'),frozen,'all outer output frozen before first reply')
            eq(inspection(env,admin),inner,'newest authority survives remaining replies')
            if action=='new legacy page' or action=='new nearest page' then mark(env,admin,'109'); eq(#packets(env),1) end
        end)
    end

    -- 10: Genuine exact-object marker/removal admission and intentional differences.
    test('nearest selected token is an entity index rather than rank with mark-time position',function()
        local env,admin,enemies=setup(10); enemies[10].pos=env.Vector(0.1,0,0)
        near(env,admin); enemies[10].pos=env.Vector(7.25,-8.5,9.75)
        local all=mark(env,admin,'110'); eq(#all,1); local out=all[1]
        eq(out.player,admin); eq(out.values[3],'event_enemy'); eq(out.values[4],'110')
        eq(out.values[5],7.25); eq(out.values[6],-8.5); eq(out.values[7],9.75); eq(out.values[8],env.now+15)
        mark(env,admin,'1'); eq(#packets(env),1); remove(env,admin,'1'); eq(enemies[10].valid,true)
        remove(env,admin,'110'); eq(enemies[10].valid,false); eq(env.totalEnemies,9)
        for _,enemy in ipairs(enemies) do env.fire('OnNPCKilled',enemy,admin) end
        eq(env.messageCount('roundFinished'),0,'cleanup never awards victory')
    end)
    for _,kind in ipairs({'off page','other admin','unindexed','duplicate across pages','changed index','reused index','killed','deleting'}) do
        test('nearest exact actions reject '..kind,function()
            local env,admin,enemies=setup(10); local target=enemies[1]
            if kind=='unindexed' then target.index=0 elseif kind=='duplicate across pages' then enemies[10].index=101 end
            near(env,admin,kind=='off page' and 2 or 1)
            if kind=='other admin' then admin=env.entity('player'); admin.admin=true
            elseif kind=='changed index' then target.index=909
            elseif kind=='reused index' then target.valid=false; local other=env.entity(target.class); other.index=101
            elseif kind=='killed' then env.fire('OnNPCKilled',target,admin)
            elseif kind=='deleting' then target.markedForDeletion=true end
            mark(env,admin,'101'); eq(#packets(env),0); remove(env,admin,'101')
            assert(not state(env).enemyRemovalRequests[target],'no rejected target removal requested')
            if kind=='duplicate across pages' then near(env,admin,2); mark(env,admin,'101'); eq(#packets(env),0); remove(env,admin,'101'); eq(enemies[10].valid,true) end
        end)
    end
    test('nearest unique unknown-distance row can mark its later readable position',function()
        local env,admin,enemies=setup(2); local original=enemies[1].GetPos
        enemies[1].GetPos=function() return nil end
        near(env,admin); enemies[1].GetPos=original; enemies[1].pos=env.Vector(1.25,2.5,3.75)
        mark(env,admin,'101'); local all=packets(env); eq(#all,1)
        eq(all[1].values[4],'101'); eq(all[1].values[5],1.25); eq(all[1].values[6],2.5); eq(all[1].values[7],3.75)
        remove(env,admin,'101'); eq(enemies[1].valid,false)
    end)
    test('nearest deferred cleanup consumes permission before replay across admins',function()
        local env,admin,enemies=setup(2); local other=env.entity('player'); other.admin=true
        near(env,admin); near(env,other); env.deferRemoval=true; local count=0; local original=enemies[1].Remove
        enemies[1].Remove=function(self)
            count=count+1; remove(env,admin,'101'); remove(env,other,'101'); original(self)
        end
        remove(env,admin,'101'); eq(count,1); eq(env.totalEnemies,2); eq(enemies[1].markedForDeletion,true)
        mark(env,other,'101'); eq(#packets(env),0); env.flushRemovals(); eq(env.totalEnemies,1)
        remove(env,admin,'102'); eq(enemies[2].valid,true,'consumed page cannot remove second row')
    end)
    for _,kind in ipairs({'malformed','out-of-range','origin','map','dead','demoted'}) do
        test('nearest failed '..kind..' retains removal and retires marker',function()
            local env,admin,enemies=setup(); near(env,admin); local previous=inspection(env,admin); local get=admin.GetPos
            if kind=='origin' then admin.GetPos=function() return nil end elseif kind=='map' then env.map=''
            elseif kind=='dead' then admin.alive=false elseif kind=='demoted' then admin.admin=false end
            near(env,admin,kind=='malformed' and 'nope' or kind=='out-of-range' and 99 or nil)
            eq(inspection(env,admin),previous); eq(state(env).enemyMarkerGrants[admin],nil)
            admin.GetPos=get; env.map='gm_construct'; admin.alive=true; admin.admin=true
            mark(env,admin,'101'); eq(#packets(env),0); remove(env,admin,'101'); eq(enemies[1].valid,false)
        end)
    end
    for _,outer in ipairs({'!listEventEnemies','!nearEventEnemies'}) do
        test('nearest successful mode switch replaces actual page from '..outer,function()
            local env,admin,enemies=setup(10); install(env,admin,outer,1)
            install(env,admin,outer=='!listEventEnemies' and '!nearEventEnemies' or '!listEventEnemies',2)
            mark(env,admin,'101'); eq(#packets(env),0); remove(env,admin,'101'); eq(enemies[1].valid,true)
            mark(env,admin,'109'); eq(#packets(env),1); remove(env,admin,'109'); eq(enemies[9].valid,false)
        end)
    end
    test('nearest construction diagnostic cannot acquire delayed marker authority',function()
        local env=gmod.new(); local admin=env.entity('player'); admin.admin=true; local create=env.ents.Create; local captured
        local count=0
        env.ents.Create=function(class)
            local enemy=create(class)
            if class=='npc_stalker' then
                count=count+1; enemy.index=100+count
                if count==2 then near(env,admin); captured=inspection(env,admin); assert(captured and captured.targets['101']); mark(env,admin,'101'); eq(#packets(env),0) end
            end
            return enemy
        end
        env.fireTimer('activatorSpawner'); local actor=env.ents.FindByClass('activatorent')[1]; admin.pos=actor.pos
        actor:AcceptInput('Use',admin,admin); env.receive('SendNPCInformation',admin,'Raid')
        assert(captured); mark(env,admin,'101'); eq(#packets(env),0); near(env,admin); mark(env,admin,'101'); eq(#packets(env),1)
    end)
    test('nearest interrupted paused and map-changed removal retain existing contracts',function()
        local env,admin,enemies=setup(); near(env,admin); remove(env,admin,'103')
        env.fire('PlayerSay',admin,'!pauseActivatorSpawns'); near(env,admin); mark(env,admin,'101'); eq(#packets(env),1)
        env.map='gm_other'; mark(env,admin,'101'); eq(#packets(env),1,'marker retains map lease')
        remove(env,admin,'101'); eq(enemies[1].valid,false,'removal has no map lease')
        eq(env.timers.activatorSpawner.stopped,true); eq(env.messageCount('roundFinished'),0)
    end)
    test('nearest attempt cancels in-flight shared spawn marker operation',function()
        local env,admin=setup(); env.fire('PlayerSay',admin,'!listSpawns enemy')
        local original=admin.Alive; local result; local triggered=false
        admin.Alive=function(self)
            admin.Alive=original; triggered=true
            result=env.fire('PlayerSay',admin,'!nearEventEnemies nope'); return original(self)
        end
        env.fire('PlayerSay',admin,'!markSpawn enemy 1'); assert(triggered); eq(result,''); eq(#packets(env),0)
    end)

    -- 11: Frozen default bytes and native access/callback order.
    test('nearest increment preserves default byte and scalar access parity',function()
        local env,admin,enemies=setup(2); local trace={}; local native=env.isvector
        env.isvector=function(p) trace[#trace+1]='isvector'; return native(p) or p.native==true end
        admin.GetPos=function() error('legacy path read requester origin') end
        local expected={}
        for i,enemy in ipairs(enemies) do
            local values={x=i,y=0,z=0}; local tag=tostring(i)
            enemy.GetPos=function() trace[#trace+1]=tag..':GetPos'; return setmetatable({native=true},{__index=function(_,axis)
                trace[#trace+1]=tag..':'..axis; return values[axis]
            end}) end
            enemy.IsMarkedForDeletion=function() trace[#trace+1]=tag..':deleting'; return false end
            enemy.EntIndex=function() trace[#trace+1]=tag..':index'; return 100+i end
        end
        local _,lines,text=say(env,admin,'!listEventEnemies')
        local frozen={'Active encounter: "Raid".','Enemy locations, page 1/1: progress 2/2; listed 2; omitted invalid/deleting 0.',
            'Entity index 101: approx rounded world position (1, 0, 0).','Entity index 102: approx rounded world position (2, 0, 0).',
            'Temporary entity indices can be reused. !listEventEnemies [page] (1-1); fresh snapshot.',
            "!removeEventEnemy <index> requests one listed enemy's removal; interrupts the encounter (no victory). List again after each request."}
        eq(text,table.concat(frozen,'\n'),'frozen baseline response bytes')
        eq(#trace,20)
        for offset=1,#trace,10 do
            local tag=trace[offset]:match('^(%d):deleting$'); assert(tag)
            local sequence={tag..':deleting',tag..':index',tag..':GetPos','isvector',tag..':x',tag..':y',tag..':z',tag..':x',tag..':y',tag..':z'}
            for j,value in ipairs(sequence) do eq(trace[offset+j-1],value,'default native callback order') end
        end
        local _,_,again=say(env,admin,'!listEventEnemies 01'); eq(again,text)
        local _,_,bad=say(env,admin,'!listEventEnemies nope'); eq(bad,'Usage: !listEventEnemies [page]; page must be a positive integer.')
        eq(#lines,6)
    end)

    -- 12: Inspection only; no constructor/encounter/configuration subsystem changes.
    test('nearest inspection preserves state identities and traps every unrelated side effect',function()
        local env,admin,enemies=setup(); env.fire('PlayerSay',admin,'!nextEvent Raid')
        local observer=env.entity('player'); local entityCount=#env.entities
        local before=state(env); local originalOwners=before.activeEnemies
        local preserved={}; local seen={}
        local function capture(value)
            if type(value)~='table' or seen[value] then return end; seen[value]=true
            local copy={}; preserved[value]=copy
            for key,child in pairs(value) do if key~='chats' then copy[key]=child; capture(child) end end
        end
        for name,value in pairs(before) do if not name:match('^enemy') then capture(value) end end
        capture(env.SpawnPositions); capture(env.NPCEdits); capture(env.timers); capture(env.entities)
        local attempts={}; local originals={}
        local function trap(obj,key)
            originals[#originals+1]={obj,key,rawget(obj,key)}
            obj[key]=function() attempts[#attempts+1]=key; error('forbidden '..key) end
        end
        env.math=setmetatable({},{__index=math})
        for _,key in ipairs({'random','randomseed'}) do trap(env.math,key) end
        for _,key in ipairs({'Create','Start','Stop','Simple','Adjust','Remove'}) do trap(env.timer,key) end
        for _,key in ipairs({'Read','Write','Append','Delete','Exists','CreateDir'}) do trap(env.file,key) end
        for _,key in ipairs({'Create','FindByClass','FindByName'}) do trap(env.ents,key) end
        for _,key in ipairs({'Start','Send','Broadcast','WriteEntity','WriteString','WriteDouble','WriteBool','WriteUInt'}) do trap(env.net,key) end
        for _,key in ipairs({'determineRandomEvent','returnNPCInformation','returnSpawnPositions','returnActivatorSpawns','destroyActivators','stopActivatorEvent','Vector','Entity'}) do trap(env,key) end
        for _,enemy in ipairs(env.entities) do
            for _,key in ipairs({'Remove','FinishRemoval','Spawn','SetPos','SetName','SetHealth','SetModel','SetMoveType','StopMoving','TakeDamage','Fire'}) do trap(enemy,key) end
        end
        local lines,text=near(env,admin); eq(#rows(lines),3); contains(text,'listed 3')
        for _,entry in ipairs(originals) do entry[1][entry[2]]=entry[3] end
        env.math=nil; eq(#attempts,0,'no trapped access can be hidden by pcall')
        eq(#env.entities,entityCount); eq(#observer.chats,0)
        local after=state(env)
        for key,value in pairs(before) do if not key:match('^enemy') then eq(after[key],value,'state identity '..key) end end
        eq(after.activeEnemies,originalOwners); eq(env.totalEnemies,3)
        for obj,copy in pairs(preserved) do
            for key,value in pairs(copy) do eq(obj[key],value,'nested state '..tostring(key)) end
            for key,value in pairs(obj) do if key~='chats' then eq(copy[key],value,'no added nested state '..tostring(key)) end end
        end
    end)
end
