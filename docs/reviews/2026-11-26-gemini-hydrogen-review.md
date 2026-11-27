# Dead Calm ("Don't Wave Back"): Technical & Design Review Package

- **Repository:** [Samizdat-Publications/roblox-horror-game](https://github.com/Samizdat-Publications/roblox-horror-game)
- **Audit Date:** 11/26/2026
- **Target Player:** Co-op (1-4 players), phones-first, ages 10+ (Liam)

## Direct Verdict

The engineering foundation is unusually strong for a Roblox project: functional core / thin shell (`Core.Night.step(state, input) -> { Event }`), 94 Lune specs, pinned Rokit tooling (`Rojo 7.7.1`, `Selene 0.32.0`, `StyLua 2.6.0`, `Lune 0.11.1`, `luau-lsp 1.70.1`), and a clean Mild/Moderate Fear tone in [MATURITY_NOTES.md](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/MATURITY_NOTES.md).

Three issues hold it back before Liam's first real playtest:
1. **Gameplay loop exploits & dead time:** Three of four Director threats can be cheesed inside dock light, and drowned players have almost nothing to do for the rest of a 6-minute night.
2. **Graphics bottlenecks:** A single flat `SmoothPlastic` water sheet plus a 60-stud shadow-casting lantern and bright midnight ambient flatten the atmosphere.
3. **Release blockers:** Night 5's `Finale` (Rule 6) is unimplemented, `Core.Rulebook` is referenced but missing, and 15 audio assets are still waiting manual Studio upload.

---

## 1. Gameplay Loop & Co-Op Design Audit

| Mechanic / File | Current Behavior | Problem in Live Play | Concrete Fix |
| :--- | :--- | :--- | :--- |
| **Dock-Light Safe Zone**<br>[Hum.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/entities/Hum.luau), [Knocking.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/entities/Knocking.luau), [Neighbor.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/entities/Neighbor.luau) | Inside dock light, `Hum` ignores noise while hold timer continues, `Knocking` pauses its window, and `Neighbor` stops following/failing while clocks keep running. Only [WrongCatch.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/entities/WrongCatch.luau) still fires. | Players learn quickly to fish at the edge of dock light and back into safety whenever frogs thin, cheesing 3 of 4 threats. | Cut fish bite rate to `0.2x` near dock light so quota requires leaving safety, and pause `Hum`/`Neighbor` countdowns inside dock light so camping never burns down a scare. |
| **Ghost Agency**<br>[Ghost.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/Ghost.luau) | 38 lines: drowned players float near the boat and ring a faint bell on `bellCooldown`. | Dying at minute 2 of a 360-second night means 4 minutes of near-zero agency, which kills momentum for an 11-year-old. | Give ghosts an active spotter role: let them see the `Watcher` on shore or tell the real dock beacon from the `Neighbor`'s false beacon, and have their bell ping a directional ripple on the water for living crew. |
| **Boat Feel & Shore Snags**<br>[BoatModel.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/BoatModel.luau) | Shore contact (`distanceToShore < 2`) zeroes `speed` and `vel` and reverts `pos` (hard stop, zero sliding). Steering rotates `heading` at full `turnRate` at zero speed. | Panicking in fog and dead-stopping against a bank feels broken; full-speed zero-velocity turning feels like a turret instead of a rowboat. | Project velocity onto the shore tangent (slide with `0.45` drag) instead of snapping to zero, and damp stationary turn rate to `35%` of moving turn rate. |
| **Deciding Auto-Keep**<br>[Fishing.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/Fishing.luau) | If the `Deciding` timer expires (`expired = true`), `Night` keeps the fish automatically. | Hesitating while checking the Field Guide on a phone silently banks a Wrong Catch that later eats banked cooler fish. | Add a clear diegetic countdown (fish thrashing harder + heartbeat) and default Night 2's teaching catch timeout to toss-back rather than silent keep. |
| **Solo Mimicry**<br>[Neighbor.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/entities/Neighbor.luau) | Sends 1-2 fake callouts (`"LanternOn"`, `"Wave"`, `"GoHome"`) in a living crewmate's name. | In 1-player solo runs (supported by `Config.luau`), there is no living crewmate to impersonate. | Fall back to an eerie muffled "Shore Radio / Owner's Tape" callout when `livingCount == 1`. |
| **Touch Peripheral Gaze**<br>[Watcher.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/entities/Watcher.luau) | `EdgeOfSight` lunges if stared at (`stareCone`) and steps closer if unwatched (`edgeCone`). | Holding a narrow peripheral angle on a phone touchscreen while rowing or fishing feels finicky and unfair. | Widen `edgeCone` by 15 degrees on touch devices and add a subtle directional hum + edge vignette so the player feels the sweet spot without a HUD meter. |

---

## 2. Graphics, Water & Lighting Overhaul

[PROGRESS.md](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/PROGRESS.md) notes an earlier 2.5/10 look review before Look passes 1-3. Inspecting [Water.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/server/world/Water.luau), [LightingController.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/server/LightingController.luau), and `src/shared/Look.luau` shows the exact causes:

1. **Replace the flat `SmoothPlastic` lake sheet (`Water.luau`):** A single `2040x2040` `SmoothPlastic` part (`Reflectance = 0.28`, `RGB(22, 46, 62)`) has zero normal-map ripple breakup, so the lantern never shimmers across the surface and boat movement looks like sliding on matte plastic. Swap to Roblox `Terrain` water with calm settings (`WaterWaveSize = 0.04`, `WaterWaveSpeed = 4`, `WaterReflectance = 0.6`, `WaterTransparency = 0.15`) and add a subtle stern wake `Trail`/`Beam`.
2. **Force `Future` lighting & tighten the lantern (`Look.luau`, `LightingController.luau`):** `Lighting.Technology` is not explicitly set to `Enum.Technology.Future` in code, so Studio defaults can silently kill crisp lantern shadows. Meanwhile, the bow lantern uses `Range = 60` (Roblox's hard maximum) with `Shadows = true`, plus `Brightness = 1.3`, `ExposureCompensation = 0.3`, and `OutdoorAmbient = (64, 80, 80)`. That lights up too much lake at once, washes out dark silhouettes, and hurts mobile GPU performance. Cut lantern `Range` to `30-34` studs (plus a tiny low-range interior hull fill), drop `OutdoorAmbient` to `(24, 34, 38)`, and set `ExposureCompensation = 0.0`.
3. **Break the blank sky & add waterline mist:** `CelestialBodiesShown = false` and `StarCount = 0` leave a flat ceiling above the trees. Add a dark overcast `Sky` texture, a low-altitude `ParticleEmitter` mist ring following the boat 15-45 studs out at `y = 1.5`, and subtle `DepthOfFieldEffect` (`FarIntensity = 0.18`, `InFocusRadius = 35`) to give distant shore silhouettes weight.

---

## 3. Concrete Bugs & Release Blockers

- **Unimplemented Night 5 Finale & missing `Core.Rulebook` ([Night.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/Night.luau), lines 17-19):** `Night.debugForce("Finale")` currently does nothing, and `Core.Rulebook` is referenced but absent from `src/shared/Core/`. Either implement Rule 6 ("The Bell") before playtesting past Night 4, or cap the first build cleanly at a 4-night playable demo.
- **Dead `params.supplies` parameter ([Night.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/Night.luau)):** Between-night supply picks were cut on 11/26/2026, leaving `params.supplies` ignored while header docs still reference lantern refills. Remove the dead parameter and comment so Shell S2 scripts do not build against a removed feature.
- **Duplicate `WrongCatch` module names ([Fishing.luau](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/src/shared/Core/Fishing.luau), line 13):** Both `src/shared/Core/WrongCatch.luau` and `src/shared/Core/entities/WrongCatch.luau` share the exact filename. Rename the mutation/traits module to `FishMutations.luau` to prevent mis-requires.
- **15 pending audio uploads ([HUMAN_TODO.md](https://github.com/Samizdat-Publications/roblox-horror-game/blob/main/HUMAN_TODO.md)):** Four core sounds (`frog-bull-b`, `owl-hoot`, `line-creek`, `ghost-bell`), `ghost-loop`, and 10 Owner's Tapes are awaiting manual Studio upload and permission updates. Because Pillar #1 is "Sound is the HUD," these must be live before playtesting.

---

## 4. Prioritized Sprint Plan

| Priority | Target File(s) | Concrete Action |
| :--- | :--- | :--- |
| **P0 (Now)** | `Water.luau`, `Look.luau`, `LightingController.luau` | Swap `SmoothPlastic` for calm `Terrain` water, force `Future` lighting, cut lantern `Range` to 32 studs, lower `OutdoorAmbient` to `(24,34,38)`. |
| **P0 (Now)** | `Hum.luau`, `Knocking.luau`, `Neighbor.luau`, `BoatModel.luau` | Pause threat timers inside dock light + cut dock bite rate to `0.2x`; replace shore hard-stop with tangent sliding. |
| **P0 (Now)** | `HUMAN_TODO.md`, `SoundRegistry.luau` | Upload the 4 redone cue sounds + `ghost-loop`, publish privately as "Don't Wave Back," and grant audio permissions for Liam. |
| **P1 (Playtest)** | `Ghost.luau`, `Watcher.luau`, `Neighbor.luau` | Add ghost beacon/Watcher spotting + water-ripple bell ping; add solo Neighbor voice fallback; widen touch `edgeCone`. |
| **P2 (Core M5)** | `Night.luau`, `Fishing.luau` | Implement Rule 6 (`Finale`) + `Core.Rulebook`, strip dead `params.supplies`, rename `Core/WrongCatch.luau`. |
