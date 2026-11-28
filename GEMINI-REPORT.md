# Gemini Handoff Report: Don't Wave Back (Dead Calm)

Date: 11/27/2026  
Baseline commit: `8b5586a` ("Baseline from Claude")  
Plan: [docs/GEMINI-PLAN.md](docs/GEMINI-PLAN.md)

---

## 1. Honest Review: Senior Roblox Developer & Horror Designer

### What Is Strong
- **Clean Core vs. Shell architecture:** `src/shared/Core` has zero Roblox engine dependencies (`lint: core purity` enforces this in CI), so the Director fairness checks (`500 seeds x 5 nights = 2,500 nights`, `1,940,671` checks, `0` violations) and crew bot simulations (`pacing sim --fast`, 20 night/crew cells all on target) prove balance and rule pacing deterministically without launching Studio.
- **Audio-visual redundancy for phone and sound-off play:** Nearly every threat pairs audio with physical boat feedback (`BoatFx.buzz` vibrating floorboards, `shiver` lantern flicker, spatial emitters, `Rulebook` paper UI updates, and `Drowned` ghost outlines + `GhostBell` ripple cues so an eliminated player stays useful to a living crewmate).
- **Tight static part budget with hero fallback:** The world and boat total `1,646` parts against a `2,500` budget (built cleanly via `rojo build -o DeadCalm.rbxl`), and `HeroLook.hide` hides primitive planks cleanly without stripping attachments, colliders, lights, or seats when Blender meshes load.
- **Replay foundation already in place:** Deterministic run seeds, Rulebook amendments, Nightmare mode, Endless Nights leaderboard (`DeadCalmBestEndless_v1`), and unlocked Locker cosmetics provide strong post-story hooks.

### What Is Weak
- **Boat motion and casting first impressions:** In the baseline build, `OarPort` and `OarStarboard` sat statically welded inside the hull while rowing moved the boat forward, and `HelmSeat` cast 135 degrees behind the player's back off the stern into pitch darkness (`(+0.7, 0, +0.7)`). Both are fixed in this handoff (`4d3344a`, `5563681`), though visual Studio verification could not be run safely here.
- **Unmixed custom audio (`11/27/2026` upload batch):** All 50 ElevenLabs takes were peak-normalized to `-3 dB` against older stand-in curves. Specific cues (`night-failed-sting = 0.5`, `knock-pass = 1.5`, `neighbor-fail = 0.65`, `lanterns-die = 0.5`, `watcher-lunge = 9.14`, `hum-mid-voice = 0.6`) still need a true by-ear listening pass on PC headphones and a phone speaker.
- **Strange boat silhouette discrepancy:** `HeroLook` upgrades the player boat, lantern, shack, steeple, dead trees, and the Watcher, leaving the standing figure on `Neighbor` and `Finale` strange boats built out of blocky primitives up close.
- **Half-wired Supply system (`Config.Supplies`):** Eight supply items and `Validate.LOBBY` supply intents exist in config and validation, while `Core.Supplies` and between-nights envelope selection are still absent.

### What I Would Cut or Defer
- **Defer `Config.Supplies` until after the first 2-player live playtest:** Introducing 8 passive perks (`OilCan`, `WaxedOars`, `BigCooler`, `LuckyLure`, `Spectacles`, `BrassBell`, `TrimmedWick`, `Thermos`) before verifying base 5-night win rates and tension on live players will muddle tuning feedback. Keep Night 1 to 5 clean for Milestone `O1`, then wire `Core.Supplies` for Run 2+ / Milestone `G2`.
- **Cut unpooled per-frame ring geometry on mobile (`G2` target):** `BoatFx.waterRing` (`48` dark + `48` edge segments = `96` unpooled parts spawned every `1.5 s` during Hum) and `Drowned` ripples (`36` segments) should halve segment counts on touch (`Input.touch()`) and pool parts rather than creating/destroying bursts mid-scare.

