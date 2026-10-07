-- Observe geometry and native API configuration in the actual client source.
-- These doubles do not implement docking, text measurement, rendering or input.
return function(gmod, test, eq)
    local function open(width,height,text)
        local env=gmod.new(true)
        env.screenWidth,env.screenHeight=width,height
        local player,actor=env.entity("player"),env.entity("activatorent")
        actor.model="models/alyx.mdl"
        env.receive("OpenInteractionMenu",nil,player,actor,"Raid",text or "Ready?")
        local menu={}
        for _,panel in ipairs(env.panels) do
            if panel.class == "DFrame" then menu.frame=panel
            elseif panel.class == "DLabel" then menu.text=panel
            elseif panel.class == "DModelPanel" then menu.model=panel
            elseif panel.class == "DScrollPanel" then menu.scroll=panel
            elseif panel.class == "DButton" then
                if panel.text:find("Start",1,true) then menu.start=panel else menu.cancel=panel end
            end
        end
        assert(menu.frame and menu.text and menu.model and menu.start and menu.cancel,"actual dialogue controls")
        return env,menu
    end

    local function rectangle(panel)
        local x,y=panel:GetPos()
        local parent=panel.parent
        while parent do
            x,y=x+parent.x,y+parent.y
            parent=parent.parent
        end
        return {x=x,y=y,w=panel:GetWide(),h=panel:GetTall()}
    end

    local function inBounds(panel,width,height,label)
        local rect=rectangle(panel)
        assert(rect.w > 0 and rect.h > 0,label .. " has usable dimensions")
        assert(rect.x >= 0 and rect.y >= 0 and rect.x+rect.w <= width and rect.y+rect.h <= height,
            string.format("%s stays in %dx%d: x=%s y=%s w=%s h=%s",label,width,height,rect.x,rect.y,rect.w,rect.h))
        return rect
    end

    local function separate(a,b,label)
        assert(a.x+a.w <= b.x or b.x+b.w <= a.x or a.y+a.h <= b.y or b.y+b.h <= a.y,label)
    end

    local function bounded(env,menu)
        local width,height=env.ScrW(),env.ScrH()
        eq(menu.frame.x,0); eq(menu.frame.y,0)
        eq(menu.frame.width,width,"dialogue width tracks viewport")
        eq(menu.frame.height,height,"dialogue height tracks viewport")
        local start=inBounds(menu.start,width,height,"Start")
        local cancel=inBounds(menu.cancel,width,height,"Cancel")
        separate(start,cancel,"Start and Cancel are distinct targets")
        local model=inBounds(menu.model,width,height,"model")
        local text=inBounds(menu.scroll or menu.text,width,height,"dialogue content viewport")
        separate(model,text,"model and dialogue content have distinct rectangles")
        for _,action in ipairs({start,cancel}) do
            separate(model,action,"model stays outside action rectangles")
            separate(text,action,"dialogue content stays outside action rectangles")
            assert(model.y+model.h <= action.y,"model stays above reserved action area")
            assert(text.y+text.h <= action.y,"text stays above reserved action area")
        end
        eq(menu.frame.popup,true,"dialogue retains native popup setup")
        eq(menu.frame.draggable,false,"full-screen dialogue cannot be dragged offscreen")
        eq(menu.start.text,"Bring it on (Start the Event)")
        eq(menu.cancel.text,"You wont get the chance (Quit the menu)")
        for _,button in ipairs({menu.start,menu.cancel}) do
            eq(button.wrap,true,"full action captions request native wrapping")
        end
    end

    for _,size in ipairs({{320,240},{640,480},{800,600},{1280,720},{1920,1080},{3440,1440},{600,1000}}) do
        test("dialogue controls and content fit initial " .. size[1] .. "x" .. size[2],function()
            local env,menu=open(size[1],size[2])
            bounded(env,menu)
            eq(#env.messages,0,"opening and initial layout submit no request")
        end)
    end

    test("dialogue keeps the same controls across same-frame shrink and grow cycles",function()
        local env,menu=open(1920,1080)
        local panelCount=#env.panels
        for _,size in ipairs({{800,600},{320,240},{1920,1080},{600,1000},{3440,1440},{640,480},{1280,720},{800,600}}) do
            local oldWidth,oldHeight=env.ScrW(),env.ScrH()
            env.screenWidth,env.screenHeight=size[1],size[2]
            env.fire("OnScreenSizeChanged",oldWidth,oldHeight)
            bounded(env,menu)
            env.fire("OnScreenSizeChanged",size[1],size[2])
            env.fire("Think")
            bounded(env,menu)
            eq(#env.panels,panelCount,"resize reuses existing controls")
            eq(menu.frame.valid,true); eq(menu.frame:IsVisible(),true)
            eq(#env.messages,0,"resize never sends Start or Cancel")
            eq(env.now,0,"resize cycles occur in one frame without timer advancement")
        end
    end)

    local textCases={
        {name="short",text="Ready?"},
        {name="multiline",text="First line\n\nThird line, with punctuation.\nLast line."},
        {name="long",text=string.rep("A configured encounter has more to say.\n",180) .. string.rep("LongWord",80)}
    }
    for _,case in ipairs(textCases) do
        test("dialogue preserves full " .. case.name .. " text through native wrap and scroll setup",function()
            local env,menu=open(800,600,case.text)
            local function configured()
                eq(menu.text.text,case.text,"configured text is neither truncated nor replaced")
                eq(menu.text.wrap,true,"native wrapping is enabled")
                eq(menu.text.autoStretchVertical,true,"native label height follows wrapped text")
                eq(menu.text.dock,env.TOP,"native canvas layout constrains label width")
                local scroll=assert(menu.scroll,"long dialogue has a native DScrollPanel viewport")
                eq(scroll.parent,menu.frame)
                eq(menu.text.parent,scroll:GetCanvas(),"dialogue is inside the native scroll canvas")
                eq(scroll.addedItems[1],menu.text,"DScrollPanel owns the configured dialogue")
                bounded(env,menu)
            end
            configured()
            env.screenWidth,env.screenHeight=320,240
            env.fire("OnScreenSizeChanged",800,600)
            configured()
            env.screenWidth,env.screenHeight=1920,1080
            env.fire("OnScreenSizeChanged",320,240)
            configured()
            eq(#env.messages,0)
        end)
    end
end
