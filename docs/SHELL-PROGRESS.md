# Shell progress

ALL CHUNKS DONE (S1 to S6 written; S5 and S6 on 11/26/2026). S1 and S2 are verified in Studio; S3, S4 and S5 are not yet played in Studio (see each "Studio must check" list).

Last updated 11/26/2026 by a local builder (Polish 3 on the working tree of `main`; not committed, the main session commits).

## Needed from Core

These live behind clearly marked seams in the shell. When the Core module lands, replace the block between `-- SEAM:` and `-- END SEAM`.

- `Core.BoatModel` (seam in `src/server/BoatService.luau`, `stepKinematics`): a pure step `(state {x, z, heading, speed}, throttle, steer, motorOn, dt, cfg) -> state`. Heading convention `atan2(look.x, look.z)`; steer +1 turns to starboard (heading decreases). The shell keeps `confine` (lake edge, dock, steeple, buoy) unless LakeMap offers the same.
- `Core.Validate` and `Core.RateLimit` (seam in `src/server/Net.luau`): payload checks for `BoatInput`, `Gaze`, `Intent`, `Lobby`, `Cosmetic`, and a token bucket `(bucket, rate, burst, now) -> allowed`.
- `Core.SoundMix` (seam in `src/client/AudioDirector.luau`, `mixFor`): `NightView -> { [layerKey]: 0..1 }` for the layer keys listed at the top of AudioDirector.
  Core.SoundMix still has ChorusThin and ChorusSparse layers, which no longer exist (the chorus is the full loop plus single calls); the shell keeps its own `mixFor` until SoundMix follows.
- S5: nothing blocking. Nice to have: `Profile.recordNight` gets the crew's totals for every player (as decided in CLOUD-DECISIONS); a per-player fish count in `NightResult.tallies` would let "Bank 100 fish" count each player's own fish.
- Polish 3: `Core.BoatModel`, when it replaces the seam, should carry the shore slide (drag scaled by how squarely the bow meets the edge, a stop when nearly head on) and the 35 percent turn damping below 3 studs per second, or the shell keeps both in `confine` and its turn scale.
- Polish 3, nice to have: a direction on `GhostBell` (Validate takes no value today), so a drowned player could point the ripple at a danger instead of it spreading from their light.
- `Core.Run`: DONE in S4. NightService owns the RunState and builds every night with `Run.nightParams`; nights outside the run (Studio scenarios) use a throwaway Normal first run at that night with the scenario's seed as the night seed.

## Needed from S4

- Both items are done in Polish 3: fx/Finale uses `AudioDirector.muteAmbience` and `AudioDirector.hush` and never writes a SoundGroup; Core emits MotorChanged on a Hum fail and the client view follows it at once.

## Polish 3 (11/26/2026)

Neon's five finale fixes, the night card, the title screen, the rulebook, Hydrogen rows 2, 3, 4 and 6, and two small fixes. Calls and numbers: `docs/SHELL-DECISIONS.md`, "Polish 3". Gate green (selene and stylua clean, 205 specs, pacing sim, lints, rojo build, smoke 10 of 10). NOT yet played in Studio.

Files: `src/client/fx/Finale.luau` (rebuilt), `src/client/AudioDirector.luau` (muteAmbience fade, `hush`), `src/client/ViewState.luau` (MotorChanged), `src/client/WorldFx.luau` (ambientOverride), `src/client/Drowned.luau` (bell ripple, edge marker, real beacon outline), `src/client/fx/Neighbor.luau` (false beacon not outlined), `src/client/ui/HUD.luau`, `ui/Prompt.luau`, `ui/NightCards.luau`, `ui/Title.luau`, `ui/Rulebook.luau`, `ui/Paper.luau` (book page unrotated, new tape), `ui/CatchInspect.luau` (thrash, slipped line); `src/server/NightService.luau` (`specialAboard` on the finale view), `BoatService.luau` (slide, turn damping), `DebugRun.luau` (finale `lead`), `DebugCrew.luau` (FishMutations); `src/shared/Look.luau` (Look.Dawn, Look.Finale, Mix.hushFade), `src/shared/SoundRegistry.luau` (six derived entries); `PLAYTEST_GUIDE.md`.

Record again (Studio, in Play, server context):

```lua
-- The finale: start recording, then run this (the bell comes about 22 s in; the whole thing about 50 to 70 s)
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("finale", { async = true })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("status")
-- To open the clip closer to the bell:
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("finale", { async = true, lead = 12 })
-- The title (then the Device Simulator at 705 by 338):
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("title")
-- The rulebook on night 5 (the first run's amendment); other seeds give other amendments:
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("rulebook")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("rulebook", { seed = 2 })
```

The `rulebook` result's `amendments` says which rule was amended. From the client, `require(game.Players.LocalPlayer.PlayerScripts.Client.ui.Rulebook).debugState()` gives `amended` and `additive` (1 when it is the Neighbor's "AND ROW AWAY FROM IT"), and `require(game.Players.LocalPlayer.PlayerScripts.Client.fx.Finale).debugState()` during the finale reports phase, boats, beacons, cone, shaft, wake, chase, speed, stillFor, vignette, ambienceMute, hush and dawn. (Adjust the script path if the client folder is named differently in Studio.)

## Studio must check (Polish 3)

