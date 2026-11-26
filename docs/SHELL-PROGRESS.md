# Shell progress

Last updated 11/26/2026 by a local builder (S2 written on the working tree of `main`, not committed; the main session commits). S1 is verified in Studio.

## Needed from Core

These live behind clearly marked seams in the shell. When the Core module lands, replace the block between `-- SEAM:` and `-- END SEAM`.

- `Core.BoatModel` (seam in `src/server/BoatService.luau`, `stepKinematics`): a pure step `(state {x, z, heading, speed}, throttle, steer, motorOn, dt, cfg) -> state`. Heading convention `atan2(look.x, look.z)`; steer +1 turns to starboard (heading decreases). The shell keeps `confine` (lake edge, dock, steeple, buoy) unless LakeMap offers the same.
- `Core.Validate` and `Core.RateLimit` (seam in `src/server/Net.luau`): payload checks for `BoatInput`, `Gaze`, `Intent`, `Lobby`, `Cosmetic`, and a token bucket `(bucket, rate, burst, now) -> allowed`.
- `Core.SoundMix` (seam in `src/client/AudioDirector.luau`, `mixFor`): `NightView -> { [layerKey]: 0..1 }` for the layer keys listed at the top of AudioDirector.
  Core.SoundMix still has ChorusThin and ChorusSparse layers, which no longer exist (the chorus is the full loop plus single calls); the shell keeps its own `mixFor` until SoundMix follows.
- `Core.Run` (seam in `src/server/NightService.luau`, `buildParams`): `Run.nightParams(run)`. Until it lands, NightService builds Story, Normal, by-the-book params from `Config.Nights` (same law as `tools/sim/params.luau`), with no amendments.

## Chunks

- [x] S1 The lake you can row (code written, gate green, NOT yet played in Studio)
- [x] S2 Fishing and the night (code written, gate green, NOT yet played in Studio)
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

## S2: what exists

Server (`src/server`):
- `NightService.luau`: builds NightParams, owns `Core.Night`, steps it at `Config.Night.tick` from Main's Heartbeat (at most 5 steps a frame), observes the boat (BoatService kinematics and helm input) and each crew player (seat, helm, gaze from Net, `inWater` = not seated, root below the dock deck height, outside the boat's footprint, on the lake and outside the dock light), drains Net intents, applies the view to the world (lantern, motor, hold tokens), dispatches events (FishingService first, then per player lists on the `Events` remote with `only` respected), and sends the `View` at most 10 times a second when a coarse fingerprint changes. Every outgoing event is deep-copied through `sanitize`, which drops `wrong` and `tier` at any depth. Night 1 starts when the first player is seated (or 15 s after the first join). 15 s after a night ends the next starts (a failed night restarts, night 5 wraps to 1) unless `NightService.autoAdvance` is false. Late joiners get the current view and join the crew at the next night.
- `FishingService.luau`: a rod welded at every seat (cast direction per seat), the bobber (anchored, moved each tick: a gentle bob while waiting, quick dips on the bite, drawn toward the boat with progress and shaken by tension while reeling), the line (a Beam from the rod tip), the fish on the line (built by `world/FishModel` from the public traits, welded to the rod, named `DeadCalmFish_<UserId>` with a `Serial` attribute), fish tokens on the hold lid (one per fish in the hold), and the Field Guide drawings (`ReplicatedStorage.DeadCalmFieldGuide`, one book-true model per species).
- `world/FishModel.luau`: builds a fish from species and traits (no requires, Lune-loadable): ellipsoid body, bars as dark rings, eyes (a pair, a third on top, more pairs further back), eyeshine as Neon eyes, a pupil looking back and up for `wrongEyeDir`, eyelids for `blinks`, back fins (wedges), a belly fin for `flipFin`, whiskers, a forked, round, square or uneven tail, a green Neon shell and light for `glow`. Sizes and colors in `Look.Fish`.
- `BoatService`: `helmInput()` and `seatOf(player)` added. `Main.server`: the S1 stand-in loop is gone; Heartbeat steps the boat and NightService.
- `DebugDriver`: scenarios `night_start`, `quiet_night`, `fish_once`, `force_rule`, `status`; `state` now includes `night`.

