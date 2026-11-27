# Derived sounds while uploads are capped (11/26/2026)

The account cannot upload audio until about 12/26/2026. About 40 registry entries are still id 0. Most can be built in the engine from sounds we already uploaded, using Sound.PlaybackSpeed, TimePosition and PlaybackRegion, and the SoundEffect children (EqualizerSoundEffect, ReverbSoundEffect, EchoSoundEffect, DistortionSoundEffect, PitchShiftSoundEffect, ChorusSoundEffect, TremoloSoundEffect). A registry entry gets an optional `derive` table instead of an id; AudioDirector builds the sound from the source entry with those settings. After the reset, real uploads replace them and the `derive` table is removed.

Starting recipes (to be tuned by ear and by Neon):

| Missing | Source | Recipe |
|---|---|---|
| neighbor-oarlock-loop | oarlock-creak | speed 0.8, repeat every 2 s, heavy reverb and a low-pass so it sounds far across water |
| neighbor-pass | oarlock-creak | as above, volume ramps down over 6 s |
| neighbor-fail | lantern-off then hull-creak | lantern-off, 0.4 s gap, hull-creak at speed 0.7, loud and close |
| knock-pass | hull-creak | speed 0.6, low-pass, then dock-water-loop swell for 2 s |
| flood-in-loop | dock-water-loop | speed 1.3, louder, high-shelf cut, close |
| boat-sink | hold-lost-splash then death-drag | layered |
| lake-groan | hum-fail | speed 0.45, long reverb |
| lake-silence-drop | hum-pass | first 1 s only, speed 0.6, then all ambience muted |
| lanterns-die | lantern-off | three copies 0.15 s apart, slight pitch spread |
| watcher-tone-loop | hum-hold-loop | PitchShift up two octaves, band-pass narrow, very low volume, slow tremolo |
| watcher-step | dock-creak | first footstep only, speed 0.7, low-pass, distant |
| watcher-lunge | dock-creak | three steps at speed 1.4, louder |
| watcher-fail | lake-silence-drop recipe, then fish-release at speed 0.6 | layered |
| watcher-pass | bed-wind-trees | 4 s swell |
| wrong-blink | lantern-squeak | first 0.1 s, speed 2.5, quiet |
| wrong-glow-loop | hum-hold-loop | PitchShift up three octaves, quiet, tremolo |
| cooler-knock-inside | knock-answer (library) | 3 times 0.9 s apart, low-pass (muffled inside metal) |
| cooler-eaten | cooler-close | speed 0.7 plus fish-land-thud |
| fake-lantern-flicker | lantern-flame-loop | 1.2 s at volume dip and rise |
| fake-loon-scream | loon-call | speed 1.15, slight distortion |
| rod-clatter | fish-land-thud | speed 1.6 |
| ui-tick, ui-stamp, callout-blip | cooler-close, knock-answer | very short slices at high speed |
| title-theme, run-cleared | radio-tune-1, radio-tune-2 | radio tunes without the radio filter, for now |
| night-failed-sting, night-cleared-sting | death-sting, quota-met | as they are |

The owner's tapes are already uploaded. Knocks from the library must play three times, about 1.1 s apart (`knock-three-soft`, `knock-three-hard`).
