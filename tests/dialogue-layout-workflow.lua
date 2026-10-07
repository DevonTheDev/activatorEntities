-- Exercise the actual resized menu callbacks and typed packet transfer helpers.
-- Separate entity copies preserve server/client lifetime boundaries; native
-- rendering, focus, scrolling and asynchronous engine delivery are not modeled.
return function(gmod,test,eq)
    local function realm(deferred)
        local client={env=gmod.new(true),copies={},originals={}}
        if deferred then
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
        end
        return client
    end

    local function toClient(client,message)
        local copy={name=message.name,values={},fields=message.fields}
        for i,value in ipairs(message.values) do
            if message.fields[i].kind == "entity" then
                local entity=client.copies[value]
                if not entity then
                    entity=client.env.entity(value:GetClass())
                    entity.model=value:GetModel()
                    client.copies[value],client.originals[entity]=entity,value
                end
                copy.values[i]=entity
            else copy.values[i]=value end
        end
        client.env.deliver(copy)
    end

    local function toServer(server,client,player,message)
        local copy={name=message.name,values={},fields=message.fields}
        for i,value in ipairs(message.values) do
            if message.fields[i].kind == "entity" then
                copy.values[i]=assert(client.originals[value],"unmapped client entity")
            else copy.values[i]=value end
        end
        server.deliver(copy,player)
    end

    local function open(server,client,player,actor)
        local first=#client.env.panels+1
        actor:AcceptInput("Use",player,player)
        local message=server.messages[#server.messages]
        eq(message.name,"OpenInteractionMenu"); eq(message.player,player)
        toClient(client,message)
        local menu={actor=client.copies[actor],panels={}}
        for i=first,#client.env.panels do
            local panel=client.env.panels[i]
            menu.panels[#menu.panels+1]=panel
            if panel.class == "DFrame" then menu.frame=panel
            elseif panel.class == "DButton" then
                if panel.text:find("Start",1,true) then menu.start=panel else menu.cancel=panel end
            end
        end
        assert(menu.frame and menu.start and menu.cancel,"actual menu controls")
        return menu
    end

    local function ready(deferred)
        local server,client=gmod.new(),realm(deferred)
        local player,actor=server.ready()
        return server,client,player,actor,open(server,client,player,actor)
    end

    local function resize(client,width,height,menu)
        local env=client.env
        local before=#env.messages
        local oldWidth,oldHeight=env.ScrW(),env.ScrH()
        env.screenWidth,env.screenHeight=width,height
        env.fire("OnScreenSizeChanged",oldWidth,oldHeight)
        eq(#env.messages,before,"resize emits no request")
        if menu then
            eq(menu.frame.width,width); eq(menu.frame.height,height)
            for _,button in ipairs({menu.start,menu.cancel}) do
                assert(button.x >= 0 and button.y >= 0 and button.width > 0 and button.height > 0)
                assert(button.x+button.width <= width and button.y+button.height <= height,"resized action is in bounds")
            end
        end
    end

    local function geometry(menu)
        local state={}
        for _,panel in ipairs(menu.panels) do
            state[panel]={x=panel.x,y=panel.y,width=panel.width,height=panel.height,
                positions=panel.positionChanges or 0,sizes=panel.sizeChanges or 0}
        end
        return state
    end

    local function unchanged(menu,state)
        for _,panel in ipairs(menu.panels) do
            local old=state[panel]
            eq(panel.x,old.x); eq(panel.y,old.y); eq(panel.width,old.width); eq(panel.height,old.height)
            eq(panel.positionChanges or 0,old.positions,"obsolete frame is not repositioned")
            eq(panel.sizeChanges or 0,old.sizes,"obsolete frame is not resized")
        end
    end

    local function retained(menu)
        if menu.frame.LayoutDialogue then menu.frame:LayoutDialogue() end
        menu.start:DoClick(); menu.cancel:DoClick()
    end

    local function start(server,client,player,menu,identifier)
        local before=#client.env.messages
        menu.start:DoClick()
        eq(#client.env.messages,before+1,"one actual Start packet")
        local message=client.env.messages[#client.env.messages]
        eq(message.name,"SendNPCInformation")
        eq(#message.fields,1); eq(message.fields[1].kind,"string")
        eq(message.values[1],identifier or "Raid")
        toServer(server,client,player,message)
        return message
    end

    local function status(server,client)
        for i=#server.messages,1,-1 do
            if server.messages[i].name == "ActivatorEventStatus" then
                toClient(client,server.messages[i]); return server.messages[i]
            end
        end
        error("missing actual status packet")
    end

    for _,deferred in ipairs({false,true}) do
        test("resized actual Start preserves packet ownership and full cleanup with deferred Close " .. tostring(deferred),function()
            local server,client=gmod.new(),realm(deferred)
            server.NPCEdits[1].name="Supply Raid"
            local player,actor=server.ready()
            local menu=open(server,client,player,actor)
            for _,size in ipairs({{800,600},{320,240},{1920,1080},{600,1000},{3440,1440},{640,480},{1280,720}}) do
                resize(client,size[1],size[2],menu)
            end
            local request=start(server,client,player,menu,"Supply Raid")
            eq(server.totalEnemies,5); eq(actor.valid,false)
            retained(menu); client.env.fire("Think")
            eq(#client.env.messages,1); eq(client.env.messageCount("CloseInteractionMenu"),0)
            local enemies=server.ents.FindByName("devonsSpawnedEntity")
            server.fire("OnNPCKilled",enemies[1],player)
            toServer(server,client,player,request)
            eq(server.totalEnemies,4,"resizing does not weaken one-shot authorization")
            for i=2,#enemies do server.fire("OnNPCKilled",enemies[i],player) end
            eq(server.totalEnemies,0); eq(server.messageCount("roundFinished"),1)
            eq(server.timers.activatorSpawner.stopped,false)
            server.fireTimer("activatorSpawner")
            eq(#server.ents.FindByClass("activatorent"),3)
        end)

        test("resized actual Cancel consumes only its actor permission with deferred Close " .. tostring(deferred),function()
            local server,client,player,actor,menu=ready(deferred)
            resize(client,320,240,menu); resize(client,800,600,menu)
            menu.cancel:DoClick()
            eq(#client.env.messages,1); eq(client.env.messageCount("SendNPCInformation"),0)
            local request=client.env.messages[1]
            eq(request.name,"CloseInteractionMenu"); eq(#request.fields,1)
            eq(request.fields[1].kind,"entity"); eq(request.values[1],menu.actor)
            toServer(server,client,player,request)
            retained(menu); resize(client,1920,1080); client.env.fire("Think")
            eq(#client.env.messages,1)
            server.receive("SendNPCInformation",player,"Raid"); eq(server.totalEnemies,0)
            local replacement=open(server,client,player,actor)
            resize(client,640,480,replacement)
            start(server,client,player,replacement); eq(server.totalEnemies,5)
        end)
    end

    for _,condition in ipairs({"retired","invalid frame","marked frame","invalid actor"}) do
        local name=condition == "invalid actor"
            and "resize ignores an invalid actor before Think and retained callbacks stop after retirement"
            or "resize and retained callbacks ignore " .. condition .. " before and after liveness checks"
        test(name,function()
            local server,client,player,actor,menu=ready(true)
            resize(client,800,600,menu)
            if condition == "retired" then client.env.fire("EntityRemoved",menu.actor)
            elseif condition == "invalid frame" then menu.frame.valid=false
            elseif condition == "marked frame" then menu.frame:Remove()
            else menu.actor.valid=false end
            local before=geometry(menu)
            resize(client,320,240)
            if menu.frame.LayoutDialogue then menu.frame:LayoutDialogue() end
            unchanged(menu,before)
            if condition ~= "invalid actor" then
                retained(menu)
                for _,request in ipairs(client.env.messages) do toServer(server,client,player,request) end
                eq(server.totalEnemies,0,"resized obsolete frame cannot Start before Think")
                eq(#client.env.messages,0,"retained Start and Cancel are inert before Think")
                unchanged(menu,before)
            end
            client.env.fire("Think")
            retained(menu); resize(client,1920,1080)
            unchanged(menu,before)
            eq(#client.env.messages,0,"obsolete menu never submits")
            eq(server.totalEnemies,0)
        end)
    end

    for _,sameActor in ipairs({false,true}) do
        test("resizing a replacement preserves sole ownership on reused actor " .. tostring(sameActor),function()
            local server,client,player,actor,old=ready(true)
            resize(client,800,600,old)
            local nextActor=sameActor and actor or server.ents.FindByClass("activatorent")[2]
            player:SetPos(nextActor:GetPos())
            local menu=open(server,client,player,nextActor)
            local before=geometry(old)
            for _,size in ipairs({{320,240},{1920,1080},{600,1000}}) do
                resize(client,size[1],size[2],menu)
                retained(old); client.env.fire("Think")
                unchanged(old,before)
                eq(menu.frame:IsVisible(),true); eq(#client.env.messages,0)
            end
            start(server,client,player,menu)
            eq(server.totalEnemies,5); eq(client.env.messageCount("CloseInteractionMenu"),0)
        end)
    end

    test("resizing preserves the native DFrame Think function",function()
        local server,client=gmod.new(),realm()
        local create=client.env.vgui.Create
        local calls=0
        local nativeThink=function() calls=calls+1 end
        client.env.vgui.Create=function(class,parent)
            local panel=create(class,parent)
            if class == "DFrame" then panel.Think=nativeThink end
            return panel
        end
        local player,actor=server.ready(); local menu=open(server,client,player,actor)
        for i,size in ipairs({{320,240},{800,600},{1920,1080}}) do
            resize(client,size[1],size[2],menu)
            eq(menu.frame.Think,nativeThink,"custom layout does not replace native Think")
            menu.frame:Think(); client.env.fire("Think"); eq(calls,i)
            eq(menu.frame:IsVisible(),true); eq(#client.env.messages,0)
        end
    end)

    test("full-update actor removal preserves the resized live menu and native Start",function()
        local server,client,player,actor,menu=ready()
        resize(client,800,600,menu)
        client.env.fire("EntityRemoved",menu.actor,true)
        resize(client,320,240,menu); client.env.fire("Think")
        eq(menu.frame.valid,true)
        start(server,client,player,menu); eq(server.totalEnemies,5)
    end)

    for _,condition in ipairs({"at expiry boundary","expired","missing positions"}) do
        test("resized actual Start preserves server outcome for " .. condition,function()
            local server,client,player,actor,menu=ready()
            resize(client,320,240,menu); resize(client,1280,720,menu)
            if condition == "at expiry boundary" then server.now=60
            elseif condition == "expired" then server.now=61
            else server.SpawnPositions[1].enemySpawnPositions={} end
            resize(client,800,600,menu)
            start(server,client,player,menu)
            eq(client.env.messageCount("CloseInteractionMenu"),0)
            if condition == "at expiry boundary" then eq(server.totalEnemies,5)
            else
                eq(server.totalEnemies,0); eq(actor.valid,true)
                eq(player.chats[#player.chats],condition == "expired"
                    and "This interaction expired. Use the activator again."
                    or "No enemy spawn position is available. Ask an admin to fix it, then use the activator again.")
            end
        end)
    end

    test("another player's Start retires the resized observer before client actor invalidation",function()
        local server,client,player,actor,menu=ready(true)
        local other,starter=realm(),server.entity("player")
        starter:SetPos(actor:GetPos())
        local otherMenu=open(server,other,starter,actor)
        resize(client,320,240,menu); resize(other,800,600,otherMenu)
        start(server,other,starter,otherMenu)
        eq(server.totalEnemies,5); eq(menu.actor.valid,true)
        eq(status(server,client).values[1],true)
        eq(menu.frame:IsVisible(),false); eq(menu.frame:IsMarkedForDeletion(),true)
        local before=geometry(menu)
        resize(client,1920,1080); retained(menu); client.env.fire("Think")
        unchanged(menu,before); eq(#client.env.messages,0)
        eq(server.totalEnemies,5)
        local admin=server.entity("player"); admin.admin=true
        server.fire("PlayerSay",admin,"!stopEvent")
        eq(server.totalEnemies,0); eq(server.messageCount("roundFinished"),0)
        eq(server.timers.activatorSpawner.stopped,false)
        eq(status(server,client).values[1],false)
        resize(client,640,480); retained(menu); unchanged(menu,before)
        eq(#client.env.messages,0)
    end)
end