Client (`src/client`):
- `Events.luau` (bus for the `Events` remote), `Chorus.luau` (one smooth chorus level: gradual between bands, instant drop to 0, `onRise`), `Fireflies.luau` (36 local Neon specks near the nearest shore and around the boat; many at bands 2 and 3, a few at band 1, frozen then faded at band 0).
- `AudioDirector`: thin and sparse chorus loops removed; the full loop at band 3 only plus single frog calls from the nearest shore (`Look.Mix.frogGaps`, random pitch and volume), `frog-first-back` once on each rise from silence; the radio is a playlist at the shack (tune 1, 4 s static, tune 2, static); the Voice group has an EqualizerSoundEffect and a DistortionSoundEffect (`Look.Mix.tape`); tapes queue with `ui-tape-click` and `ui-tape-stop` (both id 0 for now, skipped) and duck the ambience; `Tape` events play `tape-night-<n>`, `tape-amended`, `tape-endless`; a failed night plays `tape-night-failed`; fishing, bank and oil events play their sounds; `reel-click-loop` while a line's tension is rising.
- `Input`: cast and reel on left mouse, Space and R2 (hold to charge and let go to cast; hold to reel during the bite and the fight), interact on E and A (keep, else bank at the dock, else refill), throw back on X and B (else reel in). Space, R2, E and X are ContextActionService bindings at High priority; Cast and Use get touch buttons.
- `ui/Paper` (helpers), `ui/ReelBar` (band, tension mark, progress, a note for the bite, a snap or a lost fish), `ui/CatchInspect` (a local copy of the fish on your line held in front of the camera and lit by the world, turning slowly; the Field Guide as a half-screen card on the right with a sepia ViewportFrame drawing of the book fish, the facts and the note; Keep (E) and Throw back (X) buttons with the decide timer), `ui/Prompt` (one hint: bank, refill, cast, wait), `ui/NightCards` (Night N title, and the clear or fail card with a dry tally line per player).
- `DebugBot`: commands `hello`, `intent` and `autoreel` (Studio-only auto-reel: sets the hook on a bite and keeps the predicted tension in the middle of the band with ReelHold intents through `Input.sendIntent`, under its own 5 per second token bucket).

Offline check (a scratchpad Lune sim of Core.Night with the quiet params and the same reel law, 0.1 s view lag, 5 intents a second): 20 of 20 seeds cleared night 1 (quota 7 for one player), no fish lost.

## How to verify S2 in Studio (server side, during Play)

```lua
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("state")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("fish_once")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("fish_once", { wrong = true, decide = false })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("fish_once", { keep = false, hold = 3 })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("quiet_night", { seconds = 360, seed = 1 })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("quiet_night", { seconds = 360, seed = 1, async = true })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("status")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("force_rule", { rule = "Hum", teaching = true })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("night_start", { night = 1, autoAdvance = true })
```

`quiet_night` blocks for the whole night (about 6 minutes plus a few seconds); use `async = true` and poll `status` if the MCP call times out. It prints `SCENARIO DONE quiet_night cleared` (or `not-cleared`) when it ends and leaves the end card up (no auto advance; `night_start` resumes). `fish_once` starts a quiet night 1 if none is running and moves the boat out of the dock light; its result has `catch` (what the client was sent), `model` (the visible traits of the fish built on the line) and `via`. `force_rule` needs a running night; on a quiet night the rule still runs once (debugForce), but for the director's normal world start a normal night with `night_start` first.

## Studio must check (S2)

