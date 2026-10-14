-- Focused callback contract; no addon setup, encounter helpers or engine runtime.
-- The bounded evidence runner supplies the exact source registration chunk.
return function(callbackSource)
    local idle = "There is no event running"
    local denial = "Only admins can stop encounters."
    local usage = "Usage: !stopEvent"
    local guards = "valid,player,admin"
    local cases = {
        {name="admin success", stop=true, result="", calls=1, broadcast=true},
        {name="dead admin success", alive=false, stop=true, result="", calls=1, broadcast=true},
        {name="admin idle false", stop=false, result="", calls=1, reply=idle},
        {name="dead admin idle", alive=false, stop=false, result="", calls=1, reply=idle},
        {name="admin idle nil", stopNil=true, result="", calls=1, reply=idle},
        {name="stop function unavailable", unavailable=true, result="", reply=idle},
        {name="stop function disabled", disabled=true, result="", reply=idle},
        {name="nonadmin exact", admin=false, result="", reply=denial},
        {name="nonadmin extra", admin=false, text="!stopEvent extra", result="", reply=denial},
        {name="nonadmin whitespace", admin=false, text="!stopEvent ", result="", reply=denial},
        {name="dead nonadmin", admin=false, alive=false, result="", reply=denial},
        {name="admin extra", text="!stopEvent extra", result="", reply=usage},
        {name="admin extra spaces", text="!stopEvent  extra", result="", reply=usage},
        {name="admin tab argument", text="!stopEvent\textra", result="", reply=usage},
        {name="admin newline argument", text="!stopEvent\nextra", result="", reply=usage},
        {name="admin trailing space", text="!stopEvent ", result="", reply=usage},
        {name="admin trailing tab", text="!stopEvent\t", result="", reply=usage},
        {name="admin trailing newline", text="!stopEvent\n", result="", reply=usage},
        {name="admin trailing carriage return", text="!stopEvent\r", result="", reply=usage},
        {name="invalid sender", valid=false, trace="valid"},
        {name="nil sender", senderKind="nil", trace="valid"},
        {name="false sender", senderKind="false", trace="valid"},
        {name="nonplayer sender", isPlayer=false, trace="valid,player"},
        {name="nonplayer extra", isPlayer=false, text="!stopEvent extra", trace="valid,player"},
        {name="near match suffix", text="!stopEventExtra"},
        {name="capitalized command", text="!StopEvent"},
        {name="lowercase command", text="!stopevent"},
        {name="uppercase command", text="!STOPEVENT"},
        {name="leading space", text=" !stopEvent"},
        {name="unrelated chat", text="ordinary chat"},
        {name="unknown command", text="!unrelated"},
        {name="empty text", text=""},
        {name="nil text", textKind="nil", trace=""},
        {name="false text", textKind="false", trace=""},
        {name="number text", textKind="number", trace=""},
        {name="table text", textKind="table", trace=""},
        {name="stop error remains uncontained", throwAt="stop", calls=1},
        {name="reply error remains uncontained", throwAt="reply", stop=false, calls=1, reply=idle},
        {name="broadcast error remains uncontained", throwAt="net.Start", stop=true, calls=1},
    }
    local function eq(actual, expected, context)
        assert(actual == expected, (context or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
    local passed, failed, failures = 0, 0, {}
    local function check(case)
        local trace, replies, starts, sends = {}, {}, {}, {}
        local calls, getAllCalls, registrations = 0, 0, 0
        local sentinel = {}
        local recipients = {{kind="requester"}, {kind="other player"}}
        local function record(name)
            trace[#trace + 1] = name
            if case.throwAt == name then error(sentinel, 0) end
        end
        local sender = setmetatable({}, {
            __index=function(_, key) error("Unexpected sender method: " .. tostring(key)) end,
        })
        sender.valid = case.valid ~= false
        sender.alive = case.alive ~= false
        sender.IsPlayer = function(self)
            eq(self, sender); record("player"); return case.isPlayer ~= false
        end
        sender.IsAdmin = function(self)
            eq(self, sender); record("admin"); return case.admin ~= false
        end
        sender.ChatPrint = function(self, line)
            eq(self, sender); replies[#replies + 1] = line; record("reply")
        end
        local env = {
            type=type,
            IsValid=function(value)
                record("valid")
                return value == sender and sender.valid
            end,
            player={GetAll=function()
                getAllCalls = getAllCalls + 1; record("player.GetAll"); return recipients
            end},
            net={
                Start=function(name, ...)
                    eq(select("#", ...), 0); starts[#starts + 1] = name; record("net.Start")
                end,
                Send=function(target, ...)
                    eq(select("#", ...), 0); sends[#sends + 1] = target; record("net.Send")
                end,
            },
        }
        if case.disabled then env.stopActivatorEvent = false
        elseif not case.unavailable then
            env.stopActivatorEvent = function(...)
                eq(select("#", ...), 0, "stop receives no arguments")
                calls = calls + 1; record("stop")
                if case.stopNil then return nil end
                return case.stop == true
            end
        end
        local callback
        env.hook = {Add=function(event, name, fn)
            registrations = registrations + 1
            eq(event, "PlayerSay"); eq(name, "setUpSpawnPoints")
            eq(type(fn), "function"); callback = fn
        end}
        setmetatable(env, {
            __index=function(_, key)
                if key == "stopActivatorEvent" and case.unavailable then return nil end
                error("Unexpected callback global: " .. tostring(key))
            end,
            __newindex=function(_, key) error("Unexpected callback global write: " .. tostring(key)) end,
        })
        assert(load(callbackSource, "@setUpSpawnPoints", "t", env))()
        eq(registrations, 1, "exactly one callback registration")
        local inputSender = sender
        if case.senderKind == "nil" then inputSender = nil
        elseif case.senderKind == "false" then inputSender = false end
        local text = case.text
        if text == nil then text = "!stopEvent" end
        if case.textKind == "nil" then text = nil
        elseif case.textKind == "false" then text = false
        elseif case.textKind == "number" then text = 17
        elseif case.textKind == "table" then text = {} end
        local ok, result = pcall(callback, inputSender, text)
        if case.throwAt then eq(ok, false); eq(result, sentinel, "original error identity")
        else eq(ok, true, "callback returned normally"); eq(result, case.result, "chat return") end
        eq(calls, case.calls or 0, "stop call count")
        eq(#replies, case.reply and 1 or 0, "private reply count")
        if case.reply then eq(replies[1], case.reply, "exact private text") end
        local broadcast = case.broadcast == true
        eq(#starts, (broadcast or case.throwAt == "net.Start") and 1 or 0, "broadcast start count")
        if #starts > 0 then eq(starts[1], "entitiesDeleted", "unchanged broadcast name") end
        eq(#sends, broadcast and 1 or 0, "broadcast send count")
        eq(getAllCalls, broadcast and 1 or 0, "recipient lookup count")
        if broadcast then eq(sends[1], recipients, "complete original recipient table") end
        local expectedTrace = case.trace or guards
        if case.calls then expectedTrace = expectedTrace .. ",stop" end
        if case.reply then expectedTrace = expectedTrace .. ",reply" end
        if broadcast then expectedTrace = expectedTrace .. ",net.Start,player.GetAll,net.Send"
        elseif case.throwAt == "net.Start" then expectedTrace = expectedTrace .. ",net.Start" end
        eq(table.concat(trace, ","), expectedTrace, "ordered boundary calls")
    end
    for _, case in ipairs(cases) do
        local ok, message = pcall(check, case)
        if ok then passed = passed + 1; print("PASS " .. case.name)
        else
            failed = failed + 1; failures[#failures + 1] = case.name
            print("FAIL " .. case.name .. ": " .. tostring(message))
        end
    end
    eq(#cases, 39, "frozen case count")
    print("RESULT " .. passed .. " passed; " .. failed .. " failed; " .. #cases .. " total")
    assert(failed == 0, table.concat(failures, "; "))
    return passed
end
