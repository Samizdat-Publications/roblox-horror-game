# Self-review against the original brief

Draft started 11/26/2026, late night. Every requirement from Cowork's "Dead Calm" brief, marked **Done**, **Partial** (with why) or **Not done** (with why), with where the proof is. Finished and audited at the end of the run; see PROGRESS.md for the summary.

Note: Stewart gave Fable 5.2 full creative control after the brief, so a few things deliberately differ from it (title, night length, the supply pick). Those are marked **Changed** with the reason.

## Ground rules

| Requirement | Status | Proof or reason |
|---|---|---|
| Work autonomously, log calls in DECISIONS.md | Done | `DECISIONS.md`, `docs/CLOUD-DECISIONS.md`, `docs/SHELL-DECISIONS.md` |
| Keep going through every milestone | Done (in progress overnight) | Commit history |
| Human-only steps in HUMAN_TODO.md | Done | `HUMAN_TODO.md` |
| Work only inside this folder; never modify the fishing repo | Partial | Two deliberate exceptions, both at Stewart's request: one local ignore line in the fishing repo's `.git/info/exclude`, and scrubbing a child's age and an account name from the fishing repo before Stewart had both repos made public. |
| Never publish to Roblox, never buy, no real product ids | Done | Nothing published. Stewart later allowed a private publish when useful; not done yet. `MonetizationStubs.luau` has no ids. |
| Commit after every milestone; PROGRESS.md current | Done | Commit history; `PROGRESS.md` |
| No em dashes | Done | `tools/lint/emdash.py` in the gate |

## Concept and loop

| Requirement | Status | Proof or reason |
|---|---|---|
| 5 nights, 10 PM to 5 AM, about 8 to 10 real minutes | Changed | Nights are 6 minutes, after Neon's design review (pacing for phone attention spans). `Config.Night.realSeconds = 360`. |
| Per-night quota to the dock cooler | Done | Core.Quota, cooler banking; Studio quiet_night cleared |
| 1 to 4 players in one boat; solo scaled | Done | Four seats; `Config.Scaling`; sims for crews 1 to 4 |
| Non-graphic death; ghost spectate with limited help; whole crew gone restarts the night | Done | Death cards, drowned view, ghost bell; Studio checks |
| Procedural lake with dock, shack, trees, steeple, buoy | Done | `src/server/world/*`; stills in `docs/making-of/stills` |
| Cast, bite, reel minigame with a tension zone | Done | Core.Fishing, ReelBar; Studio fish_once |
| 6 to 8 species with a Field Guide page each | Done | 8 species in Config.Fish; Field Guide card and page |

## Lake Rules (entities)

| Requirement | Status | Proof or reason |
|---|---|---|
| The Hum: cue, counter, fail | Done | entities/Hum; Studio hum_pass and hum_fail; Neon reviews |
| Wrong Catch | Done | entities/WrongCatch, FishMutations; Studio wrongcatch scenarios |
| The Neighbor | Done, reworked | Hunts lantern light and fakes callouts (Neon's design review) |
| The Knocking | Done | entities/Knocking; flooding and bailing |
| The Watcher on the Shore | Done | entities/Watcher; gaze tracking |
| Finale: the Lake Wakes | Done | entities/Finale; Studio finale scenario cleared |
| One new entity per night | Done | Config.Nights |
| Fake-outs | Done | Core.Fakeouts; 8 kinds |
| Some cues to one player only | Done | `only` on events; fairness rule tested |

## Scare director

| Requirement | Status | Proof or reason |
|---|---|---|
| Tension with calm, build, peak | Done | Core.Director |
| Guaranteed quiet windows | Done | Property tests: 2,500 nights, 0 violations |
| Per-night budget of scares and fake-outs, growing | Done | Config.Nights |
| Randomized from a logged per-run seed | Done | Core.Rng; seed in NightStarted |
| Normal and Nightmare; solo longer warnings | Done | Config.Difficulty, Config.Scaling |
| All timings in one config module | Done | `src/shared/Config.luau` |

## Atmosphere, audio, visuals

| Requirement | Status | Proof or reason |
|---|---|---|
| Night lighting, fog, lantern as main light with flicker, dock beacon, lantern oil | Done | Look.luau; LightingController; WorldFx |
| SoundRegistry with named entries, 3D sounds, layered ambience | Done | `SoundRegistry.luau`; AudioDirector |
| SOUNDS_NEEDED.md | Done | `SOUNDS_NEEDED.md` |
| Never invent asset ids; missing sounds fail silently | Done | `tools/lint/asset_ids.py`; every id is an upload, a verified library asset or derived |
| Blocky, procedural, silhouette monsters | Done | world and fx modules |

## Content rules, UI, progression, tech

| Requirement | Status | Proof or reason |
|---|---|---|
| No gore; Mild to Moderate fear; MATURITY_NOTES.md | Done | `MATURITY_NOTES.md`; ui words lint |
| Title with Play, difficulty, Lake Rules | Done | ui/Title |
| Rulebook with taped-in pages | Done | ui/Rulebook; amendments |
| Field Guide page | Done | ui/FieldGuide and CatchInspect card |
| Minimal HUD; end-of-night screen | Done | ui/HUD; NightCards with tallies |
| Mobile buttons | Done, phone check pending | ui/MobileButtons; Device Simulator check is still to do |
| Endless Nights, best-night board stub with graceful fallback | Done | Core.Run Endless; OrderedDataStore adapter with memory fallback |
| DataStore saves with pcall, retries, defaults | Done | DataService and Core.SaveLogic; mock-store specs |
| Cosmetics earned by play; Game Pass stub hooks, no ids | Done | Cosmetics, Locker, MonetizationStubs |
| Rojo, Rokit, Selene, StyLua, Lune, luau-lsp | Partial | All pinned and used except luau-lsp type analysis, which needs a Roblox definitions file that was not downloaded |
| `--!strict`, standard layout, small modules | Done | Every Core file is strict (core purity lint) |
| Server authority, validated remotes | Done | Net, Core.Validate, Core.RateLimit |
| Pure logic tested with Lune; one check command | Done | `tools/check.ps1`: 205 specs and 3 sims |
| Studio MCP used to verify in-engine | Done | Scenarios, captures, clips, Neon reviews |
| `rojo build` makes DeadCalm.rbxl | Done | Gate step 10 |
| Private repo under Samizdat-Publications, pushed | Changed | Created private, made public later at Stewart's request |

## Milestones

| Milestone | Status |
|---|---|
| M0 to M5 | Done |
| M6 UI and mobile | Partial until the phone check |
| M7 Persistence and Endless | Done (memory fallback verified; real DataStores need a published place) |
| M8 Polish and docs | In progress |

## Specific audit (to run at the end)

- [ ] Untrusted client input
- [ ] Entities firing inside a guaranteed quiet window
- [ ] Any scare without a learnable cue
- [ ] Gore or graphic content
- [ ] Invented asset ids
- [ ] Em dashes in text
