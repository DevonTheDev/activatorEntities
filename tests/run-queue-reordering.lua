-- Stock Lua 5.3 callback-double runner, not a native Garry's Mod test.
-- From the repository root: lua5.3 tests/run-queue-reordering.lua candidate
-- Baseline control only: from a pinned baseline root, invoke this candidate file
-- with: witness /absolute/path/to/candidate/tests
-- The reviewed host wrapper additionally binds bytes and caps resources.
-- No tests/run.lua, automatic retries, network, installation or native runtime.
local mode=(arg and arg[1]) or "candidate"
local tests=(arg and arg[2]) or "tests"
assert(mode=="candidate" or mode=="witness","mode must be candidate or witness")
assert(not arg or not arg[3],"no extra arguments")
assert(mode=="witness" or tests=="tests","candidate requires repository cwd and local tests")

local nativeDofile=dofile
local helperLoads,sourceLoads,fixtures,registered,executed,passed=0,0,0,0,0,0
local allowedTests={}
for _,path in ipairs({"gmod.lua","queue-reordering-allocations.lua","queue-reordering.lua","queue-reordering-witness.lua","encounter-queue.lua"}) do allowedTests[tests .. "/" .. path]=true end
allowedTests["tests/find-upvalue.lua"]=true
_G.dofile=function(path)
    assert(allowedTests[path],"test source outside fixed allowlist")
    helperLoads=helperLoads+1; assert(helperLoads<=(mode=="candidate" and 6 or 4),"helper source-load cap")
    return nativeDofile(path)
end
local function safe(value)
    local s=tostring(value); if #s>8192 then s=s:sub(1,8192) .. " [truncated]" end
    return (s:gsub("[^ -~]",function(c) return string.format("\\x%02X",c:byte()) end))
end
local function report(label,value) io.write(label," ",safe(value),"\n"); io.flush() end
local gmod=dofile(tests .. "/gmod.lua")
local allocations=dofile(tests .. "/queue-reordering-allocations.lua")
local expected=allocations[mode]
assert(type(expected)=="table","allocation selector missing")
local sourceCounts={}
local allowedSources={
    ["roleplayAddon/lua/autorun/server/sv_config.lua"]=true,
    ["roleplayAddon/lua/entities/activatorent/init.lua"]=true,
    ["roleplayAddon/lua/entities/activatorent/shared.lua"]=true,
}
local current,caseFixtures,caseSources
local originalSource=gmod.source
function gmod.source(path)
    assert(current and allowedSources[path],"application source outside fixed allowlist")
    sourceLoads=sourceLoads+1; caseSources=caseSources+1
    sourceCounts[path]=(sourceCounts[path] or 0)+1
    assert(sourceLoads<=expected.source_loads and caseSources<=current.fixtures*3,"application source-load cap")
    return originalSource(path)
end
local originalNew=gmod.new
function gmod.new(client)
    assert(current and not client,"server-only case fixture required")
    fixtures=fixtures+1; caseFixtures=caseFixtures+1
    assert(fixtures<=expected.fixtures and caseFixtures<=current.fixtures,"fixture cap")
    return originalNew(client)
end
local function eq(actual,wanted,message)
    assert(actual==wanted,(message or "equality") .. ": expected " .. tostring(wanted) .. ", got " .. tostring(actual))
end
local function run(name,allocated,callback)
    registered=registered+1; current=assert(expected.cases[registered],"case registration cap")
    assert(current.name==name and current.fixtures==allocated,"case identity or allocation mismatch")
    caseFixtures,caseSources=0,0; executed=executed+1
    local ok,problem=xpcall(callback,debug.traceback)
    if mode=="witness" then
        ok=not ok and tostring(problem):find("MOVE_WITNESS_UNRECOGNIZED",1,true)~=nil
        if ok then problem="pinned baseline lacks pending move command, as expected" end
    end
    if ok then
        assert(caseFixtures==current.fixtures,"actual fixture count differs from allocation")
        assert(caseSources==current.fixtures*3,"actual application load count differs from allocation")
        passed=passed+1; report("PASS",name)
    else
        report("FAIL",name); report("DETAIL",problem)
        error("queue move qualification stopped at first failed case: " .. safe(name),0)
    end
    current=nil
end
if mode=="witness" then
    dofile(tests .. "/queue-reordering-witness.lua")(gmod,run,eq)
else
    dofile(tests .. "/queue-reordering.lua")(gmod,run,eq)
    local wanted,seen={},{}
    for _,case in ipairs(allocations.regressions) do wanted[case.name]=case.fixtures end
    local registrations=0
    dofile(tests .. "/encounter-queue.lua")(gmod,function(name,callback)
        registrations=registrations+1; assert(registrations<=77,"published registration cap")
        if wanted[name] then assert(not seen[name],"duplicate regression name"); seen[name]=true; run(name,wanted[name],callback) end
    end,eq)
    assert(registrations==77,"published suite registration count changed")
    for name in pairs(wanted) do assert(seen[name],"missing selected regression " .. name) end
end
assert(registered==#expected.cases and executed==registered and passed==registered,"exact case accounting required")
assert(fixtures==expected.fixtures and sourceLoads==expected.source_loads and helperLoads==expected.helper_loads,"exact load accounting required")
for path in pairs(allowedSources) do assert(sourceCounts[path]==fixtures,"per-file source allocation mismatch") end
report("RESULT","mode=" .. mode .. " cases=" .. passed .. " fixtures=" .. fixtures .. " application_loads=" .. sourceLoads .. " helper_loads=" .. helperLoads)
_G.dofile=nativeDofile
return {registered=registered,executed=executed,passed=passed,fixtures=fixtures,source_loads=sourceLoads,helper_loads=helperLoads}
