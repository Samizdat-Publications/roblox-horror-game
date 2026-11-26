# Cloud shell brief

You are the second cloud session for Don't Wave Back (code name Dead Calm), a co-op Roblox horror game. A sibling cloud session builds the pure rules engine (`src/shared/Core`, `tests`, `tools/sim`; see `docs/CLOUD-BRIEF.md`). You build the Roblox shell around it: server, client, world, UI. A local session on a PC that is often offline owns Roblox Studio: it will play what you write, capture it, fix what Studio disagrees with, and add sound ids. Nobody will answer questions: make the reasonable call, write one line in `docs/SHELL-DECISIONS.md`, keep going.

## Read first

`CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN.md`, `src/shared/Core/Types.luau`, `src/shared/Config.luau`, `audio/sounds.json`, then `docs/SHELL-PROGRESS.md` if it exists (resume from it).

## What you own

- `src/server/**`, `src/client/**`
- `src/shared/Look.luau`, `src/shared/Remotes.luau`, `src/shared/SoundRegistry.luau`, `src/shared/AssetRegistry.luau`
- `PLAYTEST_GUIDE.md`, `SOUNDS_NEEDED.md`, `README.md`
- `docs/SHELL-PROGRESS.md`, `docs/SHELL-DECISIONS.md`

Do not edit `src/shared/Core/**`, `tests/**`, `tools/sim/**` or `Config.luau` (the core session owns them). If you need a Core function that does not exist, code against the contract in `ARCHITECTURE.md`, and list what you need at the top of `docs/SHELL-PROGRESS.md` under "Needed from Core". To use Core work that is not on `main` yet, merge the newest `origin/claude/core-*` branch into your branch.

## You have no Roblox Studio

So be strict with yourself:

- Check every Roblox API you use against the current documentation at create.roblox.com/docs before using it. Do not rely on memory; properties and enums change. Prefer long-stable APIs.
- Run before every commit: `selene src`, `stylua --check src tests tools`, `lune run tools/test/run.luau`, the lints in `tools/lint`, `rojo build -o DeadCalm.rbxl`, and `lune run tools/smoke/place.luau`. If `luau-lsp analyze` can be run with Roblox type definitions and a Rojo sourcemap, run it and fix what it finds.
- Keep logic out of the shell. Anything that can be decided by a pure function belongs in Core. The shell reads `NightView` and `Event`s and shows them.
- Every module must be safe when a sound or asset id is `0` and when a remote arrives malformed.
- Tools come from Rokit (install Rokit on Linux with its official install script, then `rokit install`).

## How to work

One branch per chunk: `claude/shell-s1`, `claude/shell-s2` and so on, each cut from the latest `main` (or from your previous branch if it has not merged). Push and open a pull request to `main` when a chunk is done, then start the next. Commit small. No em dashes in any text. Dates as MM/DD/YYYY. Keep `docs/SHELL-PROGRESS.md` current, including a "Studio must check" list: the specific things the local session should look at in Studio for each chunk.

## Design decisions already made (do not reopen)

- **Water is a large flat Part**, not Terrain: dark, slightly glossy, `CanCollide` off, with a lake bed a few studs below so a player who leaves the boat wades. The server reports `inWater` when a character's root is below the dock height and outside the boat.
- **The whole world is built by code** at server start from `Config.Lake`: the lake, a ring of shore with crooked tree silhouettes (trunk and two or three canopy blocks, varied height), the dock with sagging planks, the bait shack with a lit window and the radio, the beacon on a pole by the dock (warm light, double blink every six seconds), the sunken steeple leaning out of the water with a bell under the surface, the old buoy, reeds along the east shore. Parts only. Keep it under about 2,500 parts. Deterministic from a fixed world seed.
- **The boat** is an unanchored assembly owned by the server, moved with constraints toward the velocity and heading that `Core.BoatModel` computes from helm input, held level at the water line with a small scripted bob. Four seats: bow faces forward, port and starboard seats face outward, the helm at the stern faces forward. A lantern hangs on a post at the bow (PointLight plus a small glowing part, flicker). A cooler-sized hold box sits in the middle.
- **Camera** is locked to first person while seated. The client reports gaze yaw at `Config.Net.gazeHz`.
- **Look** starts from these values in `Look.luau` (the local session tunes them in Studio): ClockTime 0, Brightness 0.4, Ambient and OutdoorAmbient very dark blue-green (about RGB 10, 16, 19), Atmosphere Density 0.6, Offset 0.1, Haze 2.4, Color and Decay near the fog color `#1B2A2E`, a faint ColorCorrection toward teal, a little Bloom, no DepthOfField. Lantern: PointLight Range 34, Brightness 1.6, Color `#FFB45A`, Shadows on. Beacon: Range 60, Brightness 4. Never pure black.
- **All UI is built in code**, paper and ink, per DESIGN.md. Handwriting font for rules, typewriter for the Field Guide (verify the font names exist in current Roblox before using them; fall back to a built-in font).
- **Input** maps keyboard, touch and gamepad to the same intents. Suggested keys: W A S D helm, M motor, F lantern, left mouse or Space cast and reel, Q knock, E interact (bank, refill, bail, keep), X throw back, R rulebook, G Field Guide, C callouts. On touch, a button for every verb, large, bottom corners, never under the jump button (jump is disabled while seated).
- **The default emote menu is off.** Our Wave lives in the callout wheel.
- **The frog chorus is built from pieces, not from three loops** (decided 11/26/2026 after the generated "thin" and "sparse" loops came out too busy). `AudioDirector` plays the `chorus-frogs-full` loop only at band 3. At every band above 0 it also schedules single frog calls (`frog-peeper-a`, `frog-peeper-b`, `frog-bull-a`, `frog-bull-b`, `frog-gray-a`, `frog-green-a`) from random points along the nearest shore, with slight random pitch and volume: about one call every 0.4 to 1.2 seconds at band 3 (under the loop), every 1.5 to 4 seconds at band 2, every 5 to 11 seconds at band 1, none at band 0. Moving between bands is gradual over a few seconds except the drop to 0, which is instant. `frog-first-back` plays once when the band rises from 0. The ids `chorus-frogs-thin` and `chorus-frogs-sparse` no longer exist.
- **The dock radio is a playlist, not a loop:** `radio-tune-1`, a few seconds of `radio-static-loop`, `radio-tune-2`, static, repeat. It plays from the shack with distance rolloff.
- **The cassette sound is made in the game:** the Voice sound group gets an EqualizerSoundEffect (cut lows and highs) and a light DistortionSoundEffect, with `ui-tape-click` before and `ui-tape-stop` after each tape. The tape files themselves are clean speech.
- **SoundRegistry** gets one entry per id in `audio/sounds.json` plus the tape ids in `audio/tapes.json`, all with id `0` for now, with volume, looped, spatial and a group (Ambience, Boat, Fishing, Rule, UI, Music, Voice). The local session fills in ids.

