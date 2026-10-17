return function(gmod, test, eq)
    test("QMW01 pinned baseline has no pending move command",1,function()
        local upvalue=dofile("tests/find-upvalue.lua")
        local e=gmod.new(); local p=e.entity("player"); p.admin=true
        local handler=e.hooks.PlayerSay.manageActivatorEventQueue
        handler(p,"!queueEvent Raid"); handler(p,"!queueEvent Raid")
        local q=upvalue(e.timers.activatorSpawner.callback,"encounterQueue"); local first,second=q[1],q[2]
        assert(first and second and first~=second,"witness fixture must contain two occurrences")
        local reply=handler(p,"!moveQueuedEvent 2 1")
        assert(reply=="","MOVE_WITNESS_UNRECOGNIZED")
        eq(q[1],second,"moved occurrence"); eq(q[2],first,"preserved occurrence")
    end)
end
