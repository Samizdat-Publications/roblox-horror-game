# Shell progress

Last updated 11/26/2026 by a local builder (S3 written on the working tree of `main`, not committed; the main session commits). S1 and S2 are verified in Studio.

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
- [x] S3 The rules on screen (code written 11/26/2026, selene and stylua clean on shell files, rojo build and smoke pass; NOT yet played in Studio)
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

## S3: what exists

Server (`src/server`):
- `EntityPresenter.luau`: what every player must see the same way. On `PlayerDied` the taken player's character is hidden (no body), their hat (a clone of a Hat accessory's handle, or a stand-in cloth cap) floats beside their seat for 7 s and sinks over 5 s, and their seat's rod is hidden while a copy clatters onto the floorboards (`rod-clatter`, id 0). On a Neighbor `EntityFail` with `effects.silhouette`, a black seated figure sits in the taken player's seat for 25 s. Every Knock intent plays `knock-answer` on the hull as a server Sound (Core sends no event for a knock). Each night start puts everything back: characters shown, rods back, props gone, anyone out of the boat seated again. It sets `Net.isDrowned` so a drowned helm player never steers.
- `NightService`: `onStart(fn)`, `onIntents(fn)`, `debugEmit(events)` (Studio fake-outs), and `StartOpts.rulesPatch` (Studio only: patch `Config.Rules.<Rule>` fields in a copy of Config for one night).
- `Net`: `Net.isDrowned` refuses BoatInput from the drowned.
- `DebugRules.luau`: the S3 scenarios, registered into DebugDriver (`DebugDriver.register`, `DebugDriver.helpers`). `botIntent` now carries `text`.
- `Main.server`: `EntityPresenter.init()`.