### What Will Break or Confuse Players on Phones
- **Fixed in commit `dff486b`:**
  1. Touch players had no `CutLine` (`Reel in`) trigger during `phase == "Waiting"` (`MobileButtons.phaseLabel` showed `"Reel"` on `Cast`, `Prompt.textFor` omitted `"Line in"`, and `Input.interact()` ignored `Waiting`). Added `"Line\nin"` on `Use` and `"Wait"` on `Cast` during `Waiting`.
  2. `CatchInspect` cached `Input.touch()` once at `build()`, keeping desktop `(E)/(X)` key labels if input mode changed dynamically, and fixed `Choice` width at `380 px` (`AnchorPoint 0.5` at `x = 0.29`), causing the `"Throw back"` button to overlap the `0.42`-wide `FieldGuide` card on `705x338` phones. Now updated dynamically on `open()` and `ViewportSize` changes.
  3. `Camera.luau` skipped initial yaw alignment when mounting (`lastSeat ~= seat`) or starting/resetting a night (`NightStarted`), which could leave side-seat players (`PortSeat`/`StarboardSeat`) or Night 2+ restarts facing off-axis until turning the boat.
- **Still to watch live on phone:** `12 s` `Config.Fishing.decideSeconds` decision window while reading a 3D fish against `FieldGuide` text on a small screen, accidental camera drags near right-hand `MobileButtons`, and `SpotLight` shadow frame drops on low-end Android phones during Night 5 Finale.

### What Was Missing Before the First Two-Player Test
- **Code/UX fixes landed here:** Animated rowing oars, visible forward-divergent casts for both `HelmSeat` (Player 1) and `BowSeat` (Player 2), touch `Line in` parity, seated camera yaw sync, and hiding the in-boat rulebook mesh (`DeadCalmRulebookInBoat`) during `Title` and capsizes.
- **Still needed from Owner/Claude before inviting Tester 2:**
  1. Private Roblox publish (`DeadCalm.rbxl`), enabling **Studio Access to API Services**, completing `MATURITY_NOTES.md`, and adding Tester 2 under Permissions.
  2. Live 2-client Studio visual check of the bug fixes (`[claude]`).
  3. Co-op safeguard watch/fix (`[claude]`): `ToggleLantern` and `ToggleMotor` flip state unconditionally with zero cross-player cooldown, and `Knocking` sums intents across all living players (`2 + 2 = 4` double-knocks if two non-voice players both answer `"2"`).

---

## 2. Roadmap & Priority Ranking

Full milestone plan, value-for-effort table, sound pass targets, style pass steps, replay roadmap, mobile optimization notes, and design risk register live in:

-> [docs/GEMINI-PLAN.md](docs/GEMINI-PLAN.md)

Summary of milestones in [docs/GEMINI-PLAN.md](docs/GEMINI-PLAN.md):
- **G1 (`[gemini]` - Done & verified via gate):** Bug 1 (`BoatFx` oar animation), Bug 2 (`Look.Gear.seats` / `FishingService` casts, `RodTip.Axis`, line visibility, drifting tether), touch `Line in`, seat camera snap, `CatchInspect` responsive layout, `Rulebook` Title/capsize hide, sim column clarity.
- **O1 (`[owner]` - Blocker for playtest):** Private publish, API Services toggle, maturity form, second-account Play invite, 2-device Story Night 1 to 5 playtest (`PLAYTEST_GUIDE.md`).
- **C1 (`[claude]` - High value):** Visual verify G1 in Studio, execute by-ear sound pass across headphones and 50% phone speaker, add 0.45 s cross-player toggle guard / knock count cue if needed after O1.
- **O2 + C2 (`[owner]` -> `[claude]`):** Style selection from `art/style-board/index.html`, lighting/palette/Blender pass, M9 Blender mesh for the strange boat standing figure.
- **G2 / C3 (`[gemini]` / `[claude]`):** Touch ring pooling & idle `RenderStepped` throttling on phones, `Core.Supplies` 8-item tactical envelope UI, Daily Seed / Field Guide completion stamps, low-end Finale graphics profiling.

---

## 3. Root Causes of the Two Playtest Bugs

