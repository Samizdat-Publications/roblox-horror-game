# Cloud helper progress

ALL CHUNKS DONE (M1 to M5 and M7; M6 is not a Core chunk). Updated 11/26/2026. Chunks M1 to M7 were built locally in the working tree on `main` (not on `claude/` branches) by Opus builders; the main session reviews and commits them.

## Design review changes (11/26/2026)

From `docs/reviews/2026-11-26-gemini-hydrogen-verdict.md` (points 1, 4, 5, 6, 8) plus two main-session calls. Details and every Config change in `docs/CLOUD-DECISIONS.md` (section "Design review changes").

- Rules pause in the dock light (`Night.rulePaused`); the director still never starts one there; dawn still ends the night.
- Bites fall off near the dock (`Fishing.dockFactor`, `Config.Fishing.dockFalloff = { from = 80, to = 200 }`); `biteInDockLight` stays false.
- A deciding timeout throws the fish back (`Released` with data.timeout = true; `Config.Fishing.timeoutKeeps = false`).
- Solo Neighbor: no fake callouts. Watcher: `PlayerObs.touch` widens both cones by `touchConeBonus` (15 degrees).
- A Hum fail turns the motor off and emits `MotorChanged` (entity "Hum", data.on = false).
- `Core/WrongCatch.luau` (traits) renamed `Core/FishMutations.luau`, with a shim at the old name for `src/server/DebugCrew.luau`. Core no longer sets `NightParams.supplies`.
- Nightmare retries 1 (was 2). Quotas retuned for the falloff (see decisions).
- Sim bots fish where fish bite and leave the light under a paused rule; the contract audit counts only rule time and checks that no rule resolves while paused.

For the shell: fill `PlayerObs.touch` from the client's input type; show `Released.data.timeout`; switch `DebugCrew` to `Core.FishMutations`, then the shim can go.

## Core M5 and M7 (11/26/2026)

**Core M5** (specs green)
- `src/shared/Core/Run.luau`: night table, rules accumulate, crew and difficulty scaling (solo warns longest), retries with a fresh night seed and the same page (Normal 3, Nightmare 2 per run), RunCleared after night 5, RunOver when out of retries, Endless from night 6 (random rule mixes and amendments from the run seed, growth with caps, one life). Supplies cut: `supplyChoices` returns {}.
- `src/shared/Core/Rulebook.luau`: rule text ids and English, the page, amendment policies (Normal first run: one amendment on night 5; later runs, Nightmare and Endless: any amendable rule any night from amendFromNight), tapes, death card ids and English for every cause.
- `src/shared/Core/entities/Finale.luau` and Night wiring: the 4 AM bell, silence, lantern locked on with the oil as the clock, director rules let go, director stopped, Neighbor boats and false beacons on a fast clock, stopping too long, the dark, waving, `EntityStrike` (takes a player, the finale goes on), pass home with a true Steeple Cat aboard or banked (hold banked, night cleared at once), dawn without it fails "SpecialOrder" or "NotHome". The first fish hooked where and when the Steeple Cat bites is one (`Rules.Finale.firstOrderSure`).
- Nights start with the lantern lit (Studio playtest fix).
- Sims: `tools/sim/run.luau` (whole runs through Core.Run, three bots, Normal and Nightmare, crews 1 to 4, Endless), crewbot plays night 5 (steeple run, finale escape), pacing night 5 needs 85% reached.

**Core M7** (specs green)
- `src/shared/Core/Profile.luau`: schema (SAVE_VERSION 1), defaults, migration from version 0, repair of bad data, "Future" saves read-only, stats, sticky cosmetic unlocks exactly per DESIGN.md, equipped validated against unlocks, merge that never loses progress.
- `src/shared/Core/Leaderboard.luau`: best Endless night order (night, then earlier, then user id), top N with shared ranks, submit, encode for an ordered store.
- `src/shared/Core/SaveLogic.luau`: retries with backoff (store and sleep passed in), load (outage gives defaults with canSave false), save through UpdateAsync with merge, never over a future save, submitBest only raises.
- Specs: `tests/Run.spec.luau`, `tests/Rulebook.spec.luau`, `tests/Finale.spec.luau`, `tests/Profile.spec.luau` (in-memory mock store with GetAsync, SetAsync, UpdateAsync that can be told to fail).

Spec summary: `TESTS: 198 passed, 0 failed, 18 spec files`. Gate: `GATE PASS: 11 steps`.

### Full-run scorecard (300 seeds per cell, first runs; `artifacts/score/run.md`)