Client (`src/client`):
- `RulesFx.luau`: routes `EntityCue`, `EntityStage`, `EntityMoved`, `EntityPass`, `EntityFail` by `entity` to `fx/<Rule>`, `Fakeout` to `fx/Fakeouts`, and `BoatRocked`, `Flooding` and `Sunk` to BoatFx; resets every rule on `NightStarted`.
- `BoatFx.luau`: floorboard buzz (five local slats over the hull floor, jittered), the lantern shiver and the fake-out flicker (WorldFx multiplies the lantern brightness by `BoatFx.lanternFactor()`), camera shake (`BindToRenderStep` at Camera + 2), water in the boat from `view.flood`, `flood-in-loop` while leaking, and a thrown scoop of water plus `bail-scoop` every 1.1 s per bailing crewmate.
- `fx/Common.luau` (local parts, Vec2 to world, ground height by raycast against the Ground and Bank folders, silhouette figures from parts, fades, and the drowned's sight: `outline` adds a Highlight, `ghostOnly` parts are invisible to the living), `fx/Hum.luau`, `fx/WrongCatch.luau`, `fx/Neighbor.luau`, `fx/Knocking.luau`, `fx/Watcher.luau` (the figure, the stare tone and the vignette), `fx/Finale.luau` (STUB: plays `bell-dock-solo` on the cue), `fx/Fakeouts.luau` (all eight ids).
- `Drowned.luau`: a dim light for every dead crewmate near the boat (every client, from the view). For the local drowned player, after the card: an orbit camera over the boat, `ghost-loop`, outlines on, the cast button rings `GhostBell` (client cooldown `Config.Ghost.bellCooldown`; the server checks again), a tag says when the bell is ready. A `GhostBell` event rings `ghost-bell` at that ghost's light and makes it flare.
- `ui/DeathCard.luau` and `ui/DeathTexts.luau`: fade to black with `death-drag` (or `boat-sink` for the Knocking), then `death-sting` and a paper card with the line and "Rule N."; it goes after 7 s or on a click, tap or key; `DeathCard.hold` keeps it up. `DragWarning` plays `water-pull-warning` and a dark pulse.
- `ui/Callouts.luau`: the wheel of `Config.Callouts` (C, D-pad up, the Call touch button; gamepad selection starts on the first phrase). Wave also sends the Wave intent. A speech tag over the speaker's head with `callout-blip`, and a feed line at the bottom left. Fake callouts look exactly the same. A crewmate's death adds "<name> is gone." to the feed.
- `Input`: Q or L1 (touch Knock) knocks; C or D-pad up (touch Call) opens the wheel; hold E or A to bail while there is water in the boat; the cast button rings the bell while drowned; the drowned never send helm input.
- `ui/Prompt`: "Hold E  Bail" while flooding, "Q  Knock on the hull" during a Knocking window (never the count).
- `ui/NightCards`: the end card waits for the death card; tally lines say "twice", "three times".
- `DebugBot`: commands `knock`, `bail`, `callout`, `look` (turns the real camera toward a point every frame, so the server's gaze follows), `cardhold`; `intent` carries `text`.
- `AudioDirector`: `loop(name, part?, volume?)` and `baseVolume(name)`.

Shared: `SoundRegistry` gained `rod-clatter` (id 0). No ids changed.

## How to verify S3 in Studio (server side, during Play)

```lua
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hum_pass")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hum_fail")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("wrongcatch_pass")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("wrongcatch_fail")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("neighbor_pass")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("neighbor_fail")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("knocking_pass")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("knocking_fail")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("watcher_pass")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("watcher_fail")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("fakeouts")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("death_card")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("neighbor_pass", { form = "FalseBeacon" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("knocking_fail", { sink = true })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hum_pass", { async = true })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("status")
```

Each scenario starts a seeded quiet night with auto advance off, forces its rule and prints `SCENARIO DONE <name> <result>`: `pass` or `fail` (the rule's outcome), `died` for death_card, `played-8` for fakeouts, `timeout` or `error:...` when something is wrong. Expected: every `_pass` prints `pass`, every `_fail` prints `fail`. Longest: neighbor_pass and watcher_pass about 45 s, knocking_fail about 35 s (plus about 45 s with `sink = true`); the rest 10 to 30 s. Use `async = true` and `status` if an MCP call times out.

Seats and views: every scenario stays in the first-person helm view. The bot turns its head toward the Neighbor (neighbor_*) and the Watcher (watcher_*; about 0.8 rad off it for the edge of sight in watcher_pass). wrongcatch_fail switches to the `dock` camera shot while the cooler knocks, then resets. watcher_* move the boat to open water off the west shore (-470, -150). wrongcatch_fail shortens the knock delay to 8 to 10 s with `rulesPatch`; neighbor_pass with the false beacon shortens its burn to 20 s.

## Studio must check (S3)

1. Output on Play: still only the two `[DeadCalm] ... up` lines. No errors from EntityPresenter, RulesFx, fx/*, Drowned, DeathCard or Callouts. Every scenario prints its `SCENARIO DONE` line with the expected result.
2. hum_pass: the chorus and fireflies stop at once; after the beat of silence `hum-rise` then `hum-hold-loop`; the lantern flame shivers fast and the floorboard slats visibly buzz; the camera trembles slightly. On the pass the hum sinks, `hum-pass`, buzz and shiver settle, `frog-first-back`. Check the five floor slats sit on the hull floor at rest (not floating, not hidden under it).
3. hum_fail: `hum-fail`, a hard shake, then the death card "The motor was running while the frogs were quiet." with "Rule 1.", the hat floating beside the helm and sinking, the helm rod lying in the boat. After the card: orbit camera over the boat, the dim light near the boat, the outlined shape under the hull (only the drowned see it), the bell tag; Space or a click rings the bell and the light flares. The night failed card comes after the death card, not over it.
4. wrongcatch_pass and wrongcatch_fail: the wrong tell on the held fish; throwing it back gives no cooler events. Kept and banked: from the dock shot, three knocks with the cooler jumping on the dock each time, then the thump; the banked total drops by the eaten points. The jump moves the server's cooler part locally; if it looks wrong, lower the lift in `fx/WrongCatch`.
5. neighbor_pass: the oarlock creak far off (id 0 now, silent), then a dark rowboat with its own warm lantern appears in the fog where the bot looks, a tall seated figure in it with one arm up, waving slowly (one wave per 3.6 s). It drifts smoothly (no stepping every 0.5 s) and always faces the boat. One or two fake callouts appear over the bot's head and in the feed, exactly like real ones. With the lantern out it drifts off and fades. With `form = "FalseBeacon"`: a steady light on a pole, never blinking, out after 20 s. Check the waving arm turns from the shoulder; if it swings the wrong way, flip the sign of `math.rad(150)` in `Neighbor.step`.
6. neighbor_fail: the bot's "(waves)" tag, then `neighbor-fail`, the other boat is gone, the lantern goes out, the death card "You waved back." "Rule 3.", and a black seated silhouette in the helm seat, visible from the orbit camera for 25 s.
7. knocking_pass: three knocks shake the boat three times; the hint "Q  Knock on the hull" shows during the window; the two answers are heard on the hull (`knock-answer`, a server Sound); pass.
8. knocking_fail: the harder second round (bigger jolts), then water appears in the boat and rises; the hint switches to "Hold E  Bail"; while the bot bails, scoops of water fly over the side and the level falls. Check the water plane stays inside the hull and reads as water at night.
9. watcher_pass: a figure about 13 studs tall and very narrow stands in the trees on the west shore with two pale pin eyes, feet on the ground (not on a canopy, not floating). While the bot glances straight at it the screen edges darken and the tone rises (id 0 now); at the edge of sight both clear and it holds; after about 40 s it is simply gone (removed once off screen, or after 6 s).
10. watcher_fail: staring deepens the vignette fully; it lunges two steps at a time toward the water; at the waterline the lanterns die, then the death card "You let the thing on the shore reach the water." "Rule 5.".
11. fakeouts (the bot faces the bow): loon and branch from the shore, a dark fish arcing out of the water by the gunwale with two ripples, one jolt for the single knock, the buoy clank, the lantern nearly going out for 0.6 s, a warm light low on the shore that drifts apart into fireflies after 4 s. Most fake sounds are id 0 now (silent); the visuals must still show. ChorusDip shows nothing in this scenario (Night owns that timer).
12. death_card: the bot goes over the side; `water-pull-warning` and a dark pulse at 2 s, then the fade to black and "You got out of the boat. The water is not yours at night." "Rule 0." stays up. `night_start` clears it, shows the character again and seats the player.
13. Callouts by hand: C opens the wheel, a click says the phrase (your own tag is inside your head in first person; the feed shows "You: ..."), Escape or C closes it; with a gamepad, D-pad up opens it with the first phrase selected. On a phone (Device Simulator) the Knock and Call buttons appear beside Cast and Use.
14. Two players (Studio Test, 2 clients): the speech tag shows over the other player's head; the drowned player's light is visible to the living one; both hear the knocks; both see the hat and the rod.
15. Highlights: the outlines show through fog and water for the drowned only, and are gone at the next night.

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
- S3: `luau-lsp analyze` not run (no Roblox definitions file); the new client code is checked by selene, StyLua and rojo only. Most rule sounds are still id 0 and skipped; the visual tells carry the scenarios until ids land.
- S3: the ghost bell cooldown shown on screen comes from the client clock; the server (Core.Ghost) is the judge.
- Bobbers are animated on the server at the tick rate (10 Hz), so they may look a little stepped on clients.

## How to resume

Read this file and `docs/SHELL-DECISIONS.md`, run the gate, then `lune run tools/shell/world_count.luau`. Next: the Studio checks for S3, then S4 (with the Finale's presentation: `fx/Finale.luau` is a stub).
