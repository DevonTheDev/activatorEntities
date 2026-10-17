-- One missing-capability witness, drafted but not run. It deliberately does not
-- require a new hook or inspect new locals: baseline fails on the spawned name.
return function(gmod, test, eq)
    test("queue capability witness schedules two appended exact names in FIFO order",function()
        local env=gmod.new(); local admin=env.entity("player"); admin.admin=true
        local information=env.NPCEdits[1].information
        env.NPCEdits[7]={name="Queue witness A",information=information}
        env.NPCEdits[8]={name="Queue witness B",information=information}
        env.maxActivators=1; env.determineRandomEvent=function() return "Raid" end
        -- Do not assert new command dispatch: demonstrate missing behavior.
        env.fire("PlayerSay",admin,"!queueEvent Queue witness A")
        env.fire("PlayerSay",admin,"!queueEvent Queue witness B")
        for _,name in ipairs({"Queue witness A","Queue witness B","Raid"}) do
            env.timers.activatorSpawner.callback()
            local actors=env.ents.FindByClass("activatorent")
            eq(#actors,1,"one ready actor")
            eq(actors[1].EventIdentifier,name,"next fresh ready batch follows FIFO")
            actors[1]:Remove()
        end
    end)
end
