-- Finite mounted-handler checks; native entity behavior/chat delivery is unverified.
return function(gmod, test, eq)
    local function contains(text, wanted) assert(text:find(wanted, 1, true), 'missing '..wanted..' in '..text) end
    local function state(env)
        local found, seen = {}, {}
        local wanted = {enemyInspections=true, enemyMarkerCaptures=true, enemyMarkerGrants=true,
            enemyHealthRequests=true, enemyRemovalRequests=true, activeEnemies=true, eventActive=true,
            eventInterrupted=true, constructingEnemies=true, pendingSelection=true}
        local function visit(fn)
            if seen[fn] then return end; seen[fn]=true
            for i=1,100 do
                local name,value=debug.getupvalue(fn,i); if not name then break end
                if wanted[name] then found[name]=value end
                if type(value)=='function' then visit(value) end
            end
        end
        for _,hooks in pairs(env.hooks) do for _,fn in pairs(hooks) do visit(fn) end end
        return found
    end
    local function setup(count)
        local env=gmod.new(); env.NPCEdits[1].information.maxNPCs=count or 3
        local admin,enemies=env.start(); admin.admin=true; admin.chats={}; admin.pos=env.Vector(0,0,0)
        for i,enemy in ipairs(enemies) do
            enemy.index=100+i; enemy.pos=env.Vector(i,0,0); enemy.health=75; enemy.maximum=100
            enemy.observedClass='npc_stalker'; enemy.observationOrder={}
            -- Observation doubles deliberately stay local to this module.
            enemy.Health=function(self)
                self.healthReads=(self.healthReads or 0)+1; self.observationOrder[#self.observationOrder+1]='Health'; return self.health
            end
            enemy.GetMaxHealth=function(self)
                self.maxReads=(self.maxReads or 0)+1; self.observationOrder[#self.observationOrder+1]='GetMaxHealth'; return self.maximum
            end
            enemy.GetClass=function(self)
                self.classReads=(self.classReads or 0)+1; self.observationOrder[#self.observationOrder+1]='GetClass'; return self.observedClass
            end
        end
        return env,admin,enemies
    end
    local function say(env, admin, text)
        local before=admin and #admin.chats or 0
        local result=env.fire('PlayerSay',admin,text)
        local lines={}
        if admin then for i=before+1,#admin.chats do
            local line=admin.chats[i]; assert(#line<=255); assert(not line:find('%c')); lines[#lines+1]=line
        end end
        return result,lines,table.concat(lines,'\n')
    end
    local function inspect(env, admin, token)
        local result,lines,text=say(env,admin,'!inspectEventEnemy'..(token and ' '..token or ''))
        eq(result,'','health command consumed privately'); return lines,text
    end
    local function list(env,admin,mode,page)
        eq(env.fire('PlayerSay',admin,(mode or '!listEventEnemies')..(page and ' '..page or '')),'')
        return state(env).enemyInspections[admin]
    end
    local function noDetail(lines)
        for _,line in ipairs(lines) do
            assert(not line:find('Health() =',1,true),'obsolete health detail: '..line)
            assert(not line:find('GetClass() =',1,true),'obsolete class detail: '..line)
        end
    end
    local function refused(env,admin,token)
        local lines,text=inspect(env,admin,token or '101'); noDetail(lines)
        eq(#lines,1); contains(text,'list'); return lines,text
    end
    local function detail(env,admin,token,current,maximum,class)
        local lines,text=inspect(env,admin,token or '101'); eq(#lines,1)
        contains(text,'Encounter enemy index '..(token or '101')..': Health() = '..(current or '75')..'; GetMaxHealth() = '..(maximum or '100')..'; GetClass() = '..(class or '"npc_stalker"')..'.')
        contains(text,'Observed game values; may change.'); return lines,text
    end

    for _,mode in ipairs({'!listEventEnemies','!nearEventEnemies'}) do
        test('health reads the exact '..mode..' target once at inspection time',function()
            local env,admin,enemies=setup(); local page=list(env,admin,mode)
            for _,enemy in ipairs(enemies) do eq(enemy.healthReads,nil); eq(enemy.maxReads,nil); eq(enemy.classReads,nil) end
            enemies[1].health=29; enemies[1].maximum=64; enemies[1].observedClass='npc_changed'
            env.NPCEdits=setmetatable({}, {__index=function() error('inspection must not read configuration') end})
            env.returnNPCInformation=function() error('inspection must not look up the next event') end
            detail(env,admin,'101','29','64','"npc_changed"')
            eq(enemies[1].healthReads,1); eq(enemies[1].maxReads,1); eq(enemies[1].classReads,1)
            eq(table.concat(enemies[1].observationOrder,','),'Health,GetMaxHealth,GetClass')
            for i=2,#enemies do eq(enemies[i].healthReads,nil); eq(enemies[i].maxReads,nil); eq(enemies[i].classReads,nil) end
            eq(state(env).enemyInspections[admin],page)
        end)
    end
    test('health exact route yields before unrelated shared guards',function()
        local env,admin=setup(); local shared=env.hooks.PlayerSay.setUpSpawnPoints
        assert(shared,'shared config handler'); admin.IsPlayer=function() error('unrelated shared guard') end
        eq(shared(admin,'!inspectEventEnemy 101'),nil)
    end)
    test('health command whitespace is accepted without index normalization',function()
        local env,admin=setup(); list(env,admin)
        local result,lines,text=say(env,admin,'!inspectEventEnemy \t101 \t'); eq(result,''); eq(#lines,1); contains(text,'Health() = 75')
        for _,token in ipairs({'0101','+101','101.0','1.01e2'}) do refused(env,admin,token) end
    end)
    for _,argument in ipairs({'','101 102','101 extra',string.rep('9',65),'101\0','101\1'}) do
        test('health malformed token is private '..string.format('%q',argument),function()
            local env,admin,enemies=setup(); list(env,admin)
            local lines,text=inspect(env,admin,argument); eq(#lines,1); contains(text,'Usage: !inspectEventEnemy'); noDetail(lines)
            eq(enemies[1].healthReads,nil); eq(enemies[1].classReads,nil)
        end)
    end
    test('health exact command lookalikes keep existing handling',function()
        local env,admin=setup()
        for _,text in ipairs({'!inspectEventEnemyOther 101','hello !inspectEventEnemy 101',' !inspectEventEnemy 101','!inspecteventenemy 101'}) do
            local result,lines=say(env,admin,text); eq(result,nil); eq(#lines,0)
        end
    end)
    for _,kind in ipairs({'nil','invalid','nonplayer','nonadmin','throwing admin'}) do
        test('health invalid caller has no detail: '..kind,function()
            local env,admin,enemies=setup(); list(env,admin)
            if kind=='nil' then admin=nil elseif kind=='invalid' then admin.valid=false
            elseif kind=='nonplayer' then admin.class='worldspawn' elseif kind=='nonadmin' then admin.admin=false
            else admin.IsAdmin=function() error('private admission error') end end
            local before=admin and #admin.chats or 0
            -- Call the mounted owning hook; unrelated legacy hooks do not accept nil.
            eq(env.hooks.PlayerSay.selectNextActivatorEvent(admin,'!inspectEventEnemy 101'),'')
            if admin then eq(#admin.chats,before) end; eq(enemies[1].healthReads,nil); eq(enemies[1].classReads,nil)
        end)
    end
    test('health dead admin needs neither Alive nor requester position',function()
        local env,admin=setup(); list(env,admin); admin.alive=false
        admin.Alive=function() error('health must not require alive') end
        admin.GetPos=function() error('health must not read position') end
        detail(env,admin)
    end)
    for _,kind in ipairs({'absent','off page','unindexed','duplicate','changed index','reused index','removed','killed','deleting'}) do
        test('health rejects unavailable exact selection: '..kind,function()
            local env,admin,enemies=setup(9)
            if kind=='unindexed' then enemies[1].index=0 elseif kind=='duplicate' then enemies[2].index=101 end
            if kind~='absent' then list(env,admin) end
            local token=kind=='off page' and '109' or '101'
            if kind=='changed index' then enemies[1].index=201 elseif kind=='removed' or kind=='reused index' then
                enemies[1]:Remove(); if kind=='reused index' then local replacement=env.entity('npc_stalker'); replacement.index=101; replacement.Health=function() error('replacement lookup') end end
            elseif kind=='killed' then env.fire('OnNPCKilled',enemies[1],admin)
            elseif kind=='deleting' then enemies[1].markedForDeletion=true end
            refused(env,admin,token); eq(enemies[1].healthReads,nil); eq(enemies[1].classReads,nil)
        end)
    end
    test('health selection is private per admin and newer pages supersede it',function()
        local env,admin=setup(9); local other=env.entity('player'); other.admin=true
        list(env,admin); refused(env,other); list(env,other,'!nearEventEnemies',2)
        detail(env,other,'109'); refused(env,other,'101'); detail(env,admin)
        list(env,admin,'!listEventEnemies',2); refused(env,admin); detail(env,admin,'109')
    end)
    for _,mode in ipairs({'!listEventEnemies','!nearEventEnemies'}) do
        for _,failure in ipairs({'0','two','100'}) do
            test('health newer failed '..mode..' '..failure..' invalidates old page',function()
                local env,admin=setup(); list(env,admin); list(env,admin,mode,failure); refused(env,admin)
            end)
        end
        test('health waits until every '..mode..' server reply returns',function()
            local env,admin=setup(); local chat=admin.ChatPrint; local probes=0
            admin.ChatPrint=function(self,text)
                chat(self,text)
                if not text:find('Health inspection',1,true) and not text:find('Usage: !inspectEventEnemy',1,true) then
                    probes=probes+1; local lines=inspect(env,admin,'101'); noDetail(lines)
                end
            end
            list(env,admin,mode); admin.ChatPrint=chat; assert(probes>5); detail(env,admin)
        end)
        test('health rejects '..mode..' page whose server reply throws',function()
            local env,admin=setup(); local chat=admin.ChatPrint
            admin.ChatPrint=function() error('chat unavailable') end
            pcall(list,env,admin,mode); admin.ChatPrint=chat; refused(env,admin)
        end)
        test('health old '..mode..' replies cannot complete a newer page',function()
            local env,admin=setup(9); local chat=admin.ChatPrint; local once=false
            admin.ChatPrint=function(self,text)
                chat(self,text)
                if not once then once=true; list(env,admin,mode,2) end
            end
            list(env,admin,mode); admin.ChatPrint=chat; refused(env,admin,'101'); detail(env,admin,'109')
        end)
    end
    test('health construction page never gains eligibility after construction ends',function()
        local env=gmod.new(); local admin,actor=env.ready(); admin.admin=true
        local create=env.ents.Create; local seen=0; local token
        env.ents.Create=function(class)
            if class=='npc_stalker' then seen=seen+1; if seen==2 then
                token=next(list(env,admin).targets); assert(token,'construction has a listed tracked enemy'); refused(env,admin,token)
            end end
            return create(class)
        end
        actor:AcceptInput('Use',admin,admin); env.receive('SendNPCInformation',admin,'Raid')
        assert(seen>=2); refused(env,admin,token)
    end)
    for _,transition in ipairs({'map changed','map missing','map throws','disconnect','initialize','stop','complete','replacement'}) do
        test('health lifecycle rejects old page: '..transition,function()
            local env,admin,enemies=setup(); list(env,admin)
            if transition=='map changed' then env.map='other_map' elseif transition=='map missing' then env.map=nil
            elseif transition=='map throws' then env.game.GetMap=function() error('map error') end
            elseif transition=='disconnect' then env.fire('PlayerDisconnected',admin)
            elseif transition=='initialize' then env.fire('Initialize')
            elseif transition=='complete' then for _,enemy in ipairs(enemies) do env.fire('OnNPCKilled',enemy,admin) end
            else env.stopActivatorEvent(); if transition=='replacement' then env.start() end end
            local classReads=enemies[1].classReads -- Retirement's EntityRemoved fallback may read class.
            refused(env,admin); eq(enemies[1].healthReads,nil); eq(enemies[1].classReads,classReads,'refused inspection adds no class read')
        end)
    end
    test('health pending cleanup blocks only its exact target and accepts paused interrupted survivors',function()
        local env,admin,enemies=setup(); local other=env.entity('player'); other.admin=true
        list(env,admin); list(env,other); env.deferRemoval=true
        eq(env.fire('PlayerSay',other,'!removeEventEnemy 101'),'')
        enemies[1].markedForDeletion=false -- Pending-request ownership independently blocks it.
        refused(env,admin); detail(env,admin,'102'); eq(state(env).eventInterrupted,true)
        eq(env.fire('PlayerSay',admin,'!pauseActivatorSpawns'),''); detail(env,admin,'102')
        refused(env,other,'102'); enemies[1].markedForDeletion=true; env.flushRemovals(); detail(env,admin,'102')
    end)
    test('health pending next event and elapsed time do not revoke or renew exact page',function()
        local env,admin=setup(); local page=list(env,admin); env.now=100000
        eq(env.fire('PlayerSay',admin,'!nextEvent Raid'),''); detail(env,admin)
        eq(state(env).enemyInspections[admin],page)
    end)

    local cases={
        {'missing',nil,'unavailable'}, {'throwing',function() error('sensitive raw exception') end,'unavailable'},
        {'nil',function() return nil end,'invalid nonnumeric'}, {'string',function() return '75' end,'invalid nonnumeric'},
        {'boolean',function() return true end,'invalid nonnumeric'},
        {'table',function() return setmetatable({}, {__tostring=function() error('must not stringify') end}) end,'invalid nonnumeric'},
        {'NaN',function() return 0/0 end,'invalid nonfinite'}, {'positive infinity',function() return math.huge end,'invalid nonfinite'},
        {'negative infinity',function() return -math.huge end,'invalid nonfinite'},
    }
    for _,method in ipairs({'Health','GetMaxHealth'}) do
        for _,case in ipairs(cases) do
            test('health independent '..method..' '..case[1]..' diagnostic',function()
                local env,admin,enemies=setup(); list(env,admin); enemies[1][method]=case[2]
                local _,text=detail(env,admin,'101',method=='Health' and case[3] or '75',method=='GetMaxHealth' and case[3] or '100')
                assert(not text:find('sensitive raw exception',1,true))
                eq(method=='Health' and enemies[1].maxReads or enemies[1].healthReads,1); eq(enemies[1].classReads,1)
            end)
        end
    end
    for _,value in ipairs({0,-12,0.25,-0.125,275,1.2345678901234567,1e-200,1e200,9007199254740991,math.maxinteger or 2147483647}) do
        test('health finite numeric observations round trip '..tostring(value),function()
            local env,admin,enemies=setup(); list(env,admin); enemies[1].health=value; enemies[1].maximum=value
            local lines,text=inspect(env,admin,'101'); eq(#lines,1)
            local current,maximum=text:match('Health%(%) = (.-); GetMaxHealth%(%) = (.-); GetClass%(%) =')
            eq(tonumber(current),value); eq(tonumber(maximum),value)
        end)
    end
    test('health above assigned max is displayed independently',function()
        local env,admin,enemies=setup(); list(env,admin); enemies[1].health=200; enemies[1].maximum=-2
        detail(env,admin,'101','200','-2')
    end)

    local classCases={
        {'missing',nil,'unavailable'}, {'non-callable',true,'unavailable'},
        {'throwing',function() error('private class exception') end,'unavailable'},
        {'nil',function() return nil end,'invalid nonstring'}, {'number',function() return 75 end,'invalid nonstring'},
        {'boolean',function() return false end,'invalid nonstring'},
        {'function',function() return function() end end,'invalid nonstring'},
        {'hostile table',function() return setmetatable({}, {__tostring=function() error('must not stringify class') end}) end,'invalid nonstring'},
        {'empty',function() return '' end,'invalid empty string'},
    }
    for _,case in ipairs(classCases) do
        test('class independent '..case[1]..' diagnostic preserves health',function()
            local env,admin,enemies=setup(); list(env,admin); enemies[1].GetClass=case[2]
            local _,text=detail(env,admin,'101','75','100',case[3]); assert(not text:find('private class exception',1,true))
            eq(enemies[1].healthReads,1); eq(enemies[1].maxReads,1)
        end)
    end
    for _,kind in ipairs({'inherited','throwing lookup'}) do
        test('class protected method lookup: '..kind,function()
            local env,admin,enemies=setup(); list(env,admin); local reads=0; enemies[1].GetClass=nil
            setmetatable(enemies[1],{__index=function(_,key)
                if key=='GetClass' then
                    reads=reads+1; if kind=='throwing lookup' then error('private class lookup') end
                    return function(self) eq(self,enemies[1]); return 'inherited_class' end
                end
            end})
            detail(env,admin,'101','75','100',kind=='inherited' and '"inherited_class"' or 'unavailable'); eq(reads,1)
        end)
    end
    test('class byte escaping keeps quotes slashes controls and high bytes on one private line',function()
        local env,admin,enemies=setup(); list(env,admin); enemies[1].observedClass='npc"\\\0\n\127\195\169'
        detail(env,admin,'101','75','100','"npc\\x22\\x5C\\x00\\x0A\\x7F\\xC3\\xA9" [escaped]')
    end)
    for _,kind in ipairs({'exact escape boundary','truncated escape','long ASCII'}) do
        test('class bounded payload preserves longest index and numeric observations: '..kind,function()
            local env,admin,enemies=setup(1); local enemy=enemies[1]
            enemy.index=1.7976931348623157e308; enemy.health=-1.7976931348623157e308; enemy.maximum=-1.2345678901234567e-200
            enemy.observedClass=kind=='long ASCII' and string.rep('A',4096) or string.rep('\1',kind=='exact escape boundary' and 14 or 15)
            local token='1.7976931348623157e+308'; list(env,admin)
            local expected=kind=='long ASCII' and ('"'..string.rep('A',56)..'" [truncated]')
                or ('"'..string.rep('\\x01',14)..'" [escaped]'..(kind=='truncated escape' and ' [truncated]' or ''))
            local lines,text=detail(env,admin,token,'-1.7976931348623157e+308','-1.2345678901234567e-200',expected)
            if kind=='truncated escape' then eq(#text,255,'actual full reply budget') end
            eq(tonumber(text:match('index (%S+):')),enemy.index)
        end)
    end
    test('class computed budget retains diagnostic health fields and complete disclaimer',function()
        local env,admin,enemies=setup(); list(env,admin)
        enemies[1].Health=function() return {} end; enemies[1].maximum=math.huge; enemies[1].observedClass=string.rep('\1',4096)
        local lines,text=inspect(env,admin,'101'); eq(#lines,1)
        contains(text,'Health() = invalid nonnumeric; GetMaxHealth() = invalid nonfinite; GetClass() = "')
        contains(text,'" [escaped] [truncated]. Observed game values; may change.')
        local payload=assert(text:match('GetClass%(%) = "(.-)"')); assert(#payload>56); eq(payload:gsub('\\x01',''),'')
    end)
    test('class mutation leaves earlier health observations frozen without rereading',function()
        local env,admin,enemies=setup(); list(env,admin); local original=enemies[1].GetClass
        enemies[1].GetClass=function(self) self.health=5; self.maximum=10; return original(self) end
        detail(env,admin); eq(enemies[1].healthReads,1); eq(enemies[1].maxReads,1); eq(enemies[1].classReads,1)
        eq(enemies[1].health,5); eq(enemies[1].maximum,10)
    end)

    for _,method in ipairs({'Health','GetMaxHealth','GetClass'}) do
        for _,transition in ipairs({'nested inspection','relisting','failed listing','cleanup','other cleanup','retirement','replacement','disconnect','initialize','demotion','target deletion','map change','index change'}) do
            test('health '..method..' reentry: '..transition,function()
                local env,admin,enemies=setup(); list(env,admin); local original=enemies[1][method]; local once=false
                local classReadsAfterTransition
                enemies[1][method]=function(self)
                    if not once then
                        once=true
                        if transition=='nested inspection' then detail(env,admin,'102')
                        elseif transition=='relisting' then list(env,admin,'!nearEventEnemies')
                        elseif transition=='failed listing' then list(env,admin,'!listEventEnemies','0')
                        elseif transition=='cleanup' then env.deferRemoval=true; env.fire('PlayerSay',admin,'!removeEventEnemy 101')
                        elseif transition=='other cleanup' then
                            local other=env.entity('player'); other.admin=true; list(env,other)
                            env.deferRemoval=true; env.fire('PlayerSay',other,'!removeEventEnemy 101'); self.markedForDeletion=false
                        elseif transition=='retirement' or transition=='replacement' then
                            env.stopActivatorEvent(); if transition=='replacement' then env.start() end
                        elseif transition=='disconnect' then env.fire('PlayerDisconnected',admin)
                        elseif transition=='initialize' then env.fire('Initialize')
                        elseif transition=='demotion' then admin.admin=false
                        elseif transition=='target deletion' then self:Remove()
                        elseif transition=='map change' then env.map='elsewhere'
                        elseif transition=='index change' then self.index=500 end
                        -- Existing retirement cleanup may itself call GetClass; freeze its completed reads.
                        classReadsAfterTransition=self.classReads
                    end
                    return original(self)
                end
                local lines=inspect(env,admin,'101'); assert(once)
                local details=0
                for _,line in ipairs(lines) do if line:find('Health() =',1,true) then details=details+1; contains(line,'index 102:') end end
                eq(details,transition=='nested inspection' and 1 or 0)
                if method=='Health' then eq(enemies[1].maxReads,nil,'do not call next getter after lost ownership') end
                if method~='GetClass' then eq(enemies[1].classReads,classReadsAfterTransition,'do not read class after lost ownership') end
                eq(state(env).enemyHealthRequests[admin],nil,'request retired without restoring a newer token')
                if transition=='relisting' then detail(env,admin) end
            end)
        end
    end
    test('health nested inspection by another admin keeps both independent replies',function()
        local env,admin,enemies=setup(); local other=env.entity('player'); other.admin=true
        list(env,admin); list(env,other); local original=enemies[1].Health; local once=false
        enemies[1].Health=function(self) if not once then once=true; detail(env,other,'102') end; return original(self) end
        detail(env,admin); eq(enemies[1].healthReads,1)
    end)
    for _,transition in ipairs({'nested inspection','relisting','cleanup','disconnect'}) do
        test('health feedback reentry preserves newer state: '..transition,function()
            local env,admin,enemies=setup(); local old=list(env,admin); local chat=admin.ChatPrint; local once=false; local newer
            admin.ChatPrint=function(self,text)
                chat(self,text)
                if not once and text:find('Health() =',1,true) then
                    once=true; eq(state(env).enemyHealthRequests[admin],nil,'retire before feedback')
                    contains(text,'GetClass() = "npc_stalker"'); enemies[1].observedClass='changed_after_reply'
                    if transition=='nested inspection' then detail(env,admin,'102')
                    elseif transition=='relisting' then newer=list(env,admin,'!nearEventEnemies')
                    elseif transition=='cleanup' then env.deferRemoval=true; env.fire('PlayerSay',admin,'!removeEventEnemy 102')
                    else env.fire('PlayerDisconnected',admin) end
                end
            end
            local lines=inspect(env,admin,'101'); assert(once); eq(enemies[1].classReads,1)
            eq(state(env).enemyHealthRequests[admin],nil)
            if transition=='relisting' then eq(state(env).enemyInspections[admin],newer); assert(newer~=old)
            elseif transition=='cleanup' or transition=='disconnect' then eq(state(env).enemyInspections[admin],nil)
            else eq(state(env).enemyInspections[admin],old) end
        end)
    end
    test('health admission reentry claims ownership before admin getters',function()
        local env,admin=setup(); list(env,admin); local once=false
        admin.IsAdmin=function(self) if not once then once=true; detail(env,admin,'102') end; return self.admin end
        local lines=inspect(env,admin,'101'); local count=0
        for _,line in ipairs(lines) do if line:find('Health() =',1,true) then count=count+1; contains(line,'index 102:') end end
        eq(count,1)
    end)
    test('health final recipient/map validation follows class getter changes',function()
        local env,admin,enemies=setup(); list(env,admin); local original=enemies[1].GetClass
        enemies[1].GetClass=function(self)
            local once=false; admin.IsAdmin=function(ply) if not once then once=true; env.map='changed' end; return ply.admin end
            return original(self)
        end
        noDetail(inspect(env,admin,'101'))
    end)
    test('health getter exceptions and feedback failure leave existing authority unchanged',function()
        local env,admin,enemies=setup(); local page=list(env,admin); local before=state(env)
        local grant,capture=before.enemyMarkerGrants[admin],before.enemyMarkerCaptures[admin]
        enemies[1].Health=function() error('opaque') end; enemies[1].GetClass=function() error('opaque class') end
        detail(env,admin,'101','unavailable','100','unavailable')
        local chat=admin.ChatPrint; admin.ChatPrint=function() error('chat failure') end; eq(env.fire('PlayerSay',admin,'!inspectEventEnemy 101'),''); admin.ChatPrint=chat
        local after=state(env); eq(after.enemyInspections[admin],page); eq(after.enemyMarkerGrants[admin],grant); eq(after.enemyMarkerCaptures[admin],capture)
        eq(after.enemyHealthRequests[admin],nil); eq(env.fire('PlayerSay',admin,'!markEventEnemy 101'),'')
        eq(env.messageCount('ActivatorSpawnMarker'),1); eq(env.fire('PlayerSay',admin,'!removeEventEnemy 101'),''); eq(enemies[1].valid,false)
    end)
    test('health final admission cannot change map after last target validation',function()
        local env,admin,enemies=setup(); list(env,admin); local original=enemies[1].GetClass
        enemies[1].GetClass=function(self)
            local calls=0
            admin.IsAdmin=function(ply)
                calls=calls+1; if calls==3 then env.map='changed-at-final-admission' end
                return ply.admin
            end
            return original(self)
        end
        noDetail(inspect(env,admin,'101'))
    end)
    test('health reads and failures invoke no gameplay authority or publication operations',function()
        local env,admin,enemies=setup(); list(env,admin); local before=state(env); local calls={}; local restores={}
        local page,grant,capture=before.enemyInspections[admin],before.enemyMarkerGrants[admin],before.enemyMarkerCaptures[admin]
        local function forbid(owner,key)
            local original=owner[key]; restores[#restores+1]=function() owner[key]=original end
            owner[key]=function() calls[#calls+1]=key; error('forbidden '..key) end
        end
        for _,key in ipairs({'Claim','Cancel','Retire','Send'}) do forbid(env.ActivatorSnapshotMarker,key) end
        env.math=setmetatable({}, {__index=math}); forbid(env.math,'random'); forbid(env.math,'randomseed')
        for _,key in ipairs({'returnEnemyHealth','returnNPCInformation','Entity','CurTime','sendEventStatus','stopActivatorEvent'}) do forbid(env,key) end
        for _,key in ipairs({'Start','Send','Broadcast','WriteString','WriteUInt','AddNetworkString'}) do forbid(key=='AddNetworkString' and env.util or env.net,key) end
        for _,key in ipairs({'Create','Simple','Start','Stop'}) do forbid(env.timer,key) end
        for _,key in ipairs({'Read','Write','Delete'}) do forbid(env.file,key) end
        for _,key in ipairs({'Create','FindByClass','FindByName'}) do forbid(env.ents,key) end
        for _,enemy in ipairs(enemies) do for _,key in ipairs({'SetHealth','SetMaxHealth','SetPos','SetName','SetModel','Remove','Spawn','TakeDamage','GetPos'}) do forbid(enemy,key) end end
        local ok,err=pcall(function()
            detail(env,admin); refused(env,admin,'999'); enemies[1].Health=nil; enemies[1].GetClass=nil
            detail(env,admin,'101','unavailable','100','unavailable')
        end)
        for _,restore in ipairs(restores) do restore() end
        assert(ok,err); eq(#calls,0,'no swallowed forbidden operation'); local after=state(env)
        eq(after.enemyInspections[admin],page); eq(after.enemyMarkerGrants[admin],grant); eq(after.enemyMarkerCaptures[admin],capture); eq(after.activeEnemies,before.activeEnemies)
    end)
    test('health incomplete reply does not delay established marker or removal authority',function()
        for _,action in ipairs({'!markEventEnemy 101','!removeEventEnemy 101'}) do
            local env,admin,enemies=setup(); local chat=admin.ChatPrint; local once=false
            admin.ChatPrint=function(self,text)
                chat(self,text)
                if not once then
                    once=true; noDetail(inspect(env,admin,'101'))
                    eq(env.fire('PlayerSay',admin,action),'')
                end
            end
            list(env,admin)
            if action:find('mark',1,true) then eq(env.messageCount('ActivatorSpawnMarker'),1)
            else eq(enemies[1].valid,false); eq(state(env).enemyInspections[admin],nil) end
        end
    end)
    for _,method in ipairs({'EntIndex','IsMarkedForDeletion'}) do
        test('health protects throwing target admission getter '..method,function()
            local env,admin,enemies=setup(); list(env,admin)
            enemies[1][method]=function() error('private target getter error') end
            local _,text=refused(env,admin); assert(not text:find('private target getter error',1,true)); eq(enemies[1].healthReads,nil); eq(enemies[1].classReads,nil)
        end)
    end
end
