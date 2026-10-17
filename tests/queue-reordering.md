# Pending queue move callback-double tests

From the repository root, with an already installed stock Lua 5.3 interpreter:

```sh
lua5.3 tests/run-queue-reordering.lua candidate
```

This runs 31 move cases and 12 explicitly selected unchanged queue regressions.
It registers the existing 77-case queue file but invokes only the 12 selected
callbacks. It never loads `tests/run.lua`. The expected success allocation is
43 cases, 49 server fixtures, 147 application source loads (49 each of
sv_config.lua, activatorent/init.lua and activatorent/shared.lua), and 6 helper
source loads. The runner stops at the first failed case and refuses a case,
fixture or source load outside its fixed allocation. Arbitrary diagnostic bytes
are escaped before reporting. It runs real addon source through the existing
GLua translator and test doubles, not a live Garry's Mod server.

A separate baseline control uses this same candidate runner and tests, with cwd
at the pinned unmodified baseline:

```sh
lua5.3 /absolute/path/to/candidate/tests/run-queue-reordering.lua witness /absolute/path/to/candidate/tests
```

The baseline root must retain its existing `tests/find-upvalue.lua` helper.
The one control case passes only when that baseline does not recognize the new
move command. It allocates one server fixture, three application loads and four
helper loads. It is not a command for testing the feature on the candidate.

The retained review-only Python/Lupa wrapper is an additional, environment-bound
qualification path with SHA-256/Git input binding, runtime binding, a one-run
marker, a 120-second wall limit, CPU/memory/output caps and preserved logs.
Those wrapper files are not published dependencies of this Lua runner. This
source preparation did not execute either invocation. Any later run must report
its own result; neither callback-double path qualifies native chat privacy,
engine callbacks, timer behavior, or addon interactions.
