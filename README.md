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
- `!listSpawns enemy|activator [page]`: privately inspect this map's configured positions
- `!removeEnemySpawn <key>` / `!removeActivatorSpawn <key>`: remove one freshly inspected position
- `!moveEnemySpawn <key>` / `!moveActivatorSpawn <key>`: move one freshly inspected position to where you are standing
- `!stopEvent`: remove the current event's enemies and restart the spawn delay
- `!refreshActivators`: retire ready addon activators and restart the normal spawn delay
- `!nextEvent <name>`: choose a configured encounter for the next fresh activator batch
- `!listEvents [page]`: browse all configured names and their selection eligibility
- `!clearNextEvent`: clear that pending choice
- `!eventStatus`: inspect the active encounter, ready activators and pending choice

Accepted spawn additions, removals and moves attempt a verified save immediately
to the DATA directory; clean shutdown also checks the latest state. Positions load on initialization.
Back up the existing spawn data before testing changes.

### Correct one spawn point

Use `!listSpawns enemy` to inspect the first eight enemy positions, or
`!listSpawns enemy 2` for the next page. Use `activator` for the other list.
Each row shows its actual stored key and coordinates. For example, after the
list shows key `2`, walk to the replacement location and use `!moveEnemySpawn 2`.
That point keeps its key, the number of points stays the same, and every other
point keeps its key and coordinates. Use `!moveActivatorSpawn 2` for a freshly
inspected activator point. To delete or add a point instead, use the existing
`!removeEnemySpawn 2` or `!setEnemySpawn` commands.

Copy the exact displayed key, including scientific notation if shown for an
unusually large key. Keys identify stored entries, not row numbers or positions
within the page. The bare remove commands still remove the highest stored key; an
invalid indexed request never falls back to that behavior. Bare or malformed
move commands give usage help and never add or remove a point.
If a maximum key is too large for adding one to produce a distinct valid key,
adding a point is refused instead of overwriting an existing point or wrapping.

The original add and bare remove commands also refuse ambiguous current-map
records, malformed map identities, and missing or malformed existing target
lists. A refusal leaves the configuration and saved files unchanged; it does not
repair or choose between duplicate records. These commands still work without a
prior inspection. Adding on a genuinely absent map creates one record with both
point lists; removing from an absent map or an empty valid list changes nothing.
Valid local edits keep the existing save behavior, including remaining in memory
if another invalid position list prevents the complete configuration from saving.

Moving a point or removing it by key requires your latest inspected page for that map and point
kind. Listing another page or kind replaces it. An accepted edit by any admin
invalidates inspections for the affected map/kind, even if saving fails.
Moving to the same coordinates still counts as an accepted edit and invokes the
save path once. Byte-identical acknowledged data is verified without rewriting it.
Changed coordinates on the shown page, replaced lists, missing entries and stale or reused keys
require listing again. Inspections are temporary, private to the requesting
admin and cleared on initialization or disconnection. They are not persistent
point IDs; arbitrary external replacement with identical content cannot be
distinguished. Missing or malformed target lists and ambiguous current-map
records are refused without modifying them.

These commands edit the input lists used by future ordinary spawn attempts.
They do not move existing actors or change an active encounter. A coordinate
listing does not prove a point is navigable, clear of collisions or otherwise
usable by the native engine. A move captures your position once and stores a
separate Vector; if that position or its copy is unusable, the point and your
inspection remain unchanged. Accepted moves and removals use the same immediate save
path as other edits; if saving fails or is disabled, the accepted change stays
in memory and the reply says so.

Local tests exercise actual command, persistence and encounter handlers using
engine doubles. Native chat-addon interaction, Vector serialization, DATA-file
persistence and world placement still need a disposable Garry's Mod server
check. On that server, have two admins list and move a middle point, trigger a
stale inspection with another edit, and restart to verify persistence. Repeat
for both point kinds, verify future spawns use the edited point, and check that
existing actors and an active encounter continue normally. Enemy spawns retain
their existing `(30, 30, 0)` placement offset from the stored point.

### Apply changes to a fresh ready batch

After editing activator positions or queueing a different encounter, an admin
can use `!refreshActivators` while no encounter is active. It requests removal
of every addon `activatorent`, including manually spawned ones, and clears the
selected ready batch. The pending next encounter stays queued. Other NPC types,
spawn data and persistence settings are unaffected.

The command restarts the ordinary timer, including when no activators are
present. It does not spawn immediately or start an encounter. The next normal
attempt still requires enough players, usable configuration and spawn positions,
and available capacity. A pending choice is consumed only after a fresh
activator successfully spawns. Use `!eventStatus` to inspect blocked conditions.

Active encounters refuse this command without changing their enemies or
progress. Use the separate `!stopEvent` command if you intend to cancel a fight.
Extra arguments to `!refreshActivators` produce usage help without refreshing.