| Difficulty | Crew | Follow: run cleared | Finale passed per try | Blind: death by night 2 | Greedy: real scares per night | Follow: real scares per night |
|---|---|---|---|---|---|---|
| Normal | 1 | 100% | 79% | 100% | 3.60 | 2.60 |
| Normal | 2 | 100% | 79% | 100% | 4.00 | 3.00 |
| Normal | 3 | 100% | 85% | 100% | 4.20 | 3.00 |
| Normal | 4 | 100% | 85% | 100% | 4.20 | 3.00 |
| Nightmare | 1 | 98% | 82% | - | - | 3.00 |
| Nightmare | 2 | 99% | 80% | - | - | 3.20 |
| Nightmare | 3 | 99% | 79% | - | - | 3.40 |
| Nightmare | 4 | 100% | 84% | - | - | 3.40 |

Before tuning (10 and 40 seed probes, night 5 quota 12.4, no order guarantee): Normal run cleared 70% solo and 90% crew of 4, finale passed on 25% to 56% of tries. Endless (follow, Normal, 75 seeds): best night median 10 to 12, max 16 to 21. Nightmare clears nearly as often as Normal for this bot because retries absorb night 5; its real scares per night are higher (3.0 to 3.4 against 2.6 to 3.0). If Nightmare should be harder for careful crews, cut its retries or shorten `Rules.Finale.oilSeconds` there.

### For the local session (M5 and M7)

- Contract additions (additive): `EntityObs.specialAboard`, `NightResult.bankedFish`, event `EntityStrike` (entity Finale, data.effects; Night applies it like a fail but the finale goes on), Finale `EntityCue.data` { bell, oilSeconds, stopLimit, needSpecies }, Finale `EntityMoved.data` { hazard, form, pos, appear?, gone? }, `EntityPass.data.endedBy = "Finale"`, `NightFailed.data.reason` "SpecialOrder" or "NotHome", `Run.finishNight` may return "RunOver", `Run.setPlayers`, `Run.view`. None of these are in ARCHITECTURE.md yet (not edited by the helper).
- NightService can now call `Run.new` and `Run.nightParams` at its SEAM. DataService can use `SaveLogic.load(cfg, DataStore, key, { sleep = task.wait })` and save with `allowed = result.canSave`.
- Death card and rule English: `Rulebook.TEXT`; `Rulebook.deathCard(id)` for any `PlayerDied.data.text`.

## Done (earlier chunks)

**Core M1** (specs green): LakeMap, BoatModel, Lantern, SoundMix, RateLimit, Validate.

**Core M2** (specs green): NightClock, Quota, FishTable, Fishing, WrongCatch (traits), first Night, the pacing sim.

**Core M3** (specs green)
- `src/shared/Core/Attention.luau`: value and floor (motor, lantern, reeling, decay, dock drain, kept wrong fish).
- `src/shared/Core/Director.luau`: calm, build, peak; quiet gaps; real and fake budgets; teaching first, inside the band; attention shortens calm, earns one bonus scare, allows an overlap when very high; chorus band from tension; log. Property tests: `tests/Director.spec.luau`.
- `src/shared/Core/EntityBase.luau`: the stage machine and the fairness gate (one cue, one outcome, no fail before the warning time, 12 s for a solo cue).
- `src/shared/Core/entities/Hum.luau` (LanternOut and LanternLit), `src/shared/Core/Ghost.luau` (the bell).
- `Night`: the rules, the Director, deaths with death card text ids, whole crew lost, in-water drag, the leak, bailing and sinking, chorus silence, ChorusDip, `debugForce` really starts a rule, per-player tallies in the result.

**Core M4** (specs green)
- `src/shared/Core/entities/WrongCatch.luau` (the cooler knock), `Neighbor.luau` (reworked boat, false beacon, NoWaveRowAway, fake callouts), `Knocking.luau` (AnswerTwo, AnswerOne, AnswerNone, second round, flood), `Watcher.luau` (EdgeOfSight, StareItDown, lunge, steps, retreat, solo first sighting), `src/shared/Core/Fakeouts.luau`.
- Specs: `tests/Rules.spec.luau` (each rule and variant: cue, counter, fail, fairness), `tests/NightRules.spec.luau` (Night with the rules in).
- Sims: `tools/sim/crewbot.luau` (follow, blind, greedy), `tools/sim/params.luau`, `tools/sim/rules.luau` (writes `artifacts/score/rules.md` and `.json`).

Spec summary: `TESTS: 145 passed, 0 failed, 14 spec files`.
Director property tests: 500 seeds x 5 nights = 2500 nights, 1,940,671 checks, 8,618 real spawns, 9,232 fake-outs, 0 violations (plus 150 nights at dt 0.1, 0 violations).

Design changes from the main session (11/26/2026) are applied: Neighbor rework with fake callouts, glanceable wrong fish tells, 360 s nights, no supplies, per-player tallies. Details in `docs/CLOUD-DECISIONS.md`.

