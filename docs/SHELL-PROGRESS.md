# Shell progress

Last updated 11/26/2026 by a local builder (S1, working tree on `main`, not committed; the main session commits).

## Needed from Core

These live behind clearly marked seams in the shell. When the Core module lands, replace the block between `-- SEAM:` and `-- END SEAM`.

- `Core.BoatModel` (seam in `src/server/BoatService.luau`, `stepKinematics`): a pure step `(state {x, z, heading, speed}, throttle, steer, motorOn, dt, cfg) -> state`. Heading convention `atan2(look.x, look.z)`; steer +1 turns to starboard (heading decreases). The shell keeps `confine` (lake edge, dock, steeple, buoy) unless LakeMap offers the same.
- `Core.Validate` and `Core.RateLimit` (seam in `src/server/Net.luau`): payload checks for `BoatInput`, `Gaze`, `Intent`, `Lobby`, `Cosmetic`, and a token bucket `(bucket, rate, burst, now) -> allowed`.
- `Core.SoundMix` (seam in `src/client/AudioDirector.luau`, `mixFor`): `NightView -> { [layerKey]: 0..1 }` for the layer keys listed at the top of AudioDirector.

## Chunks

- [x] S1 The lake you can row (code written, gate green, NOT yet played in Studio)
- [ ] S2 Fishing and the night
- [ ] S3 The rules on screen
- [ ] S4 Front and back of a run
- [ ] S5 Saves and Endless
- [ ] S6 Docs

## S1: what exists

Server (`src/server`):
- `Main.server.luau`: builds the world, applies lighting, opens remotes, launches the boat, seats every joining player in the first free seat (helm, bow, port, starboard), steps the boat every Heartbeat, and applies `ToggleLantern` / `ToggleMotor` intents directly (S2 NightService replaces that). Prints only `[DeadCalm] server up`.
- `WorldBuilder.luau` plus `world/` (`Parts`, `Assemble`, `Water`, `Shore`, `Dock`, `Landmarks`, `BoatHull`): parts only, deterministic from `WorldBuilder.SEED = 20261126`. The world modules have no requires, so `tools/shell/world_count.luau` runs the same build in Lune.
- `LightingController.luau`: Look.Lighting, Atmosphere, ColorCorrection, Bloom, a Sky with no stars or moon.
- `BoatService.luau`: unanchored hull, server network owner, `AlignPosition` + `AlignOrientation` (OneAttachment) toward the kinematic pose, bob, four seats with an `OccupantUserId` attribute, lantern (`LanternOn` attribute) and motor (`MotorOn` attribute).
- `Net.luau`: creates the remotes, validates, rate limits, distance check for Bank and RefillOil, queues intents. Studio only: a second folder `DeadCalmDebugRemotes` with `DebugCamera` and `DebugBot`.
- `DebugDriver.luau`: scenarios `hello`, `state`, `tour`, `row_to_steeple`, `camera`.

Client (`src/client`):
- `Main.client.luau`: emote menu off, starts everything. Prints only `[DeadCalm] client up`.
- `BoatClient` (lazy lookups), `ViewState` (NightView, local stand-in until the server sends `View`), `Input`, `Camera`, `AudioDirector`, `WorldFx` (lantern flicker, beacon double blink), `ui/HUD`, `DebugBot` (Studio only).

Shared: `Look.luau` (filled), `Remotes.luau` (debug names, `Remotes.wait`), `SoundRegistry.luau` (98 sounds + 10 tapes, all id 0).

Tool: `tools/shell/world_count.luau` builds the world and boat in Lune and counts parts. Last run: Water 2, Shore 1050, Dock 102, Landmarks 199, world 1,353, boat 28, total 1,381 of 2,500.

## How to verify S1 in Studio (one-liners for the command bar or execute_luau, server side, during Play)

```lua
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hello")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("state")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("tour", { hold = 3 })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("row_to_steeple", { motor = true })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("row_to_steeple", { motor = false, timeout = 150 })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("row_to_steeple", { motor = true, via = "net" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("camera", { shot = "bow" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("camera", { shot = "dock" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("camera", { shot = "shore" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("camera", { shot = "steeple" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("camera", { shot = "top" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("camera", { shot = "reset" })
```

`row_to_steeple` with the motor takes about 25 s; rowing takes about 65 s. `via = "client"` (default) sends helm input from the player's client through `Input.sendHelm` and the `BoatInput` remote; it falls back to `"net"` (the same `Net.handlers.BoatInput` call, made on the server) if the DebugBot does not ack within 3 s. The result says which path ran.

## Studio must check (S1)

1. Output on Play shows exactly `[DeadCalm] server up` and `[DeadCalm] client up`, no warnings. `state.warnings` is empty.
2. Collision groups: `workspace:RegisterCollisionGroup` worked (no "collision groups failed" warning). If it warns, the PhysicsService fallback also failed.
3. The player is seated in `HelmSeat` within a second of spawning (`state.boat.seats`). If `Seat:Sit` does not take on a far-away fresh character, the warning "Seat:Sit never took" appears.
4. The boat floats level at the water line at the tie spot (z about -375), does not sink, spin or jitter with a seated player. `state.boat.networkOwner` is `server`. If it wobbles, raise `Responsiveness` or try `RigidityEnabled = true` on the two constraints in `BoatService.init`.
5. `row_to_steeple` arrives (`arrived = true`) with `via = "client"` and `helmAccepted` climbing; `refused` stays 0.
6. `tour` drift values are small (under 2 studs) at every stop: AlignPosition holds a teleported boat.
7. W A S D steer from the helm: W forward, D turns right. M toggles the motor (faster), F toggles the lantern (light off, glow dims).
8. First person is locked while seated, jumping does nothing, and the emote menu is gone.
9. Lighting: night, heavy fog, never pure black; the lantern pool is warm, about two boat lengths; the beacon by the dock blinks off twice every 6 s; the shack window glows. Check the bloom on the lantern from the bow seat.
10. Camera shots: each `camera` call returns `ack` with the shot name and the view changes; `reset` returns to first person.
11. Water reads as dark and slightly glossy; the mud strip shows the water line; the steeple leans out of the water with its spire up; the buoy, reeds and narrows snags are where `tour` stops.
12. Workspace `StreamingEnabled`: the client code tolerates streaming (lazy lookups), but check the shack radio and beacon still resolve when the boat is far out (the beacon blink and, once ids exist, the radio sound).
13. HUD: a small paper tag top left reads Night 1, 10:00 PM, Quota 0 / 10, Oil with a full bar, in the typewriter font (SpecialElite). If the font is missing it falls back to SourceSans.
14. Audio: with every id at 0 nothing errors. After setting one bed id, it starts within a second with no code change.

## Known issues and limits

- Not run in Studio yet (this builder had no Studio by instruction).
- `luau-lsp analyze` not run: it needs the Roblox type definitions file, which this builder did not download.
- Touch steering reads the default PlayerModule's move vector (pcall'd); touch buttons for the other verbs arrive with MobileButtons in S4.
- `inWater` for characters is not reported yet (S2 NightService observations).
- The lantern and motor flags live in BoatService until NightService owns them in S2.

## How to resume

Read this file and `docs/SHELL-DECISIONS.md`, run the gate, then `lune run tools/shell/world_count.luau`. Next chunk: S2.
