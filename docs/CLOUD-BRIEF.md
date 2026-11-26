# Cloud helper brief

You are the cloud helper for Don't Wave Back (code name Dead Calm), a co-op Roblox horror game. A local session (Fable 5.2, the orchestrator) owns Roblox Studio, sound, visuals and the server and client shell. The local PC is on a phone hotspot and goes offline for hours at a time. You keep the pure game logic moving while it is away. Nobody will answer questions: make the reasonable call, write one line in `docs/CLOUD-DECISIONS.md`, keep going.

## Read first

`CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN.md`, `src/shared/Core/Types.luau`, `src/shared/Config.luau`, then `docs/CLOUD-PROGRESS.md` if it exists (resume from it).

## What you own

- `src/shared/Core/**` (every pure rules module)
- `tests/**` (Lune specs)
- `tools/sim/**` (bot-night simulations and the pacing scorecard)
- `docs/CLOUD-PROGRESS.md` and `docs/CLOUD-DECISIONS.md`
- Gameplay numbers in `src/shared/Config.luau` (you may tune values and add fields; say what and why in CLOUD-DECISIONS)

Do not touch anything else: not `src/server`, `src/client`, `src/shared/Look.luau`, `Remotes.luau`, the registries, `tools/check.ps1`, `tools/lint`, `tools/studio`, `audio`, `art`, or the other docs. If a contract in `Types.luau` or `ARCHITECTURE.md` must change, make the change additive, and list it at the top of your pull request under "Contract changes".

You have no Roblox Studio. Everything you write must run under Lune. Follow the Core rules in `docs/ARCHITECTURE.md` exactly (strict, pure, `script.Parent` requires, config passed in, `Core.Rng` for all randomness).

## How to work

- Tools come from Rokit: install Rokit, run `rokit install`, then use `lune`, `selene`, `stylua`, `rojo`.
- Before every commit, run what the gate runs: `selene src`, `stylua --check src tests tools`, `lune run tools/test/run.luau`, `lune run tools/sim/pacing.luau --fast`, the lints in `tools/lint`, and `rojo build -o DeadCalm.rbxl`. All must pass.
- Work in the order below. One branch per chunk, named `claude/core-m1`, `claude/core-m2` and so on, each cut from the latest `main`. Push each branch when its chunk is done and open a pull request to `main` titled like "Core M2: fishing, quota, clock". Then start the next chunk on a new branch cut from your previous branch if `main` has not merged it yet.
- Commit small and often. No em dashes in any text. Dates as MM/DD/YYYY.
- Keep `docs/CLOUD-PROGRESS.md` current: done, in progress, next, anything the local session must know.
- Never publish anything, never add asset ids, never add network calls.

## The work, in order

**Chunk M1.** `LakeMap` (zone at a point, inside lake, distance to shore, nearest shore point, safe zone, random point in a zone), `BoatModel` (pure kinematics: throttle and steer to velocity and heading, oars and motor), `Lantern` (on, off, forced out, oil burn, refill), `SoundMix` (from a NightView and local facts, return target volumes for ambience layers: chorus band crossfade, motor masking, dock radio by distance, cue ducking), `RateLimit` (token bucket), `Validate` (payload shape and range checks for every remote in ARCHITECTURE.md). Specs for each.

**Chunk M2.** `NightClock`, `Quota`, `FishTable`, `Fishing` (cast, bite timing, the reel bar simulation, snap and slack), `WrongCatch` (mutate exactly one trait by tier; tier 1 obvious, 3 subtle; a Walleye's eyeshine is never the mutation), first `Night` composition (clock, fishing, hold, bank, lantern, refills, attention stub, clear and fail), `tools/sim/pacing.luau` with a rule-following bot that fishes and banks. Scorecard: the bot reaches quota in 60 to 80 percent of the night on nights 1 to 5 across 200 seeds, for crew sizes 1 to 4.

**Chunk M3.** `Attention`, `Director` (with the invariants in ARCHITECTURE.md proven by property tests over at least 500 seeds), `EntityBase`, `entities/Hum` (both amendment variants), `Ghost`, death handling in `Night`, in-water drag. The sim bot now answers the Hum.

**Chunk M4.** `entities/WrongCatch` consequences (cooler knock), `entities/Neighbor` (boat and false beacon variants, lantern-out amendment), `entities/Knocking` (three amendment variants, second round, flooding, bailing, sinking), `entities/Watcher` (edge of sight and stare-it-down variants, lunge, retreat), `Fakeouts`. Each rule has spec coverage for cue, correct counter, and fail, and for the fairness rule.

**Chunk M5.** `Run` (night table, scaling by crew size, difficulty, retry), `Rulebook` (rule text ids, amendments from the run seed with the Normal and Nightmare policies, death card text ids), `entities/Finale`, `Supplies`, Endless night generation. Full-run sims with three bots:
- the rule-following bot clears a Normal run in at least 95 percent of 300 seeds, and a Nightmare run in at least 70 percent;
- the rule-blind bot (fishes, ignores every cue) is dead by the end of night 2 in at least 90 percent;
- the greedy bot (keeps every wrong fish, always uses the motor) sees clearly more real scares than the rule-following bot.
Tune `Config` until these hold, and record before and after numbers in `artifacts/score/` and in CLOUD-PROGRESS.

**Chunk M7.** `Profile` (schema, defaults, migration by `SAVE_VERSION`, cosmetic unlock rules from DESIGN.md), `Leaderboard` (best Endless night ordering, top N), with specs that use an in-memory mock store exposing `GetAsync`, `SetAsync`, `UpdateAsync` that can be told to fail.

## Done looks like

Every chunk: specs green, sim targets met or the gap explained with numbers, a pull request open, CLOUD-PROGRESS updated. When all chunks are done, write "ALL CHUNKS DONE" at the top of `docs/CLOUD-PROGRESS.md` and stop.