1. Output on Play: still only the two `[DeadCalm] ... up` lines, no warnings or errors from NightService, FishingService or the new client modules. `state.night.running` is true within a few seconds of being seated, and `state.night.view.night` is 1.
2. The HUD follows the server: the clock runs 10:00 PM to 5:00 AM over 6 minutes, quota reads `0 / 7` solo, oil drains while the lantern is lit; F and M still work (through Core.Night now).
3. `fish_once` returns `result = "Kept"` with `via = "client"`, a `catch` table with no `wrong` or `tier` key, and a `model` whose traits match `catch.traits`.
4. The rod at your seat, the bobber and the line (Beam): the bobber bobs, dips on the bite and comes toward the boat while reeling. If the Beam is invisible or the sag curls the wrong way, flip the sign of `CurveSize0` in `FishingService.makeBeam`.
5. The fish on the line hangs head up below the rod tip and moves with the boat without jitter or tipping the boat (its parts are Massless and welded to the rod).
6. CatchInspect: the held fish shows left of center in front of the camera, side on, slowly turning, lit by the lantern (with the lantern off it should be dim but not black). The Field Guide card on the right shows the name, a sepia drawing, the facts and the note. Keep and Throw back work by click and by E and X. The card closes on the decision and after the 12 s timer.
7. `fish_once` with `wrong = true, decide = false`: the wrong tell is visible at a glance on the held fish (third eye on top, extra back fin, wrong tail, green glow, blinking lids, an eye looking back, a fin on the belly). Check the WedgePart fins sweep back toward the tail; if they point forward, turn them 180 degrees about Y in `FishModel`.
8. Hold tokens appear on the hold lid as fish are kept and vanish on Bank. At the dock the hint reads "E  Bank the hold (n)" and E banks (cooler sounds, quota rises).
9. `quiet_night` (full 360 s) clears: `cleared = true`, `banked >= quota`, `kept` about 7, the clear card shows with a tally line, and no Night 2 title follows (auto advance held).
10. Reel bar: visible only during the bite and the fight; the band wanders, the mark tracks tension, the progress strip fills. Reel one fish by hand with the mouse.
11. Frogs: at band 3 the full loop plus frequent single calls from the nearest shore (they should sound like the shore, not the boat). `force_rule` Hum on a normal night: the loop, calls and crickets stop at once; when it passes, `frog-first-back` plays and the calls return gradually.
12. Fireflies: dozens of faint blinking specks around the boat and along the near shore at band 3; during the Hum they freeze, then fade; they return with the chorus. Check they are not too bright with bloom (`Look.Fireflies`).
13. Radio at the dock: tune 1, a few seconds of static, tune 2, static, repeating, fading with distance; no double playback after rowing far out and back (streaming).
14. Tape at night start: `tape-night-1` plays through the Voice group and sounds like a cassette (thin lows and highs, slight grit). If it sounds broken, lower `Look.Mix.tape.distortion` or move the effects onto the Sound.
15. Space does not unseat or jump; in the Device Simulator the Cast and Use touch buttons appear and work.
16. Night end: let a normal night run out short of quota: the fail card ("Five o'clock and the cooler is short.") shows, `tape-night-failed` plays, and 15 s later night 1 restarts with the boat back at the dock.

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
- S2 not run in Studio yet. `luau-lsp analyze` not run (no Roblox definitions file on this PC; downloading one needs approval).
- Late joiners are not in the crew until the next night; a player who leaves mid-night stays "alive" in Core.Night (Night fills missing players with seated defaults), so the night cannot fail by CrewLost while they are gone. S4 LobbyService should own crew changes.
- `bookOpen` is always false (no remote carries it yet; S4 decides how the rulebook and Field Guide report it).
- Event `data` tables with sparse numeric keys (for example keyed by UserId) would not survive a RemoteEvent; S3 rule events should use arrays or string keys.
- Bobbers are animated on the server at the tick rate (10 Hz), so they may look a little stepped on clients.

## How to resume

Read this file and `docs/SHELL-DECISIONS.md`, run the gate, then `lune run tools/shell/world_count.luau`. Next chunk: S3 (after the Studio checks for S2).
