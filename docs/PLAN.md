# Plan: "Don't Wave Back" (code name Dead Calm), a co-op Roblox horror game

Written 11/26/2026 by Fable 5.2 in plan mode. Nothing has been created yet.

## Context

Stewart wants a second Roblox game, separate from the fishing game, in its own subfolder and its own private repo. Cowork handed over a detailed brief ("Dead Calm": a 5-night co-op fishing horror game with a rulebook of Lake Rules). Stewart then gave three rulings that outrank the brief:

1. Full creative control is mine: study the popular horror games and build the best combination that is still its own thing.
2. Sound and ambience matter most. Be liberal with ElevenLabs. Try Gemini music too.
3. Uploads of generated sounds and models to his Roblox account are approved (private assets, nothing published as a game).

One hard fact shapes the run: this PC is on a phone hotspot over Thanksgiving, so everything local stops whenever the hotspot leaves the house. Stewart chose "local plus one cloud helper" to keep work moving through those gaps.

## Answer to "Opus or Fable to run it?"

Keep Fable 5.2 as the orchestrator. Do not switch this session down. Reasons: the run is unattended, and the calls that decide whether this game is good (is the scare readable, is the frog chorus doing its job, is the fog right on a phone, did a builder really prove its work) are judgment calls nobody else will be there to make. The heavy typing goes to Opus builders, Sonnet grunts and the cloud helper anyway, so Fable's share of the tokens stays small. If Stewart still prefers Opus in the chair, this plan works unchanged: Opus leads and calls the `fable-advisor` agent at every item tagged [fable].

## Where it lives

