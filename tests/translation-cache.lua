-- Cache contracts use real files and observe completed translations through the
-- translator's existing table.concat call. No production cache introspection.
return function(_, test, eq)
    local cases = {}
    local function add(name, calls, fixtures, callback)
        cases[#cases + 1] = {name=name, calls=calls, fixtures=fixtures, callback=callback}
    end
    local function comment(bytes) return "--" .. string.rep("x", bytes - 2) end
    local function unclosed(ok, message)
        eq(ok, false)
        assert(tostring(message):match("^tests/gmod%.lua:%d+: unclosed comment$"), tostring(message))
    end
    local function fill(ctx)
        for i=1,8 do ctx.write(i, "!" .. i); ctx.source(i) end
    end
    local function hits(ctx)
        for i=1,8 do eq(ctx.source(i), "not " .. i) end
    end

    add("lexical miss and hit preserve exact bytes and existing limitations", 2, 0, function(c)
        c.write(1, "!a != b // !quoted\nlocal s='! !='; local unsupported=[[!x]]")
        local expected="not a ~= b -- !quoted\nlocal s='! !='; local unsupported=[[not x]]"
        eq(c.source(1), expected); eq(c.source(1), expected); eq(c.translations(), 1)
    end)
    add("open read and close still happen on every hit", 2, 0, function(c)
        c.write(1, "!x")
        local open, counts = io.open, {0,0,0}
        io.open=function(path, mode)
            local file, message=open(path, mode)
            if path ~= c.path(1) or not file then return file, message end
            counts[1]=counts[1]+1
            return {read=function(_, pattern) counts[2]=counts[2]+1; return file:read(pattern) end,
                close=function() counts[3]=counts[3]+1; return file:close() end}
        end
        local ok, message=pcall(function() eq(c.source(1), "not x"); eq(c.source(1), "not x") end)
        io.open=open
        assert(ok, message)
        for _, count in ipairs(counts) do eq(count,2) end
        eq(c.translations(),1)
    end)
    add("same length different length and restored edits use current bytes", 4, 0, function(c)
        c.write(1, "!a"); eq(c.source(1), "not a")
        c.write(1, "!b"); eq(c.source(1), "not b")
        c.write(1, "!longer"); eq(c.source(1), "not longer")
        c.write(1, "!a"); eq(c.source(1), "not a"); eq(c.translations(),3)
    end)
    add("identical bytes at different paths are distinct cache keys", 4, 0, function(c)
        c.write(1,"!x"); c.write(2,"!x")
        eq(c.source(1),"not x"); eq(c.source(2),"not x")
        eq(c.source(1),"not x"); eq(c.source(2),"not x"); eq(c.translations(),2)
    end)
    add("deletion fails and recreation reads the restored file", 3, 0, function(c)
        c.write(1,"!x"); eq(c.source(1),"not x")
        assert(os.remove(c.path(1)))
        local ok=pcall(c.source,1); eq(ok,false)
        c.write(1,"!x"); eq(c.source(1),"not x"); eq(c.translations(),1)
    end)
    add("nil reads close and preserve every cached entry", 17, 0, function(c)
        fill(c)
        local open, closed=io.open,false
        io.open=function(path, mode)
            if path ~= c.path(9) then return open(path,mode) end
            return {read=function() return nil,"synthetic read error" end, close=function() closed=true end}
        end
        local ok, message=pcall(c.source,9)
        io.open=open
        eq(ok,false); eq(closed,true); assert(tostring(message):find("source",1,true))
        hits(c); eq(c.translations(),8)
    end)
    add("throwing reads retain their error and do not close or evict", 17, 0, function(c)
        fill(c)
        local open, closed=io.open,false
        io.open=function(path, mode)
            if path ~= c.path(9) then return open(path,mode) end
            return {read=function() error("synthetic throwing read",0) end, close=function() closed=true end}
        end
        local ok, message=pcall(c.source,9)
        io.open=open
        eq(ok,false); eq(message,"synthetic throwing read"); eq(closed,false)
        hits(c); eq(c.translations(),8)
    end)
    add("malformed repeats retain diagnostic semantics and recover without eviction", 12, 0, function(c)
        fill(c); c.write(9,"--[[bad")
        unclosed(pcall(c.source,9)); unclosed(pcall(c.source,9))
        eq(c.source(1),"not 1"); eq(c.translations(),8)
        c.write(9,"!recovered"); eq(c.source(9),"not recovered"); eq(c.translations(),9)
    end)
    add("ninth insertion evicts FIFO and hits do not promote", 12, 0, function(c)
        fill(c); eq(c.source(1),"not 1")
        c.write(9,"!9"); eq(c.source(9),"not 9")
        eq(c.source(2),"not 2"); eq(c.translations(),9)
        eq(c.source(1),"not 1"); eq(c.translations(),10)
    end)
    add("byte accounting includes both source and translated payloads", 4, 0, function(c)
        local value=comment(300000)
        c.write(1,value); c.write(2,value)
        eq(c.source(1),value); eq(c.source(2),value)
        eq(c.source(2),value); eq(c.translations(),2)
        eq(c.source(1),value); eq(c.translations(),3)
    end)
    add("exact one MiB combined payload is retained", 2, 0, function(c)
        local value=comment(524288)
        c.write(1,value); eq(c.source(1),value); eq(c.source(1),value); eq(c.translations(),1)
    end)
    add("oversized input translates unchanged and cannot evict existing entries", 18, 0, function(c)
        fill(c)
        local value=comment(1048577)
        c.write(9,value); eq(c.source(9),value); eq(c.source(9),value)
        hits(c); eq(c.translations(),10)
    end)
    add("translation expansion beyond the byte cap does not insert or evict", 18, 0, function(c)
        fill(c)
        c.write(9,string.rep("!",209716))
        local expected=string.rep("not ",209716)
        eq(c.source(9),expected); eq(c.source(9),expected)
        hits(c); eq(c.translations(),10)
    end)
    add("cache hits compile fresh chunks with fresh local closures", 9, 2, function(c)
        local first, second=c.gmod.new(true),c.gmod.new(true)
        first.marker="first"; second.marker="second"
        local value="local count=0; return function() count=count+1; return marker,count end"
        c.write(1,value)
        local source=c.gmod.source
        c.gmod.source=function(path)
            return source(path == "roleplayAddon/lua/__cache_test__.lua" and c.path(1) or path)
        end
        local compiler, compilations=load,0
        load=function(text,...)
            if text == value then compilations=compilations+1 end
            return compiler(text,...)
        end
        local ok, message=pcall(function()
            local a=first.include("__cache_test__.lua")
            local b=first.include("__cache_test__.lua")
            local d=second.include("__cache_test__.lua")
            assert(a~=b and a~=d and b~=d)
            local name,count=a(); eq(name,"first"); eq(count,1)
            name,count=a(); eq(name,"first"); eq(count,2)
            name,count=b(); eq(name,"first"); eq(count,1)
            name,count=d(); eq(name,"second"); eq(count,1)
        end)
        load=compiler; c.gmod.source=source
        assert(ok,message); eq(compilations,3)
    end)
    add("warm server fixtures keep globals tables and callbacks isolated", 6, 2, function(c)
        local first, second=c.gmod.new(),c.gmod.new()
        assert(first._G~=second._G and first.ENT~=second.ENT)
        assert(first.NPCEdits~=second.NPCEdits and first.SpawnPositions~=second.SpawnPositions)
        assert(first.NPCEdits[1]~=second.NPCEdits[1])
        assert(first.entities~=second.entities and first.receivers~=second.receivers)
        assert(first.receivers.SendNPCInformation~=second.receivers.SendNPCInformation)
        assert(first.timers.activatorSpawner~=second.timers.activatorSpawner)
        assert(first.timers.activatorSpawner.callback~=second.timers.activatorSpawner.callback)
        local ply,enemies=first.start(); eq(#enemies,5); eq(first.totalEnemies,5)
        eq(second.totalEnemies,0); eq(#second.entities,0)
        for _,enemy in ipairs(enemies) do first.fire("OnNPCKilled",enemy,ply) end
        eq(first.messageCount("roundFinished"),1); eq(second.messageCount("roundFinished"),0)
        eq(second.totalEnemies,0); eq(second.timers.activatorSpawner.stopped,false)
        first.NPCEdits[1].name="changed"; eq(second.NPCEdits[1].name,"Raid")
    end)
    add("warm client fixtures keep tables timers receivers and closures isolated", 6, 2, function(c)
        local first, second=c.gmod.new(true),c.gmod.new(true)
        for _,key in ipairs({"ENT","panels","timers","receivers","hooks","messages"}) do
            assert(first[key]~=second[key],key)
        end
        assert(first.receivers.roundFinished~=second.receivers.roundFinished)
        first.receive("roundFinished",nil); second.receive("roundFinished",nil)
        assert(first.timers.destroyAlertFrame.callback~=second.timers.destroyAlertFrame.callback)
        first.fireTimer("destroyAlertFrame")
        eq(first.panels[1].valid,false); eq(second.panels[1].valid,true)
        eq(first.timers.destroyAlertFrame,nil); assert(second.timers.destroyAlertFrame)
        second.receive("roundFinished",nil)
        eq(second.panels[1].valid,false); eq(second.panels[3].valid,true)
        eq(#first.panels,2); eq(#second.panels,4)
        second.fireTimer("destroyAlertFrame"); eq(second.panels[3].valid,false)
    end)

    for _,case in ipairs(cases) do
        test("translation cache: " .. case.name,function()
            local gmod=dofile("tests/gmod.lua")
            local prefix=os.tmpname()
            local paths, translations, calls, fixtures={},0,0,0
            local concat=table.concat
            local source,new=gmod.source,gmod.new
            gmod.source=function(path)
                calls=calls+1
                return source(path)
            end
            gmod.new=function(...)
                fixtures=fixtures+1
                return new(...)
            end
            local ctx={gmod=gmod}
            function ctx.path(index)
                local path=prefix .. "-" .. index; paths[path]=true; return path
            end
            function ctx.write(index,contents)
                local file=assert(io.open(ctx.path(index),"wb"))
                assert(file:write(contents)); assert(file:close())
            end
            function ctx.source(index) return gmod.source(ctx.path(index)) end
            function ctx.translations() return translations end
            table.concat=function(values,...)
                translations=translations+1
                return concat(values,...)
            end
            local ok,message=pcall(case.callback,ctx)
            table.concat=concat
            os.remove(prefix)
            for path in pairs(paths) do os.remove(path) end
            assert(ok,message)
            eq(calls,case.calls,"preregistered source calls: " .. case.name)
            eq(fixtures,case.fixtures,"preregistered fixture calls: " .. case.name)
        end)
    end
end
