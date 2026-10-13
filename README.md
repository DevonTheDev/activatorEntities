# Activator Entities

A Garry's Mod addon that spawns activator NPCs. Players use an activator to start
an enemy encounter. After the tracked enemies are killed, the next activators
appear after the configured delay when automatic spawning is enabled.

## Install and configure

Copy `roleplayAddon` into the server's `garrysmod/addons` directory. Configure
`roleplayAddon/lua/autorun/server/sv_config.lua`; the supplied settings, NPC
models, health, counts, dialogue, and map positions are unchanged. Each named
entry in `NPCEdits` can be selected by the timed spawner; custom event names are
supported alongside the default `Raid`. Its model, dialogue, enemy class and
count follow the selected definition.

Encounter lookup treats a non-table `NPCEdits` pool, a non-table sampled record,
or non-table information on the first matching name as unavailable. An automatic
attempt then creates no activators; a manual actor with unavailable information
uses the existing removal path. Lookup skips unrelated non-table records, so a
valid explicit choice still works beside them. For a nonempty table pool, random
selection keeps every entry and makes one draw; an unavailable pick is not retried
or replaced with a fallback. Sparse sampling and the existing duplicate-name behavior are unchanged.
The helpers do not repair or save configuration. A later attempt can work once
valid definitions are available; restart after configuration edits because live
Lua hot-reload is unsupported. These guards check only pool, record and information
types. They do not validate event names or fields within an information table,
including models, NPC classes, dialogue, counts or health.

At Start, the server separately requires `maxNPCs` to be a finite number at
least 1, rejecting NaN as well as the other invalid counts. Finite fractions
keep their existing behavior: 2.75 attempts to create two enemies. Rejection
consumes that interaction and privately tells the requesting player: "This
encounter has an invalid enemy count. Ask an admin to correct the configuration
and restart the server." It preserves the ready actors, selected batch, queued
future choice, timer and encounter progress. Replayed or unauthorized requests
stay silent. These fields are trusted server configuration; Start receives only
the encounter identifier. Correct
invalid configuration and restart the server before normal use. This guard
does not validate native NPC classes, models or health, or add a count cap.

After expiry, enemy-position and count validation, Start also requires
`npcPath` to be a string. A non-string consumes only that player's interaction
and privately reports: "This encounter has an invalid enemy class. Ask an admin
to correct the configuration and restart the server." The ready actors, other
players' interactions, selected batch, queued choice, schedule, counts and saved
configuration stay intact. Replays remain silent; repair requires a fresh Use.
The existing single enemy-position draw still occurs before count/class checks.

