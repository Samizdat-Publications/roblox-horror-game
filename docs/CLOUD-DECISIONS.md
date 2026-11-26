# Cloud helper decisions

One line per call, newest last. Dates MM/DD/YYYY.

## Core M1 and M2 (11/26/2026, built locally in the working tree by an Opus builder)

- 11/26/2026: `cfg` is typed `any` inside Core. Core cannot require Config (config is passed in), so `typeof(require(Shared.Config))` is not reachable from a Core module; `any` keeps strict mode quiet without a fake import.
- 11/26/2026: LakeMap's nearest shore point uses the trig-free iterative ellipse projection (4 rounds); the spec checks it against a 3600-point scan to within 0.05 studs.
- 11/26/2026: BoatModel: reverse is half speed; acceleration scales with top speed so oars and motor both reach full speed in about 1.7 s; steering turns at full rate even when still (oars can pivot a rowboat); the boat stops dead at 2 studs from the shore.
- 11/26/2026: Lantern gains `lockedOn` (for the finale) and `burnMult` (for Trimmed Wick) now so M5 does not have to reshape it.
- 11/26/2026: Added `Config.Mix` (ambience target volumes, radio near and far, cue duck, drowned muffle, crossfade rate) for `Core.SoundMix`. Look.Mix was empty and Core cannot read Look; these are mix numbers, but they are the ones Core decides with. The client may still multiply by registry volumes.
- 11/26/2026: SoundMix layers: Bed, ChorusFull, ChorusThin, ChorusSparse, Crickets, Motor, Radio. Band 3, 2, 1 each play exactly one chorus layer (the client crossfades with `SoundMix.approach`); band 0 drops the bed to `bedSilent`. The drowned hear everything `drownedMuffle` quieter.
- 11/26/2026: RateLimit takes `now` from the caller (Core has no clock). A clock that goes backwards refills nothing. `RateLimit.forPlayer` builds one bucket per client remote; Lobby and Cosmetic get 4 burst, 2 per second.
- 11/26/2026: Validate defines the Lobby actions (none existed): Start, Ready (boolean), Difficulty (Normal or Nightmare), Mode (Story or Endless), Supply (a Config.Supplies id), Retry. Strings over 32 characters are refused. Gaze wraps to [-pi, pi) and refuses more than two turns. The Studio-only debug remotes are not client-to-server game remotes, so `Validate.remote` refuses them.
- 11/26/2026: Added `Config.Fishing.biteInDockLight = false`: a cast inside the dock light gets `HookLost` with why `DockLight`. Without it the crew can fish in the one safe place and the quota is free. Reversible with the flag.
- 11/26/2026: Fishing: the catch (species and wrong roll) is decided when the hook is set, from the zone and hour at the cast. The reel bar starts at tension 0.35 with the band centered; the band reverses at random (0.7 per second) and bounces off the ends. When the keep or throw back timer runs out the fish is kept (Config comment). Keeping with a full hold releases the fish (`Released`, why `HoldFull`).
- 11/26/2026: `Caught` carries `catch = { species, points, traits }` only. `Kept` reports the Field Guide points, not the tripled value, so no event tells a client a fish is wrong before it is banked. `Banked` reports the real total (the quota shows it anyway).
- 11/26/2026: WrongCatch tiers: 1 = ThirdEye, Glow, Blink; 2 = ExtraDorsal, WrongTail, Barbels (plus or minus 2); 3 = Stripes (plus or minus 1). Eyeshine is never a mutation kind, so the Walleye page stays true.
- 11/26/2026: The teaching guarantee is applied when the hook is set: on the night Wrong Catch is new, the Nth fish hooked (N = teachWrongByCatch) is wrong if none has been yet.
- 11/26/2026: NightParams has no wrongChance or wrongTier, so Night reads them from `cfg.Nights[night]` (Story) or `cfg.Endless`, and only when "WrongCatch" is in `params.rules`. Consider adding them to NightParams when Run lands (M5).
- 11/26/2026: Night applies four supplies now: OilCan (+1 refill), BigCooler (+2 hold), LuckyLure (bite wait x0.75), TrimmedWick (oil lasts x1.2). WaxedOars is the world's (BoatModel speedMult); Spectacles, BrassBell and Thermos wait for their systems.
- 11/26/2026: Attention is a stub inside Night with the real cfg.Attention numbers (rises with motor, lantern, reeling; decays when nothing raises it; drains fast in the dock light; kept wrong fish add a jump and a floor). The chorus band follows it through cfg.Director.chorusBands but never reaches 0 from attention alone (silence is for the Hum, M3).
- 11/26/2026: Tape ids: "Night1" to "Night5", "Endless", and "Amendment" (sent as a second Tape when the night has amendments).
- 11/26/2026: `Night.debugForce` is a no-op returning no events until the rules exist (M3).
- 11/26/2026: Pacing sim stops each night when the quota is met: with no rules yet nothing after that changes time to quota, and it makes the 200-seed run take about 2.5 minutes instead of much longer. M3 should run nights to dawn once deaths exist.
- 11/26/2026: Pacing pass bar: full run (200 seeds) needs median time to quota in 0.60 to 0.80 and quota reached in at least 95% of seeds per cell; `--fast` (24 seeds, the gate) uses 0.55 to 0.85 and 90% because small samples are noisy. The sim exits 1 on a miss in either mode.
- 11/26/2026: The rule-following bot rows (never the motor) to a random Shallows spot at least 100 studs from the dock end, fishes with everyone, plays the reel bar by holding below the band's middle (thumb updates 5 times a second), checks every catch against the Field Guide, throws back wrong fish, banks when the hold is full or covers the rest of the quota or dawn is close, refills the lantern under half oil. Reaction delays: bite 0.3 to 0.9 s, decide 1 to 2.5 s, recast 1 to 2.5 s.

