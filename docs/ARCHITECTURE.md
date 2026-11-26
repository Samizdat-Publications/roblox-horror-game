# Architecture

Stack: Roblox, strict Luau, Rojo 7.7.1 project, tools pinned by Rokit (`rokit.toml`): Rojo, Selene 0.32.0, StyLua 2.6.0, Lune 0.11.1, luau-lsp 1.70.1. Tool binaries live in `%USERPROFILE%\.rokit\bin`.

## The one idea

Functional core, thin shell. All rules live in pure modules under `src/shared/Core`. The server and the Lune simulator both drive the same function:

```
Core.Night.step(state, input) -> { Event }
```

The server builds `input` from the real world (boat physics, player seats, gaze, validated intents), calls `step` at `Config.Night.tick`, and turns the returned events into remotes, sounds and world changes. The simulator builds `input` from bots. Tests therefore cover what ships.

## Layout and Rojo mapping

| Folder | Becomes in the place | Owner |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | see below |
| `src/shared/Core` | `ReplicatedStorage.Shared.Core` | cloud helper |
| `src/server` | `ServerScriptService.Server` | local |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | local |
| `tests`, `tools/sim` | not in the place | cloud helper |
| everything else | not in the place | local |

File naming follows Rojo: `X.server.luau` is a Script, `X.client.luau` is a LocalScript, `X.luau` is a ModuleScript, a folder is a Folder. Do not use `init.luau` files. Lighting, SoundService and StarterGui properties are set by code at runtime, not in the project file.

## Core rules (apply to every file under `src/shared/Core`)

- `--!strict` at the top.
- Pure: no `game`, no services, no Instances, no `task`, `wait`, `os.clock`, `tick`, `math.random`, `Random.new`. Time arrives as `dt`. Randomness comes from `Core.Rng`.
- Allowed: `math`, `table`, `string`, `bit32`, `type`, `typeof`, `assert`, `error`, `pairs`, `ipairs`, `tostring`, `tonumber`, `select`, `setmetatable`.
- Requires use the instance form so they work in Roblox and in the Lune runner (which fakes `script`): `require(script.Parent.Rng)`, and from `Core/entities`: `require(script.Parent.Parent.Types)`.
- Config is passed in (`cfg`), never required from inside Core, so tests can pass altered copies. The type is `typeof(require(Shared.Config))`.
- State is plain tables. Functions take state and return events. No hidden globals.
- Positions are `Vec2` (`{x, z}`), never `Vector3`.

## Contracts

Types are in `src/shared/Core/Types.luau`. That file is the source of truth and is additive only.

### Rng

```
Rng.new(seed: number) -> RngState
Rng.next(r) -> number            -- [0, 1)
Rng.int(r, lo, hi) -> number     -- inclusive
Rng.range(r, lo, hi) -> number
Rng.pick(r, list) -> T
Rng.weighted(r, { [key]: weight }) -> key   -- iterate keys in sorted order for determinism
Rng.fork(r, label: string) -> RngState      -- an independent stream derived from seed and label
```

Same seed, same stream in Lune and in Roblox. Each subsystem forks its own stream ("director", "fish", "rule:Hum") so adding a draw in one place never shifts another.

### Night

```
Night.new(cfg, params: NightParams) -> NightState
Night.step(state, input: NightInput) -> { Event }
Night.view(state) -> NightView
Night.result(state) -> NightResult?      -- nil until the night is cleared or failed
Night.debugForce(state, rule: RuleId, opts) -- Studio scenarios and tests only: start a rule now
```

`Night` owns all rule state: clock, quota, hold, banked, lantern and oil, motor flag, each player's fishing state and alive flag, flood level, attention, the director and the active rules. The world owns only physics and presentation.

### Run

```
Run.new(cfg, { seed, difficulty, mode, playerIds, firstRun }) -> RunState
Run.nightParams(run) -> NightParams
Run.finishNight(run, result: NightResult) -> "NextNight" | "RetryNight" | "RunCleared"
Run.supplyChoices(run) -> { string }     -- three supply ids, from the run seed
Run.chooseSupply(run, id)
```