This is a trusted-configuration policy extension, not a native crash fix.
[Facepunch documents `ents.Create`](https://wiki.facepunch.com/gmod/ents.Create)
with a string class argument and a `NULL` result for nonexistent classes. Every
string passes this guard unchanged, including empty, numeric-looking and unknown
strings; the existing failed-creation lifecycle still handles invalid results.
The check does not verify class existence, model validity or engine behavior.

Ordinary inherited fields remain supported. Admission adds one `info.npcPath`
lookup before construction, so a custom getter observes an extra read at that
time. The loop still reads the field separately for each creation attempt;
callbacks or getters can change configuration after admission, including changing
the class to a non-string. This is an initial type check, not continuing
validation, a frozen configuration snapshot or exception supervision. Getter and
creation exceptions remain outside this guard. Local API doubles verify the
policy and ordering only; native GMod creation and chat delivery are unverified.

Enemy health has a separate, number-type-only check after each eligible NPC's
existing health lookup and ownership check. The first non-number sample (including
nil, tables, booleans and numeric strings) deliberately cancels that partial
encounter. Removal is requested for the remaining tracked enemies and the current
untracked NPC when still valid; no later candidate is created or sampled. The still-valid requesting player
receives one private correction: "Your encounter start was cancelled because the
configured enemy health is not a number. Ask an admin to correct the configuration
and restart the server." Values are never printed or coerced.

This cancellation has already consumed the interaction, ready actors and selected
batch. It preserves the queued future choice, clears the old counts and construction
state without victory, and restarts the normal delay only when automatic spawning
is enabled. Paused spawning stays paused until resumed; a later batch and fresh
Use/Start are required. Cleanup or feedback callbacks may start a replacement
encounter; the old constructor still cleans up its current NPC and then returns
without changing the replacement's state or timer. A getter that already cancelled
or replaced the event takes precedence and gets no additional correction.

The [documented SetHealth argument](https://wiki.facepunch.com/gmod/Entity:SetHealth)
is `number newHealth`. All numeric samples, including zero, negatives, fractions,
NaN and infinities, still reach the setter unchanged. This check adds no finite,
positive, integer or range policy. Setter exceptions remain outside this check.
Local API doubles establish admission and call order, not native health behavior,
rounding, death, hook timing or chat delivery; verify those on a disposable GMod
server. No native failure on an invalid health type is claimed.

If a custom `returnEnemyHealth()` throws, Start makes a best-effort recovery
before rethrowing the original Lua error object unchanged. It retires the captured
construction only while that construction still owns the encounter, clears its
counts and inspection state, and requests removal of its admitted enemies and
current unadmitted NPC independently. Secondary retirement or removal callback
errors cannot replace the original error or prevent the other removal attempts;
a failed removal request can leave an NPC behind. No cleanup-success diagnostic,
non-number correction, empty-start notice, victory or automatic retry is added.

Retirement restarts the ordinary delay only when automatic spawning is enabled,
before cleanup callbacks run. A replacement encounter, selected ready batch,
queued future choice, or pause/resume decision made by getter or removal callbacks
keeps its ownership; the old recovery path writes no timer decision after cleanup.
A previously removed ready activator's deferred `EntityRemoved` callback retains
its existing behavior and can still restart an enabled idle timer. This recovery
does not change that separate ready-actor hook.
A later ordinary batch and fresh Use/Start can recover after configuration repair.
This is conditional robustness for a custom throwing getter: the shipped getter
only returns the configured value. It does not supervise other construction APIs
or promise cleanup after every native engine failure.

Admin chat commands:

- `!activatorHelp [events|spawns|enemies|markers|control]`: privately read command help
- `!setActivatorSpawn` / `!setEnemySpawn`: add your current position for this map
- `!removeActivatorSpawn` / `!removeEnemySpawn`: remove the last position
- `!listSpawns enemy|activator [page]`: privately inspect this map's configured positions
- `!nearSpawns enemy|activator [page]`: privately inspect configured bases nearest to a living admin
- `!markSpawn enemy|activator <key>`: privately mark one freshly inspected stored base for 15 seconds
- `!clearSpawnMarker`: privately clear your temporary spawn snapshot
- `!removeEnemySpawn <key>` / `!removeActivatorSpawn <key>`: remove one freshly inspected position
- `!moveEnemySpawn <key>` / `!moveActivatorSpawn <key>`: move one freshly inspected position to where you are standing
- `!saveSpawns`: privately retry the verified save of accepted spawn positions for all maps
- `!spawnSaveStatus`: privately read cached session/load and historical save-attempt status, also while dead
- `!stopEvent`: remove the current event's enemies; restart the spawn delay unless paused
- `!refreshActivators`: retire ready addon activators; restart the normal spawn delay unless paused
- `!spawnActivatorsNow`: attempt one fresh ready batch now when enabled, idle and empty
- `!nearActivators [page]`: privately locate existing ready actors by current 3D distance from a living admin
- `!markNearestActivator`: privately mark the nearest ready actor's captured position for up to 15 seconds
- `!pauseActivatorSpawns` / `!resumeActivatorSpawns`: pause or resume automatic activator spawning for this session
- `!nextEvent <name>`: choose a configured encounter for the next fresh activator batch
- `!nextEventRef <ref>`: queue an eligible entry from your latest catalog page
- `!inspectEventRef <ref>`: privately inspect its configured model, enemy class and requested count
- `!listEvents [page]`: browse all configured names and their selection eligibility
- `!eligibleEvents [page]`: browse only names passing the existing next-event selection checks
- `!findEvents <page> <text>`: privately search configured names by a literal substring
- `!findEligibleEvents <page> <text>`: search only names passing the existing next-event selection checks
- `!clearNextEvent`: clear that pending choice
- `!eventStatus`: inspect automatic spawning, the active encounter, ready activators and pending choice
- `!listEventEnemies [page]`: privately inspect the active encounter's tracked enemy locations
- `!nearEventEnemies [page]`: privately inspect those enemies by current 3D distance from a living admin
- `!inspectEventEnemy <index>`: privately observe one exact listed enemy's `Health()`, `GetMaxHealth()` and `GetClass()`
- `!markEventEnemy <index>`: privately mark one freshly inspected remaining enemy's current position for 15 seconds
- `!clearEventEnemyMarker`: privately clear the shared temporary snapshot slot

Accepted spawn additions, removals and moves attempt a verified save immediately
to the DATA directory; clean shutdown also checks the latest state. Positions load on initialization.
Back up the existing spawn data before testing changes.

### Find a command in game

Use `!activatorHelp` for the topic index, then, for example,
`!activatorHelp spawns` for the exact commands and their main cautions. Topics
are the literal lowercase words `events`, `spawns`, `enemies`, `markers` and
`control`. Use one ASCII space before the topic, with no trailing spaces or
extra arguments. Unknown or malformed arguments receive fixed private usage
help; input is never echoed. Dead admins can also read help; nonadmins receive
one private denial.

Each response is fixed text with at most ten lines of 240 bytes each, sent only
to the requester. Help does not inspect current configuration, run another
command, change a selection or marker, or consume, replace or renew any inspected
page/reference. Existing command syntax, replies and permissions are unchanged.
The command needs an updated server; native delivery through the deployed chat
addon still requires an in-game check.

### Correct one spawn point

Use `!listSpawns enemy` to inspect the first eight enemy positions, or
`!listSpawns enemy 2` for the next page. Use `activator` for the other list.
Each row keeps its actual stored key and exact coordinates, followed by an
approximate 3D straight-line distance from your server position to that stored
base, in Source world units. The whole page uses one position snapshot taken
at list time. Walk and list the same page again to see distances change. An
unusable player position or an unrepresentable distance shows `distance unavailable`;
the coordinates and ordinary inspection/edit permissions remain usable.

Use `!nearSpawns enemy` (or `!nearSpawns activator [page]`) to sort the configured
bases by approximate 3D distance from one finite snapshot of your current server
position. Finite numeric distances sort before pagination, with the original
numeric stored key breaking exact distance ties. Unrepresentable distances appear
last as `distance unavailable`, tied by stored key; those valid bases still have
normal exact-key edit and marker permission. Sorting uses the numeric distance,
so rows with the same rounded distance text can have different order. Each page
holds at most eight rows and two framing lines, all at most 255 bytes.

Every nearby page request is fresh: walking between requests can change which
bases appear on each page. Copy the exact shown stored key into `!markSpawn`,
`!moveEnemySpawn` / `!moveActivatorSpawn`, or the matching indexed remove command.
A row's rank, page number or live enemy index is never an edit alias. This
configured-base catalogue is separate from `!nearEventEnemies`, which lists live
tracked enemies. Viewing neither samples nor changes spawn configuration, saved
data, actors, RNG, dialogue, timers or marker packets.

Nearby viewing requires a living admin and one usable finite position, including
for an empty list. A dead admin or an unavailable position receives no nearby
page; retry or use `!listSpawns`, which still allows dead admins and shows exact
key-ordered rows with unavailable distances when it cannot capture an origin.
Both catalogues retain the existing actor rejection boundary: invalid/nonplayer
and nonadmin requests keep a prior configured page, while an admitted invalid
request clears it. An accepted nearby page has the same edit/marker permissions
as an ordinary page, with no time or death expiry and no requirement to stay near
the base. Accepted edits invalidate affected map/kind pages even if saving fails;
existing shown-coordinate, raw map-record/list identity and lifecycle checks
still apply. An already sent marker remains a historical snapshot.

Both configured catalogues now share pending request identity. A nested newer
ordinary/nearby attempt, accepted scoped edit, disconnect or initialization can
retire an older capture before it installs a page. Nearby publication additionally
rechecks the complete captured key/coordinate set, list identity, current map and
living-admin admission. This tightens a prior ordinary-list callback edge where
an older capture could overwrite a newer page before replies began. Pages remain
installed before the first reply, with no acknowledgement or later permission
write: nested reply actions retain their resulting authority even if frozen
outer output continues. These bounded checks cover the tested callback and
lifecycle transitions, not arbitrary hostile native getters or hot-reload safety.

These are distances to configured bases, not live NPC locations or a prediction
of which base a later spawn will sample. Activators use their stored position as
the placement input. Enemy placement starts from one sampled base and advances
by `(30, 30, 0)` for every valid creation: the first uses base + `(30, 30, 0)`,
the second base + `(60, 60, 0)`, and so on. A distance does not check navigation,
collision clearance or whether an NPC can reach the point. There is no periodic
update; earlier chat output remains a historical snapshot.

After inspecting a page, a living admin can use `!markSpawn enemy 2` (or
`!markSpawn activator 2`) with the exact shown key. It sends only that admin one
labelled, 15-second **stored-base snapshot**; another accepted marker replaces it.
`!clearSpawnMarker` clears it, including when already clear. The mark does not
consume or refresh the page's edit permission. Invalid or stale requests preserve
an existing marker. A new listing replaces admission for future requests, while
an already sent snapshot keeps its captured coordinates. Later edits, deletion
or key reuse do not move that historical snapshot or authorize another mark:
inspect the current page again. Marking never edits, saves, teleports, spawns,
samples a location or changes the encounter, dialogue or spawn schedule.

Turn toward the point to see its cross inside the viewport. The fixed label and
help remain while it is behind you or outside view; there is no edge arrow. The
cross may show through walls and is not a line-of-sight, collision or navigation
test. Enemy markers show the configured base **before** cumulative placement
offsets. Extreme finite coordinates can be declined if the native Vector cannot
copy them exactly or projection fails; chat confirms a snapshot was sent, not
that it appeared. Short screens trim labels to available space.

Expiry uses synchronized game time, with at most one second of clock tolerance
on receipt and a separate maximum of 15 local real seconds. A delayed packet has
only its remaining game-time life. Think and HUD checks permanently discard a
snapshot on observed expiry, death, loss of admin, invalid/replaced local player
or map change, and initialization/reload clears it. A failure entirely between
client callbacks is not observable. Same-map cleanup need not erase a historical
point. The server stores no displayed markers and sends no automatic refreshes;
the client sends no marker requests, acknowledgements or retries.

Update both server and client addon files and reconnect. An old client cannot
show a new marker packet, while an old server may treat the new command as public
chat. Mixed versions do not provide private-command or display guarantees.

For example, after the list shows key `2`, walk to the replacement location and
use `!moveEnemySpawn 2`.
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
existing actors and an active encounter continue normally. Have both admins
list from different locations, move and relist, and verify each sees only their
own updated base distances with the same keys and coordinates. Include vertical
separation and verify readable private chat rows and the cumulative enemy
placement offset described above.
Also compare ordinary and nearby ordering, including ties and page changes after walking;
copy literal nearby keys into move/remove/mark and check stale pages with two admins.
Native nearby privacy, Vector precision, chat rendering, deployed hook interactions,
placement, navigation and clearance remain unverified by the API-double tests.

### Apply changes to a fresh ready batch

After editing activator positions or queueing a different encounter, an admin
can use `!refreshActivators` while no encounter is active. It requests removal
of every addon `activatorent`, including manually spawned ones, and clears the
selected ready batch. The pending next encounter stays queued. Other NPC types,
spawn data and persistence settings are unaffected.

When automatic spawning is enabled, the command restarts the ordinary timer,
including when no activators are present. While paused, it keeps spawning paused
and says so in its private reply. It does not spawn immediately or start an
encounter. The next normal attempt still requires enough players, usable
configuration and spawn positions,
and available capacity. A pending choice is consumed only after a fresh actor
returns from `Spawn` valid and not marked for deletion. Use `!eventStatus` to
inspect blocked conditions.

Active encounters refuse this command without changing their enemies or
progress. Use the separate `!stopEvent` command if you intend to cancel a fight.
Extra arguments to `!refreshActivators` produce usage help without refreshing.

Old interaction grants are cleared before removal starts. Removal can remain
pending until the [next engine tick](https://wiki.facepunch.com/gmod/Entity:Remove),
so the reply reports a request rather than immediate disappearance. The
[existing timer is restarted](https://wiki.facepunch.com/gmod/timer.Start) only
when spawning is enabled; the command does not bypass its configured delay.
Open client dialogues retire
through their existing actor-removal/liveness handling.

Local command and workflow tests use engine doubles. A disposable Garry's Mod
server is still needed to check native timer timing, replicated removal, open
dialogue retirement and chat-addon interaction. Include a manually spawned
activator, queue a different encounter, refresh after moving a point, and verify
that only a later ordinary spawn uses the new position and queued definition.

### Mark the nearest ready activator

Use exactly `!markNearestActivator`, with no arguments, as a living admin while
no encounter is active. It sends a private position snapshot of the nearest
valid, non-deleting activator in a freshly copied actor scan, including manual
actors. It compares unrounded 3D distance from your captured current position,
with descriptive numeric entity index as the tie-break. It reads each native
position once. If any captured ready actor has an unreadable, nonfinite or
unrepresentable distance, or the selected index is unusable or changes, it
refuses and preserves the current marker. It never silently chooses a farther
readable actor or resolves a replacement through a reused index.

The label says `Activator actor index ... - position snapshot`; the actor may
move or disappear. This is nearest within that request's captured list, not a
live tracking, navigation, health, configuration or reachability promise. The
point shares the existing private marker slot and maximum 15-second lifetime;
`!clearSpawnMarker` clears it. New accepted marks replace that slot. Recognized
malformed requests stay private and preserve the displayed point; command near
matches remain ordinary chat. The command grants no interaction or other action,
and changes no catalogue lease, actor, config, queued choice or timer. Normal
Use and Start still apply their existing checks.

Before sending, it rechecks operation ownership, living-admin admission, map,
encounter identity, captured ready actors and the selected index. Newer marks,
clears, qualifying configured/enemy lists, disconnect and initialization retire
an older in-flight operation. Getter failures are contained. No prior
`!nearActivators` page is needed or used as authority.

Update both server and client addon files and reconnect. The new `ready_actor`
subtype uses the existing bounded packet and one-bit clear. Older clients reject
that unknown subtype and keep their prior valid marker; updated clients retain
the stored-base and encounter-enemy behavior. An old server may expose this
unknown command as public chat. Native GMod packet delivery, entity timing and
rendering remain unverified by the local host-Lua fixtures.

### Locate existing ready activators

A living admin can use `!nearActivators [page]` to find current valid,
non-deleting `activatorent` actors, including manually placed actors. This is
useful when `!spawnActivatorsNow` reports that a ready actor already exists.
The command refuses during an active encounter, when using a ready actor is
already blocked. It needs a finite current requester position.

Each private page shows up to eight actors with a descriptive entity index,
approximate actual world coordinates and distance from the requester's captured
position in 3D Source units. It reads each position once and orders detached
scalar copies by unrounded finite distance, then index and position text. Actors
with unreadable or nonfinite positions remain visible as position/distance
unavailable; unrepresentable distances sort last. Each request is fresh, so
movement, spawning and deletion can change pages. This lists actual actors,
whereas `!nearSpawns activator` lists configured spawn bases.

"Ready" uses the existing validity/deletion predicate. It does not prove
selected-batch ownership, valid encounter configuration, health or reachability.
Indices can be reused and confer no action permission. Listing creates no
inspection lease, interaction, marker or target grant and changes no actors,
configuration, queued choice, timer or existing permission. Normal Use and Start
still perform their existing checks.

A short-lived request identity suppresses older captures superseded by another
request, disconnect or initialization. Before replying, the command checks the
requester, current map, encounter identity and captured actor validity again.
Controlled getter callbacks are covered by local tests; this is not a promise
against arbitrary addon side effects in every native getter. Native GMod
chat/wire/render behavior remains unverified.

### Attempt a ready batch now

An admin can use exact `!spawnActivatorsNow` with no arguments to make one
ordinary ready-batch attempt immediately. Dead admins can also use it. Replies
are private and bounded; extra arguments give usage help. It refuses while
spawning is paused, an encounter is active, another spawn attempt is in flight,
or any valid, non-deleting `activatorent` exists, including manual actors and
actors left by an earlier error. Refusals leave selected ownership, the pending
choice, RNG and the schedule unchanged.

An admitted request still checks minimum players, current-map activator
positions, event selection and capacity in the ordinary order. It uses the
pending choice for an empty batch, otherwise ordinary random selection. It
neither unpauses spawning nor changes configuration, removes actors or starts
combat. Players still use an activator to start an encounter. Use the separate
`!refreshActivators` command to retire existing ready actors and restart the
normal delay; refresh remains a delayed operation.

The command reports an admission blocker, the final observed ready count and
capacity, an interruption, or an error. A valid actor returning from `Spawn`
can consume only the exact pending selection admitted for that batch. A
selection replaced or cleared inside another addon's callback is not consumed
by the old attempt, even when its replacement uses the same name. A false
`Spawn` return value retains the existing behavior: actor validity and deletion
state determine admission, not that return value. These observations do not
prove native placement or successful engine spawning.

The command does not start, replace, restart or rewind the existing timer.
The reused ordinary attempt still stops it on reaching capacity, and existing
lifecycle/control callbacks retain their timer effects. Zero, partial and
error outcomes schedule no retry, including when the timer was already stopped.
An error can leave actors or consume the admitted choice before it occurs;
there is no rollback. Inspect the current state before deciding what to do next.

Pause, pause followed by resume, and refresh from a Spawn callback retire the
old attempt after ownership is completed for any surviving actor. An encounter
left active by a callback also stops further work by this immediate command.
Interrupted attempts report that outcome without another stale recount or
capacity stop. An encounter that starts and fully finishes within one callback
is not detected as an interruption. Ordinary timed callback behavior is
preserved. Native timer timing, callback interactions, chat privacy/rendering,
replicated removal and world placement still need a disposable Garry's Mod
server check; the local suite uses API doubles.

### Pause automatic activator spawning

Use `!pauseActivatorSpawns` to hold new automatic batches while editing spawn
points or staging an encounter. Pause stops the automatic timer and blocks an
already-due callback. It leaves ready and manually spawned activators usable,
preserves existing Start/Cancel interactions and queued selections, and lets
active fights finish normally. It does not remove entities or change spawn
data, configuration, progress or victory rules.

For a clear arena, pause first, use `!stopEvent` separately if a fight is active,
then use `!refreshActivators` to retire ready actors. Both commands keep automatic
spawning paused. You can now edit positions and queue `!nextEvent <name>`.
`!eventStatus` shows `paused` or `enabled` independently of the active, ready and
pending encounter details.

Use `!resumeActivatorSpawns` when ready. With no active encounter, it restarts the
existing timer with its full configured delay; it never spawns immediately. If a
fight is active, the delay starts when that encounter ends. The next attempt
still checks players, capacity, positions and selection eligibility. Pending
selection is consumed only by a usable fresh actor. Repeating either command
does not reset the delay or restart a timer stopped because its capacity is full.
Both commands require an admin and accept no extra arguments. Pause lasts only
for this server/addon session; a fresh session starts enabled.

If another addon's synchronous Spawn callback pauses spawning, the actor already
being set up may finish normally, but that old attempt cannot add another actor.
A pause followed by resume in the same callback leaves further admissions to the
new delay and cannot let the old attempt stop the restarted timer.

The [stop operation rewinds the timer](https://wiki.facepunch.com/gmod/timer.Stop),
and [start restarts it](https://wiki.facepunch.com/gmod/timer.Start). Source-level
tests check these calls and callback ordering through doubles. Native elapsed
timing, server hibernation and replicated removal still require a disposable
Garry's Mod server: pause and refresh, wait beyond the configured delay, verify
no replacement, resume and verify replacement only after the full delay. Repeat
with a fight ending while paused and check the private admin replies.

### Choose the next encounter

For example, `!nextEvent Raid` selects the configured `Raid` encounter. Use the
entry's `name` from `NPCEdits` to choose among configured encounters. Names
match exactly, including case and spaces; unknown or duplicate names are
rejected without losing an existing pending choice. A later valid selection
replaces the one pending slot. This choice lasts only for the current server
session and is not written into spawn data.

The choice waits for a fresh batch with no active encounter or existing usable
activators: either a normal timed attempt or an explicit `!spawnActivatorsNow`
request. Both respect player requirements, spawn positions and capacity; only
the command attempts it before the normal delay. The choice is consumed after
an actor returns from `Spawn` valid and not marked for deletion. An attempt
that creates no usable actor leaves it pending; an error after a usable actor
may already have consumed it. Automatic refills keep the chosen name while that
selected batch still has its own activators. Manually spawned actors do not
consume a pending choice or keep a departed selected batch alive.

Queueing or clearing does not replace ready actors, interrupt an encounter or
start one automatically. Players still use an activator and pass the existing
server checks. `!clearNextEvent` clears only the future choice, so it does not
change a selected batch already waiting on the map. `!stopEvent` leaves the
future choice intact. If a selected definition becomes unavailable, it is
reported as unavailable rather than silently replaced with a random choice.

`!eventStatus` reports a snapshot of the actual current state, including whether
automatic spawning is paused or enabled and mixed ready encounter names where
applicable. It does not choose a random event,
restart a timer, change permissions, or save data.

It also explains the current conditions for an automatic activator spawn:
the player minimum, available actor capacity, applicable selected encounter,
and this map's activator positions. Use this when no activators appear, before
changing the configuration. Empty, missing, malformed or ambiguous map data is
reported without changing it; sparse position lists are counted normally.
Enemy positions are shown separately because they are needed when a player
starts an encounter, not when the timed spawner creates its activators.

Automatic attempts skip creation when the effective `maxActivators` is a
nonnumeric value, NaN or infinity. The existing one-actor fallback for nil/false
and `multipleEntities ~= true` remains; finite negative, zero and fractional
values keep their existing behavior. Rejection leaves the pending choice,
ready actors, interaction grants and timer state intact. Event and initial
position sampling still occur before this capacity check. Correct invalid
configuration and restart the server as usual.

These are current configuration checks, not a countdown or a guarantee that
an NPC will spawn. An encounter definition can be present while its model or
NPC class is unusable in the engine. The status command does not consume the
pending choice, sample random events/positions, advance the timer, or start an
encounter. Existing spawning and selection rules continue to decide what the
next normal attempt does.

### Find a remaining encounter enemy

If an encounter still has enemies that players cannot find, use
`!listEventEnemies`, then `!listEventEnemies 2` for another page. The command
privately shows the requesting admin up to eight enemy rows per page. It reads
the active encounter's owned enemies and their current world positions; the
configured starting positions remain available separately through `!listSpawns`.

Coordinates are approximate. Missing or unreadable positions and unavailable
entity indices are identified explicitly. Invalid or deleting tracked entities
are omitted and counted separately, so the listed row count may differ from the
encounter's remaining count. Inspection does not prune that set or decide when
the fight finishes. Available entity indices are sorted numerically; they are
temporary references and can be reused after deletion, as described by
[the engine's EntIndex API](https://wiki.facepunch.com/gmod/Entity:EntIndex).

Each request builds a fresh snapshot before sending replies. Moving enemies,
kills and removals can change the next page request; no cursor or persistent
enemy ID is created. A successful page keeps a private, server-local selection
for that admin until their next successful page, an accepted removal request,
disconnection or encounter retirement. Listing has no gameplay, timer, randomness,
saved-data or network-publication side effects.

A living admin can instead use `!nearEventEnemies [page]` for nearest-first
ordering from their captured position at request time. It uses straight-line 3D
Source units, including height, with six significant digits in the approximate
distance display. Ranking uses the captured unrounded coordinates. Equal distances
use the existing numeric-index and position-text order; unavailable enemy distances
remain listed last. A usable current map and finite native requester position are
required. If that position is unavailable, use `!listEventEnemies [page]`.

Each nearest page captures the admin and all included enemies once, including rows
on other pages. Actor or enemy movement, kills and removals can move rows between
fresh requests. There is no radius, cursor, navigation route, visibility test or
reachability guarantee. The action token is the exact displayed entity index,
never its distance rank. A successful nearest page supplies the same private
marker/removal selection as a successful ordinary page. A failed nearest attempt
retires marker permission while preserving the last successful removal page;
current action admission still applies. A capture superseded during getters cannot
overwrite a newer page. Ordinary listing retains its existing output and ordering.

### Inspect one enemy's observed health and class

After `!listEventEnemies [page]` or `!nearEventEnemies [page]`, use
`!inspectEventEnemy <index>` with one exact unique index from your latest eligible
page. The command reads the same owned entity's `Health()`, `GetMaxHealth()` and
`GetClass()`, in that order, once each at inspection time and sends one private
line. Another admin must list independently. Dead admins can inspect an eligible
page; inspection needs neither a living requester nor their position.

These are independent observed game values, as described by the engine's
[Health API](https://wiki.facepunch.com/gmod/Entity:Health) and
[GetMaxHealth API](https://wiki.facepunch.com/gmod/Entity:GetMaxHealth).
The addon sets spawn health with `SetHealth`, but does not set `SetMaxHealth`.
No ratio, configured-maximum claim, invulnerability diagnosis or kill prediction
is made. The three reads are not an atomic engine snapshot and may change afterward;
a later getter changing health does not cause an earlier observation to be reread.
Finite zero, negative, fractional and above-maximum observations are retained.
Each missing or throwing health getter shows `unavailable`; a nonnumeric or
nonfinite result has a fixed diagnostic, without hiding other usable observations.
Configured health generators are never sampled by inspection.

The observed class is display information from that exact entity, not the configured
`npcPath`, validation of a class for spawning, or authority over other entities.
A missing, non-callable or throwing `GetClass` shows `unavailable`; a nonstring
result shows `invalid nonstring`, and an empty string shows `invalid empty string`.
Class failures leave usable health observations visible, and health failures leave
usable class observations visible while the target stays eligible. No arbitrary
value or exception is converted to text.

Nonempty class strings are quoted. Printable ASCII appears directly except quote
and backslash; those and every other byte are shown as complete `\xHH` escapes,
with `[escaped]` when needed. Only the class payload is shortened, with an explicit
`[truncated]` note when bytes are omitted. The formatter reads a bounded prefix and
reserves space for both health fields and the complete disclaimer within the single
255-byte reply. Escaped bytes are never split.

Health eligibility starts only after the exact page's full server reply sequence
returns, outside encounter construction. This does not prove client receipt or
display. Existing marker/removal grants keep their established timing. Any newer
listing attempt, even a failed one, invalidates health eligibility. Accepted
removal consumes the requester's page as before; disconnect, server Initialize,
encounter retirement/replacement, changed or unavailable map, changed index,
death/removal/deletion and pending target cleanup also prevent inspection.
A reused index never resolves a replacement entity. List again and copy one exact
current index when refused. There is no timed health lease. Stable interrupted
encounters and paused automatic spawning still allow eligible surviving targets;
another admin's pending cleanup blocks only its selected target.

Inspection neither consumes nor renews marker/removal authority, changes health,
spawns, removes, invokes randomness, writes saved data, creates timers or sends
network packets. Nested requests and lifecycle changes suppress obsolete replies;
feedback itself has no later state writes. The regression tests exercise bounded
callback transitions, not arbitrary mutation by unsupported getters. Native
Garry's Mod entity lifetime/index reuse, health/class APIs, pending deletion and deployed
chat-addon privacy remain unverified. A disposable-server smoke check should use
both listing commands and two admins, compare the listed target's class with its
server observation, damage a surviving enemy between observations, exercise
dead-admin inspection, pending removal and encounter replacement, and confirm
ordinary marker/removal workflows.

### Mark one inspected encounter enemy

After a successful `!listEventEnemies [page]` or `!nearEventEnemies [page]` outside
encounter construction, a
living admin can use `!markEventEnemy <index>` with one exact index shown on that
page. The server captures that same owned enemy's current position **at mark
time**, including fractional coordinates. It sends only that admin a 15-second
**encounter-enemy position snapshot**. Movement after listing is reflected in the
new mark; movement after marking does not move the point. This is distinct from
the configured stored bases shown by `!markSpawn enemy <key>`.

Another admin must inspect independently. Only unique, indexed enemies on the
actual selected page can be marked; duplicate indices, including duplicates on
other pages, grant no target. Changed indices, killed/removed/deleting enemies,
pending cleanup, a retired/replaced encounter and stale pages require a fresh
inspection. The server retains the selected object and never finds a replacement
by its index. Any newer `!listEventEnemies` or `!nearEventEnemies` attempt, even a
failed one, invalidates
marker permission; existing removal permission still follows the successful-page
rules above. A page captured while construction is in progress cannot authorize
a later mark: list again once construction finishes. Stable interrupted encounters
and paused automatic spawning still allow eligible remaining enemies to be marked.

Repeated marking and clearing do not consume or refresh enemy-removal permission.
An accepted cleanup consumes that page as before. A successful enemy mark replaces
the same single HUD slot used by stored-base marks. Invalid or stale requests keep
the previously displayed snapshot. Either `!clearEventEnemyMarker` or
`!clearSpawnMarker` privately clears that shared slot, including when already
clear; clearing requires an admin but does not require them to be alive.

The label identifies an encounter enemy's position snapshot and warns that the
enemy may move. After acceptance, movement, death, removal or encounter retirement
leave only the historical point until expiry or clear; the point does not prove
that the enemy or encounter is still active. It uses the same projection, viewport,
clock, local-player and reload rules as stored-base markers above. The cross may
show through walls, and fixed status text may remain when projection is unavailable
or the point is outside view. Marking does not navigate, teleport, delete, damage,
track or change the encounter, queued event, saved configuration or interaction.

Update both server and client addon files and reconnect. New clients accept the
unchanged legacy stored-base and clear packets. A client with only stored-base
marker support rejects the new `event_enemy` subtype and keeps its prior valid
marker; there is no misleading fallback to a stored-base label. The new clear
alias still uses the legacy one-bit clear packet. An old server can expose an
unknown command as public chat, so mixed versions cannot guarantee private command
handling or display.

### Remove one inspected encounter enemy

After `!listEventEnemies` or `!nearEventEnemies`, an admin can use
`!removeEventEnemy <index>` with the
exact index shown on their latest page. This requests removal of that one captured
owned enemy, keeps the other enemies fighting and preserves the queued next event.
Each accepted request consumes that admin's page; list again before another cleanup.
Another admin must inspect independently. Off-page, unindexed, duplicate, changed,
already-removing and stale targets are refused. The command keeps direct object
ownership and never looks up a new entity by a potentially reused index.

Cleanup immediately marks the encounter **interrupted**, so finishing its survivors
cannot award the ordinary victory notice. Remaining counts change only when the
existing kill/removal hooks run; an engine removal request may be deferred. Once the
last enemy is accounted for, the normal spawn delay resumes unless automatic
spawning is paused, and the queued encounter
can appear on its ordinary eligible attempt. The acknowledgement is private and
reports a removal request, without the full-event deletion announcement used by
`!stopEvent`.

These commands do not move NPCs or repair navigation. Native Garry's Mod chat
delivery, coordinates, entity-index lifetime and deferred removal still need a
disposable-server smoke check; local Lua doubles do not establish those results.
Use two admins to inspect and request the same target, verify replay is refused,
check the interrupted progress HUD with survivors still fighting, then remove the
last enemy and verify the next ordinary spawn. Also check non-admin rejection.

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

Every eligible row now includes a short `ref`, for example `ref r0000000000000012-3`.
Copy that whole token into `!nextEventRef r0000000000000012-3` to queue its exact configured
name, including leading/trailing spaces, Unicode, or escaped diagnostic names.
This command accepts one reference only. It never treats an argument as a name,
entry number or stored key. `!nextEvent <name>` keeps its exact-name behavior,
including names that look like numbers or commands.

References belong to the requesting admin's latest successful page and expire
60 seconds after that page was prepared on the server. A new successful page
replaces every earlier reference, even for the same entry. A failed page request
keeps the previous successful page. Selecting once consumes that page; list
again for another choice. Another admin must list independently. Disconnection
or session initialization clears references. Changed maps, invalid server time,
removed/renamed/replaced definitions, replaced information tables, and newly
duplicated names are refused without changing an existing pending choice.

Long names continue across numbered parts, which can span pages. Parts of one
entry on a page use the same reference; even a continuation-only page can select
that entry. Listing the next page gives it a new reference. Entry and part numbers
remain display labels. To use the older name command, join the contents inside
the outer quotes without adding spaces. Names containing control characters use
an explicitly **escaped diagnostic** representation, which is not raw name input;
the short reference avoids typing or reconstructing that raw name.

Each reply contains at most eight body lines plus a header and footer, with each
line kept below the [ChatPrint byte limit](https://wiki.facepunch.com/gmod/Player:ChatPrint).
Invalid or out-of-range pages give usage feedback. Every listing reads the current
configuration. References bind the exact pool, stored key, record, name and
information-table identity, but do not freeze fields inside that table. After a
reference is accepted, the existing pending-name selection rules remain live.
Reading and selecting references do not sample randomness, advance timers,
spawn/start/remove entities, change ready or active encounters, or save data.
A queued selection waits for the next fresh timed batch or an admitted
`!spawnActivatorsNow` request. Both remain blocked while automatic spawning is
paused. Runtime Lua hot-reload remains unsupported.

Local tests exercise actual PlayerSay handlers, raw identity/eligibility checks,
expiry, pagination, UTF-8 boundaries, reentrant callbacks and preserved lifecycle
state with Garry's Mod API doubles. Native ChatPrint delivery/rendering and
interaction with a deployed chat addon still need a disposable-server check:
have two admins list independently, select a long or escaped name by its ref,
try a stale/refreshed/expired ref, and confirm a queued choice waits for the next
ordinary fresh batch while ready actors and active encounters stay unchanged.

### Search configured encounter names

Use `!findEvents 1 raid` to search original configured names for `raid`, then
`!findEvents 2 raid` for the next page. This admin-only command folds ASCII
letters A-Z only. It treats punctuation, quotes, backslashes and Lua pattern
characters literally; it does not search information fields, apply Unicode
case folding, or search the escaped display representation. Ordinary non-ASCII
query bytes are preserved. A name containing a control byte can still be found
by another substring and selected or inspected by its exact reference.

Both arguments are required. Use exactly one ASCII space after `!findEvents`
and after the page. The page is a positive decimal integer of one to six digits;
leading zeros are allowed (`000001` means page 1), but an all-zero page is not.
The text is 1-128 bytes, with no leading/trailing ASCII space, ASCII control
bytes, UTF-8 C1 controls, or U+2028/U+2029 line separators. Internal spaces are
literal. The complete command is limited to 147 bytes. Invalid input gives
private usage help; it is not trimmed, repaired, or interpreted as another
command. The original `!listEvents [page]` grammar and replies are unchanged.

Each search reports the matching-name count and page range. Counts include
unavailable matching groups: exact duplicate names remain duplicates across the
whole pool, and missing/non-table information stays visible. Search never makes
an unavailable group eligible. Entries retain the complete catalog's sorted
display IDs, so gaps are expected. Long names use the same complete numbered
continuations and eight-body-line, 240-byte-per-line budget as the full catalog.
Pages count body lines, including continuations and diagnostic summaries.

Records without string names cannot match. Their counts remain in an explicitly
**unfiltered pool diagnostics** summary, outside the matching-name count and
without references. Zero matches is a successful one-page result with an
explicit no-match line; a malformed/missing pool is also described. Search does
not infer that a zero-match result means the configuration is valid.

Only eligible entries on the displayed page receive references. List and search
share the same latest-page ownership, one-selection-per-page rule, 60-second
lifetime, and live map/time/configuration identity checks. A successful search,
including zero matches, replaces older list/search references; a failed request
keeps the previous successful page. `!inspectEventRef <ref>` can inspect a search
result without consuming or renewing it, and `!nextEventRef <ref>` queues its
exact original name. Searching alone does not select, spawn, remove, save, draw
randomness, or change timers, interactions, ready actors or active encounters.

Local real-handler tests cover literal matching, strict input limits, complete
pool eligibility, private pagination, escaped/Unicode continuation names,
list/search replacement, reentrant callbacks and preserved lifecycle state.
They use Lua 5.3 with GMod doubles. Native Garry's Mod remains unverified: on a
disposable server, have two admins search independently, inspect and select a
long or escaped name by reference, switch between list/search pages, and try
expired references while checking private chat delivery and unchanged actors.

### Browse eligible encounter names

Use `!eligibleEvents` for page 1, then `!eligibleEvents 2` for the next page.
This requester-private admin catalogue includes only nonempty string names
that are unique across the complete configured pool and have table-valued
information, matching the existing `!nextEvent` name-selection checks. All
records are grouped before filtering, so excluded records cannot conceal a
duplicate name. Excluded entries and malformed-record diagnostics remain
inspectable with `!listEvents`; `!findEvents` keeps its literal-name search.
Eligibility does not validate models, NPC classes, health, counts or other
encounter settings. The engine remains unchecked.

The optional page follows `!listEvents` grammar: a positive decimal integer,
with surrounding whitespace and leading zeros allowed. Omit it for page 1.
There is no name-query argument. Output preserves complete-catalogue sorted
entry IDs (gaps are expected), exact configured names, long-name continuations,
eight body lines per page and the 240-byte line budget. Zero eligible names
produce a successful page; missing or malformed pools are described without
claiming that the configuration is valid.

List, search, eligible and eligible-search pages share one latest-page reference set. Any
successful page, including zero eligible names, replaces previous references.
Invalid pages or unavailable configuration/map/time checks preserve the last
successful page. Only entries on the displayed page can be inspected or queued
by reference, within the original 60 seconds and one selection per page, with
the existing requester, map, time and live configuration identity checks.
`!inspectEventRef` does not consume or renew a reference. Browsing changes no
pending choice, encounter, actor, interaction, timer or saved configuration and
does not sample health or randomness. Native Garry's Mod remains unverified.

### Search eligible encounter names

Use `!findEligibleEvents 1 raid` to search only eligible configured names for
`raid`, then `!findEligibleEvents 2 raid` to continue with the same text. This
private admin command also works when dead. It combines the literal-name rules
of `!findEvents` with the existing selection checks of `!eligibleEvents`.
Grouping and duplicate detection still inspect the complete pool before either
filter is applied. Models, enemy classes and other encounter settings remain
engine unchecked.

Both arguments are required: a positive page of 1-6 decimal digits and text of
1-128 bytes, separated by single ASCII spaces. Leading page zeros are allowed;
query edge spaces, ASCII controls, UTF-8 C1 controls and U+2028/U+2029 separators
are rejected. Matching folds ASCII A-Z only, uses the original name bytes and
treats punctuation literally. The total command limit is 155 bytes; the existing
`!findEvents` limit remains 147 bytes.

Counts include only matching eligible names. A successful empty page says
"No eligible configured names match this literal search." Missing or malformed
pools retain their explanations. Use `!findEvents <page> <text>` or `!listEvents`
to inspect excluded records and diagnostics. Results preserve global sorted IDs,
exact names, continuation pages, eight body lines per page and 240-byte lines.
Retry, range and page guidance keeps the combined command and asks for the same
text again.

All four catalogue commands share the latest successful page. Even an empty
successful search replaces older references; invalid input, out-of-range pages
and unavailable configuration/map/time checks preserve the last successful page.
References remain requester-owned, shown-page-only, valid for the original 60
seconds and usable for one selection per page. Inspection never renews them.
Combined searching preserves pending choices, actors, encounters, timers,
interactions and saved configuration. Local tests use GMod doubles; native
Garry's Mod behavior and deployed private chat delivery remain unverified.

### Inspect one configured encounter

Copy an eligible reference from your latest `!listEvents`, `!findEvents`,
`!eligibleEvents` or `!findEligibleEvents` page into
`!inspectEventRef r0000000000000012-3`. This exact admin command accepts one
reference, with optional surrounding whitespace. It replies privately with five
short rows: a **configuration snapshot** of the event name, `activatorModel`,
`npcPath` (the enemy class), `maxNPCs` (the requested count), and a scope reminder.
It reads the current configured base values, including ordinarily inherited
properties, before emitting any details. A throwing configuration getter is
reported as unavailable without exposing its error text.

Missing fields, empty model/class strings and invalid field types are identified
without serializing tables or calling their string-conversion callbacks.
`maxNPCs` must be a finite number at least 1 to pass the existing Start count
check. Finite fractions keep their existing floor behavior: 2.75 means two
creation attempts. Numeric labels retain enough precision to distinguish a
fraction just below an integer from that integer. This is a configured request, not a promise of that many
spawned enemies or an additional count cap. Models/classes remain **engine
unchecked**: the command does not check assets, physics or native NPC validity,
and never calls the potentially random health helper or expands dialogue.

Each line is at most 255 bytes. Valid UTF-8 characters stay intact when a long
label is shortened, and `[truncated]` says that the displayed value is incomplete.
Control-bearing labels use an explicitly escaped diagnostic representation;
these labels are not raw model paths, class names or event-name input. The raw
configuration is unchanged. Native arbitrary malformed byte-string rendering
still needs an engine check, as does private delivery through deployed chat addons.

Inspection shares the reference's existing owner, latest-page, 60-second,
map/time, exact pool/key/record/name/information identity and current eligibility
checks. It neither consumes the page nor renews it: `!listEvents` →
`!inspectEventRef <ref>` → `!nextEventRef <ref>` works within the original lifetime.
A subsequent successful listing or selection, disconnect, changed definition or
expiry can make the reference unavailable. Every details row rechecks authority;
callbacks that replace the page, revoke permission or successfully select/clear
a pending choice stop the older reply stream, including a select-then-clear
callback from another admin. Values already copied for a valid reply stream stay
a snapshot even if fields within the same information table later change.

The command does not alter pending, ready or active encounters, timers, RNG,
spawns, network messages or saved data. Local mounted `PlayerSay` tests cover
this workflow, inherited/malformed fields, finite fractional counts, bounded
Unicode/control diagnostics and reentrant invalidation. They use the actual
addon under API doubles, not a native Garry's Mod server. On a disposable server,
list and inspect with two admins, select the inspected reference, and try an
expired or replaced reference while confirming the existing encounter is intact.

### Saved spawn data and recovery

Use the exact admin command `!spawnSaveStatus` for three private, fixed-text
lines: the session initialization/load decision (`pending`, `no file`,
`read failure`, `invalid file`, or `loaded`), the current session save permission
(`enabled` or `disabled`), and the last normally completed save-attempt result.
That last result is explicitly historical: `none completed`, `disabled`,
`invalid current positions`, `serialization failure`, `serialized validation failure`,
`backup verification failure`, `canonical verification failure`, or `verified success`.
Verified success includes byte-identical canonical read-back without a rewrite.
An interrupted attempt records no result; the last completed attempt stays visible.
Initialization resets both history labels before trying to load.

The inquiry also works while dead. Extra arguments receive private usage help;
non-admins receive a private denial. It only copies cached labels, before the
first reply, so a reply callback that triggers a save or initialization cannot
mix old and new labels within that inquiry. Native admission and reply exceptions
are contained; this is not a guarantee against arbitrary modified API callbacks.
It performs no filesystem, codec, configuration-validation, entity-enumeration,
timer work or custom net operations. Its private ChatPrint replies still use
native networking. Inspection authority and encounter state stay unchanged.
A historical success says nothing about current disk health, later external
changes or durability; the inquiry neither verifies nor repairs storage.

Use the exact admin command `!saveSpawns` after correcting a transient save
failure. It retries the complete accepted configuration, including empty lists,
without another edit or shutdown. Extra arguments give private usage help.
The command leaves points, inspection permissions, ready dialogues, active
encounters, pending choices and timers unchanged. Its private success reply
means this attempt verified the saved bytes; failure may follow an actual write,
so check the server console. It does not force saving, restore a backup or bypass
the failed-load lockout below.

- The canonical filename is `garrysmod/data/devonsspawninfo.json`. Garry's Mod
  [lowercases `file.Write` paths](https://wiki.facepunch.com/gmod/file.Write),
  while [reads can be case-sensitive](https://wiki.facepunch.com/gmod/file.Read).
  If that file is absent, the historical `DevonsSpawnInfo.json` spelling is
  also checked. A present canonical file always takes precedence, even if it
  cannot be read or validated. A successfully loaded mixed-case file is left
  in place; the next successful admin edit, `!saveSpawns` or clean shutdown
  writes the canonical lowercase name.
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
  its admin; `!saveSpawns`, the next successful edit or clean shutdown can retry saving. Empty
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
  snapshot, its captured activator is removed or remains invalid, or its captured
  player is observed dead or invalid. This also
  covers another player's Start and a start that removes the actors but creates
  no enemies. Automatic retirement sends no Start or Cancel request, and old
  callbacks cannot submit through a replacement dialogue. An inactive progress
  snapshot alone leaves a valid fresh menu usable.
  Opening and button/close callbacks also check the captured player's liveness.
  A death and respawn entirely between client observations cannot be detected
  by these checks; server interaction grants remain authoritative.
  Client full-update removal notices are ignored immediately because an entity
  can be recreated during that refresh; later liveness checks still retire an
  actor that remains invalid ([Facepunch removal-hook documentation](https://wiki.facepunch.com/gmod/GM:EntityRemoved)).
- Only NPCs actually spawned for the active event affect its count. World/NPC
  kills are supported. A victory notice is sent once, only if all tracked
  enemies were killed. Cleanup/removal and admin cancellation restart spawning unless paused
  without announcing a victory. The completion popup closes after five seconds;
  a newer completion replaces it and restarts that one-shot dismissal.
- Missing/empty spawn lists safely pause spawning. Missing enemy spawns leave
  existing activators available and privately tell the requesting player to ask
  an admin to fix the missing enemy position, then use the activator again.
- Invalid enemy counts and non-string enemy classes also leave activators
  available and privately tell the requester to ask an admin to correct the
  configuration and restart the server.

These four failed starts consume the interaction without starting an encounter
or changing the ready actors, selected batch, future choice, timer or progress.
An admin repair does not start it automatically; a fresh Use and Start are
required. Unissued, invalid, mismatched, cancelled and replayed requests stay
silent, including mismatched or invalid requests after expiry. Guidance uses
short constant `ChatPrint` text without raw configuration; it adds
no addon network message or client behavior.

If activation admits no enemies, the server keeps its existing cleanup: retire
ready actors and the selected batch, preserve the queued future choice, publish
inactive progress, and restart the ordinary delay unless paused. After the
console diagnostic, the still-valid requesting player now receives one private
message: "No enemies could be spawned for your encounter. Ask an admin to check
the server console." This includes candidates that remove themselves before
admission. Replays remain silent; partial success and enemies killed during
setup do not produce this failure notice. Cancellation or replacement during
construction also remains silent. A later ordinary spawn and fresh Use/Start
are needed to try again; no automatic retry is added.

Local doubles check the notice, cleanup ordering and callback replacement.
Native NPC creation, self-removal timing and private chat delivery still need a
disposable Garry's Mod server check, with automatic spawning enabled and paused.

Runtime spawning requires one unambiguous record for the requested map and a
complete target list of finite Vectors at positive integer keys. Malformed or
missing map data, duplicate current-map records, and missing, empty or malformed
target lists are unavailable: the initial attempt consumes no spawn randomness
and creates no entities. Activator and enemy lists remain independent; sparse
valid lists keep their existing sampling order. Validation does not repair or
save configuration. If a callback invalidates activator positions after a
successful creation, the partial batch remains and later creations stop; a
normal attempt can refill it after repair.

If a server callback cancels an encounter during initial spawning, the abandoned
loop stops creating enemies and requests removal of any enemy it just created.
It cannot change the progress of a replacement encounter. Tracked kills and
removals during setup still update that encounter's counts; their progress
notifications and completion handling wait until construction settles. Explicit
cancellation still retires the event immediately. The initial count includes
enemies added and then killed or removed during setup; removal still prevents
victory.
Candidates that request removal before admission, including during Spawn or
health setup, are excluded from both counts even when removal is deferred.
They receive no replacement attempt; if none are usable, the start fails normally.

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

The standalone source-adapter regressions run separately with
`texlua tests/translator.lua` (or `lua tests/translator.lua`). They check exact
lexical output and malformed-comment errors, immediate file edits, and isolated
include environments. The adapter scans the original source by index without
caching source or compiled chunks. It preserves the existing limitations:
`continue`, `&&`, and `||` are not translated, and long-bracket strings are not
protected from operator/comment translation.

The suite runs the actual addon Lua in isolated environments with Garry's Mod
API doubles. It covers authorization, stale/repeated requests, client/server
message ordering, custom named event lifecycles, event completion and cleanup,
missing spawn configuration,
admin spawn editing, and completion-popup replacement/one-shot cleanup. Persistence tests also cover invalid decoded structures,
sparse native Vectors, intentionally empty lists, file-name precedence,
read/serialization/write failures, immediate persistence of spawn-edit
commands, session-only warnings, explicit save-only and shutdown retries, and
preservation after a rejected load. Save-only cases retain both admins' existing
inspection leases, actual ready Start/Cancel authority, active progress and
pending selection across verified and failed attempts.
Encounter-progress tests also cover actual spawned counts, every end path,
unrelated/repeated NPC callbacks, late-join snapshots, request throttling and the
client panel's update/clear/resize and input settings. Synthetic cross-realm
delivery checks the protocol fields without claiming real engine networking.
Automatic-schedule tests cover exact admin pause/resume commands, idempotence,
due-callback gates, all restart paths, selected/pending ownership, current
Start/Cancel grants, paused refresh with deferred removal, ordinary encounter
retirement, and reentrant Spawn callbacks that pause or pause then resume.
Encounter-definition tests exercise malformed pool, record and information types
through actual timer and manual Spawn callbacks, including recovery, unchanged
configuration, and absence of extra entity, encounter, network or persistence
side effects. They preserve the ordinary manual-removal timer restart and paused
behavior, sparse random sampling, one-draw rejection, valid explicit choices beside
bad records and first-match duplicate lookup. Table-shaped information remains
accepted without claiming its fields are engine-valid.
Capacity-admission tests bound the unguarded infinity reproduction with a
fourth-attempt sentinel and check malformed rejection, fallback/finite controls,
pending recovery, surviving ready actors and Use grants, and direct due callbacks
with stopped, paused and active-encounter schedules. These are real addon
callbacks under API doubles, not native engine scheduling or creation evidence.
Count-admission tests exercise NaN through actual selected-batch timer, Use and
Start callbacks with capped, running and paused timers. They check retained ready
state, consumed replay, fresh-Use retry after a controlled table repair, normal
completion and the separately queued next encounter. Existing invalid-count and
finite fractional controls preserve the prior rejection and floor behavior.
The controlled repair is a test fixture, not support for live Lua hot-reload.
Class-admission tests exercise missing, boolean, number, hostile-table, function
and thread fields through the actual selected-batch timer, Use and Start handlers.
They check private constant correction, retained readiness and other players'
Start/Cancel grants, running/capacity-stopped/paused schedules, queued selection,
no creation/removal/health/persistence work, consumed replay and fresh-Use repair.
Controls preserve expiry/position/count precedence, inherited strings, fractional
counts, per-attempt class changes and the extra inherited getter read. Empty and
unknown strings explicitly model an invalid Create result; the general double
remains permissive and supplies no evidence of native non-string failure.
Health-admission tests exercise the real Start receiver with nil/table samples
at the first and second eligible NPC, immediate/deferred cleanup, enabled/paused
schedules, consumed batches, and private correction. Controlled callbacks cover
getter cancellation/replacement, replacement during both cleanup stages and
feedback, old-hook replay, earlier tracked kill/removal, getter self-removal,
invalid requesters and pause/resume during cleanup. Numeric-string/boolean and
hostile-table cases cannot serialize values. Numeric pass-through controls include
NaN/infinities; failed Create and Spawn self-removal retain eligible sampling order.
The deliberately strict mock setter raises a labeled test error on a non-number;
that is controlled mock behavior, not observed native SetHealth behavior.
Health-lookup recovery adds 36 controlled callback cases for first/second throws,
immediate/deferred removal, enabled/paused schedules, getter cancellation and
replacement, cleanup replacement and schedule changes, original error payloads,
and secondary status/removal callback errors. They assert consumed replay,
independent cleanup attempts, no stale result, queued-choice preservation and
fresh Use/Start recovery. These are Lua/API-double checks, not native GMod results.
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
Runtime-spawn tests load accepted duplicate-map data, exercise malformed input
through real lookup, timer and menu/Start handlers, and check rejection before
RNG and creation. They cover fresh-use recovery, unchanged storage and selection,
valid sparse sampling order, and callback invalidation of a partial batch.
Start-feedback tests transfer the actual menu callback's request to the server
receiver. They check private expiry/missing-position/invalid-count guidance, the exact 60/61
second boundary, consumed replays, silent invalid requests, retained actors and
selection, and fresh-use recovery after the actual admin repair callback.
Count tests retain enabled/paused schedules, position sampling order and finite
fractional admissions, and check that earlier rejection reasons keep precedence. They
also cover private empty-start guidance with enabled/paused spawning, silent
replays, retained future choice, invalidated requesters, and replacement started
inside the notice callback. Construction controls distinguish zero admissions
from partial success, completed admissions and cancelled/replaced construction.
Dialogue-lifecycle checks transfer real server packets between separate client
entity copies, exercise actor-removal and client update callbacks, and preserve
valid menu replacement, ordinary Start/Cancel and completion/progress panels.
They also cover player death/invalidation, delayed opening packets, callbacks
before Think, and fresh same-actor Use after an observed death and respawn.
Deferred panel-removal checks also reject retained Start/Cancel callbacks while
a panel is marked for deletion but still valid, and preserve normal DFrame
Close/Cancel ordering. They verify request ownership without claiming native
Derma focus or network delivery timing.
Dialogue-layout checks cover 320x240 through wide and tall viewports, repeated
shrink/grow cycles, distinct action bounds, complete configured text, and native
wrap/scroll setup. They inspect panel geometry and API configuration, not rendered
font metrics, scrollbar reachability, pointer routing or model pixels. Native
DFrame and DLabel Think behavior remains responsible for their normal updates.
Spawn-distance tests cover known 3D and vertical distances, movement and private
per-admin snapshots, one protected position capture, copied scalar coordinates,
sorted pages, exact coordinate tokens, and preserved inspection grants. They
also exercise malformed/throwing positions, tiny and huge finite distances,
subtraction/norm overflow, and unchanged ready/active encounter behavior with
unavailable distances. Scaled distance arithmetic avoids intermediate square
overflow; only the approximate suffix uses compact formatting.
Only in-memory file/codec doubles and test fixtures are used; the tests never
read or write a server's DATA directory. They exercise the addon at the codec
boundary, not Garry's Mod's actual JSON parser or filesystem.
Backup checks tie encoded tokens to detached sparse-Vector snapshots and record
the order of file operations. They inject partial and complete writes with
failed returns, read errors and changed recovery copies, checking exact bytes
before retries and preserving normal admin/encounter behavior.

The suite exits nonzero on failure. The harness supports Lua
5.1 and newer; its small source adapter translates GLua operators/comments.
Earlier work was checked in Lua 5.3 via `texlua`, plus Lua 5.1 and LuaJIT 2.1
through Lupa 2.6. The player-liveness correction was checked with the installed
Lua 5.4 shared library via its C API; those earlier runtimes were not rerun.

These tests do **not** run the Garry's Mod engine. NPC behavior, entity networking,
native `ChatPrint` delivery/rendering, Derma layout, real timer timing, and saved
Vector JSON round-trips still need an in-game check. Suggested multiplayer smoke
test:

1. On `gm_construct`, wait for three activators. Use one and cancel, then use it
   again and start. Confirm five enemies appear and the activators disappear.
2. Have two players open activators; start from one. The other player's old
   dialogue should close automatically and must not create another event. Also
   remove an idle actor while its dialogue is open, and check that it closes.
   Die with a dialogue open and confirm the popup closes and releases the cursor.
   Respawn, use the same retained actor afresh, and confirm Start works while the
   old controls stay inert. Check another player's dialogue remains usable.
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

For a disposable-server definition-shape check, separately configure `NPCEdits`
as a string, as `{true}`, and as `{{name="Raid", information=true}}` before
startup. Check that automatic attempts produce no repeated Lua type errors, and
that an unusable manually spawned activator is removed. Then restart with valid
definitions and confirm normal activators and a player-started encounter. The
local doubles do not establish native Initialize error handling or entity removal
and replication timing; those behaviors still need this in-engine check.

## Remaining follow-ups

- Verify previous-save recovery and native DATA read-back on a disposable server
- Exercise live Lua hot-reload during an active encounter; local round state is
  intentionally not persisted across script reloads
- Verify native dialogue wrapping, scrolling, focus and model framing with the
  disposable-client checks above

### Temporary marker verification limits

The Lua harness transfers the real server packet through the real client receiver
and checks exact payload bit counts, typed field order, double-coordinate inputs,
private destinations, lifecycle, inspection authority and drawing API arguments.
The payload is one bool, three NUL-terminated strings and four doubles (including
expiry); clear is exactly one bool bit. Coordinates use `net.WriteDouble`, avoiding
`net.WriteVector` compression and its ±16384 range loss. These are API/state tests,
not native packet serialization or pixel checks.

An in-game smoke test is still required for projected alignment/FOV/third-person
views, native Vector and double network round-trips, font readability/clipping,
through-wall expectations, hidden HUD behavior, pause timing and two-client
privacy. No native rendering pass is claimed.

### Encounter-enemy snapshot verification

Focused tests transfer actual server output into the real client receiver in
isolated Lua realms. They check selected-object authority, mark-time coordinates,
private destinations, shared-slot replacement, historical lifetime and unchanged
encounter, queued-event, interaction, configuration and progress behavior. Finite
pre-feature fixtures compare exact existing command strings and legacy typed
packet payloads without reading checkout history at test time. These checks do
not encode native engine packets or establish real ChatPrint privacy, entity
handle lifetime/reuse, network delivery, Vector/projection behavior or HUD pixels.

On a disposable multiplayer server, use two admins and a moving remaining enemy.
List an exact page, move the enemy, mark its shown index and confirm that only the
requester receives the mark-time point. Move, kill or remove that enemy and confirm
the point stays fixed; reject a stale request after encounter replacement. Replace
the slot in both directions with a stored-base mark, exercise both clear commands,
wait for expiry and check a narrow viewport. Confirm ordinary victory, interrupted
cleanup, the queued next event, pause/resume and Start/Cancel still work. A native
Garry's Mod run is required before claiming those multiplayer or rendering results.
