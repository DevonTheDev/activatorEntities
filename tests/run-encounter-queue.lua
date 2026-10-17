-- Finite proposed runner; NOT EXECUTED during source-only preparation.
-- Run with cwd at candidate (default), or at baseline in witness mode and give
-- the candidate tests directory as argument 2. Never load tests/run.lua.
local mode=(arg and arg[1]) or "candidate"
assert(mode=="candidate" or mode=="witness","usage: run-encounter-queue.lua candidate|witness [tests-directory]")
local tests=(arg and arg[2]) or "tests"
local gmod=dofile(tests .. "/gmod.lua")
local passed,failed=0,0
local function eq(actual,expected,message)
    assert(actual==expected,(message or "equality") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function run(name,callback)
    local ok,err=xpcall(callback,debug.traceback)
    if ok then passed=passed+1; io.write("PASS ",name,"\n")
    else
        failed=failed+1; io.write("FAIL ",name,"\n",tostring(err),"\n"); io.flush()
        error("encounter queue qualification stopped at first failed case: " .. name,0)
    end
end
if mode=="witness" then
    local count=0
    dofile(tests .. "/encounter-queue-witness.lua")(gmod,function(name,callback)
        count=count+1; assert(count<=1,"witness budget"); run(name,callback)
    end,eq)
    assert(count==1,"one witness required")
else
    assert(tests=="tests","candidate mode requires its repository cwd and local tests directory")
    local count=0
    dofile("tests/encounter-queue.lua")(gmod,function(name,callback)
        count=count+1; assert(count<=77,"queue acceptance budget"); run(name,callback)
    end,eq)
    assert(count==77,"all 77 authored queue acceptance cases must register")
    local suites={
        {path="selection.lua",names={
            "successful refill retains its admitted pin when Spawn removes the last old owner",
            "last EntityRemoved releases the pin before native physical invalidation",
        }},
        {path="spawn-schedule.lua",names={
            "paused empty callback avoids event lookup sampling and all side effects",
        }},
        {path="immediate-batch.lua",names={
            "immediate exact command makes one private random ready batch without starting combat",
            "immediate ignores invalid and deleting manual actors",
            "immediate guard preserves ordinary timer reentry",
            "immediate exact pending table ownership through Spawn replace",
            "immediate exact pending table ownership through Spawn clear",
            "immediate exact pending table ownership through Spawn same name",
            "immediate exact pending table ownership through Spawn self remove",
            "immediate exact pending table ownership through Spawn false return",
            "immediate sparse position list samples only existing positions including the final extra draw",
            "immediate all invalid Create attempts retain position/queue/schedule stopped=false",
            "immediate all invalid Create attempts retain position/queue/schedule stopped=true",
            "immediate partial position exhaustion preserves stopped=false",
            "immediate partial position exhaustion preserves stopped=true",
        }},
    }
    local selectedCount=0
    for _,suite in ipairs(suites) do
        local wanted,seen={},{}
        for _,name in ipairs(suite.names) do wanted[name]=true end
        -- Published files only register callbacks. The finite exact allowlist
        -- invokes none of their interaction/admission/packet/grant test bodies.
        dofile("tests/" .. suite.path)(gmod,function(name,callback)
            if wanted[name] then
                assert(not seen[name],"duplicate regression name: " .. name)
                seen[name]=true; selectedCount=selectedCount+1; run(name,callback)
            end
        end,eq)
        for _,name in ipairs(suite.names) do assert(seen[name],"missing unchanged regression: " .. name) end
    end
    assert(selectedCount==16,"exactly sixteen unchanged regressions required")
end
io.write(string.format("%d passed; %d failed\n",passed,failed))
if failed>0 then os.exit(1) end