### Bug 1: The Oars Do Not Animate
- **Root cause:** `src/server/world/BoatHull.luau` constructs `OarPort` (`(-1.9, 1.15, 0.2)`) and `OarStarboard` (`(1.9, 1.15, 0.2)`) as static planks rigidly attached via `WeldConstraint` to `Hull`. `src/shared/HeroLook.luau` intentionally excludes both parts from `HeroLook.hide.BoatInterior`, and `tools/blender/boat.py` builds gunwale oarlocks at `(+-2.72, 2.05, -1.2)`, specifically preparing for client-side oar animation. However, `src/client/BoatFx.luau` only implemented `stepMotor()` (`motorCopies`) and never implemented oar stand-ins or a stroke update loop. While `AudioDirector.luau` played `oar-stroke-a/b` every `Look.Mix.oarStrokeSeconds` (`1.7 s`), the static oars remained frozen inside the hull.

### Bug 2: Casting Shows No Line or Bobber (Even Though "Waiting" and Reel-In Show)
- **Primary root cause:** `BoatHull.luau` orients the boat with bow toward `-Z` and auto-seats Player 1 in `HelmSeat` (`(0, 0.95, 4.4)` facing `-Z` in `LockFirstPerson` camera mode). In `src/server/FishingService.luau`, local table `SEATS.HelmSeat.dir` was set to `Vector3.new(0.7, 0, 0.7).Unit`, which has `dir.Z = +0.707` (aft). That aimed `Rod_HelmSeat`, the `Beam` line, and `Bobber_<userId>` 135 degrees behind the player's back off the stern into unlit dark water outside the 70-degree camera FOV, while `Core.Fishing.cast` succeeded on the server and triggered the `"Waiting"` UI prompt.
- **Compounding causes found alongside it:**
  1. `BowSeat.dir` (`Vector3.new(0, 0, -1)` from `(0, 0.95, -5.2)`) aimed straight along `x = 0` through `LanternPost` (`x = 0, z = -7.4`) and `LanternGlow` (`x = 0, z = -8.55`).
  2. `RodTip` `Attachment` on `rod` (`CFrame.lookAt(mid, tip)`) kept Roblox's default `Axis = (1, 0, 0)`, so `Beam.CurveSize0 = -1.5` pulled line slack horizontally sideways instead of sagging downward toward the water, paired with thin `lineWidth = 0.04` and `LightInfluence = 1` (invisible at night).
  3. `FishingService.step()` never clamped `l.castAt` during `Waiting`/`Bite`, leaving bobbers fixed at world coordinates even if the boat moved slowly away.

---

## 4. Changes Made (File-by-File)