The local session may have built some of this already. Before each chunk, pull `main`. If a module on your list already exists there, review it against the brief, fix gaps, and move on. Do not rewrite working code.

## The work, in order

**S1 The lake you can row.** `WorldBuilder` and `world/*`, `LightingController`, `BoatService`, `Net` with `Remotes` (validation through `Core.Validate` and `Core.RateLimit` when they exist, local checks until then), client `Input`, `Camera`, `AudioDirector` (ambience layers driven by a `NightView`-shaped table; use `Core.SoundMix` when it exists), a minimal `HUD`. `DebugDriver` scenarios `row_to_steeple` and `tour` (teleports the boat to each point of interest in turn) and a Studio-only client `DebugBot` that can sit in a seat and send helm input through the real remotes.

**S2 Fishing and the night.** `NightService` (owns `Core.Run` and `Core.Night`, ticks at `Config.Night.tick`, gathers observations, drains intents, dispatches events, replicates the view), `FishingService` (bobber, line, the fish shown on the line, built from parts using the catch's traits so that a wrong fish really looks wrong), `ReelBar`, `CatchInspect` (the fish held up to the lantern, keep or throw back), hold and cooler, HUD (night, clock, quota, oil), night clear and fail. Scenario `quiet_night` where the bot fishes a whole night.

**S3 The rules on screen.** `EntityPresenter` and one `fx` module per rule (Hum, WrongCatch, Neighbor, Knocking, Watcher, Finale) turning `EntityCue`, `EntityStage`, `EntityPass`, `EntityFail` into sound, light and silhouettes; fake-outs; `DeathCard`; the drowned (spectate, outlines, bell); `Callouts`. Scenarios `<rule>_pass` and `<rule>_fail` for every rule, each seeded, each ending with a console line `SCENARIO DONE <name> <result>`.

**S4 Front and back of a run.** `LobbyService`, `Title` (Play, difficulty, Lake Rules), `Rulebook` (taped-in pages, amendments in a second ink), `FieldGuide`, tapes at night start, `EndOfNight`, the supply pick, `MobileButtons`, the five-night flow and the finale. Scenario `full_run`.

**S5 Saves and Endless.** `DataService` on `Core.Profile` with a store adapter (real DataStore, memory fallback, pcall, retries with backoff, never errors a player out), cosmetics, Endless Nights, the best-night board through an OrderedDataStore stub that degrades to memory, and clearly marked Game Pass stub hooks with no ids.

**S6 Docs.** `PLAYTEST_GUIDE.md` (how to open and play, what to test each night, a report-back checklist), `SOUNDS_NEEDED.md` (every registry entry: description, length, search terms, and its id or "needed"), `README.md` (pitch, controls, how to tune `Config`, the gate command for Windows PowerShell with full paths under `C:\Users\stewa\Documents\Claude\Roblox\dead-calm`).

## Done looks like

Every chunk: the gate steps above green, a pull request open, `docs/SHELL-PROGRESS.md` updated with the "Studio must check" list. When all chunks are done, write "ALL CHUNKS DONE" at the top of `docs/SHELL-PROGRESS.md` and stop.
