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
