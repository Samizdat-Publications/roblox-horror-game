# Gemini Plan: Roadmap to a Two-Player Evening Session

Date: 11/27/2026
Status: Proposed by Gemini review pass for review by the owner and Claude.

This plan maps the stretch from today's build (M0 through M9, 212 specs, custom audio and Blender hero meshes uploaded) to a game two people can sit down and enjoy together for an evening.

Tags used below:
- `[gemini]`: Pure code, config, tests, or documentation changes finishable in this folder without Studio uploads or publishing.
- `[claude]`: Work requiring Roblox Studio driving (visual checks, captures, by-ear Studio playtest mixing), Blender modeling/uploads, or ElevenLabs re-generation/uploads.
- `[owner]`: Actions only the Roblox account owner can perform (private publish, game settings, friend play permissions, creative style choice).

---

## Priority Ranking (Value for Effort)

| Rank | Item | Tag | Value | Effort | Target Milestone |
|---|---|---|---|---|---|
| 1 | Fix Bug 1: Animate the oars in `BoatFx` while rowing (`src/client/BoatFx.luau`) | `[gemini]` | Very High | Low | G1 |
| 2 | Fix Bug 2: Fix `HelmSeat` / `BowSeat` cast direction, rod tip axis, and line/bobber visibility (`src/shared/Look.luau`, `src/server/FishingService.luau`, `tests/Fishing.spec.luau`) | `[gemini]` | Very High | Low | G1 |
| 3 | Fix touch "Line in" (`CutLine`) gap and `Waiting` button label (`MobileButtons`, `Prompt`, `Input`) | `[gemini]` | High | Low | G1 |
| 4 | Snap first-person camera yaw to seat facing on sit and `NightStarted` (`Camera.luau`, `Rulebook.luau`) | `[gemini]` | High | Low | G1 |
| 5 | Refresh `CatchInspect` phone touch labels and compact button width (`CatchInspect.luau`) | `[gemini]` | High | Low | G1 |
| 6 | Clarify `"Shortest start-to-start gap"` column label in `tools/sim/rules.luau` | `[gemini]` | Medium | Trivial | G1 |
| 7 | Private publish, enable Studio API Services, and invite second player account | `[owner]` | Blocker | Low | O1 |
| 8 | Verify Bug 1 and Bug 2 fixes visually in Studio Play mode (`HelmSeat` and `BowSeat`, PC + phone) | `[claude]` | Very High | Low | C1 |
| 9 | Run two-player private test session and collect observations | `[owner]` | Very High | Medium | O1 |
| 10 | By-ear sound level pass in live Studio playtest (PC headphones + phone speaker) | `[claude]` | High | Medium | C1 |
| 11 | Cross-player 0.45s toggle guard on `ToggleLantern` / `ToggleMotor` and live knock feedback in co-op | `[claude]` | High | Low | C1 |
| 12 | Pick preferred visual style from `art/style-board/index.html` | `[owner]` | High | Trivial | O2 |
| 13 | Look pass in the chosen style (`Look.luau`, `HeroLook.luau`, `palette.py`) + M9 figure mesh for strange boats | `[claude]` | High | Medium | O2 + C2 |
| 14 | Mobile performance pass: halve/pool `BoatFx.waterRing` parts on touch and skip idle `FloorSlat` / `Watcher` per-frame work | `[gemini]` | Medium | Low | G2 |
| 15 | Wire up between-nights Supply Pick (`Core.Supplies` for the 8 items in `Config.Supplies`) and envelope UI | `[gemini]` | High | Medium | G2 |
| 16 | Auto-reel or trail-cancel `Waiting` lines when the motor engages; Night 4 teaching separation (`Knocking` before `Watcher`) | `[claude]` | Medium | Low | C3 |
| 17 | Daily / shared run seed input + Field Guide species/mutation completion checklist in Locker | `[gemini]` | Medium | Medium | G2 |

---

## 1. The First Private Two-Player Test

### Readiness Checklist

Before inviting a second player on a second device:

- `[gemini]` **Oars animate while rowing:** `BoatFx.luau` replaces the static `OarPort` and `OarStarboard` visuals with local oar assemblies pivoted at the gunwale oarlocks that sweep and feather with hull speed/turning, and stow cleanly along the gunwales when the outboard motor is on.
- `[gemini]` **Casting shoots forward into view and lantern light:** `Look.Gear.seats` points `HelmSeat` forward-starboard and `BowSeat` forward-port (instead of `HelmSeat` casting 135 degrees backward over the stern and `BowSeat` clipping the bow `LanternPost`), with `RodTip.Axis` aimed downward for natural line sag and higher-visibility bobber/line sizing.
- `[gemini]` **Touch players can cancel a cast (`Line in`):** On phones, `MobileButtons` shows `Wait` on `Cast` and `Line in` on `Use` while `phase == "Waiting"` so touch players have parity with `X` on PC.
- `[gemini]` **Seated camera faces the seat direction:** `Camera.luau` aligns horizontal camera yaw to the occupied `Seat.CFrame.LookVector` on initial sit and on `NightStarted`, so `PortSeat`/`StarboardSeat` players and Night 2+ transitions never start staring backward or sideways.
- `[gemini]` **CatchInspect fits narrow phones:** `CatchInspect.luau` removes key hints dynamically on touch and narrows `Choice` buttons when needed so they stay clear of the `FieldGuide` card.
- `[owner]` **Private publish and permissions:**
  1. Open `DeadCalm.rbxl` in Roblox Studio.
  2. File -> Publish to Roblox As -> create or update the private experience named `"Don't Wave Back"`. Keep visibility **Private**.
  3. Game Settings -> Security -> enable **Enable Studio Access to API Services** so `DeadCalmProfiles_v1` and `DeadCalmBestEndless_v1` persist across sessions.
  4. Complete the Maturity Questionnaire using `MATURITY_NOTES.md`.
  5. Game Settings -> Permissions -> invite the second tester's Roblox account with **Play** permission.
  6. If any custom audio (`audio/ids.json`) or M9 hero mesh (`art/ids.json`) falls back or stays silent in the published place, grant experience asset permissions under create.roblox.com -> Configure -> Permissions -> Assets.
- `[claude]` **Quick Studio visual check:** Confirm `HelmSeat` and `BowSeat` casts, oar motion, and two-client `OccupantUserId` seat replication in Studio Test tab (`Clients = 2`) before sending the link.

### What to Watch For During the Two-Player Test

1. **Seat roles and sightlines (`HelmSeat` + `BowSeat`):** Player 1 auto-seats at `HelmSeat` and Player 2 at `BowSeat`. Watch whether `BowSeat` can watch the forward fog and cast port-forward while `HelmSeat` steers and casts starboard-forward without their rods or bobbers crossing.
2. **Double-toggles under pressure (Hum):** Both players can press `F` / `Light out` and `M` / `Motor off`. Watch if both players react to the frogs stopping at the same instant and accidentally toggle the lantern off and right back on (fatal in Rule 1).
3. **Double-knocking (Night 4, Knocking):** `Core.entities.Knocking` sums `Knock` intents across all living players. Watch whether both players tap `Q` / `Knock` twice (`2 + 2 = 4` knocks) and fail Round 1 unnecessarily because there is no verbal voice chat.
4. **Solo-cued scares and fake callouts (`only` events, Neighbor):** Watch whether the player who receives a solo `Watcher` or solo fake-out realizes the other player did not see it, and whether the Neighbor's impersonated callouts (`"Lantern on."`, `"(waves)"`, `"Go home."`) cause genuine suspicion and laughter rather than UI confusion.
5. **Drowned co-op loop:** Intentionally fail a rule on one player to verify the `DeathCard`, the cold blue-green `Drowned` orbit camera, the `DrownedSight` outlines (shape under hull, Watcher, Neighbor, and real dock beacon only), and whether the living player notices the `GhostBell` ripple and screen-edge marker.
6. **Phone comfort and text readability:** On the phone client, verify thumbstick steering never conflicts with `Callouts` feed, `MobileButtons` remain reachable without accidental jumps, and `CatchInspect` comparisons against the `FieldGuide` feel fair inside the 12-second `decideSeconds` timer.

---

## 2. By-Ear Sound Pass

On `11/27/2026`, 50 custom ElevenLabs takes replaced the library stand-ins and derived recipes, peak-normalized to `-3 dB`. Because those levels were set mathematically against the old stand-ins (and `PROGRESS.md` specifically flags `night-failed-sting` and `knock-pass` as the weakest), a structured listening pass is required before locking levels.