| Commit | File | Change |
|---|---|---|
| `8b5586a` | Repository baseline | Initial commit of unmodified Claude handoff (478 files). |
| `348be7a` | [docs/GEMINI-PLAN.md](docs/GEMINI-PLAN.md) | Proposed ranked roadmap across G1, O1, C1, O2+C2, and G2/C3 milestones. |
| `4d3344a` | [src/client/BoatFx.luau](src/client/BoatFx.luau) | Added `BoatFx.OAR`, shared `createOarAssembly` helper (reused by `thrownOar` and local `oarCopies`), `resetOars()` in `BoatFx.reset()`, and `stepOars(dt, hull)` hiding `OarPort`/`OarStarboard` (`LocalTransparencyModifier = 1`), stowing along gunwales when idle or `motorOn == true`, and sweeping/feathering in the oarlocks synced to `Look.Mix.oarStrokeSeconds` on forward/reverse motion or turning (with teleport spike protection and capsize hiding). |
| `5563681` | [src/shared/Look.luau](src/shared/Look.luau) | Updated `Look.Gear` (`lineWidth = 0.065`, `lineLightInfluence = 0.35`, `lineLightEmission = 0.15`, `bobberSize = 0.55`, `bobberCapSize = 0.3`), added `Look.Gear.seats` (`HelmSeat` forward-starboard `(0.42, 0, -0.907).Unit`, `BowSeat` forward-port `(-0.32, 0, -0.947).Unit`), and added shared `Look.rodLocal(seat)`. |
| `5563681` | [src/server/FishingService.luau](src/server/FishingService.luau) | Switched to `Look.Gear.seats` and `Look.rodLocal`, set `RodTip.Axis = Vector3.new(0, -1, 0)` with `curve = 1.4`, applied `Look.Gear` lighting/sizes, and tethered `Waiting`/`Bite` `castAt` within `26` studs horizontally of `rodTipWorld`. |
| `5563681` | [tests/Fishing.spec.luau](tests/Fishing.spec.luau) | Added geometry unit test asserting `HelmSeat` and `BowSeat` cast forward (`dir.Z < -0.8`), clear hull/gunwales and bow lantern post, and diverge port vs. starboard. |
| `dff486b` | [src/client/ui/MobileButtons.luau](src/client/ui/MobileButtons.luau) | Labeled `Cast` as `"Wait"` during `phase == "Waiting"` and `Use` as `"Line\nin"` (`CutLine`) when waiting and not bailing. |
| `dff486b` | [src/client/Input.luau](src/client/Input.luau) | Updated `Input.interact()` to send `CutLine` when `phase == "Waiting"`. |
| `dff486b` | [src/client/ui/Prompt.luau](src/client/ui/Prompt.luau) | Updated touch prompt during `Waiting` to `"Wait for the bite, or tap Line in."`. |
| `dff486b` | [src/client/Camera.luau](src/client/Camera.luau) | Added `Events.on("NightStarted", ...)` trigger and seat-facing horizontal yaw alignment in `DeadCalmBoatYaw` whenever mounting a seat (`lastSeat ~= seat`) or starting a night. |
| `dff486b` | [src/client/ui/Rulebook.luau](src/client/ui/Rulebook.luau) | Hidden `DeadCalmRulebookInBoat` (`Transparency = 1`, `MaxActivationDistance = 0`) when on `Title` or during `BoatFx.capsizing()`. |
| `dff486b` | [src/client/ui/CatchInspect.luau](src/client/ui/CatchInspect.luau) | Added dynamic `fitButtons()` called on `open()` and `ViewportSize` changes to refresh touch vs. keyboard button text and constrain `Choice` width left of `FieldGuide` on narrow phones. |
| `dff486b` | [tools/sim/rules.luau](tools/sim/rules.luau) | Clarified table column header `"Shortest real gap (s)"` to `"Shortest start-to-start gap (s)"`. |

`src/shared/Core` was not modified.

---

## 5. Verification

Every commit passed all 11 steps of `tools/check.ps1`:

- **Selene (`[1/11]`):** `0 errors, 0 warnings, 0 parse errors`
- **StyLua (`[2/11]`):** `stylua --check: ok`
- **Lune specs (`[3/11]`):** `TESTS: 213 passed, 0 failed, 18 spec files` (including `Director property: 500 seeds x 5 nights = 2500 nights, 1940671 checks, 8618 real spawns, 9232 fake-outs, 0 violations` and new casting geometry specs in `tests/Fishing.spec.luau`)
- **Pacing sim (`[4/11]`):** `pacing sim --fast: ok` (all 20 Story Night 1 to 5 x Crew 1 to 4 cells on target)
- **Lint (`[5/11]` - `[9/11]`):** `emdash: ok`, `asset ids: ok`, `secrets: ok`, `core purity: ok`, `ui words: ok`
- **Build (`[10/11]`):** `rojo build` built `DeadCalm.rbxl` cleanly
- **Place smoke test (`[11/11]`):** `SMOKE: 10 of 10 checks passed`

**Visual Studio verification status:** **not seen in Studio.** Per the handoff rules, no existing Roblox Studio window on the machine was touched, and no visual Play-mode inspection in Studio was run for the oar animation (`BoatFx.luau`), casting line/bobber visibility (`Look.luau`, `FishingService.luau`), camera yaw alignment (`Camera.luau`), world rulebook hiding (`Rulebook.luau`), or touch UI (`MobileButtons.luau`, `CatchInspect.luau`). All visual fixes need live verification in Milestone `C1`.

---

## 6. What Was Not Done and Why

