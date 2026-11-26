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
