# Activator Entities

A Garry's Mod addon that spawns activator NPCs. Players use an activator to start
an enemy encounter. After the tracked enemies are killed, the next activators
appear after the configured delay.

## Install and configure

Copy `roleplayAddon` into the server's `garrysmod/addons` directory. Configure
`roleplayAddon/lua/autorun/server/sv_config.lua`; the supplied settings, NPC
models, health, counts, dialogue, and map positions are unchanged.

Admin chat commands:

- `!setActivatorSpawn` / `!setEnemySpawn`: add your current position for this map
- `!removeActivatorSpawn` / `!removeEnemySpawn`: remove the last position
- `!stopEvent`: remove the current event's enemies and restart the spawn delay

Positions are saved to the DATA directory on clean server shutdown and loaded
on initialization. Back up the existing spawn data before testing changes.

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
  without announcing a victory.
- Missing/empty spawn lists safely pause spawning. Missing enemy spawns leave
  existing activators available so an admin can add positions and retry.

## Regression tests

From the repository root, run either:

```sh
lua tests/run.lua
# Or, when TeX Live's Lua interpreter is available:
texlua tests/run.lua
```

The suite runs the actual addon Lua in isolated environments with Garry's Mod
API doubles. It covers authorization, stale/repeated requests, client/server
message ordering, event completion and cleanup, missing spawn configuration,
and admin spawn editing. It exits nonzero on failure. The harness supports Lua
5.1 and newer; its small source adapter translates GLua operators/comments.

These tests do **not** run the Garry's Mod engine. NPC behavior, entity networking,
Derma layout, real timer timing, and saved Vector JSON round-trips still need an
in-game check. Suggested multiplayer smoke test:

1. On `gm_construct`, wait for three activators. Use one and cancel, then use it
   again and start. Confirm five enemies appear and the activators disappear.
2. Have two players open activators; start from one. The other player's stale
   menu must not create another event. Repeat after dying and respawning.
3. Kill enemies with player weapons and world damage. Confirm one completion
   notice and the next activator batch after the configured delay.
4. Remove an enemy with a cleanup tool, then kill the rest. Confirm spawning
   resumes without a victory notice. Repeat with the admin `!stopEvent` command.
5. On an unconfigured map, add both spawn types, remove their final positions,
   and re-add them. Confirm there are no Lua errors or duplicate map entries.
6. Restart the server cleanly and check that edited spawn positions reload.

## Remaining follow-ups

- Validate/migrate malformed or older saved spawn JSON instead of trusting it,
  and consider persisting edits immediately rather than only on shutdown
- Exercise live Lua hot-reload during an active encounter; local round state is
  intentionally not persisted across script reloads
- Check the existing full-screen dialogue layout at different resolutions and
  the completion popup's repeating cleanup timer in the real client
