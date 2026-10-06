-- Execute the actual server/client source with separate entity lifetimes.
-- The API doubles do not model native Derma focus or engine packet timing.
return function(gmod, test, eq)
    local function clientRealm()
        return {env=gmod.new(true), copies={}, originals={}}
    end

    -- Panel.Remove defers deletion; native DFrame.Close hides, marks, then calls
    -- OnClose. Keep the original eager double and exercise this interval too.
    local function deferPanels(client)
        local create=client.env.vgui.Create
        client.env.vgui.Create=function(class,parent)
            local panel=create(class,parent)
            panel.deleteOnClose=true
            function panel:SetDeleteOnClose(value) self.deleteOnClose=value end
            function panel:Remove() self.markedForDeletion=true end
            function panel:Close()
                self:SetVisible(false)
                if self.deleteOnClose then self:Remove() end
                if self.OnClose then self:OnClose() end
            end
            return panel
        end
        local function remove(panel)
            panel.valid=false
            for _,child in ipairs(panel.children) do remove(child) end
        end
        function client.env.flushPanelRemovals()
            for _,panel in ipairs(client.env.panels) do
                if panel.markedForDeletion and panel.valid then remove(panel) end
            end
        end
    end

    local function toClient(client, message)
        local copy={name=message.name, values={}, fields=message.fields}
        for i,value in ipairs(message.values) do
            if message.fields[i].kind == "entity" then
                local entity=client.copies[value]
                if not entity then
                    entity=client.env.entity(value:GetClass())
                    entity.model=value:GetModel()
                    client.copies[value], client.originals[entity]=entity, value
                end
                copy.values[i]=entity
            else copy.values[i]=value end
        end
        client.env.deliver(copy)
    end

    local function toServer(server, client, player, message)
        local copy={name=message.name, values={}, fields=message.fields}
        for i,value in ipairs(message.values) do
            if message.fields[i].kind == "entity" then
                copy.values[i]=assert(client.originals[value], "unmapped client entity")
            else copy.values[i]=value end
        end
        server.deliver(copy, player)
    end

    local function open(server, client, player, actor)
        local first=#client.env.panels+1
        actor:AcceptInput("Use", player, player)
        local message=server.messages[#server.messages]
        eq(message.name, "OpenInteractionMenu"); eq(message.player, player)
        toClient(client, message)
        local menu={actor=client.copies[actor]}
        for i=first,#client.env.panels do
            local panel=client.env.panels[i]
            if panel.class == "DFrame" then menu.frame=panel
            elseif panel.class == "DButton" and panel.text:find("Start",1,true) then menu.start=panel
            elseif panel.class == "DButton" then menu.cancel=panel end
        end
        assert(menu.frame and menu.start and menu.cancel, "actual menu controls")
        eq(menu.frame.popup, true); eq(menu.frame.width, client.env.ScrW())
        eq(menu.frame.height, client.env.ScrH())
        return menu
    end

    local function status(server, client)
        for i=#server.messages,1,-1 do
            local message=server.messages[i]
            if message.name == "ActivatorEventStatus" then
                toClient(client, message)
                return message
            end
        end
        error("missing actual encounter status")
    end

    local function ready(deferred)
        local server,client=gmod.new(),clientRealm()
        if deferred then deferPanels(client) end
        local player,actor=server.ready()
        return server,client,player,actor,open(server,client,player,actor)
    end

    local function pair()
        local server,observer,player,actor,menu=ready()
        local starter=server.entity("player"); starter:SetPos(actor:GetPos())
        local other=clientRealm()
        return server,observer,player,actor,menu,other,starter,open(server,other,starter,actor)
    end

    local function start(server, client, player, menu)
        local before=#client.env.messages
        menu.start:DoClick()
        eq(#client.env.messages,before+1,"one actual Start request")
        eq(client.env.messages[#client.env.messages].name,"SendNPCInformation")
        toServer(server,client,player,client.env.messages[#client.env.messages])
    end

    local function noRequests(client)
        eq(#client.env.messages,0,"retirement must not send any request")
    end

    local function retired(menu)
        eq(menu.frame.valid,false,"obsolete dialogue is removed")
        eq(menu.frame:IsVisible(),false,"obsolete popup is no longer visible")
        for _,child in ipairs(menu.frame.children) do eq(child.valid,false) end
    end

    local function oldCallbacks(menu)
        menu.frame:OnClose()
        menu.start:DoClick()
        menu.cancel:DoClick()
        if menu.frame.Think then menu.frame:Think() end
    end

    local function hud(client)
        for _,panel in ipairs(client.env.panels) do
            if panel.valid and panel.class == "DPanel" and not panel.parent then return panel end
        end
    end

    test("another player's active snapshot retires the observer before actor invalidation",function()
        local server,client,player,actor,menu,other,starter,otherMenu=pair()
        start(server,other,starter,otherMenu)
        eq(server.totalEnemies,5); eq(actor.valid,false); eq(menu.actor.valid,true)
        local snapshot=status(server,client); status(server,other)
        eq(snapshot.values[1],true); retired(menu); retired(otherMenu)
        assert(hud(client)); assert(hud(other)); noRequests(client)
        eq(other.env.messageCount("SendNPCInformation"),1)
        eq(other.env.messageCount("CloseInteractionMenu"),0)
        status(server,client); oldCallbacks(menu); client.env.fire("Think")
        noRequests(client); eq(server.totalEnemies,5)
    end)

    test("zero-enemy accepted start retires the observer when its actor disappears",function()
        local server,client,player,actor,menu,other,starter,otherMenu=pair()
        server.failClass="npc_stalker"
        start(server,other,starter,otherMenu)
        eq(server.totalEnemies,0); eq(actor.valid,false)
        eq(status(server,client).values[1],false); status(server,other)
        eq(menu.frame.valid,true,"inactive status alone is not evidence against a live actor")
        menu.actor:Remove(); client.env.fire("Think")
        retired(menu); retired(otherMenu); noRequests(client)
        eq(hud(client),nil); eq(server.timers.activatorSpawner.stopped,false)
        server.failClass=nil; server.fireTimer("activatorSpawner")
        local nextActor=assert(server.ents.FindByClass("activatorent")[1])
        player:SetPos(nextActor:GetPos())
        local nextMenu=open(server,client,player,nextActor)
        oldCallbacks(menu); client.env.fire("Think")
        eq(nextMenu.frame.valid,true); noRequests(client)
        start(server,client,player,nextMenu); eq(server.totalEnemies,5)
    end)

    test("idle actor removal retires its dialogue even before validity changes",function()
        local server,client,player,actor,menu=ready()
        actor:Remove()
        eq(menu.actor.valid,true)
        client.env.fire("EntityRemoved",menu.actor)
        retired(menu); noRequests(client)
        menu.actor.valid=false; oldCallbacks(menu); client.env.fire("Think")
        noRequests(client); eq(server.totalEnemies,0)
    end)

    test("Think retires a silently invalidated dialogue actor without requests",function()
        local server,client,player,actor,menu=ready()
        actor:Remove(); menu.actor.valid=false
        client.env.fire("Think")
        retired(menu); noRequests(client)
        oldCallbacks(menu); client.env.fire("Think"); noRequests(client)
    end)

    test("a client full update preserves the dialogue while its actor remains valid",function()
        local server,client,player,actor,menu=ready()
        client.env.fire("EntityRemoved",menu.actor,true)
        client.env.fire("Think")
        eq(menu.frame.valid,true); noRequests(client)
        start(server,client,player,menu); eq(server.totalEnemies,5)
    end)

    test("Think retires a full-update actor that remains invalid afterward",function()
        local server,client,player,actor,menu=ready()
        client.env.fire("EntityRemoved",menu.actor,true)
        eq(menu.frame.valid,true)
        menu.actor.valid=false; client.env.fire("Think")
        retired(menu); noRequests(client)
    end)

    test("removing an unrelated actor leaves the current dialogue usable",function()
        local server,client,player,actor,menu=ready()
        local unrelated=client.env.entity("activatorent"); unrelated:Remove()
        client.env.fire("Think"); eq(menu.frame.valid,true); noRequests(client)
        start(server,client,player,menu); eq(server.totalEnemies,5)
    end)

    test("an actual inactive snapshot preserves a fresh usable dialogue",function()
        local server,client,player,actor,menu=ready()
        server.receive("RequestActivatorEventStatus",player)
        eq(status(server,client).values[1],false)
        client.env.fire("Think"); eq(menu.frame.valid,true); noRequests(client)
        start(server,client,player,menu); eq(server.totalEnemies,5)
    end)

    for _,counts in ipairs({{0,0},{0,5},{6,5}}) do
        test("invalid active counts preserve a fresh dialogue: " .. counts[1] .. "/" .. counts[2],function()
            local server,client,player,actor,menu=ready()
            client.env.receive("ActivatorEventStatus",nil,true,"Raid",counts[1],counts[2],false)
            client.env.fire("Think"); eq(menu.frame.valid,true); noRequests(client)
            eq(hud(client),nil)
            start(server,client,player,menu); eq(server.totalEnemies,5)
        end)
    end

    for _,sameActor in ipairs({false,true}) do
        test("old callbacks cannot close or cancel a replacement on reused actor " .. tostring(sameActor),function()
            local server,client,player,actor,menu=ready()
            local oldThink=client.env.hooks.Think or {}
            local nextActor=sameActor and actor or server.ents.FindByClass("activatorent")[2]
            player:SetPos(nextActor:GetPos())
            local nextMenu=open(server,client,player,nextActor)
            retired(menu); oldCallbacks(menu)
            if not sameActor then
                actor:Remove(); menu.actor:Remove()
            end
            for _,callback in pairs(oldThink) do callback() end
            client.env.fire("Think")
            eq(nextMenu.frame.valid,true); noRequests(client)
            start(server,client,player,nextMenu); eq(server.totalEnemies,5)
            eq(client.env.messageCount("CloseInteractionMenu"),0)
        end)
    end

    for _,callback in ipairs({"Start","Close","Cancel"}) do
        test("a directly removed frame's old " .. callback .. " cannot affect a reused interaction",function()
            local server,client,player,actor,menu=ready()
            menu.frame:Remove()
            local nextMenu=open(server,client,player,actor)
            if callback == "Start" then menu.start:DoClick()
            elseif callback == "Close" then menu.frame:OnClose()
            else menu.cancel:DoClick() end
            client.env.fire("Think")
            noRequests(client); eq(nextMenu.frame.valid,true)
            start(server,client,player,nextMenu); eq(server.totalEnemies,5)
        end)
    end

    test("liveness cleanup releases an externally removed frame without sending Cancel",function()
        local server,client,player,actor,menu=ready()
        menu.frame:Remove(); client.env.fire("Think"); oldCallbacks(menu)
        noRequests(client)
        local nextMenu=open(server,client,player,actor)
        start(server,client,player,nextMenu); eq(server.totalEnemies,5)
    end)

    for _,thinkFirst in ipairs({false,true}) do
        for _,callback in ipairs({"Start","Cancel"}) do
            test("marked live frame rejects retained " .. callback .. " after Think " .. tostring(thinkFirst),function()
                local server,client,player,actor,menu=ready(true)
                menu.frame:Remove()
                eq(menu.frame.valid,true); eq(menu.start.valid,true)
                eq(menu.frame:IsMarkedForDeletion(),true)
                if thinkFirst then client.env.fire("Think") end
                if callback == "Start" then menu.start:DoClick() else menu.cancel:DoClick() end
                -- Deliver any real request first so an obsolete Start cannot hide
                -- behind a client-only assertion when the server still allows it.
                for _,request in ipairs(client.env.messages) do toServer(server,client,player,request) end
                eq(server.totalEnemies,0,"a removed dialogue cannot start the encounter")
                noRequests(client)
                client.env.fire("Think")
                eq(menu.frame:IsVisible(),false,"liveness hides the pending-deletion frame")
                oldCallbacks(menu); noRequests(client)
                local nextMenu=open(server,client,player,actor)
                oldCallbacks(menu); noRequests(client); eq(nextMenu.frame:IsVisible(),true)
                start(server,client,player,nextMenu); eq(server.totalEnemies,5)
            end)
        end
    end

    for _,callback in ipairs({"Start","Cancel"}) do
        test("normal " .. callback .. " works when native Close marks before OnClose",function()
            local server,client,player,actor,menu=ready(true)
            local onClose=menu.frame.OnClose
            local closeCalls=0
            menu.frame.OnClose=function(...)
                closeCalls=closeCalls+1
                eq(menu.frame:IsVisible(),false)
                eq(menu.frame.valid,true); eq(menu.start.valid,true)
                eq(menu.frame:IsMarkedForDeletion(),true)
                return onClose(...)
            end
            if callback == "Start" then
                start(server,client,player,menu); eq(server.totalEnemies,5)
                eq(client.env.messageCount("CloseInteractionMenu"),0)
            else
                menu.cancel:DoClick()
                eq(client.env.messageCount("CloseInteractionMenu"),1)
                toServer(server,client,player,client.env.messages[1])
                server.receive("SendNPCInformation",player,"Raid"); eq(server.totalEnemies,0)
            end
            eq(closeCalls,1)
            oldCallbacks(menu); client.env.fire("Think"); eq(#client.env.messages,1)
            client.env.flushPanelRemovals(); retired(menu)
        end)
    end

    test("active retirement detaches before native Close marks its still-valid frame",function()
        local server,client,player,actor,menu=ready(true)
        client.env.receive("ActivatorEventStatus",nil,true,"Raid",5,5,false)
        eq(menu.frame.valid,true); eq(menu.frame:IsVisible(),false)
        eq(menu.frame:IsMarkedForDeletion(),true)
        oldCallbacks(menu); noRequests(client)
        local nextMenu=open(server,client,player,actor)
        oldCallbacks(menu); client.env.fire("Think")
        noRequests(client); eq(nextMenu.frame:IsVisible(),true)
        start(server,client,player,nextMenu); eq(server.totalEnemies,5)
        client.env.flushPanelRemovals(); retired(menu)
    end)

    test("dialogue liveness leaves native DFrame Think behavior intact",function()
        local server,client=gmod.new(),clientRealm()
        local create=client.env.vgui.Create
        local calls=0
        local nativeThink=function() calls=calls+1 end
        client.env.vgui.Create=function(class,parent)
            local panel=create(class,parent)
            if class == "DFrame" then panel.Think=nativeThink end
            return panel
        end
        local player,actor=server.ready(); local menu=open(server,client,player,actor)
        eq(menu.frame.Think,nativeThink)
        menu.frame:Think(); client.env.fire("Think")
        eq(calls,1); eq(menu.frame.valid,true); noRequests(client)
    end)

    for _,reason in ipairs({"expired","missing positions"}) do
        test("liveness preserves existing Start guidance for " .. reason,function()
            local server,client,player,actor,menu=ready()
            if reason == "expired" then server.now=61; client.env.now=61
            else server.SpawnPositions[1].enemySpawnPositions={} end
            client.env.fire("Think"); eq(menu.frame.valid,true); noRequests(client)
            start(server,client,player,menu)
            eq(server.totalEnemies,0); eq(actor.valid,true)
            eq(player.chats[#player.chats],reason == "expired"
                and "This interaction expired. Use the activator again."
                or "No enemy spawn position is available. Ask an admin to fix it, then use the activator again.")
            eq(client.env.messageCount("CloseInteractionMenu"),0)
        end)
    end

    test("normal Cancel after liveness checks still consumes the real server permission",function()
        local server,client,player,actor,menu=ready()
        client.env.fire("Think"); menu.cancel:DoClick()
        retired(menu); eq(client.env.messageCount("CloseInteractionMenu"),1)
        eq(client.env.messageCount("SendNPCInformation"),0)
        toServer(server,client,player,client.env.messages[1])
        oldCallbacks(menu); client.env.fire("Think"); eq(#client.env.messages,1)
        server.receive("SendNPCInformation",player,"Raid"); eq(server.totalEnemies,0)
        local nextMenu=open(server,client,player,actor)
        start(server,client,player,nextMenu); eq(server.totalEnemies,5)
    end)

    test("actor retirement leaves completion popup and passive encounter HUD independent",function()
        local server,client,player,actor,menu=ready()
        client.env.receive("roundFinished",nil)
        local alert
        for _,panel in ipairs(client.env.panels) do
            if panel.class == "DFrame" and panel ~= menu.frame then alert=panel end
        end
        actor:Remove(); menu.actor:Remove(); client.env.fire("Think")
        retired(menu); eq(alert.valid,true); noRequests(client)
        client.env.receive("ActivatorEventStatus",nil,true,"Raid",3,5,true)
        local progress=assert(hud(client))
        eq(progress.mouseInput,false); eq(progress.keyboardInput,false); eq(progress.popup,nil)
        client.env.fireTimer("destroyAlertFrame")
        eq(alert.valid,false); eq(progress.valid,true); noRequests(client)
    end)
end