Old interaction grants are cleared before removal starts. Removal can remain
pending until the [next engine tick](https://wiki.facepunch.com/gmod/Entity:Remove),
so the reply reports a request rather than immediate disappearance. The
[existing timer is restarted](https://wiki.facepunch.com/gmod/timer.Start);
the command does not bypass its configured delay. Open client dialogues retire
through their existing actor-removal/liveness handling.

Local command and workflow tests use engine doubles. A disposable Garry's Mod
server is still needed to check native timer timing, replicated removal, open
dialogue retirement and chat-addon interaction. Include a manually spawned
activator, queue a different encounter, refresh after moving a point, and verify
that only a later ordinary spawn uses the new position and queued definition.

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
- Before replacing an acknowledged save with different serialized bytes, the
  addon prepares `garrysmod/data/devonsspawninfo.backup.json` and reads it back
  exactly. This is one previous snapshot successfully loaded or saved by the
  current server session. It may omit more recent intentional changes. The
  canonical write is acknowledged only after a successful write result and
  exact read-back; serialization must also pass the existing load validation.
  A first save has no predecessor, so it leaves an existing orphan backup alone.
  A valid mixed-case legacy load is backed up before creating canonical data,
  and the legacy file stays untouched.
- Backup preparation failures leave canonical data untouched. If canonical
  writing fails after a verified backup, retries recheck and reuse that same
  recovery copy. They never copy partial canonical bytes over it. During such a
  retry, a prepared backup that changes or cannot be read blocks further writes until
  the same bytes can be verified again. Accepted edits remain in memory and
  receive the existing warning when saving cannot be verified.
- If both the newly serialized data and canonical bytes exactly match the last
  acknowledged snapshot, the save succeeds without rewriting either file.
  This includes byte-identical shutdown saves, preserving the older backup.
  Different JSON formatting or ordering is not treated as byte identity.
- After a failed load, saving is disabled for that server session so shutdown
  cannot overwrite the recoverable file with defaults. Admin spawn commands
  still work in memory, but those edits are **not saved**. The admin receives an
  explicit session-only warning with each accepted edit. Back up and repair
  the reported DATA file while the server is stopped, then restart to re-enable
  saving. To deliberately start fresh, move the backed-up file out of DATA
  before restarting; check both filename spellings if both exist. A backup is
  never loaded automatically and does not bypass this lockout.
- A shutdown before initialization, invalid runtime spawn data, or serialization
  failure also skips writing. Write failures are reported without a success
  message. An immediate save failure keeps the accepted edit in memory and warns
  its admin; the next successful edit or clean shutdown can retry saving. Empty
  removals, non-admin requests, unrelated chat and event cancellation do not
  trigger writes. The backup is not an atomic transaction or a durability
  guarantee. Immediate read-back cannot prove that bytes will survive power
  loss, device failure or external edits while the server is running.

To recover deliberately, stop the server and preserve separate copies of the
canonical file, backup and any mixed-case legacy file. Inspect the backup you
intend to restore, then copy its contents to the lowercase canonical filename
while retaining those copies. Restart and check the expected positions and
saving. Do not delete canonical data merely to trigger a legacy fallback.

Local fault-injection tests exercise truncating writes, false successes,
read-back failures, repeated retries and actual admin/encounter handlers. Native
Vector JSON, DATA reads/writes and recovery still need a disposable Garry's Mod
server check, including a case-sensitive filesystem. These tests do not simulate
power-loss durability; do not crash a production server to test it.

## Interaction and event lifecycle

- Starting requires a server-issued interaction belonging to the requesting
  player. The player must be alive, within 200 units of that activator, and
  reply within 60 seconds. Cancel, death, respawn, disconnect, removal, and
  activation invalidate the interaction. A matching reply from a living nearby
  player after expiry receives a private message to use the activator again.
  A reply at exactly 60 seconds is still accepted.
- Start and cancel are separate requests. Starting consumes permission once;
  repeated or forged messages cannot replenish the event's enemies.
- The full-screen dialogue fits its model and wrapped text into separate content
  areas above Start and Cancel. Long dialogue uses native vertical scrolling;
  the original button captions also wrap at narrow widths. Resolution changes
  resize the same open menu without submitting a request. Its full-screen frame
  cannot be dragged off-screen.
- An open dialogue retires when the client receives a valid active-encounter
  snapshot or its captured activator is removed or remains invalid. This also
  covers another player's Start and a start that removes the actors but creates
  no enemies. Automatic retirement sends no Start or Cancel request, and old
  callbacks cannot submit through a replacement dialogue. An inactive progress
  snapshot alone leaves a valid fresh menu usable.
  Client full-update removal notices are ignored immediately because an entity
  can be recreated during that refresh; later liveness checks still retire an
  actor that remains invalid ([Facepunch removal-hook documentation](https://wiki.facepunch.com/gmod/GM:EntityRemoved)).
- Only NPCs actually spawned for the active event affect its count. World/NPC
  kills are supported. A victory notice is sent once, only if all tracked
  enemies were killed. Cleanup/removal and admin cancellation restart spawning
  without announcing a victory. The completion popup closes after five seconds;
  a newer completion replaces it and restarts that one-shot dismissal.
- Missing/empty spawn lists safely pause spawning. Missing enemy spawns leave
  existing activators available and privately tell the requesting player to ask
  an admin to fix the missing enemy position, then use the activator again.

These two failed starts consume the interaction without starting an encounter
or changing the ready actors, selected batch, future choice, timer or progress.
An admin repair does not start it automatically; a fresh Use and Start are
required. Unissued, invalid, mismatched, cancelled and replayed requests stay
silent, including mismatched or invalid requests after expiry. Guidance uses
short constant `ChatPrint` text without configured names or positions; it adds
no addon network message or client behavior. Failure to create any enemies
after activation retains its existing cleanup path.

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
read/serialization/write failures, immediate persistence of spawn-edit
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
Start-feedback tests transfer the actual menu callback's request to the server
receiver. They check private expiry/missing-position guidance, the exact 60/61
second boundary, consumed replays, silent invalid requests, retained actors and
selection, and fresh-use recovery after the actual admin repair callback.
Dialogue-lifecycle checks transfer real server packets between separate client
entity copies, exercise actor-removal and client update callbacks, and preserve
valid menu replacement, ordinary Start/Cancel and completion/progress panels.
Deferred panel-removal checks also reject retained Start/Cancel callbacks while
a panel is marked for deletion but still valid, and preserve normal DFrame
Close/Cancel ordering. They verify request ownership without claiming native
Derma focus or network delivery timing.
Dialogue-layout checks cover 320x240 through wide and tall viewports, repeated
shrink/grow cycles, distinct action bounds, complete configured text, and native
wrap/scroll setup. They inspect panel geometry and API configuration, not rendered
font metrics, scrollbar reachability, pointer routing or model pixels. Native
DFrame and DLabel Think behavior remains responsible for their normal updates.
Only in-memory file/codec doubles and test fixtures are used; the tests never
read or write a server's DATA directory. They exercise the addon at the codec
boundary, not Garry's Mod's actual JSON parser or filesystem.
Backup checks tie encoded tokens to detached sparse-Vector snapshots and record
the order of file operations. They inject partial and complete writes with
failed returns, read errors and changed recovery copies, checking exact bytes
before retries and preserving normal admin/encounter behavior.

The suite exits nonzero on failure. The harness supports Lua
5.1 and newer; its small source adapter translates GLua operators/comments.
This pass was checked in Lua 5.3 via `texlua`, plus Lua 5.1 and LuaJIT 2.1
through Lupa 2.6.

These tests do **not** run the Garry's Mod engine. NPC behavior, entity networking,
native `ChatPrint` delivery/rendering, Derma layout, real timer timing, and saved
Vector JSON round-trips still need an in-game check. Suggested multiplayer smoke
test:

1. On `gm_construct`, wait for three activators. Use one and cancel, then use it
   again and start. Confirm five enemies appear and the activators disappear.
2. Have two players open activators; start from one. The other player's old
   dialogue should close automatically and must not create another event. Also
   remove an idle actor while its dialogue is open, and check that it closes.
   Repeat the server's stale-request checks after dying and respawning.
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
   positions reload, including on a case-sensitive Linux server. Make another
   changed save and confirm `devonsspawninfo.backup.json` contains its previous
   acknowledged snapshot; a byte-identical shutdown must retain that backup.
7. Rename the configured event on a disposable server, then check that its
   activators appear and its dialogue, enemies and completion still work.
8. On a disposable server with a backup, try malformed saved JSON. Confirm the
   configured positions work, a warning appears, and shutdown leaves the bad
   file and backup unchanged even after admin edits. Use the deliberate recovery
   steps above while stopped, then restart; confirm loading and saving resume.
   Check the mixed-case fallback
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
12. With a second player watching, leave an interaction open for more than 60
    seconds, then Start. Confirm only the requester sees expiry guidance and
    a fresh Use can start normally. Remove the final enemy spawn position,
    open and Start again, and confirm only the requester sees admin-repair
    guidance. Add a position with `!setEnemySpawn`; confirm it does not start
    automatically, then use the retained activator again and Start.
13. Open the dialogue at 800x600, 1280x720, 1920x1080, and wide/tall window sizes;
    include 320x240 if the client permits it. Shrink and grow the same open menu.
    Check model framing, full wrapped button captions, and both click targets.
    With long text and explicit line breaks, scroll to the final line, resize
    while scrolled, and confirm all text remains reachable. Exercise Start and
    Cancel after resizing, then repeat the two-player retirement check in step 2.

## Remaining follow-ups

- Verify previous-save recovery and native DATA read-back on a disposable server
- Exercise live Lua hot-reload during an active encounter; local round state is
  intentionally not persisted across script reloads
- Verify native dialogue wrapping, scrolling, focus and model framing with the
  disposable-client checks above
