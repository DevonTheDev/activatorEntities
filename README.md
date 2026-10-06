# Activator Entities

A Garry's Mod addon that spawns activator NPCs. Players use an activator to start
an enemy encounter. After the tracked enemies are killed, the next activators
appear after the configured delay.

## Install and configure

Copy `roleplayAddon` into the server's `garrysmod/addons` directory. Configure
`roleplayAddon/lua/autorun/server/sv_config.lua`; the supplied settings, NPC
models, health, counts, dialogue, and map positions are unchanged. Each named
entry in `NPCEdits` can be selected by the timed spawner; custom event names are
supported alongside the default `Raid`. Its model, dialogue, enemy class and
count follow the selected definition.

Admin chat commands:

- `!setActivatorSpawn` / `!setEnemySpawn`: add your current position for this map
- `!removeActivatorSpawn` / `!removeEnemySpawn`: remove the last position
- `!stopEvent`: remove the current event's enemies and restart the spawn delay
- `!nextEvent <name>`: choose a configured encounter for the next fresh activator batch
- `!listEvents [page]`: browse all configured names and their selection eligibility
- `!clearNextEvent`: clear that pending choice
- `!eventStatus`: inspect the active encounter, ready activators and pending choice

Accepted spawn additions/removals are saved immediately to the DATA directory,
with another save on clean server shutdown. Positions load on initialization.
Back up the existing spawn data before testing changes.

### Choose the next encounter

For example, `!nextEvent Raid` selects the configured `Raid` encounter. Use the
entry's `name` from `NPCEdits` to choose among configured encounters. Names
match exactly, including case and spaces; unknown or duplicate names are
rejected without losing an existing pending choice. A later valid selection
replaces the one pending slot. This choice lasts only for the current server
session and is not written into spawn data.

The choice waits for a normal timed spawn with no active encounter or existing
usable activators. It respects player requirements, spawn positions, delay and
capacity. It is consumed only after an activator successfully appears; failed
attempts leave it pending. Automatic refills keep the chosen name while that
selected batch still has its own activators. Manually spawned actors do not
consume a pending choice or keep a departed selected batch alive.

Queueing or clearing does not replace ready actors, interrupt an encounter or
start one automatically. Players still use an activator and pass the existing
server checks. `!clearNextEvent` clears only the future choice, so it does not
change a selected batch already waiting on the map. `!stopEvent` leaves the
future choice intact. If a selected definition becomes unavailable, it is
reported as unavailable rather than silently replaced with a random choice.

`!eventStatus` reports a snapshot of the actual current state, including mixed
ready encounter names where applicable. It does not choose a random event,
restart a timer, change permissions, or save data.

It also explains the current conditions for an automatic activator spawn:
the player minimum, available actor capacity, applicable selected encounter,
and this map's activator positions. Use this when no activators appear, before
changing the configuration. Empty, missing, malformed or ambiguous map data is
reported without changing it; sparse position lists are counted normally.
Enemy positions are shown separately because they are needed when a player
starts an encounter, not when the timed spawner creates its activators.

These are current configuration checks, not a countdown or a guarantee that
an NPC will spawn. An encounter definition can be present while its model or
NPC class is unusable in the engine. The status command does not consume the
pending choice, sample random events/positions, advance the timer, or start an
encounter. Existing spawning and selection rules continue to decide what the
next normal attempt does.

### Browse configured encounters

Use `!listEvents` to open page 1, then `!listEvents 2` for the next page. Replies
are private to the requesting admin. Each fresh page lists names in the same
case-sensitive order while the configuration stays unchanged. It identifies
duplicate names, missing information and malformed records instead of presenting
them as ordinary choices. Bare `!nextEvent` keeps its short help list and points
to this complete catalog.

An **eligible** entry passes the existing name-selection checks. The engine is
unchecked: an information table can exist while its model, NPC class or other
settings are unusable. The catalog does not queue an encounter or alter an active
one. Use `!nextEvent Supply Raid: Alpha!` to choose that exact configured name;
do not add quotation marks merely because the catalog surrounds names with them.

Long names continue across numbered parts, which can span pages. Join the contents
inside their outer quotes without adding spaces. Entry and part numbers are
display references, not selection IDs. Names containing control characters use
an explicitly **escaped diagnostic** representation, not text to paste directly
into a selection command. Native chat input and third-party chat addons may
limit which names can be entered.

