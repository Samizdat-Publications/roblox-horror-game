# Shell decisions

One line each: date, call, why. All reversible.

- 11/26/2026: Seat order for auto seating is helm, bow, port, starboard, so a solo player can steer.
- 11/26/2026: Only the helm occupant's BoatInput is accepted; others are refused and counted in Net.stats.
- 11/26/2026: The boat ties up 9 studs past `Config.Lake.dockEnd`, bow pointing out along the dock, so it does not overlap the dock planks.
- 11/26/2026: World parts are in collision group "World", boat parts in "Boat", and the two never collide; BoatService keeps the boat on the lake and clear of the dock, steeple and buoy itself. Characters stay in Default and collide with both.
- 11/26/2026: Collision groups use the WorldRoot methods (`workspace:RegisterCollisionGroup`); the PhysicsService ones are deprecated and are only the fallback.
- 11/26/2026: Only the Hull carries mass; every other boat part is Massless, so the drive constraints see a predictable assembly.
- 11/26/2026: Studio-only debug remotes (`DebugCamera`, `DebugBot`) live in a separate folder `DeadCalmDebugRemotes`, created only when `RunService:IsStudio()`. The production remote list is unchanged.
- 11/26/2026: World geometry modules have no requires (deps come in `ctx`) so `tools/shell/world_count.luau` builds the exact same world in Lune and catches bad property or enum names before Studio.
- 11/26/2026: The beacon is a steady warm light that blinks OFF twice every 6 s (rather than two flashes from dark), so the safe zone stays lit. Look.Beacon holds the timing.
- 11/26/2026: The beacon pole stands 6 studs east of `Config.Lake.beacon` so it does not sit in the dock's footprint.
- 11/26/2026: The steeple leans 20 degrees toward the lake center with its foot 14 studs under water, so the belfry and bell are submerged and the spire stands about 27 studs above the surface.
- 11/26/2026: Lake bed sits 4.5 studs below the water so a character who leaves the boat wades with the head above water.
- 11/26/2026: Lantern flicker and beacon blink run on the client (server time for the beacon, so all clients agree). The server owns only whether the lantern is lit.
- 11/26/2026: Seat occupancy reaches clients as an `OccupantUserId` attribute on each Seat (Seat.Occupant does not replicate).
- 11/26/2026: Until NightService exists, the client keeps a local NightView stand-in (Config defaults plus the boat's LanternOn and MotorOn attributes and the dock-light distance) so the HUD and mix always have a view.
- 11/26/2026: Malformed or over-rate client messages are dropped silently and counted in Net.stats rather than warned, so a client cannot flood the server console.
- 11/26/2026: Chorus layers, crickets, beds and the lake air are 2D; the wind in the trees plays from eight shore emitters; the radio, dock water, lantern flame and motor are spatial at their parts. Follows the `spatial` flag in audio/sounds.json.
- 11/26/2026: HUD uses the SpecialElite typewriter font (Enum.Font item confirmed in the current API dump) with a SourceSans fallback.

## Look pass 1 (11/26/2026)

- 11/26/2026: Seat facing: the boat already moors bow out (+z) and the helm and bow seats already face the bow (helm LookVector (0, 0.013, 1.0) at start); the backward view came from the Spawn facing south, because the first-person camera keeps its spawn yaw when seated. The Spawn now faces the lake (+z). A client-side snap of the camera to the seat's facing on sit would make this robust (client is outside this pass).
- 11/26/2026: Shore trees are now three kinds from the world seed: crooked broadleaf (two leaning trunk segments, 2 or 3 upward branches, a crown and one leaf clump), dead bare trees (paler wood, no canopy, 15 percent), and conifers (thin trunk, 3 or 4 narrowing block tiers, 35 percent). About one in eight is 56 to 80 studs tall. Tree count 230 to 190 to pay for the extra parts.
- 11/26/2026: The steeple is 30 percent taller along its axis, leans 18 degrees, and has a solid belfry with four dark openings; the belfry straddles the waterline, the bell stays just under it, and the cross tops out about 40 studs above the water.
- 11/26/2026: The steeple leans mostly across the boat's approach from the dock (70 percent sideways to the west, 30 percent back toward the dock), because a lean straight at the viewer is foreshortened and read as upright. BoatService's clearance follows via Landmarks.steepleWaterline.
- 11/26/2026: The beacon lamp is a 2.5 by 3 by 2.5 Neon block in warm amber (255, 190, 110) inside a dark cage of four bars, a crossed hoop, a cap and a finial, on a metal base. Name BeaconLamp and its BeaconLight are unchanged. WorldFx sets the lamp's Color to Look.Beacon.Color every frame, so the amber only shows once Look.Beacon.Color matches it.
- 11/26/2026: The dock cooler is a weathered DiamondPlate chest (120, 135, 125) with a darker metal lid band and two handles; the oil can is rust red-brown (110, 52, 38) Metal with a small spout. Colors live in Dock.luau, not Look.Palette.cooler.
- 11/26/2026: The boat's hold box is a wooden crate in hull tones (WoodPlanks, lid in trim Wood) instead of the tan plastic cooler color.

## S2 (11/26/2026)

- 11/26/2026: Core.Run does not exist yet, so NightService builds Story, Normal params from Config.Nights with no amendments (seam marked); quiet nights (DebugDriver) have no rules and zero real and fake budgets.
- 11/26/2026: Night 1 starts when the first player is seated (or 15 s after the first join), so loading does not eat the 6-minute night. The crew is fixed at night start; late joiners wait for the next night.
- 11/26/2026: 15 s after a night ends the next one starts by itself (a fail repeats the night, night 5 wraps to 1) until S4 adds the lobby and the five-night flow.
- 11/26/2026: The view is resent at most every 0.1 s and only when a coarse fingerprint changes (time left to 0.5 s, oil and tension to about 1 percent), to keep traffic low while idle.
- 11/26/2026: Every outgoing event is a sanitized deep copy that drops any `wrong` or `tier` key, on top of Core already stripping them, so a future Core event cannot leak them by accident.
- 11/26/2026: The fish builder lives on the server (world/FishModel). The client never builds fish: CatchInspect clones the fish on its own line from the workspace, and the Field Guide clones the book models the server puts in ReplicatedStorage.DeadCalmFieldGuide. One builder, so the held fish always matches the line.
- 11/26/2026: The held fish is a local copy in the world in front of the camera (not a ViewportFrame), so the boat's lantern lights it and a dark lantern makes it hard to see, as the design asks. The Field Guide drawing is a ViewportFrame with a sepia ImageColor3.
- 11/26/2026: Each seat has its own rod and casts the way the seat faces; the helm casts to the starboard quarter, clear of the motor.
- 11/26/2026: The hold shows in the world as fish tokens on the hold lid, not on the HUD (the HUD stays four things); the dock hint shows the count when banking.
- 11/26/2026: Cast is hold to charge, release to cast (power 0.2 to 1 over 1 s). E is keep, else bank, else refill; X is throw back, else reel in (CutLine). Space, R2, E and X use ContextActionService at High priority so Space never jumps; Cast and Use get the automatic touch buttons until MobileButtons (S4).
- 11/26/2026: The Studio auto-reel lives in DebugBot and sends the same ReelHold intents through Input.sendIntent: hold below 30 percent into the band, release above 70 percent, tension predicted between views from the Config.Fishing rates, under a 5 per second token bucket. A server fallback ("net") runs the same law through Net.handlers.Intent when no DebugBot answers.
- 11/26/2026: The chorus level is one client number shared by sound and fireflies: it moves between bands at 1/3 band per second and drops to 0 at once. Frog call gaps blend between bands on a log scale and stretch below band 1 as the chorus wakes.
- 11/26/2026: Frog calls come from a separate pool of 12 emitter parts placed just off the nearest shore (within 0.45 rad of the nearest shore point), so a reused emitter never drags a call that is still playing.
- 11/26/2026: The radio playlist forces Looped off for the tunes (the registry marks them looped) and on for the static, which stops after Look.Mix.radioStaticSeconds (4 s).
- 11/26/2026: The cassette effects (EqualizerSoundEffect low -14 dB, mid +2, high -12; DistortionSoundEffect 0.12) sit on the Voice SoundGroup. The docs show effects parented to a SoundGroup but give no gain ranges, so Studio must confirm the sound.
- 11/26/2026: Fireflies are 36 local Neon balls (half around the boat, half along the nearest shore): 15 percent lit at band 1, 55 at band 2, all at band 3; at band 0 they freeze for 0.6 s, then fade over 2.5 s.
- 11/26/2026: Night cards are simple for S2: "Night N" on start, and a clear or fail card with banked points, fish landed and one dry tally line per player. S4 replaces them.
