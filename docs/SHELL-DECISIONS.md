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

## Inspect fixes (11/26/2026)

- 11/26/2026: The held fish is posed from a frame measured off its own parts (Body center to the Mouth for the head, the back fins for up, the body axes only as a fallback), not from the model's pivot, then set side-on to the camera: head right, tail left, back up, about 3 studs out at 29 percent across and 44 percent down the screen. It is scaled (Model:ScaleTo) to fill a third of the screen height, capped at 46 percent of the width so it stays clear of the Field Guide card, and sways only slightly (yaw 0.12 rad, roll 0.05 rad).
- 11/26/2026: When a fish is landed the server removes that player's bobber and its line, including any stray `Bobber_<id>` left in the fishing folder, and any older fish still on the line; the next cast builds a fresh bobber and line. While the copy is held up, the client also turns off the original fish's lights (a glowing fish's pale green light) along with hiding its parts and its line.

## S3 (11/26/2026)

- 11/26/2026: Presentation every player must share lives on the server (EntityPresenter: hidden characters, the floating hat, the dropped rod, the Neighbor's silhouette in the boat, knocks on the hull); anything an `only` cue may show to one player is built on the client from events (fx/*), so `only` is respected for free.
- 11/26/2026: The drowned stay in their seat with the character hidden (all parts and decals transparent) instead of being unseated, so camera and physics need nothing new; the server refuses their helm input (`Net.isDrowned`) and the client stops sending it.
- 11/26/2026: Knocks have no Core event, so the server plays `knock-answer` as a server Sound on the hull for every Knock intent (everyone hears it), and the knocker's client adds a small jolt at once.
- 11/26/2026: The drowned's lights are built on every client from the view (players[].alive), not on the server, so they move smoothly with the boat.
- 11/26/2026: The floorboard buzz uses five local slat parts laid over the hull floor and moved with the hull every frame, rather than moving the server's welded boat parts on the client.
- 11/26/2026: The Watcher's stare (tone and vignette) is judged on the client from the camera's look and Config.Rules.Watcher.stareCone, matching what the server judges from the reported gaze.
- 11/26/2026: On a pass the Watcher is simply not there: it is removed the moment it is off screen, or after 6 s.
- 11/26/2026: The vignette is four black edge bands with UIGradient transparency, no image asset (no invented ids).
- 11/26/2026: Death card texts live in the client (`ui/DeathTexts`) as the brief asks, in the owner's voice; they match Core.Rulebook's lines in meaning, with the rule number on its own line.
- 11/26/2026: The end-of-night card waits until the death card is gone (at most 15 s), so the last death reads first.
- 11/26/2026: Wave in the callout wheel sends both the Callout (a "(waves)" tag) and the Wave intent; there is no separate wave button.
- 11/26/2026: Callouts also go to a short feed at the bottom left: a tag over a head behind you is easy to miss, and your own tag is inside your head in first person.
- 11/26/2026: Bail is "hold E" while there is water in the boat (and no fish to decide on); knock is Q, L1 or a touch button; callouts are C, D-pad up or a touch button.
- 11/26/2026: Studio scenarios get Fakeout events built with Core.Fakeouts.event and sent through `NightService.debugEmit`; ChorusDip's chorus timer stays Night's, so it shows nothing in that scenario.
- 11/26/2026: wrongcatch_fail shortens the cooler's knock delay to 8 to 10 s with a Studio-only `rulesPatch` on a copy of Config, to stay under a minute; Config.luau is untouched.
- 11/26/2026: Added registry entry `rod-clatter` (id 0) for the rod dropping into the boat.

## Studio and Neon fixes 11/26/2026

- Fix 1, drowned view: the death card times out after 4 s (a tap closes it after 0.6 s), the drowned camera starts under the black and the black lifts into it; the view is a high three-quarter orbit (radius 18, height 12) that drifts slowly, with a cold blue-green ColorCorrection on the local camera and a dim cold PointLight 22 studs over the boat, so the boat reads even with the lantern out. The Neighbor's silhouette in the boat, the Watcher at the waterline (12 s) and the Hum's shape (20 s) stay outlined for the drowned. Solo: the night-failed card waits 4 s of drowned view after the death card.
- Fix 2, clean starts: every rule scenario begins with `fullReset` (clean every client: no death card, night cards, catch card or rule leftovers, first-person camera, tape cut and tapes muted; then a fresh quiet night, helm seat, lantern lit, motor off, boat at the scenario's spot). New `reset` scenario (opts.scenario applies that scenario's seed, spot and patch) and opts.reset = false on every scenario, so a recording can start after the reset. `night_start` and `quiet_night` unmute tapes.
- Fix 3, framing: DebugBot "track" keeps the camera (and so the gaze the server reads) on the Neighbor's or the Watcher's drawn figure every frame, pitch included, from the cue on, and keeps it there through a fail. The Neighbor scenarios patch it close with rulesPatch (appearDist 80, driftSpeed 1.5, holdDist 40, linger 12 to 14 s, leaveDist 120); results report the server-side gaze error. Interpretation: "replicated head-look" is the gaze yaw the client reports from its camera (what Core judges); the character's head is not posed for other players.
- Fix 4, Hum fail: a local copy of the boat rolls and heaves for 1.2 s (the server boat is hidden locally with LocalTransparencyModifier) and the camera rolls with it; 1 to 4 fish and a bucket fly over the gunwale and splash (hold-lost-splash at each); then the taken player's camera drops under the surface with an underwater tint, blur and death-drag, and the death card's fade waits 1.75 s (DeathCard.LEAD_IN.Hum). Layered: hum-fail, hold-lost-splash, death-drag. The death sting now ramps in over 0.18 s (the likely pop), and the night-failed sting and tape moved to the end card.
- Fix 5, moonlight: while the lantern is out WorldFx fades in a cool PointLight (brightness 0.85, range 50) 26 studs over the boat and lifts OutdoorAmbient locally from (64, 80, 80) to (82, 100, 108); both fade out as the lantern comes back, so the lit lantern stays the warm, bright thing.
- Fix 6, motor: the motor-idle-loop layer was already wired to the Motor part (spatial) with motor-start and motor-stop and the chorus duck; added a shaking local copy of the outboard while it runs, a "Motor: on" line on the HUD paper, and motor layer details in AudioDirector.debugState for the Studio check.
- Fix 7, tapes: any EntityCue cuts the tape (fades in 0.25 s, then ui-tape-stop), a new night cuts a leftover tape, and a Tape event is taken only within 3 s of NightStarted. Interpretation: the night-failed "Rough night" tape still plays, but only with the end card, after the death card and the drowned beat.
- Fix 8, death cards: every line in DeathTexts now states what went wrong and the counter in the owner's dry voice; "Rule N." stays on its own line.
- Fix 9, card jumping: cause not reproduced from code. The card is now a fixed offset size (480 by 200, narrowed only on small screens and refit on viewport change), centered at (0.5, 0.5) on a gui with IgnoreGuiInset and ScreenInsets None, text centered with a size cap, and nothing moves it while it is up.

## Derived sounds 11/26/2026

Audio uploads are capped until about 12/26/2026, so 28 id-0 entries now carry a `derive` table and are built in the engine from sounds we already have (docs/SOUND-DERIVED-PLAN.md). AudioDirector plays them by the same name through `play` and `loop`; callers do not change. Starting volumes are conservative and every recipe is a first guess to tune by ear and with Neon. When a real upload lands: set the id, delete the derive table.

APIs used, checked against create.roblox.com/docs (and the creator-docs YAML for ranges) on 11/26/2026, none deprecated: Sound.PlaybackSpeed, TimePosition, PlaybackRegion with PlaybackRegionsEnabled (seconds of the source; LoopRegion left unset so a loop uses the PlaybackRegion), Looped, Destroying; EqualizerSoundEffect, ReverbSoundEffect, EchoSoundEffect, DistortionSoundEffect, PitchShiftSoundEffect, ChorusSoundEffect, TremoloSoundEffect and SoundEffect.Priority. Allowed classes and properties are listed in `SoundRegistry.EFFECT_PROPS`.

"Low-pass" below means an EqualizerSoundEffect with HighGain -30 dB and MidGain -8 dB. "Far reverb" is a ReverbSoundEffect with DecayTime 4, DryLevel -10, WetLevel 0. "Room" is DecayTime 2, DryLevel -4, WetLevel -6.

| Entry | Vol | Source | Recipe as built |
|---|---|---|---|
| neighbor-oarlock-loop | 0.55 | oarlock-creak | speed 0.8, replayed every 2 s while the loop lives, low-pass, far reverb |
| neighbor-pass | 0.55 | oarlock-creak | as the loop, lasts 6 s, fades out over the whole 6 s |
| neighbor-fail | 0.75 | lantern-off | then hull-creak at 0.8 s, speed 0.7, layer volume x1.2 (2D, close) |
| knock-pass | 0.6 | hull-creak | speed 0.6, low-pass; dock-water-loop layer at 0.6 s for 2 s, fade in 0.6 s, out 1.2 s, x0.7 |
| flood-in-loop | 0.8 | dock-water-loop | speed 1.3, EQ HighGain -12 dB, looped |
| boat-sink | 0.7 | hold-lost-splash | death-drag layer at 0.6 s |
| lake-groan | 0.6 | hum-fail | speed 0.45, reverb DecayTime 8, DryLevel -4, WetLevel -2 |
| lake-silence-drop | 0.6 | hum-pass | region 0 to 1 s, speed 0.6 (the ambience mute is not built, see below) |
| lanterns-die | 0.6 | lantern-off | layers of lantern-off at 0.15 s (speed 0.94) and 0.3 s (speed 1.07) |
| watcher-tone-loop | 0.12 | hum-hold-loop | two PitchShift Octave 2 (two octaves up), EQ LowGain -40, HighGain -18 (narrow band), Tremolo 0.4 Hz depth 0.6 |
| watcher-step | 0.5 | dock-creak | region 0 to 0.6 s, speed 0.7, low-pass, room reverb |
| watcher-lunge | 0.8 | dock-creak | region 0 to 0.6 s at speed 1.4, three times 0.3 s apart (two layers) |
| watcher-fail | 0.7 | hum-pass | region 0 to 1 s, speed 0.6; fish-release layer at 1.8 s, speed 0.6 |
| watcher-pass | 0.5 | bed-wind-trees | 4 s, fade in 1.5 s, fade out 2 s |
| wrong-blink | 0.35 | lantern-squeak | region 0 to 0.1 s, speed 2.5 |
| wrong-glow-loop | 0.12 | hum-hold-loop | three PitchShift Octave 2 (three octaves up), Tremolo 3 Hz depth 0.5 |
| cooler-knock-inside | 0.6 | knock-answer | EQ HighGain -35, MidGain -12 (muffled), repeat 3 times 0.9 s apart |
| cooler-eaten | 0.65 | cooler-close | speed 0.7; fish-land-thud layer at 0.2 s, x0.9 |
| fake-lantern-flicker | 0.5 | lantern-flame-loop | 1.2 s, fade in 0.2 s, out 0.4 s, Tremolo 7 Hz depth 0.8 (the dip and rise) |
| fake-loon-scream | 0.7 | loon-call | speed 1.15, Distortion Level 0.2 |
| rod-clatter | 0.6 | fish-land-thud | speed 1.6 |
| ui-tick | 0.35 | cooler-close | region 0 to 0.06 s, speed 2.2 |
| ui-stamp | 0.45 | knock-answer | region 0 to 0.18 s, speed 1.5 |
| callout-blip | 0.35 | knock-answer | region 0 to 0.06 s, speed 2.6 |
| title-theme | 0.5 | radio-tune-1 | as it is, looped |
| run-cleared | 0.5 | radio-tune-2 | up to 40 s, fades out over the last 4 s |
| night-cleared-sting | 0.5 | quota-met | as it is |
| night-failed-sting | 0.5 | death-sting | as it is |

Also: `knock-three-soft` and `knock-three-hard` (library single thuds) get `["repeat"] = { count = 3, gap = 1.1 }`. `repeat` works on any entry. Knocking passes the server's gap (`data.gap`, default 1.1) as `repeatGap` so the sound and the jolts stay together, and a reset or a new round cancels knocks still to come.

Calls made while building:

- Two or three octaves up: PitchShiftSoundEffect.Octave tops out at 2 (one octave), so the effects are stacked. PlaybackSpeed was not used for it because Watcher sets the tone's PlaybackSpeed every frame.
- No band-pass class exists; an equalizer with low and high cuts stands in.
- Region times are seconds of the source (PlaybackRegion is in source seconds; TimePosition advances at PlaybackSpeed per second). wrong-blink takes the first 0.1 s of the source literally, heard as 0.04 s at speed 2.5; widen the region if it is too short.
- The dock-creak "first footstep" is assumed to be the first 0.6 s, and neighbor-fail's 0.4 s gap after lantern-off is a fixed 0.8 s delay (the lantern-off length was not measured). Both are guesses to fix by ear.
- An entry's `volume` is the final level of the first piece (so `AudioDirector.baseVolume` and Watcher's fade stay right); a layer's `volume` multiplies it.
- `opts.speed` on `AudioDirector.play` now multiplies PlaybackSpeed instead of setting it (same result for plain sounds, keeps a derived entry's speed).
- Not built: lake-silence-drop's "then all ambience muted" is behavior, not a sound; nothing calls lake-silence-drop or lake-groan yet. title-theme "without the radio filter": the filter is baked into the radio tunes, so they play as they are.
- Server sounds: `EntityPresenter.play` (server, outside this task) does not read `derive`. `SoundRegistry.uri` now resolves a derived name to its source, so the server's rod-clatter plays fish-land-thud unshaped instead of nothing. The derive shaping on the server is a follow-up for whoever owns src/server.
- Still silent (not in the plan's table): ui-book-close, ui-envelope, ui-pencil-scratch, ui-tape-click, ui-tape-stop.

## S4 (11/26/2026)

- 11/26/2026: NightService owns the run (Core.Run); LobbyService owns the title flow and the timing between nights (12 s to the next night, 30 s on the run's end card, then the title). Nights started by Studio scenarios are outside the run and advance nothing.
- 11/26/2026: Nights outside the run are built by a throwaway Normal first run at that night, with the scenario's seed used as the night seed, so S2 and S3 scenarios replay as before (night 5 scenarios now carry the first run's one amendment).
- 11/26/2026: The server starts on the title screen; nothing runs until the host presses Play (the S2 auto start when the first player sits is gone). Any night start, a Studio scenario included, takes the title down.
- 11/26/2026: The host is the first player in the server; when the host leaves, the next player in the list takes over. Only the host picks the difficulty, starts, or leaves the run's end card early.
- 11/26/2026: The book flag and the touch flag ride the Lobby remote ("Book", "Touch") rather than new Intent kinds, so Core's intent list is untouched. While the book is open the server refuses intents that need hands and the helm goes slack; letting go of the reel and the bail is always allowed.
- 11/26/2026: Tonight's page reaches clients on LobbyState (rules, newRules, amendments); the client builds the text with Core.Rulebook (page and TEXT), which is in ReplicatedStorage.
- 11/26/2026: An amendment is drawn as the printed rule crossed out (RichText strikethrough, faded) with the new line under it in the amendment ink and handwriting, a little crooked. Fresh tape and a "taped in tonight" pencil note mark tonight's new rule.
- 11/26/2026: "Opens from the boat": a small paper block on the stern thwart with a ClickDetector (on a client-made part; the docs do not say whether client-side ClickDetector events fire for local parts, so Studio must check). R, the D-pad and the Book button always work.
- 11/26/2026: Gamepad: D-pad left rulebook, D-pad right Field Guide, B shuts the book; the guide turns pages with the shoulders (L1 knock is blocked while the book is open). Title: A plays, X toggles the difficulty, Y opens the Lake Rules.
- 11/26/2026: MobileButtons replace the ContextActionService touch buttons. Layout is computed from the screen size: Cast (84 px at 338 tall, scaled up to 1.6x on bigger screens), Use and Knock in the bottom right around Roblox's default jump button rectangle (70 px at 95 and 90 from the right and bottom when the short side is 500 or less, else 120 px at 170 and 210; from the PlayerModule as remembered, the source could not be fetched); six 54 px buttons in two columns on the left edge so the move stick can still start in the open middle. Touch is chosen by UserInputService.PreferredInput when present, else TouchEnabled without a keyboard.
- 11/26/2026: Late joiners are hidden in a seat through EntityPresenter (so Net.isDrowned refuses their helm) and watch from the drowned view with their own tag and no bell until the next night.
- 11/26/2026: The night start card carries the words of tonight's tape (Rulebook.TEXT) for players with the sound off; the run-cleared card carries the run-cleared tape's words.
- 11/26/2026: The finale's "every water sound stops" fades the DeadCalmAmbience SoundGroup to 0 from fx/Finale (AudioDirector has no public call for it and was being edited by another builder); it is restored on pass, fail, reset and the title. All finale sounds go through AudioDirector.play and loop.
- 11/26/2026: The locked lantern is shown by two dark bands clamped round the lantern glow and a small Neon flame inside it that shrinks and reddens with the oil, plus "Oil (locked)" in the amendment ink on the HUD. There is no dock bell in the world, so fx/Finale puts a small bell on a post at the dock end when it rings (local).
- 11/26/2026: Dawn after the finale's pass is a camera ColorCorrection tint toward the dawn color over 6 s (local), cleared at the next night or on the title.
- 11/26/2026: full_run and finale use a server crew bot (DebugCrew, a port of crewbot "follow") that hands Night its intents directly and steers through BoatService.setHelmInput(nil, ...): the remote paths are proven by S2 and S3, and a five-night run through Net would trip the per-player rate limits. full_run's fast clock scales the quota by seconds / 360 (rounded up).
- 11/26/2026: The finale scenario starts night 5 of a run with quota 3, jumps the raw clock to 3:50 AM and puts a book-true Steeple Cat in the hold, so getting home banks the cat, clears the night and clears the run.

## Scare polish 2 (11/26/2026)

From Neon's listening test (`docs/critic/11-26-2026-derived-sounds-listen-neon.md`: oarlock 1/10, knocks 1 and 2/10, footsteps 1/10, Watcher tone 8/10) and the second Hum fail review (4.5/10). Items 0 to 6 of `docs/SCARE-POLISH-2.md`.

### The mix (item 0)

Cause found: not only the ambience level. The first listening test played every spatial cue at the hull, but the real Neighbor and Watcher cues play 90 to 260 studs away, where the old rolloff (minDist 20 or 40, InverseTapered) took 12 to 17 dB off; and the "far" recipe itself took most of the creak away (EQ HighGain -30, MidGain -8, reverb DryLevel -10). So distance now comes from reverb and a gentle high cut, minDist covers the real distance, and the Ambience group is lower and ducks.

SoundGroup levels (Look.Mix.groups; SoundGroup.Volume ranges 0 to 10, creator docs YAML):

| Group | Before | Now | Change |
|---|---|---|---|
| Ambience, below band 2 | 0.9 | 0.75 | -1.6 dB |
| Ambience, at band 3 (band3Trim 0.6, eased in from band 2) | 0.9 | 0.45 | -6.0 dB |
| Ambience, during any rule cue (cueDuck 0.4) | no duck | x0.4 | -8 dB more (band 3: 0.18, -14 dB from before) |
| Ambience, death card up | 0.9 | 0 | muted from the fade to black until the card goes |
| Boat | 0.8 | 0.8 | random hull creaks and shore wildlife skip while ducked |
| Rule | 1.0 | 1.6 | +4.1 dB |
| Fishing, UI, Music, Voice | 0.8, 0.6, 0.6, 1.0 | same | |

Ducking: any Rule-group sound that is playing above volume 0.02 ducks the Ambience group (entries can opt out with `duck = false`; only ghost-loop does), and every EntityCue holds the duck for Look.Mix.cueHold (3 s) even before its sound loads. Attack 0.12 s, release 1.0 s. The Hum already silences the chorus by design; its loops duck the beds too.

Cue entries (volume is the entry's; final level is entry x group):

| Entry | Volume before, now | Rolloff min/max before, now | Shape now |
|---|---|---|---|
| neighbor-oarlock-loop, neighbor-pass | 0.55, 1.3 | 20/400, 160/900 | EQ HighGain -12, MidGain -2; reverb DecayTime 3.5, Dry -4, Wet -3 |
| knock-three-soft | 0.7, 1.3 | 4/90, 14/120 | plays under the keel, `with` knock-thump-soft |
| knock-three-hard | 0.7, 2.0 | 4/90, 14/120 | plays under the keel, `with` knock-thump-hard |
| knock-thump-soft (new, derived) | 0.8 | 14/120 | fish-land-thud at speed 0.55, 0.35 s, EQ Low +6, Mid -8, High -30, three times |
| knock-thump-hard (new, derived) | 1.3 | 14/120 | fish-land-thud at speed 0.45, 0.45 s, EQ Low +8, Mid -6, High -30, three times |
| knock-pass | 0.6, 0.9 | 4/90, 14/120 | under the keel |
| fake-single-knock | 0.7, 1.2 | 4/90, 14/120 | under the keel |
| watcher-step | 0.5, 1.3 | 40/700, 150/900 | EQ Low +3, High -12, Mid -2; reverb 2.5, Dry -3, Wet -5 |
| watcher-lunge | 0.8, 1.5 | 40/700, 150/900 | as before |
| watcher-tone-loop | 0.12 | 2D | second PitchShift 1.8 instead of 2 (about two semitones lower) |
| cooler-knock-inside | 0.6, 1.1 | 4/90, 30/300 | EQ Low +4, Mid -8, High -30 (muffled but present) |
| hum-rise, hum-hold-loop | 0.7, 0.9 | 2D | the loop now starts with the rise |
| hum-hull-resonance (new, derived) | 0.55 | 2D | hum-hold-loop two octaves up (PitchShift 2 twice), Distortion 0.18, EQ Low +2, Mid -9, High -30 |
| motor-idle-loop | 0.7, 1.4 | 4/90, 12/140 | layer level motorIdle 0.8 to 1.0 |

Calls made:
- New registry fields: `with` (companion entries started at the same place with the same options, stopped with it) and `duck` (false opts a Rule sound out of ducking). A real-id entry cannot carry a derive (the lint), so the knocks' thump is its own derived entry started through `with`.
- Knocks play from AudioDirector.under(): an invisible part that follows the hull 1.6 studs under the keel.
- Band 3 trim is applied to the Ambience group, not the layers, so the single frog calls (one-shots in the Ambience group) come down with the loop.
- fx/Finale tweens the DeadCalmAmbience group's Volume itself. AudioDirector now writes that group every frame, so it reads a change made by someone else as a new base and rides on top of the tween instead of fighting it. Cleaner: Finale calls `AudioDirector.muteAmbience("Finale", on)` (logged under Needed from S4).
- WrongCatch started cooler-knock-inside three times, and the entry itself repeats three times: nine knocks. It now starts it once with repeatGap = KNOCK_GAP.
- Listening test: `play_sound` plays each cue where the real fx would (AudioDirector.auditionSpot: the Neighbor 200 studs off the bow, 40 degrees to one side; the Watcher, branch snap and loon scream on the nearest shore; the buoy clank 150 studs to port; knocks, flooding and bailing under the keel; cooler sounds at the dock cooler; lantern and motor sounds at those parts; 2D entries in 2D), through the same group and ducking. `ambience = true` holds the chorus at band 3 (full loop, crickets, single frogs, band-3 trim) for the cue's length plus 6 s, so a sequence of cues never drops to silence between them; `stop_sound` releases it.

### Fail moments (items 1 to 6)

- Capsize: one big throw (roll 0.85 rad, heave 1.8 studs, periods 0.95 s and 0.6 s) that dies away over the full 1.2 s and ends level, instead of a fast 0.55 s wobble. A white foam burst of 30 Neon flecks at both gunwales and two pale foam rings, a brief cold PointLight on the thrown copy (brightness 1.8 fading to 0 over the throw) so it reads with the lantern out, and loose gear: the bucket (paler), an oar and an orange tackle box join the fish. Under the surface, 22 bubbles rush up past the camera. Interpretation: the flash is a stylized cue for phones, not a light in the world; it is the most reversible choice (BoatFx.FLASH).
- Motor: louder loop (see table), the outboard copy shakes more (0.06 studs) and a faint camera rumble (0.008) runs while the motor is on and you are alive. `AudioDirector.debugState().motorIdle` now also reports soundVolume and group, plus the group volumes, duck and mute.
- Hum on a phone: hum-hull-resonance swells in over 1.6 s with the rise and the hold loop (1.0 s); camera rattle at full buzz 0.04 (was 0.02); rings of 28 short Neon segments spread on the water around the hull every 0.8 s while the hum builds, 10 to 44 studs across over 2.6 s.
- Silence to hum: the gap was Config.Rules.Hum.silence (2.5 s) plus the client waiting 2.2 s for the hold loop while hum-rise starts softly. Now silence is 1.3 s (logged in CLOUD-DECISIONS) and the loop and the resonance start with the Window stage, so the hum is heard about 1.5 s after the frogs stop.
- Death card: about 70 percent of the screen width (clamped 300 to 980 px, never wider than the screen less 24 px), height 0.42 of the width, text sized from the width (main up to 54 px, scaled down to fit), both lines in the marker hand in near-black ink on opaque paper with a dark 3 px edge; held 5 s or until a tap (after 0.6 s). The ambience is muted from the fade to black until the card goes.
- Clean state: the hint line goes blank the moment the boat is thrown, while the camera is under and while the death card is up; "Motor: on" is hidden for the drowned; the drowned view opens on the boat still rocking for 5 s (a local copy, no camera roll); your own ghost light carries a small "You" (BillboardGui, marker hand).

## S5 Saves and Endless (11/26/2026)

- 11/26/2026: The store backend is decided once per server (`DataStores.open`): memory when `game.PlaceId == 0` or when a probe `GetAsync` errors (Studio access to API services off); else the real DataStore. The memory store is announced with one print, `[DeadCalm] saves are in memory this session: <reason>`, so Studio output now has three normal lines.
- 11/26/2026: Store names `DeadCalmProfiles_v1` (keys `u_<userId>`, user id passed as the user data tag on writes) and `DeadCalmBestEndless_v1` (ordered, keys `<userId>`, values `Leaderboard.encode`). A published place in Studio with API access writes real data (needed to test M7); `unlock_all_debug` sessions never save.
- 11/26/2026: Each real call waits up to 6 s for request budget (legacy type first, then the Standard or Ordered type, whichever the engine answers); after that it tries anyway and SaveLogic's retries and backoff handle errors. No retries in the adapter itself.
- 11/26/2026: What counts: only run nights (LobbyService runs) record progress; Studio scenario nights outside a run earn nothing. Every crew player at the night's start gets the night's crew totals (fish banked, scares survived), per CLOUD-DECISIONS.
- 11/26/2026: Saves happen when a run night ends (every crew player), when a player leaves, and in BindToClose (all sessions in parallel, waits up to 25 s). Equipping does not save at once; it rides on the next save.
- 11/26/2026: The best Endless night goes to the board after each cleared Endless night (SaveLogic.submitBest only raises it). The board is read at start and at most every 60 s, plus right after a raise; top 10 shown, names from `UserService:GetUserInfosByUserIdsAsync` (display names, "A fisher" if the lookup fails). No user id ever reaches the client.
- 11/26/2026: The boat is shared, so it wears the HOST's lantern and paint; each player's hat is their own. ASSUMED, reversible (Cosmetics.applyBoat takes any pair).
- 11/26/2026: Endless Nights opens when the HOST's profile has a cleared run (`stats.runsCleared >= 1`), checked on the server for "Mode" and again at "Start". Play sends Mode Story then Start; the Endless button sends Mode Endless then Start (Validate.LOBBY already has "Mode").
- 11/26/2026: Hats are an Accessory named `DeadCalmHat` (two Fabric cylinders, crown and brim, an Attachment named HatAttachment, `Humanoid:AddAccessory`, a hand weld to the head if no attachment matched). Avatar hats are hidden under it (Transparency 1, original kept in the `DeadCalmStowed` attribute) and come back on "No hat". The floating hat on a death is the earned hat (EntityPresenter now keeps welds inside the hat and skips hidden avatar hats).
- 11/26/2026: Paint colors the outer planks only (sides, transom, bow planks); floor, benches and trim stay wood. Bare Wood restores each plank's built color. Lantern colors set both the PointLight and the Neon ball (the ball deeper, since bloom washes it out).
- 11/26/2026: Cosmetic names, swatches and how-to-earn lines live on the server (`Cosmetics.ITEMS`, `Profile.UNLOCKS` text) and reach the client in the Profile payload, so there is one copy. Look.luau was not touched.
- 11/26/2026: The Locker is a BookState page ("locker", title only, like the Lake Rules), so Escape, gamepad B, the dim and Close shut it and the title's keys pause while it is open. Keyboard K, gamepad R1. Endless has no keyboard key (E is the boat's interact key and is bound at High priority).
- 11/26/2026: Endless text: HUD "Endless night N"; start card "Endless night N" and "Any rule, any night. One try."; end card "Endless night N next. It gets worse." or "The lake does not give Endless nights back. The run is over."; run card "The Endless run is over." with the best night reached.
- 11/26/2026: `MonetizationStubs` has a commented idea list (look-only packs), every gamePassId 0, no MarketplaceService, and functions that return false or {}. Nothing calls it yet.
- 11/26/2026: The client says Hello on the Lobby remote once listening; the server answers with the LobbyState and the Profile, so a Profile fired before the client connected is never lost.

## S6 Docs (11/26/2026)

- 11/26/2026: `SOUNDS_NEEDED.md` is generated from the registry, sounds.json, tapes.json and ids.json (status: uploaded, library stand-in, derived, missing). Search terms are the first few content words of each prompt; regenerate it when ids change rather than editing rows by hand.

## Polish 3 (11/26/2026)

From Neon's finale review (`docs/critic/11-26-2026-finale-neon.md`, 1.5/10, all five fixes), rows 2, 3, 4 and 6 of `docs/reviews/2026-11-26-gemini-hydrogen-verdict.md`, and the title and rulebook notes. All reversible; numbers live in `Look.Finale`, `Look.Dawn` and the module constants.

- The turn: fx/Finale no longer writes the DeadCalmAmbience SoundGroup. At the cue it calls `AudioDirector.muteAmbience("Finale", true, 0.08)` (muteAmbience gained an optional fade in seconds) and the new `AudioDirector.hush("Finale", on)`, which takes every group except Rule (motor, lantern, fishing, music, tapes) to silence over `Look.Mix.hushFade` (0.12 s). 1.5 s later (`Look.Finale.silence`) the hush lifts, the bell tolls three times 1.7 s apart (`finale-bell`, derived from bell-dock-solo with an echo and reverb, audible from 160 studs at full level, played at 1.6x), the bell swings on a post at the dock end and "The bell. Go home." punches in (PermanentMarker, about 60 px at 600 px tall, pale ink, dark UIStroke). The muffled hum-pass "lake-silence-drop" is no longer played: the silence itself is the cue.
- The night start card is hidden on the Finale's EntityCue; the tape is already cut by AudioDirector on any cue. The `finale` scenario now starts `opts.lead` seconds (default 22) before the bell instead of at 3:50 AM, so the 4 s card and the night 5 tape finish before 4 AM on camera.
- The run: a SpotLight on an invisible part at the lantern, aimed forward and 24 degrees down (brightness 7 scaled by oil, range 58, angle 70, gutters below 15 percent oil), plus up to 34 pale flecks laid on the water 7 to 38 studs ahead in the cone that stay put as the boat passes (1.3 s life), so speed reads. The real beacon gets a 90-stud Neon shaft (45 percent transparent) and an AlwaysOnTop halo of three round frames sized 26 studs plus 46 px (it grows as you come in), both following `WorldFx.beaconDark` (the double blink).
- Hazards are drawn closer than Core holds them: only the gap beyond the kill distance (45 for boats, 60 for false beacons) is scaled by `Look.Finale.pull` (0.5), so a strike lands where the hazard looks to be. Neighbor boats: brighter lantern (range 44, brightness 3.2) hanging from a hook and swaying, the oarlock loop at the hull. False beacons: a flame-like flicker with short dropouts (never the clean double blink), a thin pitched whine (`finale-hazard-whine`). A toll through water (`finale-hazard-toll`) marks each appearing.
- The chase: `finale-chase-drone` (hum-hold-loop at 0.7 speed, tremolo, low shelf) and `finale-chase-under` (finale-bed at 0.8 speed, high cut, reverb) replace the plain finale-bed; the drone's tremolo runs 1.6 Hz at speed up to 4.5 Hz as fear rises. Fear = the larger of how slow the boat is (below 3x stillSpeed, weighted 0.45) and how long it has sat still against the stop limit Core sent in the cue; the vignette (four edge bands, no image asset) follows it to 0.85.
- The HUD: the oil bar has its own 14 px row; it pulses red (1.2 to 3.5 Hz, faster as it drains) below 35 percent oil and all through the finale, where the label reads "Oil: locked on". The paper uses AutomaticSize. On the last night a line under the quota reads "Owner's fish: aboard" or "Owner's fish: not yet". NightService adds `specialAboard` and `specialSpecies` to the replicated view on a finale night; it checks the species only, never whether the fish is true to the book (that would leak `wrong`). The quota line stays because Core still needs the quota on night 5.
- No hint at all during the finale. While the motor runs, no fishing hint; the rule verbs (bail, knock) still show, since a leak or a knocking can come with the motor on. ASSUMED, reversible (Prompt).
- Dawn: Look.Dawn holds the sunrise (ClockTime 6.3, warm ambient and outdoor ambient, a thinner warm fog, a warm color correction). fx/Finale saves the Lighting, Atmosphere (DeadCalmAtmosphere) and ColorCorrection (DeadCalmColor) values and tweens to the dawn over 2.6 s, then puts them back exactly at the next night or on the title. `WorldFx.ambientOverride` stops the moonlight from writing OutdoorAmbient meanwhile. The water comes back (unmute over 2.5 s), dawn-cue, then `dawn-birds` (a stand-in: peepers sped up into chirps with a far loon; no bird recording exists) and a bold paper banner "Dawn. You made it home." (5.5 s). The run card now waits 5 s after the clear (was 2.5) so the sunrise is seen first. "The fog fades up and warm" is read as: the fog lightens, thins a little and turns warm.
- Night start card: a small strip at the top middle (max 440 by 140), "Night N" and one or two short lines, 4 s, no tape words. Night 5 says "Quota N, and the owner's Steeple Cat."
- Title: the name is hand lettering straight over the lake (about 72 px at 600 px tall, pale ink, dark stroke), shifted right of Roblox's own buttons by `GuiService.TopbarInset`; both paper panels use AutomaticSize and shrink to their content; the left wash is lighter (0.5, fading out by 45 percent across). Short screens show the top five Endless rows. The difficulty notes read retries from `Config.Difficulty` (Normal "Three retries", Nightmare "One retry").
- Rulebook: an amendment whose text starts with "And" or "Also" adds to the rule (the printed line stays, the new line goes under it in red ink); any other amendment strikes the printed rule. The real cause of the list running past the paper: `ClipsDescendants` is ignored under a rotated ancestor (creator docs, GuiObject.ClipsDescendants, checked 11/26/2026), and the book page was rotated. The page and the rule blocks are now unrotated. Tape strips are 58 by 17, translucent, rotated only 6 to 7 degrees, straddling the top corners; since rotated descendants may still escape clipping, a strip is hidden while its center is outside the visible list.
- Boat feel: on contact with the shore, the dock or an obstacle the speed loss is drag over time scaled by how squarely the bow meets the edge (5 per second at head on), so a glancing boat slides along; nearly head on (more than 0.85) it still halves at once, so a boat rammed into the shore never counts as moving. Turning is damped by up to 35 percent below 3 studs per second. Both in the BoatService kinematics seam (server).
- Ghost bell: every client draws a ripple ring (36 pale segments, 3 to 70 studs over 3.2 s) from that ghost's light; the living also get a pale "bell" marker on the screen edge toward it for 3 s. The ghost's light is the only position the drowned have (Core's GhostBell carries no direction).
- The drowned see a faint outline (outline only, 50 percent transparent) on the real dock beacon lamp and on no false beacon: false beacons in fx/Finale and fx/Neighbor are no longer outlined.
- Deciding timeout: over the last 3 s the held fish thrashes (tail flick, twist and a small hop, faster and wider toward the end) and the timer bar turns red; a timeout Release shows "Too slow. It slipped back." for 2.5 s.
- Touch: already wired end to end (MobileButtons sends Lobby "Touch", Net stores it, NightService puts `Net.touchOf` into each PlayerObs). Checked, not changed.
- Motor after a Hum fail: Core's MotorChanged now patches the client's view at once (ViewState), so the HUD line and the motor loop stop before the next view; NightService already syncs the boat from the view.
- DebugCrew requires `Core.FishMutations` (was `Core.WrongCatch`).
- New derived registry entries (id 0): finale-bell, finale-chase-drone, finale-chase-under, finale-hazard-whine, finale-hazard-toll, dawn-birds. No real id changed.

## Finale v2 (11/26/2026, Neon scored the finale 2/10; docs/critic/11-26-2026-finale-v2-neon.md)

- The bell: `finale-bell` is now non-spatial (plays from SoundService, Rule group, volume 1.6), so it is heard at full strength anywhere on the lake. Before it was spatial at the dock, about 600 studs from the steeple, and inaudible. 1.75 s of true silence after the cue, then three slow tolls 2.8 s apart; one Sound per toll, the previous toll is faded out over 0.3 s as the next starts, so at most one bell Sound exists at a time. The hush (motor, lantern, music) now holds through the tolls and 1.2 s after the last one; only then do the motor and the chase layer return (about 8.6 s after the cue). The hazard toll through water is skipped until then so it never plays over the bell.
- The light cone: the SpotLight now lives on the lantern itself, inside an Attachment `FinaleConeAim` on `LanternGlow` (welded to the hull), aimed along the bow (the lantern's local -Z) and pitched 14 degrees down; warm color, angle 70, brightness 4 at full oil (dims with oil, gutters under 15 percent), shadows on. Range is 60, not the 70 asked: the engine caps light range at 60 studs. The lantern's own PointLight is unchanged. The invisible `FinaleCone` part is removed (it drew nothing); no visible beam mesh was added. ASSUMED, reversible: add a faint beam only after seeing it in Studio.
- The dock beacon from the bell: the shaft and halo are built at the cue (was at the first toll). The Neon shaft is taller (160 studs, 3 wide) and breathes; a new `FinaleBeaconColumn` BillboardGui (AlwaysOnTop, LightInfluence 0, 3.5 studs wide plus 4 px, 150 studs tall, warm, brightest at the lamp and fading upward) is drawn over the fog so home reads from anywhere on the lake. Both blink twice with the beacon (WorldFx.beaconDark) and pulse at 0.5 Hz; the column fades out inside 110 studs of the camera, where the shaft and halo carry it. ASSUMED, reversible: AlwaysOnTop means the thin column shows through the boat and shoreline when they are in front of it.
- Hazards: see CLOUD-DECISIONS (Config.Rules.Finale). fx/Finale draws them as before (pulled in by Look.Finale.pull).
- 11/26/2026 (phone pass): all touch buttons on the right half in two rows of three above Cast and Knock; bottom-left 40 percent by 45 percent stays free for the thumbstick. The HUD oil label and bar share one line everywhere (not just on phones); the compact HUD switches on below 450 px tall. Roblox's touch controls hide while the title or a book is up (GuiService.TouchControlsEnabled and ControlModule Disable, touch only). On touch the Waiting hint drops 'X Reel in' since touch has no reel-in button.
- 11/26/2026 (finale v6, Neon finale-v5 2/10, docs/critic/11-26-2026-finale-v5-neon.md). The turn: silence, the first toll, then "The bell. Go home." 0.4 s after the toll Sound is actually playing (waits at most 1.5 s for it to start; Look.Finale.captionAfterToll, captionWaitMax); faceHome still turns the view at the first toll. Sound on the run home: finale-chase-under (the slowed finale-bed, the "synth music" Neon heard) no longer plays; finale-chase-drone volume 0.55 to 0.13 (a quarter); water and frogs stay muted until dawn as before. Beacon: the 160-stud Neon shaft and the FinaleBeaconColumn sky billboard are removed; home is now an 8-stud wooden light post with a small Neon lamp at the dock end (3 studs east, 1 south of DockEnd), a 24-stud PointLight and a small AlwaysOnTop halo (9 studs plus 14 px, MaxDistance 2500) so it shows across the lake; all double-blink with WorldFx.beaconDark. False beacons are built the same (post, lamp, halo) and blink wrong: even hazard ids steady with a faint shimmer, odd ids one dark flicker every 6 s. HUD: the oil label is always "Oil" (the longer finale label squeezed the flex bar into a square); in the finale the fill is solid red, eases toward the oil level so the drain shows, and pulses only under 25 percent (Look.Finale.oilWarnFinale). The HUD paper widens to its longest visible line (TextBounds plus padding, capped at 45 percent of the screen width); compact paper says "Fish: aboard" / "Fish: not yet". Wake: thin (0.08 by 1.8 to 3.4 studs) streaks at most 30 percent opaque, fading in, out with age, and fully within 5 studs behind the boat. Deck fish: while the Steeple Cat is aboard (specialAboard and hold above 0) a clone of the server's Field Guide SteepleCat model (ReplicatedStorage.DeadCalmFieldGuide, the same FishModel the catch uses), scaled to 2.6 studs, lies on its side on the hold lid, and one HoldFish token is hidden on this client (LocalTransparencyModifier). ASSUMED, reversible: the deck pose (hold lid, 75 degrees across the boat) and the post's spot by the dock end; check both in the next recording. Not done: the Book/Guide key hints (recorded on a PC) and the big prompt over the horizon (not in this brief).

## M8 polish (11/27/2026, docs/M8-POLISH.md, Neon hum-fail v3 5/10 and finale v6 3/10)

- 1. Capsize debris (BoatFx): the held fish are clones of the server's Field Guide models (ReplicatedStorage.DeadCalmFieldGuide, a plain body only if a model is missing); the bucket is an upright pail with a dark rim and a wire handle; the oar has a round shaft, a grip and a flat blade; the tackle box stays. Thrown models move with PivotTo and fade with LocalTransparencyModifier. Every white and blue sphere is gone: the foam is 4 ParticleEmitter bursts of 14 droplets along each gunwale (Emit, tilted out over the side) and every splash is a burst plus a dim pale ring. Droplet texture is the engine's own `rbxasset://textures/particles/smoke_main.dds` (not an uploaded id). ASSUMED, reversible: that texture reads as soft droplets at sizes 0.45 to 0.12; check it in the next clip.
- 2. Hum rings (BoatFx.RINGS): no Neon. A dark, low-contrast band (RGB 16, 24, 26, at most 45 percent opaque) with a faint pale edge just outside it (at most 22 percent), every 1.5 s (was 0.8), 7 to 24 studs across (was 10 to 44), over 3.8 s (was 2.6), easing in so it never pops.
- 3. Motor: motor-idle-loop volume 1.4 to 2.8 (+6 dB, the loop only; start and stop unchanged). The stern vibrates harder (copy jitter 0.06 to 0.08 studs, the tiller now jitters with the motor and shaft, camera rumble 0.008 to 0.012) and a faint churn of droplets rises at the foot of the shaft while it runs. HUD "Motor: on" unchanged.
- 4. Lantern glow (WorldFx.setGlow, every frame, written only where it differs): lit is deep orange Neon (Look.Lantern.glowLit); out is a dull brass Metal (glowOut, RGB 78, 64, 38) and every Light under the glass is off (the PointLight and the finale's SpotLight cone). State comes from the boat's LanternOn attribute.
- 5. Drowned characters (Drowned): every dead crewmate's character (parts and decals) is hidden on every client with LocalTransparencyModifier, bound after the camera scripts (render priority Camera + 3) so first-person code cannot show it again, and restored when they are alive. The server's own hide (EntityPresenter) is unchanged.
- 6. Dawn (fx/Finale): eased by hand over Look.Dawn.seconds 3 (was a 2.6 s tween that read as one frame): the horizon (Lighting colours, ClockTime from Look.Dawn.clockFrom 5.2 to 6.3, fog colour, colour grade) warms over the whole 3 s; fog Density, Offset and Haze lift and thin from a quarter of the way in; the banner shows only at the end. ASSUMED, reversible: the first frame jumps ClockTime from 0 to 5.2 (both read as night through the fog); check it in Studio.
- 7. Steeple Cat: lies on the floor boards along the port side beside the hold box (hull frame x -1.7, z 1.6, along the boat, 2.4 studs), clear of every rod, and stays in the boat through the dawn (also kept inside the dock light if the banked view lands before the pass event).
- 8. HUD under the banner: new HUD.setHidden(key, on); fx/Finale hides the HUD when the dawn banner shows and shows it again once the banner has faded (Look.Dawn.bannerHold 4.5 s plus a 1.5 s fade) or on reset.
- 9. Oil bar: outside the finale the fill is lamp-oil amber (HUD.OIL_FILL, RGB 214, 140, 52) on a pale ink track, so a full bar no longer reads as an empty black slot; the finale's red still takes over at the bell (the refill to full there is real, Core refills the lantern at 4 AM).
- 10. Hazards closer: see CLOUD-DECISIONS (M8 polish). fx/Finale unchanged (Look.Finale.pull 0.5 still draws the gap beyond the kill distance at half).
- 11. Prompt text: never under 16 px (Prompt.MIN_TEXT); short touch screens 16 (was 15), others Paper.fit(18, 18, 24). Not changed: the "Line in." note is ReelBar's (20 px already, outside this brief's files); suggest hiding that note at the bell instead.
- 12. Studio Hum scenarios (DebugRules): the hum_pass and hum_fail resets wait until the server chorus has been full for 9.5 s (the clients' climb from silence at Look.Mix.chorusRisePerSecond), then each scenario holds 3.5 s more of full chorus before forcing the Hum; results carry chorusHeld.