Each reply contains at most eight body lines plus a header and footer, with each
line kept below the [ChatPrint byte limit](https://wiki.facepunch.com/gmod/Player:ChatPrint).
Invalid or out-of-range pages give usage feedback. Every call reads the current
configuration; pages are not a saved snapshot across commands. Reading the catalog
does not sample randomness, advance timers, spawn entities or save data.

Local tests exercise the actual command handler, selection checks, pagination,
UTF-8 boundaries and lifecycle state with Garry's Mod API doubles. Native chat
rendering, copying long names and interaction with a deployed chat addon still
need a live-server check.

### Saved spawn data and recovery

- The canonical filename is `garrysmod/data/devonsspawninfo.json`. Garry's Mod
  [lowercases `file.Write` paths](https://wiki.facepunch.com/gmod/file.Write),
  while [reads can be case-sensitive](https://wiki.facepunch.com/gmod/file.Read).
  If that file is absent, the historical `DevonsSpawnInfo.json` spelling is
  also checked. A present canonical file always takes precedence, even if it
  cannot be read or validated. A successfully loaded mixed-case file is left
  in place; the next successful admin edit or clean shutdown writes the canonical
  lowercase name.
- The complete decoded file is checked before it replaces the configured
  `SpawnPositions`. Map records must have a nonempty string `map` and both
  `enemySpawnPositions` and `activatorSpawnPositions` tables. Map/position lists
  use positive integer keys; gaps are preserved. Positions must be native
  Vectors with finite coordinates. Garry's Mod's existing
  [Vector JSON representation](https://wiki.facepunch.com/gmod/File_Based_Storage)
  is still read and written through its own JSON functions. No coordinate-table
  conversion or schema migration is performed.
- Empty map configurations and empty position lists are valid and remain empty.
  Invalid JSON, wrong-shaped records/lists, or unreadable existing files retain
  the configured positions and log a warning. The entire load is rejected rather
  than silently discarding individual entries.
- After a failed load, saving is disabled for that server session so shutdown
  cannot overwrite the recoverable file with defaults. Admin spawn commands
  still work in memory, but those edits are **not saved**. The admin receives an
  explicit session-only warning with each accepted edit. Back up and repair
  the reported DATA file while the server is stopped, then restart to re-enable
  saving. To deliberately start fresh, move the backed-up file out of DATA
  before restarting; check both filename spellings if both exist.
- A shutdown before initialization, invalid runtime spawn data, or serialization
  failure also skips writing. Write failures are reported without a success
  message. An immediate save failure keeps the accepted edit in memory and warns
  its admin; the next successful edit or clean shutdown can retry saving. Empty
  removals, non-admin requests, unrelated chat and event cancellation do not
  trigger writes. Writes are not atomic backups: crashes, disk failures, and
  external edits made while the server is running are not protected by this validation.

## Interaction and event lifecycle

- Starting requires a server-issued interaction belonging to the requesting
  player. The player must be alive, within 200 units of that activator, and
  reply within 60 seconds. Cancel, death, respawn, disconnect, removal, and
  activation invalidate the interaction. Use the activator again if it expires.
- Start and cancel are separate requests. Starting consumes permission once;
  repeated or forged messages cannot replenish the event's enemies.
- Only NPCs actually spawned for the active event affect its count. World/NPC
  kills are supported. A victory notice is sent once, only if all tracked
  enemies were killed. Cleanup/removal and admin cancellation restart spawning
  without announcing a victory. The completion popup closes after five seconds;
  a newer completion replaces it and restarts that one-shot dismissal.
- Missing/empty spawn lists safely pause spawning. Missing enemy spawns leave
  existing activators available so an admin can add positions and retry.

If a server callback cancels an encounter during initial spawning, the abandoned
loop stops creating enemies and requests removal of any enemy it just created.
It cannot change the progress of a replacement encounter. Tracked kills and
removals during setup still update that encounter's counts; their progress
notifications and completion handling wait until construction settles. Explicit
cancellation still retires the event immediately. The initial count includes
enemies added and then killed or removed during setup; removal still prevents
victory.

## Encounter progress

During an active encounter, a small panel in the upper-right corner shows its
configured name and how many hostiles remain out of the number actually spawned.
The bar represents the fraction remaining. Counts update when tracked enemies
are killed or removed; unrelated NPCs do not affect it. Removal without a kill
also shows an interruption warning, matching the existing rule that an
interrupted encounter cannot award the victory notice.

The panel clears when the encounter ends or an admin stops it. It never captures
the cursor or keyboard and does not replace the existing chat or completion
notice. Players joining mid-encounter request the current server snapshot after
the client's `InitPostEntity` ready hook. Snapshot requests are read-only and
limited to one per player per second; there is no periodic polling.

This display uses server-owned event state and does not change spawns, health,
starting permissions or completion rules. Live Lua hot-reload remains outside
the supported encounter lifecycle.

## Regression tests

From the repository root, run either:

```sh
lua tests/run.lua
# Or, when TeX Live's Lua interpreter is available:
texlua tests/run.lua
```

The suite runs the actual addon Lua in isolated environments with Garry's Mod
API doubles. It covers authorization, stale/repeated requests, client/server
message ordering, custom named event lifecycles, event completion and cleanup,
missing spawn configuration,
admin spawn editing, and completion-popup replacement/one-shot cleanup. Persistence tests also cover invalid decoded structures,
sparse native Vectors, intentionally empty lists, file-name precedence,
read/serialization/write failures, immediate persistence of all four spawn
commands, session-only warnings, shutdown retry, and preservation after a
rejected load.
Encounter-progress tests also cover actual spawned counts, every end path,
unrelated/repeated NPC callbacks, late-join snapshots, request throttling and the
client panel's update/clear/resize and input settings. Synthetic cross-realm
delivery checks the protocol fields without claiming real engine networking.
Encounter-selection tests cover administrator permissions, exact and duplicate
names, pending replacement/clear, partial and failed spawning, selected-batch
refills, manual actors, deferred removal and current/future ownership. They also
check that status and selection commands leave timers, RNG, persistence and
encounter messages alone, and preserve the normal client/server start path.
Construction tests deliberately invoke cancellation or tracked kill/removal
callbacks during another NPC's setup. They cover retired creation loops,
replacement ownership, initial/remaining counts and postponed completion. These
are controlled callback tests, not evidence of an ordinary live-server incident;
native deferred removal is checked separately in the harness.
Spawn-condition tests distinguish player/capacity limits, selected versus
pending ownership, missing and sparse map positions, and malformed or ambiguous
configuration. Repeated status reads are followed by actual source-level spawn
and start paths to check that inspection leaves their behavior intact. Timer
remaining time and native NPC/model availability are not inferred by the tests.
Only in-memory file/codec doubles and test fixtures are used; the tests never
read or write a server's DATA directory. They exercise the addon at the codec
boundary, not Garry's Mod's actual JSON parser or filesystem.

The suite exits nonzero on failure. The harness supports Lua
5.1 and newer; its small source adapter translates GLua operators/comments.
This pass was checked in Lua 5.3 via `texlua`, plus Lua 5.1 and LuaJIT 2.1
through Lupa 2.6.

These tests do **not** run the Garry's Mod engine. NPC behavior, entity networking,
Derma layout, real timer timing, and saved Vector JSON round-trips still need an
in-game check. Suggested multiplayer smoke test:

1. On `gm_construct`, wait for three activators. Use one and cancel, then use it
   again and start. Confirm five enemies appear and the activators disappear.
2. Have two players open activators; start from one. The other player's stale
   menu must not create another event. Repeat after dying and respawning.
3. Kill enemies with player weapons and world damage. Confirm one completion
   notice that disappears after five seconds, and the next activator batch after
   the configured delay. With short event delays, finish two rounds quickly and
   confirm only the latest completion popup remains.
4. Remove an enemy with a cleanup tool, then kill the rest. Confirm spawning
   resumes without a victory notice. Repeat with the admin `!stopEvent` command.
5. On an unconfigured map, add both spawn types, remove their final positions,
   and re-add them. Confirm there are no Lua errors or duplicate map entries.
6. On a disposable server, add/remove each spawn type and check that
   `devonsspawninfo.json` changes before shutdown. Restart and confirm the edited
   positions reload, including on a case-sensitive Linux server.
7. Rename the configured event on a disposable server, then check that its
   activators appear and its dialogue, enemies and completion still work.
8. On a disposable server with a backup, try malformed saved JSON. Confirm the
   configured positions work, a warning appears, and shutdown leaves the bad
   file unchanged even after admin edits. Repair the file while stopped and
   restart; confirm loading and saving resume. Check the mixed-case fallback
   separately with the lowercase file absent.
9. Start an event and confirm its passive progress panel updates after each
   tracked kill. Join from another client mid-event, remove a tracked enemy to
   check the interruption warning, and stop the event. Check the panel clears
   and never takes keyboard or mouse control, including after a resolution change.
10. Configure a second named encounter. Queue it with `!nextEvent`, inspect it
    with `!eventStatus`, and verify the next fresh batch uses it. Queue another
    choice while actors are ready or an event is active; confirm those actors
    stay unchanged. Remove one selected actor and check its refill, then clear
    the future choice and finish normally. Try these commands as a non-admin.
11. Use `!eventStatus` below the configured player minimum, on an unconfigured
    map, and after removing the last activator or enemy spawn position. Check
    that each explanation matches the state, that enemy positions are labeled
    as a start requirement, and that repeated reads do not alter the next spawn
    or the normal player interaction.

## Remaining follow-ups

- Consider an atomic/backup write flow to protect against interrupted writes
- Exercise live Lua hot-reload during an active encounter; local round state is
  intentionally not persisted across script reloads
- Check the existing full-screen dialogue layout at different resolutions