### Director

```
Director.new(cfg, rng, params: NightParams) -> DirectorState
Director.step(d, dt, ctx) -> { Decision }
   ctx = { attention, activeReal, safe, timeLeft, elapsed, eligible: { RuleId }, aliveIds: { PlayerId } }
   Decision = { kind = "Spawn", rule, teaching: boolean, only: PlayerId? }
            | { kind = "Fakeout", id, only: PlayerId? }
            | { kind = "Chorus", band }
Director.resolved(d, rule, passed: boolean)
Director.log(d) -> { { t, kind, id } }   -- for tests and seed replay
```

Invariants the tests must prove over hundreds of seeds: no real spawn inside the opening grace, inside a quiet gap, or while the boat is in the dock light; real and fake budgets never exceeded; each of tonight's new rules spawns at least once, inside the teaching band, with `teaching = true`; no fake-out within `fakeClear` seconds of a real cue; a real cue with `only` set leaves at least `soloCueMinSeconds`; never more than `maxConcurrent` real rules active.

### Rule modules (`Core/entities/<RuleId>.luau`)

```
Rule.id: RuleId
Rule.new(cfg, rng, ctx) -> RuleState     -- ctx = { variant, teaching, warningScale, only, boat, aliveIds, map }
Rule.step(state, obs: EntityObs) -> { Event }
Rule.stage(state) -> EntityStage
Rule.done(state) -> boolean
```

`EntityBase` holds the shared stage machine (Idle, Cue, Window, Pass, Fail, Cooldown) and helpers. Every rule emits `EntityCue` when its cue starts, `EntityStage` on each change, and exactly one of `EntityPass` or `EntityFail` before it is done. A rule never kills without having emitted its cue at least `warn` seconds earlier.

### Events

`kind` is one of the following. `data` fields are in parentheses.

| Group | Kinds |
|---|---|
| Night | `NightStarted` (night, seed, quota), `RuleUnlocked` (rule), `Tape` (id), `QuotaMet`, `NightCleared` (result), `NightFailed` (reason, result) |
| Fishing | `CastOut`, `Bite`, `HookLost` (why), `Caught` (catch without the `wrong` flag), `Released`, `Kept` (points), `Banked` (count, points), `HoldLost` (count) |
| Boat and light | `LanternChanged` (on, forced), `OilLow`, `OilOut`, `OilRefilled`, `MotorChanged` (on), `BoatRocked`, `Flooding` (level), `Sunk` |
| Director | `Chorus` (band), `Fakeout` (id) |
| Rules | `EntityCue` (variant, teaching, plus rule data such as positions), `EntityStage` (stage), `EntityPass`, `EntityFail` (effects) |
| Players | `PlayerDied` (rule, variant, text id), `DragWarning`, `GhostBell`, `Callout` (phrase) |

The `wrong` flag of a catch never leaves the server.

Added in Core M3 and M4 (11/26/2026):

- `EntityMoved` (rule, position data): an entity changed place (the Neighbor drifting, the Watcher stepping).
- `EntityCue.data.warn`: seconds until the counter is enforced.
- `EntityFail.data.effects`: what the fail does (hold lost, lantern out, flood, take player), for the shell to present.
- `Callout` with `data.fake = true` and `player = data.as`: the Neighbor speaking as a crewmate. The shell shows it exactly like a real callout and never reveals it is fake.
- `PlayerDied.data.text` uses ids of the form `Death.<Rule>.<Cause>` for the death card.
- `NightFailed.data.reason` can be `Sunk`. `Flooding.data.leak` says whether water is still coming in.
- `NightResult.tallies`: per-player stats for the end-of-night card (see `PlayerTally` in Types).

### Other Core modules