## Pacing scorecard (200 seeds per cell, rule-following bot answering every rule, stops at quota)

| Night | Crew | Quota | Reached | Median | P10 | P90 | OK |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 7 | 100% | 0.65 | 0.57 | 0.70 | yes |
| 1 | 2 | 9 | 100% | 0.67 | 0.48 | 0.75 | yes |
| 1 | 3 | 10 | 100% | 0.70 | 0.63 | 0.76 | yes |
| 1 | 4 | 12 | 100% | 0.65 | 0.60 | 0.68 | yes |
| 2 | 1 | 6 | 100% | 0.72 | 0.62 | 0.86 | yes |
| 2 | 2 | 8 | 100% | 0.65 | 0.58 | 0.77 | yes |
| 2 | 3 | 9 | 100% | 0.73 | 0.50 | 0.84 | yes |
| 2 | 4 | 10 | 100% | 0.75 | 0.62 | 0.82 | yes |
| 3 | 1 | 6 | 98% | 0.71 | 0.55 | 0.83 | yes |
| 3 | 2 | 9 | 98% | 0.71 | 0.52 | 0.82 | yes |
| 3 | 3 | 10 | 99% | 0.75 | 0.62 | 0.84 | yes |
| 3 | 4 | 12 | 100% | 0.72 | 0.61 | 0.84 | yes |
| 4 | 1 | 7 | 100% | 0.63 | 0.54 | 0.83 | yes |
| 4 | 2 | 10 | 100% | 0.66 | 0.54 | 0.81 | yes |
| 4 | 3 | 12 | 100% | 0.64 | 0.58 | 0.76 | yes |
| 4 | 4 | 13 | 98% | 0.65 | 0.54 | 0.87 | yes |
| 5 | 1 | 6 | 94% | 0.63 | 0.52 | 0.91 | yes (M5: Finale night, needs 85%) |
| 5 | 2 | 9 | 90% | 0.63 | 0.49 | 0.91 | yes |
| 5 | 3 | 10 | 94% | 0.64 | 0.55 | 0.91 | yes |
| 5 | 4 | 11 | 94% | 0.63 | 0.56 | 0.91 | yes |

## Rules scorecard

See `artifacts/score/rules.md` (200 seeds per cell, nights 1 to 4 to dawn, three bots). Headlines: the rule-following bot survives 100% of nights in all 16 cells, as printed and on random amendments, and clears 96% to 100%; the rule-blind bot loses someone on 86% to 100% of nights (night 1 and 2 solo and duo crews are wiped 82% to 100%); the greedy bot sees more real scares (median 3 to 6 against 1 to 4) and starts dying on night 4 (91% to 95% survival). Shortest gap between real scares: 62 to 73 s on nights 1 to 3, 42 s on night 4 crews of 2 to 4, 16.4 s once for a solo night 4 (an attention overlap, allowed by design). Rule contract audit over every simulated night: 70,612 checks, 0 violations.

## For the local session

- Contract additions (all additive, `Types.luau`): EntityObs.lanternCanLight, lastLantern, lastMotor; Traits.wrongEyeDir, flipFin; PlayerTally and NightResult.tallies; NightParams.supplies optional. `Director.resolved` takes an optional time.
- Gaps in ARCHITECTURE.md (not edited): the new event kind `EntityMoved` (entity, data { pos, step or phase }); the Neighbor's fake `Callout` events (entity = "Neighbor", player = data.as, data.fake = true) that the shell must show like real callouts; fail effects in `EntityFail.data.effects` (kill, cause, loseHold, rock, snuff, flood, eatBanked, eaten, blame, silhouette); `EntityCue.data.warn`; `PlayerDied.data.text` = "Death.<Rule>.<Cause>"; `NightFailed` reason "Sunk"; `Flooding.data.leak`.
- Config changed: see the tables in `docs/CLOUD-DECISIONS.md` (360 s nights and everything rescaled, quotas 12, 10, 11.6, 13.4, 12.4, teachTo 0.55, new Director and Neighbor and Watcher fields, amendment NoWaveRowAway, new trait flags on every fish).
- `src/client/ViewState.luau` reads `Config.Night.realSeconds` (now 360); nothing else in the shell needed a change for Core to work.
- Studio scenarios can call `Night.debugForce(state, rule, { variant, teaching, only, form })`; "WrongCatch" makes the next fish hooked a wrong one; "Finale" is a no-op until M5.

## Next

Nothing left in the brief. Open questions for the orchestrator are flagged ASSUMED in `docs/CLOUD-DECISIONS.md` (retry limits, Blue Hour as night 10, pacing night 5 at 85%, new text lines in Rulebook).