- Folder: `C:\Users\stewa\Documents\Claude\Roblox\dead-calm` (starts with `C:\Users\stewa\Documents\`, confirmed).
- Repo: its own git repo, pushed to a new private GitHub repo `Samizdat-Publications/roblox-horror-game` (gh is signed in; the repo does not exist yet).
- Output: `rojo build` writes `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\DeadCalm.rbxl`.
- The one touch outside the new folder: a single line `/dead-calm/` added to the fishing repo's local, uncommitted `.git\info\exclude`, so the fishing repo (which has an active branch and another session committing) never sees or swallows the nested repo. No tracked fishing file changes. Reading and copying tool scripts and the two API keys from the fishing folder is read-only on that side.
- The new `CLAUDE.md` will state that it overrides the parent `Roblox\CLAUDE.md` (the fishing game's instructions), because sessions opened in the subfolder inherit both.
- A project `.mcp.json` registers the Roblox Studio MCP server so future sessions opened in the new folder have Studio tools.

## The game

### Research, in one paragraph

The biggest Roblox horror game right now is 99 Nights in the Forest (survival loop, light as safety, a home base). DOORS and Pressure remain the model for learnable monsters. Rule-and-anomaly "night shift" games are the current trend. Off Roblox, the co-op hits (Lethal Company, R.E.P.O., Phasmophobia) all run on a quota or evidence job, greed, and players talking over each other. Fishing horror is an emerging niche on Steam (GONE Fishing, Voodoo Fishin', Dredge before them) and a Roblox one may be coming, so "horror fishing" alone is not unique. What nobody has combined: a rulebook that changes every run, sound as the only danger meter, and a wrong catch that pays. No game named "Don't Wave Back" turned up on Roblox or Steam.

Sources: [rowatcher top horror 2026](https://rowatcher.com/news/10-best-roblox-horror-games-in-2026-from-dandy-s-world-to-hidden-gems), [lootbar horror 2026](https://www.lootbar.com/blog/en/best-horror-games-on-roblox-2026.html), [games.gg Roblox horror 2026](https://games.gg/news/best-roblox-horror-games-2026/), [GONE Fishing on Steam](https://store.steampowered.com/app/3645890), [80.lv on co-op fishing horror](https://80.lv/articles/the-calm-of-fishing-blends-with-the-dread-of-survival-in-this-upcoming-first-person-co-op-horror), [Pro Game Guides on a datamined Roblox horror fishing build](https://progameguides.com/?p=1043202), [gamegeeker co-op horror picks](https://gamegeeker.com/editors-picks/best-co-op-horror-games-steam-summer-sale-2026?country=US).

### Title and promise

- Display title: **Don't Wave Back**. Tagline: "Night shift on Blackwater Lake. Read the Lake Rules." Dead Calm stays as the internal code name (it is also a 1989 film title, one more reason not to ship under it). The title is one constant in Config; Liam can overrule it later.
- The promise (first 60 seconds): you row out of the dock light into fog, the frogs are loud, a tape of the owner's tired voice reads Rule 1, and you realize the frogs are the only thing telling you that you are safe.

### What we take from the best, and our twist

| From | What we take | Our twist |
|---|---|---|
| DOORS, Pressure | Monsters with a sound cue and a learnable counter; die and learn | Every counter uses the same five verbs, so rules can collide |
| Lethal Company, R.E.P.O. | A quota for an absent boss; haul it home; push your luck | Only banked fish are safe; the boat's hold is at risk until you reach the dock |
| 99 Nights in the Forest | Light as safety; a home fire; nights that escalate | The dock beacon is the one safe place; lantern oil is the night's fuse |
| Rule and anomaly games | Check what you see against the rules | The owner amends the rules each run, so the book always matters, and reading it covers your eyes |
| Dredge | Calm fishing, wrong fish | The wrong fish counts triple toward quota. Greed is a choice |
| Phasmophobia | Evidence against a journal; the dead still play | Field Guide trait check; the drowned see the lake's truth and warn with a bell |
| FNAF | Five nights, a clock to dawn | Nights 4 and 5 overlap rules that want opposite things |
| Keep Talking and Nobody Explodes | One reads, the others act | "What do we do when it knocks?!" "TWO! Knock TWO!" |

### Pillars (and what each rules out)

1. **Sound is the HUD.** The frog chorus is the safety meter: it thins as danger builds and dies when the Hum comes. Rules out: an on-screen danger meter, stingers not tied to a rule, any scare with no audio cue.
2. **Every death teaches a rule.** Cue, counter, fail, then a death card naming the rule you broke. Rules out: random jump scares, instant deaths, fails you cannot read.
3. **Five verbs, hard choices.** Light (lantern), noise (motor, reel, knock), motion (row or hold still), gaze (look or look away), the book. Rules out: a new button per monster, combat, inventory juggling.
4. **Greed is the real monster.** Deeper water has bigger fish and is farther from the dock. The wrong catch pays triple. Rules out: difficulty that is only bigger numbers.
5. **One boat, different eyes.** Seats face different ways, some cues reach one player only, the dead see more than the living. Rules out: play where the crew never needs to talk.
6. **Scary, not disturbing, and funny in the gaps.** The rulebook is dry and practical. Rules out: blood, gore, bodies, injury detail, shrieking faces, real people, other games' monsters.

### The loop

Dock (safe, lit, radio playing) to open water (fish, watch, listen) to dock (bank the hold) until the quota is met and the clock reaches 5 AM. A night is about 9 real minutes. Five nights make a run. Clearing a run unlocks Endless Nights.

- **Boat:** one rowboat, four seats facing different ways, first-person view locked while aboard. Oars are slow and quiet. The motor is fast and loud: it drowns the frog chorus, so you cannot hear trouble coming. Rule 0: stay in the boat (swimmers get a short, clearly cued drag-under timer).
- **Fishing:** cast, wait for the bite, hold to reel while keeping a tension bar in its zone. Server runs the real simulation; the client only sends "reel held or not". Eight species, each with three checkable traits in the Field Guide. Zones pay more the farther they are from the dock (Shallows, Reeds, Narrows, Steeple).
- **Hold and bank:** the boat holds a few fish. Only fish banked in the dock cooler count. A failed rule can cost the hold.
- **Lantern:** the main light. Oil runs down. Some rules want it out.
- **The book:** opening the rulebook or Field Guide covers most of your view and stops your hands.
- **Callouts:** a small wheel of fixed phrases ("Frogs stopped", "Knock twice", "Don't wave", "Wave" and so on) so the crew can talk without voice chat (Liam is under the voice chat age). Fixed phrases only, no free text.
- **Death:** fade to black with a splash or drag sound, then a death card naming the rule. The dead become "the drowned": they spectate, can see outlines of what the living cannot, and can ring a faint bell. Everyone returns next night. Whole crew gone means the night restarts.
- **Between nights:** the owner's pay envelope: pick one of three supplies for the rest of the run (extra oil, quieter oars, a bigger hold, and so on). First item on the cut line.
- **The owner's tapes:** each night opens with a click and a short cassette message in one designed ElevenLabs voice (older, tired, kind, dry). It teaches the night's new rule out loud for players who will not read.

### The Lake Rules

All server-authoritative, each a pure state machine: idle, cue, window, pass or fail, cooldown.

| Night | Rule | Cue | Counter | Fail |
|---|---|---|---|---|
| 1 | **The Hum** | The whole chorus stops at once, then a low hum rises under the hull | Stop reeling, motor off, lantern out, hold still until the frogs sing again (10 to 15 s) | Boat rocked, hold lost, whoever kept making noise is dragged under |
| 2 | **Wrong Catch** | A catch with one trait that disagrees with the Field Guide (eye count, fins, stripes, a glow, a blink). Obvious at first, subtle later | Throw it back. Or keep it: it counts triple | Kept: the lake's attention rises all night; later something knocks from inside the cooler and banked fish go missing |
| 3 | **The Neighbor** | A slow oarlock creak, then a second lantern and a rowboat in the fog, a figure waving. Variant: a false beacon (steady light; the real beacon double-blinks) | There are no other boats. Never wave back. Never row toward a light that is not the dock beacon | Waving or closing the distance: lantern snuffed, a silhouette in your boat, fade |
| 4 | **The Knocking** | Three slow knocks on the hull | Answer with exactly two knocks inside the window | Harder knocks, then the boat takes on water: bail (no fishing) or sink |
| 4 | **The Watcher on the Shore** | A tall still figure in the trees; a thin tone rises while you stare at it. First sighting goes to one player only | Keep it at the edge of sight: do not stare, do not turn your back | It reaches the waterline, every lantern dies, then it takes the nearest player |
| 5 | **The Lake Wakes** | 4 AM: the dock bell rings by itself and every water sound stops | Go home. Lights on. Do not stop | A chase to the dock through fog, earlier rules firing fast, oil running out |

- **Amendments (the replay hook):** the owner crosses out and rewrites one line of an earlier rule ("answer with ~~two~~ one"). On Normal the first run is always by the book and amendments start on night 5. On Nightmare and Endless any rule may be amended any night, drawn from the run seed. The cue never changes, so players learn "recognize it, then check tonight's page".
- **Fake-outs:** a loon that sounds like a scream, a branch snap, a fish jumping at the gunwale, one knock (not three), the chorus dipping for two seconds, a buoy clank that is nearly a bell. Some go to one player only.
- **Fairness rule (tested):** a real cue shown to only one player must be one that player can counter alone, or must leave at least 12 seconds to tell the crew.

### The scare director

A pure `Director` module per night: a tension value, calm, build and peak phases, a guaranteed quiet window after every scare, a budget of real scares and fake-outs that grows each night, the night's new rule guaranteed to appear once with its long "teaching" window, everything drawn from a logged per-run seed. A hidden **attention** value (raised by motor, light, splashing, a kept wrong catch; lowered by stillness and by the dock) nudges the budget, and its only display is the density of the frog chorus. Modes: Normal and Nightmare. Solo gets longer warnings and a smaller quota. Starting values (to be tuned by the simulator, all in `Config`):

| Night | Real scares | Fake-outs | Min quiet gap | Quota (4 players) |
|---|---|---|---|---|
| 1 | 2 | 3 | 75 s | 10 |
| 2 | 3 | 3 | 65 s | 14 |
| 3 | 4 | 4 | 55 s | 18 |
| 4 | 5 | 4 | 45 s | 22 |
| 5 | 6 | 5 | 40 s | 26 |

### Look and sound bible (short form; full version goes in `docs\DESIGN.md`)

- **Palette:** water `#0B1418`, fog `#1B2A2E`, lantern `#FFB45A`, beacon `#FFE2A8` (slow double blink), wrong-glow `#8CFFC1`, silhouettes `#050607` with pin eyes `#E8F4FF`, paper `#E9DFC3`, ink `#2A2118`, amendment ink `#7A2E1E`.
- **Lighting:** midnight, heavy Atmosphere fog, very low ambient, lantern PointLight with flicker as the main light, never pure black (a phone in daylight must still read the boat).
- **Shapes:** blocky parts, built by code. Monsters are silhouettes: height, stillness, eyes, wrongness.
- **UI voice:** handwritten, second person, short and practical. "Rule 3. There are no other boats on Blackwater Lake. If you see one, you did not."
- **Sound plan (about 90 named sounds):** water and air beds; frog chorus in three densities plus crickets, loons and owls from real positions; boat foley (oars, oarlock, hull, motor, lantern); fishing (cast, plop, bobber tap, reel, splash, cooler); a signature set per rule (cue, build, pass, fail); fake-outs; paper, tape and stamp for the UI; music with a job (the dock radio's old tunes are the "safe" sound, plus title, dawn, finale and death cues); the owner's tapes. Three variants per effect, shuffled before ranking (the fishing game found Gemini's ranker favors the first file it hears). Music beds get two ElevenLabs Music takes and one Gemini music take where the key allows; the critic and I pick. Mix rules (tension crossfade, motor masking, ducking) live in a pure, tested `SoundMix` module.

### Content limits

No blood, gore, injury or bodies. Deaths are fade and sound. Target Roblox fear level Mild to Moderate. `MATURITY_NOTES.md` will give Stewart the questionnaire answers.

## Architecture

Rojo project, tools pinned with Rokit, strict Luau. Functional core, thin Roblox shell:

```
dead-calm\
  rokit.toml  default.project.json  selene.toml  stylua.toml  .mcp.json  .env (ignored)
  CLAUDE.md  README.md  PROGRESS.md  DECISIONS.md  HUMAN_TODO.md
  PLAYTEST_GUIDE.md  SOUNDS_NEEDED.md  MATURITY_NOTES.md
  docs\      DESIGN.md  ARCHITECTURE.md  PLAN.md  ROUTING.md  CLOUD-BRIEF.md  critic\  checkpoints\
  src\shared\   Config.luau (every gameplay number)  Look.luau (light, mix, UI constants)
                Remotes.luau  SoundRegistry.luau  AssetRegistry.luau
                Core\  (PURE: no services, no Instances)
                  Rng  NightClock  Quota  FishTable  Fishing  WrongCatch  LakeMap  BoatModel
                  Lantern  Attention  Director  EntityBase  entities\(Hum, WrongCatch, Neighbor,
                  Knocking, Watcher, Finale)  Fakeouts  Rulebook  Ghost  Supplies  Night  Run
                  SoundMix  RateLimit  Validate  Profile  Leaderboard
  src\server\   Main  NightService  BoatService  FishingService  EntityPresenter  LobbyService
                WorldBuilder + world\  LightingController  DataService  Net  DebugDriver (Studio only)
  src\client\   Main  Input  Camera  AudioDirector  fx\  ui\(Title, HUD, Rulebook, FieldGuide,
                CatchInspect, ReelBar, DeathCard, EndOfNight, Callouts, MobileButtons)  DebugBot
  tests\        Lune specs and bot-night simulations
  tools\        check.ps1  test\  sim\  lint\  studio\  critic\  audio\  blender\
  audio\  art\  reference\  artifacts\ (ignored)
```

The contracts everyone codes against (written first, in `docs\ARCHITECTURE.md`, with typed stubs):

- `Core.Night.step(state, dt, inputs) -> events` is the whole rules engine for one night. The server feeds it real inputs (boat position from physics, each player's flags and gaze) and turns the events into remotes and world changes. The Lune simulator feeds it bot inputs. Same code both ways, so tests cover what ships.
- `EntityBase`: `new(config, rng)`, `step(state, dt, observation) -> events`, with states idle, cue, window, pass, fail, cooldown.
- `Core.Rng` is our own seeded generator, so Lune and Roblox draw identical numbers and a logged seed replays a run.
- `Remotes` lists every remote with a validator. `Net` wraps them with type checks, per-player rate limits and distance checks. Clients send intents only (boat input, cast, reel held, keep or release, bank, lantern, knock, wave, gaze report, ghost bell). Catches, quota and deaths are decided on the server. Gaze is the one client-reported value; it is range-checked and can only make the game easier for a cheater in a co-op game (logged in DECISIONS).
- `SoundRegistry` and `AssetRegistry`: named entries; id `0` means skip silently. A lint fails the gate if any asset id appears that is not in the upload log or the verified Creator Store list. No invented ids.
- `DataService` talks to an injected store adapter, so the save logic (pcall, retries, safe defaults, migrations) is tested against a mock in Lune and degrades cleanly in a local place where DataStores do not exist.

### Reuse from the fishing repo (copy and adapt, never edit in place)

| Take | From `C:\Users\stewa\Documents\Claude\Roblox\` | Change |
|---|---|---|
| Lune test runner and spec style | `tools\test\run.luau`, `src\ServerScriptService\Tests\TestRunner.luau` | Point at `src\shared` and `tests` |
| Gemini critics (Neon, Hydrogen, Carbon) | `tools\critic\critic.py`, `gemini.py`, `rubrics\` | New context text; new rubrics: look, sound, scare readability, age fit |
| ElevenLabs batch and ranking | `tools\audio\eleven.py`, `rank_all.py`, `audio\sounds.json` schema | Shuffle before ranking; add a voice mode for the tapes |
| Open Cloud upload routine | The pattern in `build\audio_ops.txt` and `audio\README.md` | Log operation id and asset id the moment each returns |
| Studio screenshots | `tools\capture-studio.ps1` | Target our own Studio window by process id |
| Blender script pipeline (M9 only) | `art\scripts\common.py`, `palette.py`, `roblox_colors.py` | New palette |
| CI | `.github\workflows\checks.yml` | Enforce StyLua and Selene from day one |

Keys: `ELEVENLABS_API_KEY` and `GEMINI_API_KEY` copy from `C:\Users\stewa\Documents\Claude\Roblox\.env` into the new ignored `.env`. `MESHY_API_KEY` (in `stand-in-the-door\.env` and `ranch-twin\.env`) and the Sketchfab token (in `Brainless\.env`) are only fetched if M9 needs them. Values are never printed or committed.

## Harness (built in M0, before features)

| Part | Here |
|---|---|
| Gate | One command: Selene, StyLua check, Lune tests, fast pacing sim, lints, `rojo build`, a Lune smoke test that opens the built place and checks its structure. Must pass before every commit |
| Truth tests | Lune specs for every Core module; property tests over hundreds of seeds (no scare inside a quiet window, budgets never exceeded, new rule always appears, one-player cues obey the fairness rule) |
| Scorecard | Bot nights in Lune, with history: a rule-following bot must clear a Normal run in at least 95% of 300 seeds; a rule-blind bot must be dead by night 2 in at least 90%; a greedy bot must show more scares; quota must be reachable in 60 to 80% of the night |
| Capture | Our own Studio window, launched on the built place; `DebugDriver` and `DebugBot` (Studio only) play named, seeded scenarios through the real remotes; stills and clips with audio at fixed shots, each with a sidecar (seed, commit, config) |
| Contact sheet | One image of every shot per checkpoint |
| Critic | Neon scores look, sound, scare readability and age fit on stills and clips. Advisory: scores steer, my eyes and ears decide |
| Performance | Part count, server step time, phone-sized client frame rate |
| Lints | No em dashes in anything a person reads, no asset id outside the logs, no secrets, no gore words in UI strings |

The gate, as Stewart would run it:

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\check.ps1"
```

## Milestones

Tags: [fable] main session, [builder] Opus, [grunt] Sonnet, [scout] Haiku lookups (Roblox APIs are checked against current docs and the Studio skills, never from memory), [verifier] Opus, [cloud] the cloud helper, [modeler] Fable. Every milestone ends with: gate green, verifier review, `docs\checkpoints\CP-0x.md`, PROGRESS.md updated, commit, push, then straight on to the next.

**M0 Setup, harness, and the three spikes**
- [fable] Create the folder and repo, the exclude line, `CLAUDE.md`, `DESIGN.md`, `ARCHITECTURE.md` with typed stubs, `PLAN.md`, `ROUTING.md`, `CLOUD-BRIEF.md`, PROGRESS, DECISIONS, HUMAN_TODO. Create the private GitHub repo and push.
- [grunt] Install Rokit from its official GitHub release (fallback `cargo install rokit`) and pin Rojo, Selene, StyLua, Lune and luau-lsp in `rokit.toml`. Copy and adapt the reuse table. Copy the two keys.
- [builder] `default.project.json`, `tools\check.ps1`, lints, the place smoke test, CI.
- [builder] Spike 1, the Studio loop: build, launch our own Studio on `DeadCalm.rbxl`, find it over MCP, play, run a hello scenario, capture a still, read a clean console, stop, close only the window we opened. Three clean passes in a row.
- [grunt] Spike 2, sound in a local place: generate one sound, upload it, prove it loads in the unpublished place.
- [fable] Spike 3, the cloud helper: start one cloud session on the new repo with `CLOUD-BRIEF.md`.
- Done when: the gate passes on the skeleton, `DeadCalm.rbxl` builds, CP-00 records each spike as pass or fallback.

**M1 The lake and its sound**
- [fable] Lookdev: lighting, fog and palette values; three key shots (lantern and beacon in fog, the shoreline, the dock at dusk); Neon look review, target 7 of 10.
- [builder] `WorldBuilder` (lake, dock, bait shack, shoreline trees, sunken steeple, old buoy, beacon), `BoatService` on `BoatModel` (four seats, oars and motor, server-owned), first-person camera.
- [cloud] `Rng`, `LakeMap`, `BoatModel`, `SoundMix`, `Lantern` with specs.
- [grunt] First sound batch: beds, chorus in three densities, boat foley, dock radio. Generate, rank, upload, log.
- [builder] `SoundRegistry`, `AudioDirector` with 3D sources.
- Done when: a bot rows dock to steeple to dock in Studio; the soundscape clip passes my ear and Neon's sound rubric; map and boat tests pass.

**M2 Fishing and quota**
- [cloud] `NightClock`, `Quota`, `FishTable`, `Fishing`, `WrongCatch` (trait mutation only), first `Night` composition, feasibility sim.
- [builder] `FishingService`, hold and cooler banking, night clear and fail flow, minimal HUD, reel bar, catch inspect.
- Done when: the bot plays a full quiet night start to finish in Studio; quota, clock and feasibility numbers pass.

**M3 Director, the Hum, death and the drowned**
- [cloud] `Attention`, `Director`, `EntityBase`, `Hum`, `Ghost`, property tests.
- [builder] `EntityPresenter`, chorus driven by tension, death card, spectate and bell, callout wheel.
- [grunt] Hum sound set and the first tapes.
- [fable] Review clips of Hum pass and Hum fail: is the cue learnable, is the fail readable and clip-worthy.
- Done when: director tests prove quiet windows and budgets; Hum tests pass; both clips exist and read correctly.

**M4 Rules 2 to 5, fake-outs, one-player cues**
- [cloud] `WrongCatch` consequences, `Neighbor`, `Knocking`, `Watcher`, `Fakeouts`, each with cue, counter and fail tests.
- [builder] One builder per rule's presentation, in parallel on separate files.
- [grunt] Sound sets for each.
- Done when: every rule has passing state machine tests and a pass clip and a fail clip I have watched.

**M5 The five-night run**
- [cloud] `Run` (night table), `Rulebook` amendments, `Finale`, Normal and Nightmare, solo scaling, `Supplies`, full-run bot sims.
- [builder] Finale chase, night transitions, tapes wired in, the supply pick.
- Done when: the night table is config-driven and tested; scorecard targets are met; a bot clears a seeded five-night run in Studio.

**M6 UI and phones**
- [builder] Title (Play, difficulty, Lake Rules), rulebook with taped-in pages and amendments, Field Guide, HUD (night, clock, quota, oil), end-of-night screen, mobile buttons for every verb.
- [fable] Review captures on the smallest phone size in the Device Simulator.
- Done when: UI loads with a clean console in Studio and every button is reachable on the phone layout.

**M7 Saves and Endless**
- [cloud] `Profile`, `Leaderboard`, cosmetics unlock rules, Endless night generator, mock-store tests.
- [builder] `DataService`, cosmetics (lantern colors, boat paint, two hats), the ordered-store stub, clearly marked Game Pass stub hooks with no ids.
- Done when: data tests pass against mocks and the game runs cleanly with no DataStores.

**M8 Polish and docs**
- [fable] Tune pacing from the scorecard and clips; final mix pass.
- [grunt] Remaining sounds; `SOUNDS_NEEDED.md` (every entry: uploaded id or still needed, with description, length and search terms).
- [builder] Extra fake-outs. [grunt] `PLAYTEST_GUIDE.md`, `MATURITY_NOTES.md`, `HUMAN_TODO.md`, README.

**Final self-review (required):** the brief's five steps, with each requirement listed Done, Partial or Not done in PROGRESS.md; the specific audit (untrusted input, scares inside quiet windows, scares without a cue, graphic content, invented ids, em dashes); a fresh-eyes [verifier] pass; final commit and push.

**M9 Stretch, only after the self-review is green:** [modeler] hero models by Blender script (boat, lantern, steeple, shack, the Watcher, dead trees), uploaded and laid over the part-built versions, which stay as the fallback.

**Cut line, in order, if time or usage runs short:** M9, the supply pick, drowned sight, amendments beyond the Knocking, the leaderboard stub. Never cut: the gate, death cards, phone buttons, the docs.

## How the run behaves

- **Routing:** per the table in `~/.claude/skills/fable-kickoff/ROUTING.md`. The subagents exist and no model override is set. Builders run in parallel only on separate files and the main session commits. The Agent tool's worktree option is not used (it would branch the fishing repo).
- **Cloud helper:** owns `src\shared\Core\`, `tests\` and `tools\sim\` on `claude/` branches. The local session owns everything else, reviews and merges when online. If a cloud session cannot be started for the new repo, the Core work moves to local builders and that goes in HUMAN_TODO.
- **One Studio lane:** only the main session drives Studio, in a window it launched, tracked by process id. It never closes or touches a Studio window it did not open (two are open now with no place loaded). Playtests are driven by debug scenarios, not simulated mouse and keyboard, so a second session using Studio does not collide.
- **Offline gaps:** every milestone is committed and pushed; PROGRESS.md always says what is done, what is next and how to resume. I will try a 30-minute repeating wake-up in this session that says "continue from PROGRESS.md" and remove it when the run ends; if that is not available, Stewart types "continue" after reconnecting.
- **Autonomy:** no questions during the run. Calls go in DECISIONS.md (one line each). Human-only steps go in HUMAN_TODO.md with exact steps. Nothing is published, nothing is bought, no products or passes are created. Stop only for a true blocker.

## Risks and fallbacks

| Risk | Fallback |
|---|---|
| Studio cannot be launched or reached unattended | Lune tests, clean `rojo build` and the place smoke test carry the run; Studio checks move to HUMAN_TODO; said plainly in PROGRESS |
| Private sounds do not play in an unpublished local place | Verified public Creator Store audio for beds and foley; signature sounds wait for Stewart's private publish; registry stays silent, never errors |
| Roblox monthly audio upload cap (the fishing game used 27 this month) | Upload in priority order: beds, chorus, Hum, fishing, then the rest; anything over the cap is listed in SOUNDS_NEEDED.md with its file ready |
| Moderation rejects a sound | One tamer regeneration, then a placeholder row |
| Hotspot drops mid-task | Cloud helper keeps going; local resumes from PROGRESS.md |
| Lune and Studio disagree | Own Rng, pure Core, and the same specs run inside Studio at each checkpoint |
| Scope | The cut line above |

## What I need from Stewart

1. **A permission mode that does not stop to ask.** I cannot change that myself, and an unattended run stalls at the first prompt.
2. **Leave the PC on and signed in**, with Roblox Studio signed in to his account. I will ask the app to keep the PC awake.
3. **In Studio's MCP Permissions**, confirm `C:\Users\stewa\Documents\Claude\Roblox` is still an approved upload folder (it should cover the new subfolder; if Studio wants the exact folder, add `C:\Users\stewa\Documents\Claude\Roblox\dead-calm`).
4. **Connection:** the local half only moves while the hotspot is home. Type "continue" here when you are back if it has not resumed.
5. **Afterward:** to play with Liam on two devices, you publish it privately yourself. Steps will be in HUMAN_TODO.md. Solo play and a two-player test on one PC work straight from the file.

## Verification

- The gate command above passes on every commit; CI repeats it on GitHub.
- Scorecard targets (rule-following bot, rule-blind bot, greedy bot, quota feasibility) are met and their history is saved.
- In Studio: each named scenario runs with a clean console; I watch every clip and read every contact sheet; Neon reports are filed in `docs\critic\`.
- A sound load report proves every nonzero id loads at the expected length.
- A fresh [verifier] judges each checkpoint against its "Done when" list without seeing the build narrative.
- The final self-review maps every line of the original brief to Done, Partial or Not done in PROGRESS.md.