### How to Judge Levels

1. **Stage 1 (Studio isolated cue check, `[claude]`):** Use `DebugBot` `play_sound` with `opts.ambience = true` (which runs through `AudioDirector.auditionSpot` at true world distances under band-3 frog chorus and `SoundGroup` ducking).
2. **Stage 2 (Live Night 1 to 5 balance, `[claude]` + `[owner]`):** Play with two speakers/devices: PC closed-back headphones (spatial clarity and sub-bass balance) and a real phone speaker at 50% volume (250 Hz to 3 kHz midrange cut-through, with ambient room noise).

### Sounds and Levels to Judge

| Priority | Registry Name(s) | Current Setting (`SoundRegistry` / `Look.Mix`) | What to Judge by Ear |
|---|---|---|---|
| 1 | `night-failed-sting` | `volume = 0.5`, `Music` (`0.6`) | Scored `4.5/10` in ranking; verify whether it lands as dread rather than harsh synth/noise before `tape-night-failed` (`NightCards` plays it at `NightFailed`, tape follows 1.2s later). |
| 2 | `knock-pass` | `volume = 1.5`, `Rule` (`1.6`), under keel `minDist = 14` | Check if the relief settle clearly reads as "safe" after `knock-three-soft` (`3.5`) / `knock-three-hard` (`4.5`) + `knock-thump-*`. |
| 3 | `watcher-step`, `watcher-lunge` | `watcher-step = 4.02`, `watcher-lunge = 9.14`, `minDist = 150` | `watcher-lunge` sits near Roblox's volume ceiling (`10`). Check at `shoreRange` (180-260 studs) that steps are audible over `Ambience` without clipping at closer shores (60-100 studs). |
| 4 | `hum-rise`, `hum-hold-loop`, `hum-hull-resonance`, `hum-mid-voice` | `0.9`, `0.9`, `0.55` (derived), `0.6` (derived), `Rule` (`1.6`) | Judge on a phone speaker while `motor-idle-loop` (`2.8`) stops: `hum-mid-voice` (3 octaves up + tremolo) must clearly separate from the dying motor within 1.5s of frog silence. |
| 5 | `neighbor-oarlock-loop`, `neighbor-fail`, `lanterns-die` | `0.51` (`minDist = 160`), `0.65`, `0.5` | `neighbor-fail` and `lanterns-die` were noted as slightly quieter after replacing quiet takes; verify they punch cleanly through `cueDuck = 0.4`. Check `neighbor-oarlock-loop` at 200 studs vs 90 studs. |
| 6 | `lake-groan`, `boat-sink`, `finale-bell`, `finale-hazard-creak` | `5.11`, `5.43`, `1.0 * 1.6`, `1.5` (derived) | During Finale hush (`AudioDirector.hush` mutes all groups except `Rule`), verify `finale-bell` echoes without ear fatigue at `bellVolume = 1.6`, and `finale-hazard-creak` (`minDist = 22`) locates passing boats clearly in 3D. |
| 7 | `tape-night-1`..`5`, `tape-amended` vs `chorus` / `radio` | `Voice = 1.0`, EQ `-14/+2/-12`, `Distortion = 0.12`, `tape.duck = 0.6` | Verify the owner's voice is effortless to understand on a phone speaker on Night 1 while rowing out past the dock radio (`radio-tune-1/2` at `0.7`). |

---

## 3. Look Pass Once the Owner's Son Picks a Style

The project already contains 5 mocked styles in `tools/style/styles.json` (`art/style-board/index.html`):
`lantern-noir`, `papercut`, `toybox`, `vhs`, and `moonlit`.

Because `src/shared/Core` has zero visual knowledge and all world/UI look values are isolated in three places, the look pass can execute cleanly once the pick arrives:

1. **`[owner]` Style selection:** Owner's son picks one favorite (or a mix, e.g., "Moonlit colors with Lantern Noir fog") from `art/style-board/index.html`.
2. **`[claude]` Lighting, Atmosphere, and Palette pass (`src/shared/Look.luau` + `src/client/ui/Paper.luau`):**
   - Tune `Look.Lighting` (`Brightness`, `Ambient`, `OutdoorAmbient`, `Atmosphere.Density`/`Color`/`Decay`, `ColorCorrection`, `Bloom`) and `Look.Moon` to match the chosen style while preserving the phone-readability floor (silhouettes must stay separable from fog on low-brightness phones).
   - Adjust `Look.UI` (`paper`, `ink`, `amendInk`, fonts) if `toybox` or `vhs` is chosen (e.g., camcorder scanline/tint overlay for `vhs` or warmer storybook contrast for `papercut`).
3. **`[claude]` Blender Material & Vertex Palette pass (`tools/blender/palette.py`, `src/shared/HeroLook.luau`):**
   - Update `PALETTE` in `tools/blender/palette.py`, re-run `tools/blender/build_all.py`, and re-upload updated hero meshes if vertex colors change materially (`BoatShell` uses runtime `MeshPart.Color` so boat paints still work automatically).
4. **`[claude]` M9 Follow-Up Hero Mesh for Strange Boats (`tools/blender/` + `src/client/fx/Neighbor.luau` / `Finale.luau`):**
   - `PROGRESS.md` notes the strange boat's standing figure is still blocky up close (Neon `5/10`). Build a dedicated M9 Blender mesh (`StrangeFigure` in long coat and wide-brimmed hat) following the `Watcher` pattern in `HeroModels.luau` and `HeroLook.luau`, keeping the current `Common.figure` parts as the fallback.

---

## 4. Replay Value After the First Five-Night Run

Right now, post-run replay rests on Nightmare difficulty, seed-driven Rulebook amendments, Endless Nights (Night 6+ with random 2 to 4 rule mixes and a top-10 leaderboard), and 11 earned Locker cosmetics. To carry an evening session and future return nights:

1. **Restore the Between-Nights Supply Envelope (`[gemini]` Core + Shell, medium effort, high replay payoff):**
   - `Config.Supplies` already defines 8 items (`OilCan`, `WaxedOars`, `BigCooler`, `LuckyLure`, `Spectacles`, `BrassBell`, `TrimmedWick`, `Thermos`), `Validate.LOBBY` already has `Supply = "supply"`, and `ARCHITECTURE.md` specifies `Run.supplyChoices(run)` and `Run.chooseSupply(run, id)`.
   - Implementing `Core.Supplies` and a 10-second paper envelope pick between nights turns every run into a crew tactical build (for example, choosing `WaxedOars` for fast Finale rowing vs. `TrimmedWick` to save lantern oil vs. `Spectacles` for Nightmare Wrong Catch nights).
   - Keep this gated behind a config flag or Story Run 2+ / after the first two-player playtest so the initial 5-night Story test stays pure.
2. **Daily Seed and Named Seed Mode (`[gemini]`):**
   - `Core.Run` is deterministic from `run.seed`. Adding an optional seed toggle (`"Tonight's Lake"`, derived from `YYYYMMDD` on the server) or shareable numeric run code on the Title sheet lets two friends or families compete on identical fish rolls, rule sequences, and amendments.
3. **Field Guide Specimen Checklist (`[gemini]`):**
   - Track caught species (`8/8`) and discovered wrong-fish mutations in `Profile` (`flags` or a new `seenFish` table) with ink checkmarks/stamps in `FieldGuide.luau`, giving collectors a reason to visit the `Reeds`, `Narrows`, and `Steeple` even on lower nights.
4. **Deep Endless Modifiers at Night 8+ (`[gemini]`/`[claude]`):**
   - Add named Endless twists (e.g., `"Heavy Fog"`, `"Fast Current"`, `"Double Amendment"`) every 3rd Endless night starting at Night 8 so Endless climbs feel distinct rather than purely statistical scaling (`realPerNight`, `quietGapStep`).

---

## 5. Performance on Low-End Phones

Static world geometry is well within budget (`1,618` world parts + `28` boat parts = `1,646` total vs. `2,500` budget in `tools/shell/world_count.luau`), and `NightService` caps view replication at `10 Hz` with signature deduplication. However, code inspection found three dynamic runtime costs on low-end phones:

1. **Per-frame 96-part ring allocations in `BoatFx.waterRing` and `Drowned.ripple` (`[gemini]`):**
   - `BoatFx.RINGS.segments = 48` creates `96` (`dark` + `edge`) unpooled `BasePart` instances per ring, spawned every `1.5s` during the Hum and mutated (`Size`, `CFrame`, `Transparency`) inside a `task.spawn` loop every frame for `3.8s` (up to ~288 parts updated per frame). `Drowned.RIPPLE` spawns `36` segments similarly.
   - **Fix:** Halve `segments` (`48 -> 24`, `36 -> 18`) when `Input.touch()` is true, and reuse a small ring pool instead of `Instance.new`/`Destroy` bursts.
2. **Unconditional per-frame `RenderStepped` writes (`BoatFx` and `fx/Watcher`, `[gemini]`):**
   - `BoatFx.init()` sets `s.part.CFrame` on all 5 `FloorSlat` parts every `RenderStepped` even when `buzzLevel <= 0.01` and `capsizeCopy == nil`. `Watcher.init()` runs `step()` every `RenderStepped` even on Nights 1 to 3 when no Watcher exists.
   - **Fix:** Early-out or weld slats when idle, and gate `Watcher`'s `staring()` check behind `figure ~= nil`.
3. **Particle and Lighting load (`BoatFx.SPRAY`, `Shore`, `SpotLight` shadows, `[claude]`):**
   - Test on a throttled low-end Android preset in Studio (`Galaxy A06` / low graphics quality level `1-3`) to verify `Look.Finale.cone.shadows = true` and `Look.Lantern.Shadows = true` do not drop frame rate below 30 fps during Night 5 Finale with `Finale.WAKE` (`9` particles/s) and `MOTOR_CHURN` (`14` particles/s) active together.

---

## 6. Risks in the Current Design

1. **Co-op Input Collisions on Shared Boat Verbs (`ToggleLantern`, `ToggleMotor`, `Knock`):**
   - **Risk:** In `Night.luau`, `ToggleLantern` and `ToggleMotor` flip boolean state unconditionally on any living player's intent. During a tense Hum cue, two players pressing `F` within one tick (or within human reaction time ~0.3s) immediately cancel each other out (`on -> off -> on`), triggering `Death.Hum.LanternLit`. Similarly, `Knocking.luau` sums every player's `Knock` intent (`count += 1`), so two non-voice players both answering `"2"` produce `4` knocks and fail immediately.
   - **Mitigation:** `[claude]` Add a 0.45s cross-player cooldown after a state flip on `Lantern`/`Motor`, and display a brief hull knock indicator (or `"Crewmate knocked (1)"` subtle prompt/sound spatialized per seat) so co-op crews without voice chat can coordinate knocks cleanly.
2. **Line Left in `Waiting` When the Boat Moves (`Core.Fishing` + `FishingService`):**
   - **Risk:** `Fishing.cast` requires `boatSpeed < 2.0`, but once `phase == "Waiting"`, rowing or engaging the motor never cancels or updates the cast. On the server, `FishingService` left `Bobber_<id>` anchored at the original cast coordinates while the boat drove hundreds of studs away.
   - **Mitigation:** `[gemini]` In `FishingService.step()`, tether `Waiting`/`Bite` bobbers to a maximum horizontal distance (`26` studs) from the rod tip so slow rowing trails the bobber realistically. `[claude]` Consider cancelling `Waiting` lines (`HookLost` `"Moving"`) in `Core.Fishing` if the outboard motor is turned on.
3. **Night 4 Dual-Rule Teaching Spike:**
   - **Risk:** Night 4 introduces **two** complex rules at once (`Knocking` and `Watcher`) and raises `maxConcurrent` from `1` to `2` (`Config.Nights[4]`). Younger players or phone players can be overwhelmed if both teach close together or overlap with `WrongCatch` / `Neighbor`.
   - **Mitigation:** `[claude]` Watch Night 4 closely during the two-player test. If failure rates spike, space Night 4's teaching spawns cleanly (`Director` holds the second new rule until `lastResolved + quietGap`) or move `Watcher` to Night 5 before the 4 AM bell / spread Story mode if needed.
4. **No In-Run Pause or AFK Protection:**
   - **Risk:** A real-world phone call or bathroom break leaves a player's character seated, counting toward `Hum` or `Watcher` checks (and `Watcher` still requires `gazeYaw` or kills the spotter if solo).
   - **Mitigation:** Keep Night length at 6 minutes (`Config.Night.realSeconds = 360`) and monitor during playtesting whether a dock-waiting pause between nights (`Ready` button) is better than the fixed 12-second `LobbyService.BETWEEN` countdown.