### Config tuning for the pacing target (11/26/2026)

Before (200 seeds): nights 1 to 3 met the quota far too early (median 0.28 to 0.60 of the night), night 5 crews 3 and 4 too late (0.81, 0.84; crew 4 reached it in only 97% of seeds). 14 of 20 cells missed. Scorecard: `artifacts/score/pacing-baseline.md`.

| Value | Before | After | Why |
|---|---|---|---|
| `Config.Nights[1].quota` | 10 | 23 | The bot banks about 30 points in a full night with a crew of 4; 10 was met at 0.34 of the night. |
| `Config.Nights[2].quota` | 14 | 22 | Same, with about 20% of catches thrown back as wrong. |
| `Config.Nights[3].quota` | 18 | 22 | Same. |
| `Config.Nights[4].quota` | 22 | 22 | Already on target. |
| `Config.Nights[5].quota` | 26 | 23 | 26 was met at 0.84 by a crew of 4 and missed on 3% of seeds. |
| `Config.Scaling.quota` | 0.45, 0.7, 0.85, 1.0 | 0.55, 0.75, 0.86, 1.0 | A solo angler banks about 53% of a crew of 4's points (one boat, one hold, the same trips), two about 78%, three about 88%. |

After: all 20 cells on target (see CLOUD-PROGRESS and `artifacts/score/pacing.md`). Caveat for M3 to M5: with no scares the bot's rate is the same every night, so the quotas came out nearly flat. Once the Hum, Neighbor, Knocking and Watcher cost the crew time, later nights will slow and their quotas should come down again (or the early ones go up); retune then with the scare-aware bot.

## Core M3 and M4 (11/26/2026, built locally in the working tree by an Opus builder)

