-- From the repository root: lua tests/run-stop-command.lua (Lua 5.3 or newer).
-- Execute only the real chat callback with local doubles; no full addon load.
assert(not arg or #arg == 0, "This runner accepts no test selections or paths")
local file = assert(io.open("roleplayAddon/lua/autorun/server/sv_config.lua", "rb"))
local source = assert(file:read("*a"))
file:close()
source = source:gsub("\r\n", "\n")

local function unique(needle)
    local start, finish = source:find(needle, 1, true)
    assert(start, "Callback boundary is missing")
    assert(not source:find(needle, finish + 1, true), "Callback boundary is ambiguous")
    return start, finish
end
local start = unique('hook.Add("PlayerSay", "setUpSpawnPoints", function(sender, text)\n')
local finish = unique('\nend)\n\n-- file.Write lowercases DATA paths;')
assert(finish > start, "Callback boundaries are reversed")
local callback = source:sub(start, finish + #"\nend)" - 1) .. "\n"
local passed = dofile("tests/stop-command.lua")(callback)
assert(passed == 39, "Focused case count changed")
return passed