5. **Untested Live DataStore Limits in Unpublished Place:**
   - **Risk:** While `DataStores.luau` and `Core.SaveLogic` pass all mock-store specs, `OrderedDataStore` (`DeadCalmBestEndless_v1`) and `DataStoreService` (`DeadCalmProfiles_v1`) have never executed against live Roblox cloud endpoints because the place is unpublished.
   - **Mitigation:** Verify saves and leaderboard writes immediately after Milestone O1 (`[owner]` private publish with Studio API Access enabled).

---

## 7. Milestones & "Done When" Tests

### Milestone G1 (`[gemini]`): Playtest Bug Fixes & Two-Player Readiness
- **Scope:** Animate oars (`BoatFx.luau`), fix `HelmSeat`/`BowSeat` casting geometry and line/bobber visibility (`Look.luau`, `FishingService.luau`, `tests/Fishing.spec.luau`), add touch `Line in` (`MobileButtons.luau`, `Prompt.luau`, `Input.luau`), snap camera yaw on seat/night start (`Camera.luau`, `Rulebook.luau`), refresh `CatchInspect` phone layout (`CatchInspect.luau`), clarify `tools/sim/rules.luau` column label.
- **Done when:** `tools/check.ps1` exits `0` (`GATE PASS`, all 11 steps), including new geometry specs in `tests/Fishing.spec.luau`.

### Milestone O1 (`[owner]`): Private Publish & Two-Device Playtest
- **Scope:** Publish `DeadCalm.rbxl` privately to Roblox, enable Studio Access to API Services, complete `MATURITY_NOTES.md` questionnaire, invite second player account, run Night 1 to 5 test (`PLAYTEST_GUIDE.md`) on PC + phone.
- **Done when:** Two players connect to one boat on separate devices, profiles persist across a server restart, and the Section 4 checklist in `PLAYTEST_GUIDE.md` is filled in.

### Milestone C1 (`[claude]`): Studio Visual Verification, Sound Pass & Co-op Guard
- **Scope:** Verify G1 visuals (oars, `HelmSeat`/`BowSeat` lines, phone touch layout) in Studio Play mode (`DebugDriver` + 2-client test); execute Section 2 by-ear sound pass (`night-failed-sting`, `knock-pass`, `watcher-lunge`, `hum-mid-voice`, `neighbor-fail`, `lanterns-die`, tapes); add 0.45s cross-player `ToggleLantern`/`ToggleMotor` guard and knock count cue if O1 reveals accidental double-inputs.
- **Done when:** Studio captures confirm oars and forward casts from both seats, all `SoundRegistry` entries pass by-ear check on headphones and phone speaker, and `tools/check.ps1` passes.

### Milestone O2 + C2 (`[owner]` -> `[claude]`): Style Pick & Look Pass
- **Scope:** `[owner]` Son selects style from `art/style-board/index.html`. `[claude]` Apply chosen style across `Look.luau`, `Paper.luau`, and `tools/blender/palette.py`; build M9 Blender hero mesh for the strange boat standing figure (`Neighbor` / `Finale`).
- **Done when:** Studio contact sheet in the chosen style scores `>= 7/10` on phone readability and style coherence, and `HeroModels` fallback still renders cleanly with ID `0`.

### Milestone G2 / C3 (`[gemini]` / `[claude]`): Replayability & Low-End Phone Optimization
- **Scope:** `[gemini]` Implement `Core.Supplies` for the 8 items in `Config.Supplies`, hook into `Core.Run` + between-night envelope UI, add `Tonight's Lake` daily seed option and Field Guide completion stamps, and reduce/pool `BoatFx.waterRing` and `Drowned.ripple` parts on touch. `[claude]` Profile low-end mobile preset (`GraphicsLevel 1-3`) in Studio during Night 5 Finale and tune `Motor`/`Waiting` cast interaction.
- **Done when:** Lune specs cover every supply effect, `tools/sim/pacing.luau` and `tools/sim/run.luau` stay within clear-rate targets, and low-end phone capture holds steady frame pacing with zero gate errors.