1. finale, the turn: the night 5 strip is gone and the tape has ended before 4 AM. At the bell every sound stops dead (frogs, water, motor, lantern; `AudioDirector.debugState()` shows `mute` and `hush` near 0) for about 1.5 s; then three loud bell strokes with an echo tail, clearly over everything, a bell swinging on a post at the dock end, and "The bell. Go home." large in pale ink with a dark edge, readable on the dark sky, for about 4.5 s before it fades. Neon target: the_turn 6/10 or better.
2. finale, the run: a strong warm cone of light over the bow and the water ahead; pale flecks on the water slide past quickly while the motor runs (speed reads). The real beacon is a tall steady beam with a halo, both blinking off twice every 6 s, and it clearly grows as the boat closes in. Strange boats with swaying lanterns and a slow-waving figure, and lights on poles that flicker (never the double blink), appear off to the sides close enough to make out (pulled in to about half their real gap); each comes with a deep toll; the boats creak, the lights whine. If the flecks look like litter or the shaft like a laser, say so (Look.Finale and Finale.WAKE hold the numbers).
3. finale, the chase: under the motor a low pulsing drone and a dark slowed bed (no bright strings); the pulse quickens if the boat slows; the screen edges darken as the boat sits still toward the stop limit and clear when it moves.
4. HUD in the finale: the oil bar is its own thick row with no text over it, pulsing red faster as it drains; "Oil: locked on" above it; "Owner's fish: aboard" under the quota; no hint line at the bottom after the bell, and none while the motor runs on any night (bail and knock hints still show).
5. Dawn: on reaching the dock light the sky, fog and light warm into a sunrise over about 2.6 s (the dock and shore visible), the water comes back, dawn-cue then a few chirps (a stand-in), and a bold paper banner "Dawn. You made it home." near the top; the run-cleared card follows about 5 s later. Back on the title or at the next night the lighting is exactly night again (no warm cast left; the moonlight still lifts the ambient with the lantern out).
6. Night cards on nights 1 to 4: the start strip is small at the top, 4 s, never over the middle of the screen; on a phone (705 by 338) its text fits.
7. Title at 1280 by 720 and at 705 by 338 (Device Simulator): the name is large hand lettering over the lake, clear of Roblox's top-left buttons; the left paper is only as tall as its buttons, the right paper only as tall as its list; nothing overlaps or runs off screen, with and without the Endless button. Difficulty notes: Normal "Three retries if a night goes wrong.", Nightmare "One retry if a night goes wrong."
8. Rulebook (`rulebook`, a few seeds): the page is straight, the list scrolls inside the paper and never runs past its bottom edge; tape is translucent strips across the top corners of each rule, slightly crooked, never showing above the list while scrolling (if a strip pokes past the edge, say so). An additive amendment (the Neighbor's "AND ROW AWAY FROM IT") leaves Rule 3 unstruck with the red line under it; a replacing one (Hum, Knocking, Watcher) strikes the printed rule.
9. Boat: drive into the shore at a shallow angle: it slides along the edge, losing speed gradually; head on it stops. While stopped, turning on the spot is clearly slower than before.
10. Ghost bell (2 players, one drowned, for example `hum_fail` with a second client): when the drowned rings, the living see a pale ring spread over the water from the ghost's light and a pale "bell" marker at the screen edge toward it for about 3 s. The drowned see a faint outline on the real dock beacon only; false lights (`neighbor_pass` with form FalseBeacon, or the finale) have none.
11. Deciding timeout (`fish_once` with `decide = false`): over the last 3 s the held fish thrashes harder and harder and the timer bar turns red; then "Too slow. It slipped back." for a moment and the fish is gone.
12. hum_fail: the "Motor: on" line and the motor loop stop at the throw (motor-stop plays), for the living crew too.
13. Output: still only the usual `[DeadCalm]` lines; no AudioDirector warnings about effect classes or properties on the six new derived sounds.

## Scare polish 2 (11/26/2026)

Files: `src/client/AudioDirector.luau` (Ambience group trim at band 3, cue ducking, death-card mute, `with` companions, the under-keel anchor, the listening test placed like the real fx with `ambience = true`), `src/client/DebugBot.luau` (`play_sound` ambience flag, spot in the ack and the print), `src/client/BoatFx.luau` (capsize throw, foam, flash, gear, bubbles, rings, rock, motor rumble), `src/client/fx/Hum.luau` (loop and resonance start with the rise, rings), `src/client/fx/Knocking.luau`, `fx/Neighbor.luau`, `fx/WrongCatch.luau` (nine knocks bug), `fx/Fakeouts.luau`, `src/client/Drowned.luau` ("You" tag, boat rocking), `src/client/ui/DeathCard.luau` (70 percent card, 5 s, ambience muted), `src/client/ui/HUD.luau`, `src/client/ui/Prompt.luau`, `src/shared/Look.luau` (Mix), `src/shared/SoundRegistry.luau` (volumes, rolloff, recipes, `with`, `duck`, three new derived entries), `src/shared/Config.luau` (Rules.Hum.silence only). Values and calls: `docs/SHELL-DECISIONS.md`, "Scare polish 2".

Re-record the listening test (Studio, in Play, server context; one execute_luau call, about 75 s; the client prints `[DebugBot] play_sound <name>: playing (at <spot>, full chorus under it)`):

```lua
local r = game:GetService("ReplicatedStorage"):WaitForChild("DeadCalmDebugRemotes"):WaitForChild("DebugBot")
for _, c in { { "neighbor-oarlock-loop", 7 }, { "knock-three-soft", 5 }, { "knock-three-hard", 5 }, { "watcher-tone-loop", 6 }, { "watcher-step", 4 }, { "watcher-lunge", 4 }, { "cooler-knock-inside", 5 }, { "neighbor-fail", 4 }, { "lake-groan", 6 }, { "flood-in-loop", 5 }, { "lanterns-die", 4 }, { "wrong-glow-loop", 5 } } do r:FireAllClients({ cmd = "play_sound", name = c[1], seconds = c[2], ambience = true }) task.wait(c[2] + 2) end
r:FireAllClients({ cmd = "stop_sound" })
```

Start it from a clean scenario state so the boat sits on open water near a shore, for example `Invoke("reset", { scenario = "watcher_pass" })` first. Re-record the Hum fail (the bot leaves the motor running):

```lua
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("reset", { scenario = "hum_fail" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hum_fail", { reset = false })
```

Studio must check (Scare polish 2):

1. Listening test with `ambience = true`: the chorus stays at band 3 between cues; each cue ducks it (audible dip within a fraction of a second, back over about 1 s); every cue is clearly heard over it. Target from Neon: 6/10 or better on every cue.
2. The Neighbor's creak sounds far (reverb, dull top) but is not faint; knocks are close, dry and heavy, with a low thump under each; the Watcher's tone is a little lower than before.
3. `AudioDirector.debugState()` during the run: `groups.DeadCalmAmbience` about 0.45 at band 3 and about 0.18 while a cue plays; `duck` 0.4 during a cue; `motorIdle.playing = true` and `soundVolume` about 1.4 with the motor on.
4. hum_fail: about 1.5 s from the frogs stopping to the hum; the mid-range buzz is audible on laptop speakers; rings spread on the water and the view rattles. At the fail the boat throws hard and settles over about 1.2 s with white foam, a cold flash, fish, bucket, oar and tackle box over the side; bubbles rush up under the surface. The hint line is gone from the impact on. No frog during the black or the card.
5. Death card: about 70 percent of the screen width, large dark text, stays 5 s or until a tap. Check on a phone in the Device Simulator that the main line fits and is not tiny.
6. The drowned view opens on the boat still rocking for a few seconds, no "Motor: on" on the paper, and your own light is labelled "You".
7. Finale (night 5 at the bell): superseded by Polish 3 check 1 (the finale now mutes through AudioDirector).

## Chunks

- [x] S1 The lake you can row (code written, gate green, NOT yet played in Studio)
- [x] S2 Fishing and the night (code written, gate green, NOT yet played in Studio)
- [x] S3 The rules on screen (code written 11/26/2026, selene and stylua clean on shell files, rojo build and smoke pass; NOT yet played in Studio)
- [x] S4 Front and back of a run (code written 11/26/2026, selene and stylua clean on S4 files, rojo build and smoke pass; NOT yet played in Studio)
- [x] S5 Saves and Endless (code written 11/26/2026, selene and stylua clean on shell files, rojo build and smoke 10 of 10; NOT yet played in Studio)
- [x] S6 Docs (PLAYTEST_GUIDE.md, SOUNDS_NEEDED.md, README.md, 11/26/2026)

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

## S5: what exists (11/26/2026)

Server (`src/server`):
- `DataStores.luau` (new): store adapters with one shape (GetAsync, SetAsync, UpdateAsync, top). `open()` picks the real DataStore and OrderedDataStore when the place can reach them, else an in-memory store (unpublished place, or API access off). Real calls wait for request budget first (`GetRequestBudgetForRequestType`); errors go up to Core.SaveLogic, which retries with backoff.
- `DataService.luau` (new): loads each player's Core.Profile on join (SaveLogic.load: a failed load plays on defaults with canSave false), records each run night (`Profile.recordNight`, plus `Profile.recordRun` at RunCleared or RunOver) for every crew player, saves after each run night, on leave and in BindToClose (SaveLogic.save: UpdateAsync with merge, never over a newer SAVE_VERSION), submits the best Endless night to the ordered store (SaveLogic.submitBest), reads the top 10 for the title, equips cosmetics (Profile.equip on the server, refused unless unlocked) and sends the Profile remote. Prints once when saves are in memory.
- `Cosmetics.luau` (new): names, swatches, the lantern (PointLight and Neon ball colors), hull paint (outer planks), and the hat (an Accessory `DeadCalmHat` from two cylinders; avatar hats hidden under it).
- `MonetizationStubs.luau` (new): clearly marked, no ids, no prompts, nothing pay to win; functions return false or {}.
- `DebugSaves.luau` (new, Studio only): scenarios `save_roundtrip`, `unlock_all_debug`, `endless`.
- `LobbyService`: mode Story or Endless (Lobby "Mode", host only, Endless only with the host's cleared run), the boat dressed in the host's lantern and paint, LobbyState gains `mode`, `endlessOpen`, `board` (rank, display name, night) and `memorySaves`; the run totals carry `mode` and `bestNight`; "Hello" also resends the Profile.
- `NightService.newRun` takes `mode` (Endless starts at night 6; `night` can start later). `Net`: Cosmetic goes through `Core.Validate.Cosmetic`, then `Net.onCosmetic`. `EntityPresenter`: the floating hat is the earned hat, brim and all. `Main.server`: `DataService.init()` before the lobby. `DebugDriver` registers DebugSaves.

Client (`src/client`):
- `ProfileClient.luau` (new): the Profile copy, `equip(slot, id)` (locked items are not sent).
- `ui/Locker.luau` (new): a paper page from the title, three rows of item cards (swatch, name, "Wearing", "Tap to wear" or how to earn it), a note when saves are in memory or could not load. A BookState page ("locker").
- `ui/Title.luau`: Endless Nights button (host, when open), a right-hand paper with the Locker button, "New in your locker: ..." after an unlock, and "Longest Endless nights" (display names). Play sends Mode Story first.
- `ui/BookState.luau`: title pages are "lake" and "locker". `ui/HUD.luau`: "Endless night N". `ui/NightCards.luau`: Endless start, end and run-over lines. `LobbyClient`: mode, endlessOpen, board, memorySaves. `Main.client`: ProfileClient and Locker before Title.

## How to verify S5 in Studio (server side, during Play)

```lua
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("save_roundtrip")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("unlock_all_debug")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("unlock_all_debug", { lantern = "BlueHour", paint = "Oxblood", hat = "Souwester" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("endless")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("endless", { night = 9, seconds = 60, seed = 3 })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("title")
```

Expected: `SCENARIO DONE save_roundtrip same` (result has `written`, `read`, `saveStatus = "Saved"`, `loadStatus = "Current"`, `liveStore = "Memory"` in an unpublished place, and each player's session status `New` or `Current`); `SCENARIO DONE unlock_all_debug unlocked`; `SCENARIO DONE endless started` (night 6, mode Endless, two to four rules, a 90 s night).

## Studio must check (S5)

1. Output on Play in the unpublished place: `[DeadCalm] server up`, `[DeadCalm] saves are in memory this session: this place is not published, so it has no DataStores`, `[DeadCalm] client up`. No warnings or errors from DataService, DataStores, Cosmetics, ProfileClient, Locker or Title.
2. `save_roundtrip` prints `same`; `written.stats.nightsCleared` 1, `fishBanked` 7, `equipped.hat` "BucketHat", and `read` matches.
3. Title: a second paper on the right with "Locker (K)" and "Longest Endless nights" ("Nobody has lasted an Endless night yet." plus the test-place line). Check it does not cover the left menu at 1280 by 720 and on the smallest phone in landscape; if the left menu overflows with the Endless button showing, say so (the sheet may need to scroll).
4. Locker (K, R1, or the button): three rows; Amber, Bare Wood and No hat unlocked and worn (dark red border, "Wearing"); the others faded with how to earn them. Clicking a locked card does nothing. Escape, B, the dim and Close shut it. Gamepad: the first card is selected and the D-pad moves between cards.
5. `unlock_all_debug` with `{ lantern = "BlueHour", paint = "Oxblood", hat = "Souwester" }`: the boat's lantern light and ball turn blue, the sides, transom and bow planks dark red (floor and benches stay wood), and a yellow rain hat sits on the head (crown up, brim level, not inside the head or floating). The Locker shows every item unlocked with those three worn. Try each lantern color lit from the bow seat: still readable, still the brightest thing; Bone White not too harsh with bloom.
6. Hats on R15 and R6 avatars, with and without an avatar hat: ours replaces the avatar hat (hidden, not deleted); "No hat" brings the avatar hat back. If a hat sits wrong, tune `SHAPES.<id>.lift` or the attachment in `Cosmetics.buildHat`. In `hum_fail` (or any death), the floating hat is the earned hat with its brim attached.
7. Host only: with two clients, the second player's lantern and paint never show on the boat; their hat shows on their own head for both players.
8. `endless`: the HUD paper says "Endless night 6"; the start card says "Endless night 6" and "Any rule, any night. One try."; the Endless tape plays. A cleared night shows "Endless night 7 next. It gets worse."; a failed one "The lake does not give Endless nights back. The run is over.", then "The Endless run is over." with the best night. A cleared Endless night raises `stats.bestEndlessNight` and, about a second later, the title list shows the player's display name and night (never a number id).
9. Endless unlock: on a fresh server the host has no Endless button (`unlock_all_debug` does not open it: cosmetics only). After a cleared run (`full_run`) the host sees Endless Nights back on the title; a non-host never does. A client sending `Mode Endless` without a cleared run is ignored.
10. Unlocks at night end: clearing night 1 of a run shows "New in your locker: Bucket Hat." on the title paper, and the Locker shows it unlocked.
11. Published place with API access on (only after Stewart publishes privately): no memory line; play a night, leave, rejoin: stats and worn items come back. Stop the server with players in it: BindToClose saves (no "save failed" warning).
12. Errors never stop play: on a published place with API access off, the memory line says "DataStores refused"; the game plays normally.

## S4: what exists (11/26/2026)

Server (`src/server`):
- `LobbyService.luau` (new): phase Title, Playing, RunCleared, RunOver. The first player is the host (the next player takes over if they leave); the host picks Normal or Nightmare and presses Play (Lobby remote "Difficulty", "Start"; "Title" leaves the run's end card early; "Hello" asks for the state). Starts the run (`NightService.newRun`) and its nights (`NightService.startRunNight`). After a night: 12 s later the next night (NextNight) or the same night again (RetryNight); 30 s on the run-cleared or run-over card, then back to the title (boat home, everyone shown and seated, lantern lit). Late joiners wait as the drowned (hidden through `EntityPresenter.hideWaiting`, never steering) until the next night. Every change goes to every client on `LobbyState` (phase, host, difficulty, players, waiting, `Run.view`, outcome, tonight's rules, newRules and amendments, the run's totals). Any night start (a Studio scenario too) takes the title down.
- `NightService`: Core.Run in place of the Config.Nights seam. `newRun`, `startRunNight`, `endRun`, `run`, `runView`, `lastOutcome`, `isRunNight`, `onNightEnd(fn(result, outcome, runView))`, `endedFor`. `Run.finishNight` is called once when a run night ends. It no longer advances by itself (LobbyService does, while `autoAdvance` is true). `bookOpen` and `touch` in PlayerObs come from Net. Studio only: `debugState` (the raw NightState), `debugSetGaze`, `debugCrew`.
- `Net`: the Lobby remote now acts ("Book" 1 or 0 sets the book flag and lets go of the reel and the bail; "Touch" 1 or 0; the rest goes to `Net.onLobby`). Intents that need hands (lantern, motor, cast, bank, refill, knock, keep or throw back) are refused while the book is open, and the helm goes slack.
- `EntityPresenter.hideWaiting`. `Main.server`: LobbyService instead of the auto start; `LobbyService.tick` on Heartbeat.
- `DebugCrew.luau` (new, Studio only): the crewbot "follow" policy on the live server (fishes, checks every catch against the book, banks, refills, answers every rule as tonight's page says, bails, the steeple run and the run home on night 5). Its intents go straight to Night (not through Net: a five-night run would trip the rate limits; the remote paths are covered by S2 and S3).
- `DebugRun.luau` (new, Studio only): scenarios `title`, `rulebook`, `full_run`, `finale`. `DebugDriver.night_start` takes `run = true` to start a run at that night.

Client (`src/client`):
- `LobbyClient.luau` (new): the latest LobbyState and the Lobby actions.
- `ui/Title.luau` (new): the title over the lake from the dock (Camera shot "title"), Play (host), Difficulty (host; others see it), The Lake Rules, a status line; the owner's title tape (`tape-title`) and `title-theme` (id 0 now). Enter, N, L; gamepad A, X, Y. Hands blocked while it is up.
- `ui/BookState.luau` (new): which page is open; blocks the hands (`Input.setBlocked`) and tells the server.
- `ui/Rulebook.luau` (new): the page from `Core.Rulebook.page` and `Rulebook.TEXT`: Rule 0 and every rule taped in so far, each held by tape, fresh tape and "taped in tonight" for tonight's rule, an amendment as the printed line crossed out (RichText `<s>`) with the new line under it in the amendment ink. On the title it shows all seven rules as printed. A paper block on the stern thwart opens it with a click (ClickDetector).
- `ui/FieldGuide.luau` (new): the eight species down the left, the page on the right (name, sepia drawing, facts, note); arrows, A and D, or the shoulders turn pages.
- `ui/MobileButtons.luau` (new): Cast, Use, Knock bottom right beside the jump area; Lantern, Motor, Bail, Book, Guide, Call in two columns on the left edge; laid out from the screen size; labels follow the action; hidden while the book or the title is up. Reports touch to the server (PlayerObs.touch widens the Watcher's cones).
- `ui/NightCards.luau` (rewritten): night start card (night of five, which try, quota, the rule taped in tonight, "the book changed", the words of tonight's tape), end card with what comes next from the run's outcome, the run-cleared card (with `run-cleared` and `tape-run-cleared`) and the run-over card with the totals and a host button back to the title.
- `fx/Finale.luau` (was a stub): the bell rings three times by itself at the dock with a bell swinging on a post and a caption; the Ambience sound group fades out, `lake-silence-drop`, then `finale-bed`; a dark band clamps the lantern and a flame inside it shrinks and reddens with the oil; Neighbor boats (waving figure, own lantern) and false beacons drawn from `EntityMoved` hazards, smoothed and outlined for the drowned; a strike shakes the boat with `lake-groan`; home with the Steeple Cat warms the view to dawn with `dawn-cue`.
- `Input`: R or D-pad left rulebook, G or D-pad right Field Guide; `setBlocked`, `useButton`, `toggle`; no ContextActionService touch buttons (MobileButtons draws them). `HUD`: hidden on the title, "Oil (locked)" in the amendment ink during the finale, Book and Guide buttons under the paper for mouse players. `Drowned.setWaiting`. `RulesFx` routes `EntityStrike` and resets on the title. `Callouts`: the wheel scales down on short screens and the feed moves above the touch buttons. `Camera`: shot "title". `DebugBot`: command `book`. `ui/Paper`: `fit`, `bookPage`, `tape`.

## How to verify S4 in Studio (server side, during Play)

```lua
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("title")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("rulebook")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("rulebook", { page = "guide" })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("finale")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("finale", { async = true })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("full_run")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("full_run", { seconds = 120, seed = 2 })
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("status")
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("night_start", { night = 3, run = true })
```

Each prints `SCENARIO DONE <name> <result>`: `title shown`; `rulebook open` (the result lists the night 5 rules and its one amendment, `amended = 1`); `finale RunCleared` when the crew gets home (else `RunOver`, `RetryNight` or `timeout`); `full_run cleared` (or `over`, `timeout`). `full_run` is async by default (about 15 minutes at 150 s nights; poll `status`, whose progress shows the night, banked, quota and the crew bot's mode); its result has one line per night played (night, attempt, cleared, reason, banked, quota, deaths, outcome). `finale` takes 20 to 40 s.

## Studio must check (S4)

1. Press Play: the title screen shows over the lake seen from the dock (not first person), the owner's title tape plays, no HUD, no touch buttons, no night running (`state.night.running` false). Output: still only the two `[DeadCalm] ... up` lines.
2. Host: Play is there; Difficulty toggles Normal and Nightmare (the note under it changes); The Lake Rules opens a big paper page with all seven rules as printed and closes with Close, Escape, a click outside or gamepad B. With a second Studio client (Test, 2 players): the second player has no Play button, sees "Waiting for <host> to start." and the host's difficulty change.
3. Play: the title goes, the camera is back in first person at the helm, the night 1 start card shows "Night 1", "Night 1 of 5.", the quota, "Taped in tonight: Rule 1." and the words of tape 1 while the tape plays; a tap or click puts the card away.
4. R (and D-pad left, and the Book button under the HUD paper) opens the rulebook: it covers most of the view, Rule 0 and Rule 1 each held by two strips of tape, Rule 1 with fresh tape and "taped in tonight". While it is open you cannot cast, steer, light, knock or bail (try them). R again or Escape shuts it. G (D-pad right) opens the Field Guide page; R from there switches to the rulebook with a page-turn sound.
5. Click the little paper block on the stern thwart beside the helm: it opens the rulebook. If the ClickDetector on a client-made part never fires, say so (R and the button still work). Check the block sits on the thwart, not floating or inside the seat.
6. `rulebook`: night 5's page shows Rules 0 to 6 with one rule crossed out (a line through the printed text, faded) and the owner's new line under it in dark red handwriting, slightly crooked. The start card said "The owner changed the book. Read it again (R)." in red. On a phone-sized view the page scrolls.
7. Field Guide page (`rulebook` with page "guide"): eight species tabs on the left, the chosen one highlighted; the drawing, facts and note on the right; the arrows and the shoulder buttons turn pages; nothing overlaps on a 705 by 338 view.
8. Device Simulator, the smallest phone in landscape (705 by 338, or the closest preset): the touch buttons are large and round, Cast (the biggest), Use and Knock in the bottom right, clear of the jump button area; Light, Motor, Bail, Book, Guide, Call in two columns on the left edge; the move stick still starts in the open middle-left. Each button works: hold Cast to charge and let go; hold to reel; Use keeps, banks, refills; Bail only bright with water in the boat; Book and Guide open the pages (the buttons hide while open); Call opens the wheel, which fits on the screen. While a fish is being decided Cast and Knock hide, so the card's Keep and Throw back are not covered. When drowned only Bell and Call show. `MobileButtons.debugState()` from the client lists every button's position and size. The night cards and the start card's tape words fit (no text spilling off the paper).
9. Gamepad: Y lantern, X motor, R2 cast and reel, A use, B throw back, L1 knock, D-pad up callouts, D-pad left rulebook, D-pad right guide, B shuts the book; on the title A plays, X toggles the difficulty, Y opens the Lake Rules. Check gamepad A on the title does not also press a different selected button.
10. The five-night flow (`full_run`, or play): after each night the end card adds "Night N next." (or the retry line with the tries left); 12 s later the next night starts with its start card and tape. A failed night restarts the same night with the retry line. Out of tries: "No more tries. The run is over.", then the run-over card with the totals; 30 s later (or the host's "Back to the title") everyone is on the title again.
11. `full_run` result: `cleared = true` (or say which night failed and why from `nights`). Watch one night: the bot answers a Hum (lantern out, motor off, still), keeps away from a Neighbor, knocks the right count, and on night 5 goes to the steeple and runs home at the bell.
12. `finale`: at 4 AM the bell rings three times from the dock (bell-dock-solo, heard far away) and a small bell swings on a post at the dock end; the caption "The dock bell is ringing by itself." shows; the lake goes silent (no lap, wind or frogs; `Finale.debugState().ambience` 0 from the client), then the finale bed; a dark band clamps the lantern and the little flame inside it shrinks and turns red as the oil bar (red, "Oil (locked)") runs down; dark rowboats with their own lanterns and slow-waving figures, and steady lights on poles that never blink, appear off to the sides and drift; the boat motors home around them. Home: the view warms to dawn, dawn-cue, "Dawn. You made it home with the owner's fish.", then the run-cleared card with the owner's run-cleared tape and words. Result `RunCleared`, strikes 0 (if a strike happens: a hard shake, the groan, the death card for the taken player, and the finale goes on). If the lock bands look wrong (cylinders lying flat), change the rotation in `Finale.stepLock`.
13. After the finale or the run's end card, back on the title: no dawn tint, no finale bell or hazards left, the water sounds are back (`Finale.debugState().ambience` back to its normal level). The AudioDirector builder must keep the Ambience SoundGroup named `DeadCalmAmbience` (fx/Finale fades it).
14. Late joiner (Studio Test with 2 players, the second joining after Play): the newcomer is hidden in a seat, watches from the drowned view with "You join the crew at the next night.", cannot steer, has no touch buttons; at the next night they are visible and in the crew (the quota rescales).
15. Every S3 scenario still prints its expected result (they start nights outside the run; the title goes down when they start). `night_start` with `run = true` and `autoAdvance = true` plays on to the next night by itself.

## Studio and Neon fixes (11/26/2026)

From the main session's Studio run of the five rules and Neon's review of the Hum fail clip (`docs/critic/11-26-2026-scare-hum-fail-neon.md`). One line each in `docs/SHELL-DECISIONS.md`. Gate green (selene, stylua, specs, sim, lints, rojo build, smoke 10 of 10). NOT yet played in Studio.

Files: `src/client/ui/DeathCard.luau`, `ui/DeathTexts.luau`, `ui/NightCards.luau`, `ui/HUD.luau`, `Drowned.luau`, `BoatFx.luau`, `WorldFx.luau`, `AudioDirector.luau`, `DebugBot.luau`, `fx/Hum.luau`, `fx/Neighbor.luau`, `fx/Watcher.luau`; `src/server/DebugRules.luau`, `DebugDriver.luau`. No Core, Config, registry or remote changes.

How to record a scenario without the reset on tape:

```lua
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("reset", { scenario = "hum_fail" })
-- start the recording, then:
return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hum_fail", { reset = false })
```

`reset` returns `{ result = "clean", helm, seat, alive, crew, lanternOn, motorOn, rules, clock }`: expect helm true, seat "HelmSeat", alive equal to crew, lanternOn true, motorOn false, rules 0. Neighbor and Watcher results carry `gaze = { samples, meanDeg, worstDeg }` (server gaze against the figure; watcher_pass against the edge offset).

## Studio must check (Studio and Neon fixes)

1. reset: no death card, no night card, no tape (no click, no voice), first-person helm view, lantern lit, motor off, frogs singing. Run `reset` twice in a row: same state, no errors.
2. Every `<rule>_pass` and `<rule>_fail` begins clean (never black, never mid-tape) and still prints its expected `SCENARIO DONE` result. After any rule scenario, `night_start` plays the night tape again.
3. hum_fail: at the fail the boat visibly rolls and heaves for about 1.2 s with the view rolling with it; fish and a bucket arc over the gunwale and splash (rings and spouts, hold-lost-splash); then the camera drops under the surface (blue-green, blurred) with death-drag, and only then the fade to black. No server boat parts flicker or stay invisible after the roll (LocalTransparencyModifier back to 0). No audible pop when the card appears.
4. Death card: centered and still from fade to close (also in neighbor_fail); the line states the mistake and the counter, "Rule N." bottom right; it goes by itself after 4 s, or on a click or tap after 0.6 s. `DeathCard.debugState()` position stays `{0.5, 0}, {0.5, 0}`.
5. Drowned view after the card: the black lifts into a high three-quarter view of the boat, slowly circling, tinted cold blue-green, the hull and crew clearly visible with the lantern out; the dim light near the boat; the outlined shape under the hull (hum_fail), the outlined silhouette in the helm seat (neighbor_fail), the outlined Watcher at the waterline (watcher_fail); the bell tag; a click or Space rings the bell. Solo: about 4 s of this, then the night-failed card, then "Rough night" (never over the death card).
6. Lantern out (hum_pass after the counter, neighbor_pass): the hull, the seats and the water near the boat stay readable (cool, dim); with the lantern lit the warm lantern pool is clearly the brightest thing and the moonlight is gone. Check on a phone-sized Device Simulator view too.
7. Motor (hum_pass sets it on, or ToggleMotor): motor-start, then motor-idle-loop heard from the outboard (louder behind you), the outboard visibly shaking, "Motor: on" on the HUD paper, the frog chorus clearly quieter; motor-stop when it goes off and the HUD line disappears. If the loop is silent, check `AudioDirector.debugState().motorIdle` (sounds 1, playing, loaded, parent "Motor") from the client.
8. Tape and cues: start a real night (`night_start`) and force a rule while the tape talks (`force_rule` with rule "Hum"): the voice fades out within about 0.3 s, then ui-tape-stop (id 0 now, silent). No tape ever starts later in the night.
9. neighbor_pass and neighbor_fail: the head turns to the creak at once; the boat appears about 80 studs off, close enough to read the figure and its slow wave, and stays in frame the whole time (gaze worstDeg small, under about 10); neighbor_pass still ends `pass` (it gives up and drifts off), neighbor_fail ends `fail` with the boat in frame at the moment it vanishes.
10. watcher_pass and watcher_fail: the head tracks the figure (pitch included) from the moment it appears; in watcher_pass it sits near the edge of the frame and the scenario still ends `pass`; in watcher_fail it stays in frame through every lunge to the waterline and the fail.

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
- `ui/DeathCard.luau` and `ui/DeathTexts.luau`: fade to black with `death-drag` (or `boat-sink` for the Knocking), then `death-sting` and a paper card with the line and "Rule N."; it goes after 4 s or on a click, tap or key (after 0.6 s); `DeathCard.hold` keeps it up. `DragWarning` plays `water-pull-warning` and a dark pulse.
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
3. hum_fail: `hum-fail`, a hard shake, then the death card "You left the motor running. When the frogs stop: motor off, lantern out, hold still." with "Rule 1." (see the fixes checks above for the capsize and plunge), the hat floating beside the helm and sinking, the helm rod lying in the boat. After the card: orbit camera over the boat, the dim light near the boat, the outlined shape under the hull (only the drowned see it), the bell tag; Space or a click rings the bell and the light flares. The night failed card comes after the death card, not over it.
4. wrongcatch_pass and wrongcatch_fail: the wrong tell on the held fish; throwing it back gives no cooler events. Kept and banked: from the dock shot, three knocks with the cooler jumping on the dock each time, then the thump; the banked total drops by the eaten points. The jump moves the server's cooler part locally; if it looks wrong, lower the lift in `fx/WrongCatch`.
5. neighbor_pass: the oarlock creak far off (id 0 now, silent), then a dark rowboat with its own warm lantern appears in the fog where the bot looks, a tall seated figure in it with one arm up, waving slowly (one wave per 3.6 s). It drifts smoothly (no stepping every 0.5 s) and always faces the boat. One or two fake callouts appear over the bot's head and in the feed, exactly like real ones. With the lantern out it drifts off and fades. With `form = "FalseBeacon"`: a steady light on a pole, never blinking, out after 20 s. Check the waving arm turns from the shoulder; if it swings the wrong way, flip the sign of `math.rad(150)` in `Neighbor.step`.
6. neighbor_fail: the bot's "(waves)" tag, then `neighbor-fail`, the other boat is gone, the lantern goes out, the death card "You waved back. There are no other boats out here. Never wave back." "Rule 3.", and a black seated silhouette in the helm seat, visible from the orbit camera for 25 s.
7. knocking_pass: three knocks shake the boat three times; the hint "Q  Knock on the hull" shows during the window; the two answers are heard on the hull (`knock-answer`, a server Sound); pass.
8. knocking_fail: the harder second round (bigger jolts), then water appears in the boat and rises; the hint switches to "Hold E  Bail"; while the bot bails, scoops of water fly over the side and the level falls. Check the water plane stays inside the hull and reads as water at night.
9. watcher_pass: a figure about 13 studs tall and very narrow stands in the trees on the west shore with two pale pin eyes, feet on the ground (not on a canopy, not floating). While the bot glances straight at it the screen edges darken and the tone rises (id 0 now); at the edge of sight both clear and it holds; after about 40 s it is simply gone (removed once off screen, or after 6 s).
10. watcher_fail: staring deepens the vignette fully; it lunges two steps at a time toward the water; at the waterline the lanterns die, then the death card "You let the thing on the shore reach the water. Keep it at the edge of your eye. Never stare." "Rule 5.".
11. fakeouts (the bot faces the bow): loon and branch from the shore, a dark fish arcing out of the water by the gunwale with two ripples, one jolt for the single knock, the buoy clank, the lantern nearly going out for 0.6 s, a warm light low on the shore that drifts apart into fireflies after 4 s. Most fake sounds are id 0 now (silent); the visuals must still show. ChorusDip shows nothing in this scenario (Night owns that timer).
12. death_card: the bot goes over the side; `water-pull-warning` and a dark pulse at 2 s, then the fade to black and "You got out of the boat. Stay in it. The water is not yours at night." "Rule 0." stays up. `night_start` clears it, shows the character again and seats the player.
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

## Derived sounds (11/26/2026)

Files: `src/shared/SoundRegistry.luau` (the `derive` and `["repeat"]` fields, `EFFECT_PROPS`, `isDerived`; `available` and `uri` resolve a derived name to its source), `src/client/AudioDirector.luau` (builds derived sounds in `play` and `loop`: speed, PlaybackRegion, SoundEffect children, delayed layers, a repeat timer, duration and fades, the entry's `repeat` copies; `audition` and `stopAuditions` for listening tests), `src/client/fx/Knocking.luau` (knocks at the server's gap, cancelled on reset), `src/client/DebugBot.luau` (`play_sound`, `stop_sound`), `tools/lint/asset_ids.py` (derive checks). Recipes and calls: `docs/SHELL-DECISIONS.md`, "Derived sounds 11/26/2026". 28 entries are derived; 5 UI entries stay silent.

Listening test (Studio, in Play, from the server context; the client prints `[DebugBot] play_sound <name>: playing`):

```lua
game:GetService("ReplicatedStorage"):WaitForChild("DeadCalmDebugRemotes"):WaitForChild("DebugBot"):FireAllClients({ cmd = "play_sound", name = "watcher-tone-loop", seconds = 6 })
game:GetService("ReplicatedStorage"):WaitForChild("DeadCalmDebugRemotes"):WaitForChild("DebugBot"):FireAllClients({ cmd = "play_sound", name = "knock-three-hard" })
game:GetService("ReplicatedStorage"):WaitForChild("DeadCalmDebugRemotes"):WaitForChild("DebugBot"):FireAllClients({ cmd = "stop_sound" })
```

Any registry name works (real, library stand-in or derived). Loops stop after `seconds` (default 8). Spatial entries play at the hull.

Studio must check (derived sounds):

1. Each derived name plays something through `play_sound` (no warnings like "unknown effect class" or "has no property" in the output).
2. knock-three-soft and knock-three-hard knock three times about 1.1 s apart; cooler-knock-inside three muffled knocks 0.9 s apart.
3. watcher-tone-loop is thin, high and quiet; neighbor-oarlock-loop creaks every 2 s, far off, until stopped.
4. wrong-blink, ui-tick and callout-blip are audible at all (very short slices); widen their regions if not.
5. watcher-step and watcher-lunge: the first 0.6 s of dock-creak is one step. Retune the region if it is two steps or half of one.

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

Read this file and `docs/SHELL-DECISIONS.md`, run the gate, then `lune run tools/shell/world_count.luau`. Next: the Studio checks for S3, S4 and S5. All shell chunks are written.