`NightClock`, `Quota`, `LakeMap` (zone at a point, inside lake, distance to shore, nearest shore point, safe zone), `FishTable` (pick species by zone and hour), `Fishing` (cast, bite, reel bar), `WrongCatch` (mutate one trait by tier), `BoatModel` (pure kinematics for sims and for the server's target velocity), `Lantern`, `Attention`, `Fakeouts`, `Rulebook` (rule text ids, amendments from the seed, death card text ids), `Ghost`, `Supplies`, `SoundMix` (what the ambience layers and ducking should be, from a NightView), `RateLimit` (token bucket), `Validate` (payload checks), `Profile` (save schema, defaults, migration, cosmetic unlock rules), `Leaderboard` (ordered best-night logic).

## The shell

### Server (`src/server`)

- `Main.server.luau`: builds the world, starts services.
- `Net.luau`: creates the remotes in `Remotes.luau`, validates every client message (`Validate`), rate limits per player (`RateLimit`), checks distance where it matters (banking needs the boat at the dock), then queues an `Intent`.
- `LobbyService`: title flow, difficulty pick by the host, start, late joiners wait as the drowned until the next night.
- `NightService`: owns the `RunState` and `NightState`, runs the tick, gathers observations, drains intents, dispatches events, sends the `NightView` to clients on change (at most 10 per second).
- `BoatService`: the physical boat (unanchored, server network owner, driven toward `BoatModel`'s target velocity), four seats, helm input.
- `FishingService`, `EntityPresenter`: turn fishing and rule events into world objects and client effects.
- `WorldBuilder` and `world/*`: build the lake from parts using `Config.Lake`.
- `LightingController`: night look from `Look.luau`.
- `DataService`: loads and saves `Profile` through a store adapter (real DataStore, or memory when DataStores are unavailable). pcall, retries with backoff, safe defaults.
- `DebugDriver` (only when `RunService:IsStudio()`): named, seeded scenarios for captures and checks.

### Client (`src/client`)

- `Input`: keyboard, touch and gamepad all map to the same intents.
- `Camera`: first person locked while seated; reports gaze yaw at `Config.Net.gazeHz`.
- `AudioDirector`: builds sounds from `SoundRegistry`, mixes ambience from `SoundMix`, plays cues at world positions.
- `ui/*`: all UI is built in code.
- `fx/*`: one module per rule's presentation.
- `DebugBot` (Studio only): plays scenarios through the real remotes.

### Remotes

Client to server (intents): `BoatInput(throttle, steer)`, `Gaze(yaw)`, `Intent(kind, num?, flag?, text?)`, `Lobby(action, value?)`, `Cosmetic(slot, id)`. Server to client: `View(nightView)`, `Events({Event})`, `LobbyState(state)`, `Profile(profile)`. Nothing else. A client can never send a catch, a quota change or a death.

### Registries

`SoundRegistry.luau` and `AssetRegistry.luau` map names to `{ id, volume, looped, spatial, group, ... }`. Id `0` means "not available yet": the shell skips it without error. Every nonzero id must be listed in `audio/ids.json` or `art/ids.json` with its source (our upload operation, or a verified Creator Store asset). The gate fails otherwise.

## Tests and the gate

- Specs live in `tests/*.spec.luau` and return `function(t, Shared)`, using `t.test(name, fn)`, `t.ok(cond, msg)`, `t.eq(a, b, msg)`. They require modules as `require(Shared.Core.Rng)`.
- `lune run tools/test/run.luau [filter]` runs them outside Studio by faking `script` and `require`.
- `tools/sim/*.luau` are bot-night simulations that write the pacing scorecard to `artifacts/score/`.
- `tools/check.ps1` is the gate: Selene, StyLua check, specs, the fast sim, lints (em dash, asset ids, secrets, banned words in UI strings, Core purity), `rojo build -o DeadCalm.rbxl`, and a Lune smoke test that opens the built place and checks its structure. It exits non-zero on any failure.

## Studio lane

`tools/studio/launch.ps1` starts Roblox Studio on `DeadCalm.rbxl` and writes the process id to `artifacts/studio.pid`. `tools/studio/close.ps1` closes only that process. The main session finds the instance over the Studio MCP (`list_roblox_studios`), plays, runs a `DebugDriver` scenario, captures, reads the console, stops, closes. Never touch a Studio process that is not in `artifacts/studio.pid`.
