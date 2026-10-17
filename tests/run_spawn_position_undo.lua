-- Source-only release candidate. Loading/running this file requires a separate
-- validation release. The host owns process/Lua memory, CPU and output limits.
-- Interface: assert(loadfile(path))()({mode=..., source_path=..., tests_path=...})
-- Exactly one selected mode, no retries, fail closed on unknown configuration.
return function(options)
    assert(type(options) == "table", "runner options required")
    assert(options.mode == "witness" or options.mode == "candidate", "unknown mode")
    assert(type(options.source_path) == "string", "explicit bound source required")
    assert(type(options.tests_path) == "string", "explicit bound test path required")
    assert(type(options.helper_path) == "string", "explicit bound helper path required")
    local tests = options.tests_path
    local helper = assert(loadfile(options.helper_path))()
    local suite = assert(loadfile(tests .. "/spawn_position_undo_spec.lua"))()
    local allocations = assert(loadfile(tests .. "/fixture_allocations.lua"))()
    local result = suite.run(helper, options.source_path, options.mode, allocations)
    print("SPAWN_POSITION_UNDO_RESULT mode=" .. result.mode .. " registered=" .. result.registered
        .. " executed=" .. result.executed .. " passed=" .. result.passed .. " commands=" .. result.commands
        .. " lifecycle=" .. result.lifecycle .. " source_loads=" .. result.source_loads
        .. " file_ops=" .. result.file_ops .. " api_calls=" .. result.api_calls)
    return result
end