- **Studio Play verification (`[claude]`, C1):** Deferred to avoid interfering with open Studio windows and because MCP Studio tooling was kept untouched per workspace isolation rules.
- **By-ear Studio audio mixing (`[claude]`, C1):** Requires live headphones + phone speaker auditioning against `DebugBot` and Night 1 to 5 ambience.
- **Style look pass & Strange boat hero mesh (`[owner]` + `[claude]`, O2/C2):** Waiting on the owner's son to pick a visual preset from `art/style-board/index.html` and on Blender upload access.
- **Cross-player toggle guard (`[claude]`, C1) & Supply Pick / Endless Replay / Phone Ring Pooling (`[gemini]` / `[claude]`, G2):** Kept as proposals in [docs/GEMINI-PLAN.md](docs/GEMINI-PLAN.md) rather than touching `src/shared/Core` or adding unrequested gameplay mechanics before the first two-player test.

---

## 7. Suggestions for Claude When Reviewing

1. Inspect commits cleanly with `git log --stat 8b5586a..HEAD`. All changes sit in small, isolated commits outside `src/shared/Core`.
2. In Studio **Server + 2 Clients** test mode:
   - Verify `HelmSeat` rowing shows both local oars deploying out of the gunwale rests into `HeroBoatInterior` oarlocks and cycling at ~`1.7 s` (`Look.Mix.oarStrokeSeconds`), then stowing smoothly when stopping or toggling the motor (`M`).
   - Cast from both `HelmSeat` and `BowSeat` at night: confirm `HelmSeat` casts forward-starboard into beam light, `BowSeat` clears `LanternPost`/`LanternGlow` to port, and `Beam.CurveSize0 = 1.4` along `RodTip.Axis = (0, -1, 0)` arches downward cleanly.
   - Check Roblox Device Simulator (`705x338` phone) with touch input: test casting -> `"Wait"` / `"Line\nin"` (`CutLine`) -> `CatchInspect` button width against `FieldGuide`.
3. Audition `SoundRegistry` items listed in Section 2 of [docs/GEMINI-PLAN.md](docs/GEMINI-PLAN.md) (`night-failed-sting`, `knock-pass`, `watcher-lunge`, `hum-mid-voice`, `neighbor-fail`, `lanterns-die`).
4. If the two-player test (`O1`) shows accidental double-toggles or double-knocks, implement the `0.45 s` cross-player cooldown on `ToggleLantern` / `ToggleMotor` cleanly in `Night.luau`.

---

## 8. Questions Only the Owner Can Answer (With Recommended Defaults)

1. **Which art style from `art/style-board/index.html` does your son want?**
   - *Recommended default:* `lantern-noir` (or `moonlit` water/sky highlights over `lantern-noir` silhouette separation) because dark fog + warm lantern light maximizes readability on dim mobile screens.
2. **Which two devices and voice setup will you use for the first two-player playtest?**
   - *Recommended default:* One PC (`HelmSeat`) and one phone (`BowSeat`), running Story Nights 1 to 5 first **without voice chat** so co-op communication gaps (`Hum` lantern toggles, Night 4 `Knocking`, solo scare callouts) show up honestly.
3. **Should audio volumes prioritize loud scare punch on phone speakers or headphone comfort on PC?**
   - *Recommended default:* Prioritize 50% phone speaker readability for warning cues (`hum-mid-voice`, `knock-three-soft`, `neighbor-oarlock-loop`), while trimming peak-heavy stings/lunges (`watcher-lunge` at `9.14`, `night-failed-sting` at `0.5`) so PC headphones stay fatigue-free.
4. **How should pauses or AFK moments between nights work in two-player play?**
   - *Recommended default:* Keep the automatic `12 s` dock countdown (`LobbyService`) for solo flow unless interruptions happen during O1; if needed later, add an optional `"Hold at dock"` pause toggle rather than forcing Ready clicks every night.
5. **After beating Story Night 5, which replay addition should come first?**
   - *Recommended default:* Keep Endless Nights + Field Guide specimen stamps first, then enable `Core.Supplies` (8 tactical supply items) as a Run 2+ / unlockable layer once the core 5-night balance is verified live.
