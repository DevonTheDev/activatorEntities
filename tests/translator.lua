-- Standalone adapter checks: run from the repository root with texlua or Lua.
-- These lock down existing limitations as well as supported lexical behavior.
local gmod = dofile("tests/gmod.lua")
local source = gmod.source
local temporary = os.tmpname()
local passed = 0
local function eq(actual, expected, context)
    assert(actual == expected, (context or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function write(contents)
    local file = assert(io.open(temporary, "wb"))
    assert(file:write(contents))
    assert(file:close())
end
local cases = {
    {"empty", "", ""},
    {"operators", "!x != y ~= z && a || b !!= !!x", "not x ~= y ~= z && a || b not ~= not not x"},
    {"quotes", "local x = \"! != // --\"; local y = '! != // --'\n!x", "local x = \"! != // --\"; local y = '! != // --'\nnot x"},
    {"escaped quotes", "local x = \"a\\\"!b\"; local y = 'c\\'!d'; !x", "local x = \"a\\\"!b\"; local y = 'c\\'!d'; not x"},
    {"escaped backslashes", "local x = \"a\\\\\"; !x", "local x = \"a\\\\\"; not x"},
    {"unterminated quote", "local x = \"!a //b", "local x = \"!a //b"},
    {"terminal escape", "local x = \"!a\\", "local x = \"!a\\"},
    {"LF comments", "a // ! !=\n!b -- ! !=\n!c", "a -- ! !=\nnot b -- ! !=\nnot c"},
    {"CRLF comments", "a // ! !=\r\n!b -- ! !=\r\n!c", "a -- ! !=\r\nnot b -- ! !=\r\nnot c"},
    {"EOF comment", "!a // ! !=", "not a -- ! !="},
    {"CR-only comment", "!a // ! !=\r!b", "not a -- ! !=\r!b"},
    {"long comment", "!--[[ ! != // \"\n]]!x", "not --[[ ! != // \"\n]]not x"},
    {"long comment equals", "!--[===[ ! != // \" ]] ]=]\n]===]!x", "not --[===[ ! != // \" ]] ]=]\n]===]not x"},
    {"adjacent comments", "--[[]]--[=[!]=]!x", "--[[]]--[=[!]=]not x"},
    {"nested-looking comment", "a--[=[--[[ ! ]]==]!]=]!x", "a--[=[--[[ ! ]]==]!]=]not x"},
    {"unclosed comment", "--[[!x", nil, "tests/gmod.lua:18: unclosed comment"},
    {"mismatched close", "!a --[===[!x]==]", nil, "tests/gmod.lua:18: unclosed comment"},
    {"partial opener", "--[==x\n!x", "--[==x\nnot x"},
    {"comment at offset", "  x --[=[! !=]=]!y", "  x --[=[! !=]=]not y"},
    {"unsupported long string", "local x = [[! != // text\n]]; !x", "local x = [[not  ~= -- text\n]]; not x"},
    {"unsupported long string equals", "local x = [===[! != -- text\n]===]; !x", "local x = [===[not  ~= -- text\n]===]; not x"},
    {"unsupported continue", "for i=1,2 do if !x then continue end end", "for i=1,2 do if not x then continue end end"},
    {"continue in string/comment", "local x=\"continue\" -- continue\n!x", "local x=\"continue\" -- continue\nnot x"},
    {"binary bytes", "!\000!=\195\169\240\159\154\128\255", "not \000~=\195\169\240\159\154\128\255"},
    {"operator at EOF", "!", "not "},
    {"comment token at EOF", "//", "--"},
    {"minus at EOF", "-", "-"},
    {"bracket at EOF", "--[", "--["},
}
local ok, message = pcall(function()
    for _, case in ipairs(cases) do
        write(case[2])
        local translated, result = pcall(source, temporary)
        eq(translated, case[4] == nil, case[1] .. " outcome")
        eq(result, case[4] or case[3], case[1] .. " exact bytes/error")
        passed = passed + 1
    end

    -- Same module, path and length: an edit must be visible immediately.
    write("return !true")
    eq(source(temporary), "return not true")
    write("return !nil ")
    eq(source(temporary), "return not nil ")
    write("return !true")
    eq(source(temporary), "return not true")
    passed = passed + 1

    local first, second = gmod.new(true), gmod.new(true)
    first.marker, first.mutable = "first", {calls=0}
    second.marker, second.mutable = "second", {calls=10}
    write("return function() mutable.calls = mutable.calls + 1; return marker, mutable.calls end")
    -- Route only this include to our owned temporary file; retain the actual
    -- source reader and include/compiler path, without writing addon files.
    gmod.source = function(path)
        return source(path == "roleplayAddon/lua/__translator_test__.lua" and temporary or path)
    end
    local one = first.include("__translator_test__.lua")
    local two = second.include("__translator_test__.lua")
    local name, count = one(); eq(name, "first"); eq(count, 1)
    name, count = two(); eq(name, "second"); eq(count, 11)
    name, count = one(); eq(name, "first"); eq(count, 2)
    eq(first.mutable.calls, 2); eq(second.mutable.calls, 11)
    assert(first.mutable ~= second.mutable)
    passed = passed + 1
end)
gmod.source = source
local removed, removalError = os.remove(temporary)
assert(removed, removalError)
assert(ok, message)
print(passed .. " translator checks passed (28 lexical, immediate edits, isolated includes)")
