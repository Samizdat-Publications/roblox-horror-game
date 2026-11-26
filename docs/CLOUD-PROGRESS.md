# Cloud helper progress

Updated 11/26/2026. Chunks M1 and M2 were built locally in the working tree on `main` (not on `claude/` branches) by an Opus builder; the main session reviews and commits them. A cloud session resuming from here should start at Chunk M3.

## Done

**Core M1** (specs green)
- `src/shared/Core/LakeMap.luau`: inside, distanceToShore, nearestShorePoint, zoneAt, isSafe, canBank, randomPointInZone. Spec `tests/LakeMap.spec.luau`.
- `src/shared/Core/BoatModel.luau`: new, step (oars, motor, speedMult, reverse, drag, turning, shore stop), isStill, toObs. Spec `tests/BoatModel.spec.luau`.
- `src/shared/Core/Lantern.luau`: setOn, toggle, forceOut, lockOn, step (burn, OilLow, OilOut), refill. Spec `tests/Lantern.spec.luau`.
- `src/shared/Core/SoundMix.luau`: targets(cfg, view, facts) for Bed, three chorus layers, Crickets, Motor, Radio; approach for smoothing. Uses the new `Config.Mix`. Spec `tests/SoundMix.spec.luau`.
- `src/shared/Core/RateLimit.luau`: token bucket with caller time; forPlayer. Spec `tests/RateLimit.spec.luau`.
- `src/shared/Core/Validate.luau`: BoatInput, Gaze, Intent (every IntentKind), Lobby, Cosmetic, remote dispatch. Spec `tests/Validate.spec.luau`.

**Core M2** (specs green, pacing on target)
- `NightClock`, `Quota` (incl. `Quota.scaled` for crew size): spec `tests/NightClock.spec.luau`.
- `FishTable`, `WrongCatch`: spec `tests/FishTable.spec.luau`.
- `Fishing` (cast, bite window, reel bar, snap, slack, decide timer, cut, interrupt, publicCatch): spec `tests/Fishing.spec.luau`.
- `Night` (new, step, view, result, debugForce stub, loseHold helper): clock, fishing, hold, bank, quota, lantern and refills, motor, attention stub and chorus band, Wrong Catch traits and the teaching guarantee, four supplies, clear and fail. Spec `tests/Night.spec.luau`.
- `tools/sim/loader.luau` (loads src/shared under Lune), `tools/sim/crewbot.luau` (the rule-following crew bot), `tools/sim/pacing.luau` (the scorecard; writes `artifacts/score/pacing.md` and `.json`, or `pacing-fast.*` with `--fast`).

Spec summary: `TESTS: 94 passed, 0 failed, 11 spec files`.

## Pacing scorecard (200 seeds per cell)

| Night | Crew | Quota | Reached | Median | P10 | P90 | Trips | Thrown back | OK |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 13 | 100% | 0.64 | 0.58 | 0.76 | 3.3 | 0.0 | yes |
| 1 | 2 | 17 | 100% | 0.61 | 0.55 | 0.72 | 4.3 | 0.0 | yes |
| 1 | 3 | 20 | 100% | 0.69 | 0.64 | 0.74 | 5.0 | 0.0 | yes |
| 1 | 4 | 23 | 100% | 0.67 | 0.57 | 0.73 | 5.8 | 0.0 | yes |
| 2 | 1 | 12 | 100% | 0.71 | 0.62 | 0.81 | 3.0 | 3.3 | yes |
| 2 | 2 | 17 | 100% | 0.71 | 0.63 | 0.84 | 4.3 | 5.1 | yes |
| 2 | 3 | 19 | 100% | 0.72 | 0.65 | 0.77 | 4.9 | 6.1 | yes |
| 2 | 4 | 22 | 100% | 0.75 | 0.63 | 0.83 | 5.5 | 7.3 | yes |
| 3 | 1 | 12 | 100% | 0.67 | 0.59 | 0.76 | 3.0 | 2.0 | yes |
| 3 | 2 | 17 | 100% | 0.67 | 0.59 | 0.78 | 4.3 | 3.1 | yes |
| 3 | 3 | 19 | 100% | 0.70 | 0.62 | 0.76 | 4.9 | 4.3 | yes |
| 3 | 4 | 22 | 100% | 0.71 | 0.62 | 0.82 | 5.5 | 5.0 | yes |
| 4 | 1 | 12 | 100% | 0.67 | 0.60 | 0.80 | 3.0 | 2.3 | yes |
| 4 | 2 | 17 | 100% | 0.69 | 0.61 | 0.79 | 4.3 | 3.4 | yes |
| 4 | 3 | 19 | 100% | 0.70 | 0.60 | 0.76 | 4.9 | 4.4 | yes |
| 4 | 4 | 22 | 100% | 0.72 | 0.61 | 0.81 | 5.6 | 4.7 | yes |
| 5 | 1 | 13 | 98% | 0.76 | 0.64 | 0.88 | 3.4 | 3.0 | yes |
| 5 | 2 | 17 | 100% | 0.68 | 0.61 | 0.79 | 4.2 | 4.2 | yes |
| 5 | 3 | 20 | 100% | 0.72 | 0.67 | 0.78 | 5.0 | 5.3 | yes |
| 5 | 4 | 23 | 100% | 0.78 | 0.69 | 0.85 | 5.9 | 6.9 | yes |

Median and P10/P90 are the fraction of the night at which the quota was banked. Full scorecard: `artifacts/score/pacing.md`; baseline before tuning: `artifacts/score/pacing-baseline.md`.

## For the local session

- Config changed: `Config.Nights[1..5].quota` (10, 14, 18, 22, 26 became 23, 22, 22, 22, 23), `Config.Scaling.quota` (0.45, 0.7, 0.85, 1.0 became 0.55, 0.75, 0.86, 1.0), new `Config.Mix` table, new `Config.Fishing.biteInDockLight = false`. Details and reasons in `docs/CLOUD-DECISIONS.md`.
- Shell contracts that were not written down anywhere and are now fixed by Core: Lobby actions (`Validate.LOBBY`), HookLost reasons (Moving, DockLight, Missed, Snap, Slack, Cut, or a rule name via `Fishing.interrupt`), Released reasons (ThrownBack, HoldFull), `Caught.data.catch = { species, points, traits }`, `Callout.data.phrase`, Tape ids (Night1 to Night5, Endless, Amendment), `SoundMix.targets(cfg, view, { distToDock, alive, cue })`.
- No change was made to `Types.luau` or `ARCHITECTURE.md`. One gap: `NightParams` has no wrongChance or wrongTier; Night reads them from Config by night number.
- The server can build NightParams the way `storyParams` in `tools/sim/pacing.luau` does until `Core.Run` exists (M5).

## Next

Chunk M3: `Attention` (move the stub out of Night, same numbers), `Director` with property tests over 500+ seeds, `EntityBase`, `entities/Hum` (both variants), `Ghost`, deaths in `Night`, in-water drag; the crew bot answers the Hum; run nights to dawn in the sim; retune quotas with scares in.