- 11/26/2026: `Core.Attention` replaces Night's stub with the same numbers; it only holds value and floor. The Director owns the sustained-attention bonus (it reads `ctx.attention`, the contract's only input).
- 11/26/2026: Director cycle: calm (shrunk by attention x calmShrink), build, peak. The next real scare is planned at cycle start + calm + build and spawns at the first tick the world allows it. After it resolves, a new cycle starts and the quiet gap is a hard block. Phase tension: calm 0.10 to 0.25, build 0.30 to 0.85, peak and active 0.9, quiet gap 0.2, dock light 0. Chorus band = band of max(attention, phase tension). Only rules make silence (band 0).
- 11/26/2026: Teaching first: no ordinary real scare until every new director rule has been taught, one at a time, alone. The first teaching spawn is drawn in the first 12% of the band. The real budget is never below the number of rules to teach.
- 11/26/2026: Director rules are Hum, Neighbor, Knocking, Watcher. Wrong Catch follows the crew's choices and the Finale is the night 5 clock (M5); neither is a director spawn, so "each new rule is taught" means each new director rule.
- 11/26/2026: Fake-outs only in calm and build, never with a real rule active, never in the dock light, never within fakeClear + 1 s before a planned real scare, never within fakeClear after one; spaced by fakeGap plus a spread that shares the budget across the night left.
- 11/26/2026: Overlap: with maxConcurrent 2, a second rule may start only while attention is at or above budgetBonusAt and overlapAfter seconds after the first. Calm crews never see two at once.
- 11/26/2026: New `Config.Director` fields: lateCutoff 25 (no new real scare in the last 25 s), overlapAfter 15, teachWarnMult 1.5 (teaching warnings), ruleCooldown 3 (presentation linger after an outcome).
- 11/26/2026: `Director.resolved(d, rule, passed, at?)` takes an optional time (additive) so the quiet gap starts at the exact resolution tick; `Director.noteSpawn` and `Director.isActive` added for `Night.debugForce`.
- 11/26/2026: `EntityBase` holds fairness for every rule: one cue; one outcome; a fail asked for before `warn` is held and sent when the warning time is up (and a held fail beats a later pass); solo cues wait at least soloCueMinSeconds. Rules return fail effects (kill, cause, loseHold, rock, snuff, flood, eatBanked, blame) and Night applies them; rules never touch the crew.
- 11/26/2026: "No real rule starts or advances in the dock light": in the light nothing counts toward a fail, but each rule's natural end (Hum hold, Neighbor give-up, Watcher presence) still runs, so reaching the light lets the crew go. The Knocking window pauses in the light. The leak does not fill in the light. The Wrong Catch cooler timer runs anywhere (the cooler is not the lake).
- 11/26/2026: Hum: noise is counted only after silence + warn x scale; noise per tick is one unit if anything is wrong, blamed on who did it (reeler, lastMotor or helm for the motor, helm for motion, lastLantern for the lantern). The amended LanternLit Hum never counts a dark lantern the crew cannot light. Cause ids: Reeling, Motor, Moving, LanternLit, LanternDark.
- 11/26/2026: Wrong Catch consequences start when a kept wrong fish is banked: cue (the cooler settles), then the knock (EntityFail, eatBanked = fishEaten, random fish from the cooler). Every instance is a Fail; the counter (throw it back) starts nothing. The cue reveals nothing new: Banked already shows the tripled total and the choice is final. A kept wrong fish lost before banking starts nothing.
- 11/26/2026: Knocking: knocks are counted only inside the window; too many is wrong at once, otherwise judged at the window's end. Wrong twice: effects { flood }. The leak (Night): water rises at 1/floodSeconds per s; each bailer removes 1/bailSeconds per s; the leak is plugged after floodLasts seconds of bailing (with nobody bailing the boat sinks in floodSeconds). Config.Rules.Knocking.floodLasts was ambiguous (inflow alone never reached 1); this reading makes bailing required. Sinking kills everyone ("Death.Knocking.Sunk") and fails the night with reason "Sunk".
- 11/26/2026: Watcher: stands on the shore point nearest the boat, steps x stepLen studs into the trees. stareLimit and unwatchedStep scale with the warning scale. The nearest player it takes is the living player facing it least (seat positions are presentation). A solo sighting counts only that player's gaze while they live.
- 11/26/2026: Death card text ids: "Death.<Rule>.<Cause>", for example Death.Hum.Reeling, Death.Neighbor.Waved, Death.Neighbor.Closed, Death.Neighbor.Beacon, Death.Knocking.Sunk, Death.Watcher.Reached, Death.Water.Drag. Rulebook (M5) maps them.
- 11/26/2026: In-water drag: DragWarning (only to the swimmer) at warnAt x warningScale, taken at dragSeconds x warningScale; climbing back in resets it.
- 11/26/2026: Ghost: the bell has a per-player cooldown; GhostBell carries the player. No Brass Bell (supplies cut).
- 11/26/2026: Night builds a PlayerObs for every crew member (missing ones are seated defaults, helm = first id), so rules always see the whole crew.
- 11/26/2026: New event kind `EntityMoved` (entity, data { pos, step or phase }) for the Neighbor's drift (at most every 0.5 s) and each Watcher step. Not yet in ARCHITECTURE.md's event table.
- 11/26/2026: Contract additions (all additive) in Types.luau: EntityObs.lanternCanLight, lastLantern, lastMotor; Traits.wrongEyeDir, flipFin; PlayerTally and NightResult.tallies; NightParams.supplies is now optional.
- 11/26/2026: Night specs written for M2 now pass `real = 0, fake = 0` (and two of them no rules) so a director scare cannot interrupt a fishing test; rules have their own specs.

### Design changes from the main session (11/26/2026)

