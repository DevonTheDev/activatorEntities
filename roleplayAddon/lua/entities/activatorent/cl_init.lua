include("shared.lua")

local activeFrame

-- Draws the NPC model and the text
function ENT:Draw()

    self:DrawModel()

end

-- Creates the interaction menu for the client
net.Receive("OpenInteractionMenu", function(len)

    -- Gets all the information about the NPCs here
    local ply = net.ReadEntity()
    local ent = net.ReadEntity()
    local eventIdentifier = net.ReadString()
    local npcDialogue = net.ReadString()
    if not IsValid(ply) or not IsValid(ent) then return end

    -- The new server message has already replaced the previous interaction.
    if IsValid(activeFrame) then
        activeFrame.replaced = true
        activeFrame:Close()
    end

    -- Creates the background derma frame
    local frame = vgui.Create("DFrame")
    activeFrame = frame
    local submitted, closed = false, false
    frame.OnClose = function()
        if closed then return end
        closed = true
        if activeFrame == frame then activeFrame = nil end
        if submitted or frame.replaced then return end
        net.Start("CloseInteractionMenu")
            net.WriteEntity(ent)
        net.SendToServer()
    end
    ply:ScreenFade(SCREENFADE.IN, color_black, 0.3, 0)
    frame:SetVisible(true)
    frame:SetTitle("")
    frame:SetSize(ScrW(), ScrH())
    frame:Center()
    frame:MakePopup()
    frame:SetBackgroundBlur(true)
    frame:SetDeleteOnClose(true)
    frame:ShowCloseButton( false )

    -- Prints the dialogue text
    local dialogueText = vgui.Create("DLabel", frame)
    dialogueText:SetText(npcDialogue)
    dialogueText:SetFont("DermaLarge")
    dialogueText:SetColor(Color(255, 255, 255, 255))
    dialogueText:SetSize(ScrW(), frame:GetTall())
    dialogueText:Dock(BOTTOM)
    dialogueText:DockMargin(600, 0, 0, -500)
    
    -- Sets up the button to start the event
    local activatorButton = vgui.Create("DButton", frame)
    activatorButton:SetText("Bring it on (Start the Event)")
    activatorButton:SetSize(300, 100)
    activatorButton:SetPos(0, ScrH() - 100)

    activatorButton.DoClick = function()
        if submitted or closed then return end
        submitted = true
        -- Starting consumes the server interaction; do not cancel it first.
        net.Start("SendNPCInformation")
            net.WriteString(eventIdentifier)
        net.SendToServer()
        frame:Close()
    end

    -- Sets up the button to quit the menu
    local otherButton = vgui.Create("DButton", frame)
    otherButton:SetText("You wont get the chance (Quit the menu)")
    otherButton:SetSize(300, 100)
    otherButton:SetPos(ScrW() - 300, ScrH() - 100)

    otherButton.DoClick = function()
        frame:Close() -- Closes the frame
    end

    -- Makes it *pretty*
    frame.Paint = function(self, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 170))
    end

    -- Entity Frame creation
    local modelFrame = vgui.Create("DModelPanel", frame)
    modelFrame:SetSize(900, 900)
    modelFrame:SetModel(ent:GetModel())
    modelFrame:SetFOV(80)
    modelFrame:SetCamPos(modelFrame:GetCamPos() + Vector(0, -50, -10))
    modelFrame:Center()

    function modelFrame:LayoutEntity(ent) return end -- Ensures the model wont spin

end)

net.Receive("roundFinished", function()

    -- Creates the initial pop-up menu
    local alertFrame = vgui.Create("DFrame")
    alertFrame:SetDeleteOnClose(true)
    alertFrame:SetSize(ScrW(), 100)
    alertFrame:SetPos(0, 0)
    alertFrame:SetTitle("")
    alertFrame:ShowCloseButton(false)
    alertFrame:SetPaintShadow(true)

    -- Paints the menu and adds the border below it
    function alertFrame:Paint(w, h)
        draw.RoundedBox(0, alertFrame:GetX(), alertFrame:GetY(), w, h, Color(40, 40, 40, 100))
        surface.SetDrawColor(70, 70, 70, 100)
        surface.DrawRect(0, h-2, w, 2)
    end

    local alertText = vgui.Create("DLabel", alertFrame)
    alertText:SetText("You successfully killed all hostiles")
    alertText:SetFont("DermaLarge")
    alertText:SetColor(Color(255, 75, 75, 255))
    alertText:SetSize(ScrW(), alertFrame:GetTall())
    alertText:Dock(FILL)
    alertText:DockMargin((ScrW()/2) - 210, 0, 0, 18)

    -- Destroys the alert frame after 5 seconds
    timer.Create("destroyAlertFrame", 5, 0, function()
        
        if(alertFrame:IsValid()) then
            alertFrame:Close()
        end

    end)

end)

net.Receive("entitiesDeleted", function()

    for k, v in pairs(player.GetAll()) do
        v:ChatPrint("[NOTICE] - AN ADMIN HAS STOPPED THE CURRENT EVENT")
    end

end)