- 11/26/2026: Neighbor rework: while the crew's lantern is lit it drifts toward the boat at driftSpeed 4 (was 3); with the lantern out it drifts to where it last saw the light. It gives up lingerMin..lingerMax seconds (17..23, scaled from 25..35) after the lantern is out with the boat past holdDist (time inside holdDist does not count), or after presenceMax 100 s. Fail: within killDist with the lantern lit (helm) or any living wave (the waver). 1 or 2 fake callouts (Callout, player = data.as, data { phrase in LanternOn, Wave, GoHome; fake = true }) come between creakSeconds + 2 and creakSeconds + lingerMin - 2 so even a crew that goes dark at once hears them. False beacon unchanged.
- 11/26/2026: Amendment NoWaveLanternOut renamed NoWaveRowAway: closing on the Neighbor faster than closeSpeed 0.5 for more than closeGrace 0.5 s is the fail, judged only once its warning time is up (a boat already moving at the creak is not punished). New Config.Rules.Neighbor fields: warn 6, creakSeconds 4, appearDist 200, leaveDist 220, presenceMax 100, fakeCallouts { 1, 2 }, closeSpeed, closeGrace.
- 11/26/2026: Wrong Catch tells: tier 1 Glow or ThirdEye, tier 2 WrongTail or ExtraDorsal, tier 3 Blink, WrongEyeDir or FlipFin. Stripes and barbels are never mutated. New Traits booleans wrongEyeDir and flipFin, false for every species in Config.Fish; an absent flag reads as false.
- 11/26/2026: Nights are 360 s. Rescaled: openingGrace 60 to 40; quietGap per night 75, 65, 55, 45, 40 to 50, 43, 37, 30, 27; Endless quietGapBase 40 to 27, quietGapFloor 25 to 17; Lantern.burnSeconds 430 to 290; Attention.budgetBonusSeconds 45 to 30; Director calm 40..70 to 27..47, build 25..45 to 17..30, fakeGap 20 to 14; WrongCatch knockDelay 60..140 to 40..95; Neighbor spawnMin..Max 160..220 to 107..147; Watcher spawnMin 120 to 80; Finale oilSeconds 75 to 50. Rule internals (Hum hold, Knocking windows, Watcher timings) unchanged: they are moments, not night fractions.
- 11/26/2026: Night.teachTo 0.45 to 0.55: with 360 s nights the band was 90 s, too short to teach night 4's two rules one at a time (the property test found 11 of 2500 nights where the second teaching landed late).
- 11/26/2026: The supply pick is cut: Night and Ghost ignore params.supplies; Config.Supplies and the Lobby "Supply" action in Validate stay so nothing else breaks. Lantern.burnMult and Fishing biteMult stay as module features at 1.
- 11/26/2026: Per-player tallies in NightResult.tallies (crew order): brokeSilence (Hum fails where this player was the loudest), keptWrong, knocksAnswered (knocks sent while a Knocking is out), bailedSeconds (bailing with water aboard), timesStaredAtWatcher (each time the gaze lands straight on an active Watcher), deaths.

### Sim bots (11/26/2026)

- 11/26/2026: Three policies in tools/sim/crewbot.luau. follow: answers everything from events plus the book (amendments). blind: keeps every catch, lantern always lit, never knocks or bails, seat gaze. greedy: keeps every catch, motor always on except for the Hum (it must cut it to live), answers the other rules. The follow bot rows away from a Neighbor inside holdDist + 50 (always, under NoWaveRowAway), turning in place before rowing; it sits still for a false beacon.
- 11/26/2026: tools/sim/params.luau builds Story NightParams for both sims; the real budget is scaled by Config.Scaling.budget (rounded, at least 1), as Run will.
- 11/26/2026: The rules sim also audits the rule contract from the events of every simulated night.

### Quota retune for 360 s nights with scares (11/26/2026)

| Value | Before | After | Why |
|---|---|---|---|
| `Config.Nights[1].quota` | 23 | 12 | 540 s nights became 360 s and the Hum now costs time; the follow bot banks about 12 base points by 70% of the night. |
| `Config.Nights[2].quota` | 22 | 10 | Wrong Catch night: about a third of catches go back. |
| `Config.Nights[3].quota` | 22 | 11.6 | Fractional base so the rounded crew quotas land in band (crew 1 to 4: 6, 9, 10, 12); 11 put crew 2 at 0.56, 12 put crew 1 at 94% reached. |
| `Config.Nights[4].quota` | 22 | 13.4 | Crew quotas 7, 10, 12, 13; 14 put crew 4 at 0.80. |
| `Config.Nights[5].quota` | 23 | 12.4 | Without the Finale (M5) night 5 is a harder night 4; 13 left crew 4 reaching quota in only 92% of seeds. M5 will retune with the Finale. |

Before (old quotas, 360 s nights, scares on): 20 of 20 cells missed; most reached quota in under 40% of seeds. After (200 seeds): 20 of 20 cells on target (see CLOUD-PROGRESS and artifacts/score/pacing.md). Later nights need more points than earlier ones from night 2 to 4 (10, 11.6, 13.4); night 1 (12) is above night 2 because the Wrong Catch night throws back a third of its fish, and the numbers did not allow a strictly rising line without breaking the 60 to 80% band.
