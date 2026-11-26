# Audio

Every game sound, made with ElevenLabs (SFX v3 `eleven_text_to_sound_v3`, Eleven Music v2.5 `music_v2_5`) per `docs/DIRECTION.md` section 2.

How a sound gets made:
1. Its prompt goes in `audio/sounds.json`.
2. `python tools/audio/eleven.py batch audio/sounds.json` writes 2 or 3 variants to `audio/variants/` (not committed).
3. `python tools/audio/rank_all.py` has Gemini 4 Hydrogen rank them and copies the winner to `audio/final/<id>.mp3`. Report: `docs/critic/2026-11-25-sound-variants-hydrogen.md`.
4. The winner is uploaded to Roblox (audio must pass Roblox's upload rules and moderation) and its asset id recorded below and in `src/ReplicatedStorage/Shared/SoundIds.luau`, which is what the game reads. All 27 went up on 2026-11-26 through Open Cloud (Studio MCP), one upload each.
5. Neon reviews the sounds in context from a playtest clip with audio.

Note on step 3: Hydrogen picked the first variant in 19 of 27 groups, which may be a bias toward the first file it hears. Neon's in-game review is the real check.

| Sound | Kind | Seconds | Loop | Prompt | File | Roblox asset id |
|---|---|---|---|---|---|---|
| `amb-lake-dawn` | sfx | 30 | yes | Seamless dawn ambience at a calm forest lake: a gentle chorus of songbirds in pine trees, soft water lapping against a wooden dock, very light breeze, peaceful, no music, no voices | `final/amb-lake-dawn.mp3` | 75899041326551 |
| `amb-lake-day` | sfx | 30 | yes | Seamless daytime ambience at a quiet lake: wind softly moving through pine trees, a few distant birds, small waves lapping at the shore, calm and warm, no music, no voices | `final/amb-lake-day.mp3` | 131111386965866 |
| `amb-lake-dusk` | sfx | 30 | yes | Seamless dusk ambience at a northern lake: the haunting call of a distant loon echoing across still water, first evening insects, a light breeze, peaceful and slightly melancholy, no music, no voices | `final/amb-lake-dusk.mp3` | 82078051625749 |
| `amb-lake-night` | sfx | 30 | yes | Seamless night ambience at a lake: steady crickets and croaking frogs, very quiet water, an occasional soft splash far away, calm and dark, no music, no voices | `final/amb-lake-night.mp3` | 126929590872808 |
| `amb-creek` | sfx | 30 | yes | Seamless loop of a clear shallow creek running quickly over stones and pebbles, bright babbling water, close by, no birds, no music | `final/amb-creek.mp3` | 100143865714004 |
| `wait-bobber-tick` | sfx | 2 |  | A small plastic fishing bobber gently ticking and rocking in calm lake ripples, very quiet and close, tiny water sounds | `final/wait-bobber-tick.mp3` | 86176657896960 |
| `bite-nibble` | sfx | 0.8 |  | A faint, tiny tap as a small fish nibbles a fishing bobber, a soft little plop in still water, very quiet | `final/bite-nibble.mp3` | 125293862124668 |
| `bite-tap` | sfx | 1 |  | A single light tug on a fishing bobber, a short crisp dip into the water, quiet but clear | `final/bite-tap.mp3` | 84949385588097 |
| `bite-slam` | sfx | 1.2 |  | A sudden sharp strike: a fishing bobber yanked hard under the water with a quick splash and a taut fishing line snapping tight | `final/bite-slam.mp3` | 134948659349119 |
| `bite-deep-pull` | sfx | 2.5 |  | A deep, heavy, low underwater pull and swell, something big moving beneath a lake, ominous low rumble with a slow water drag, suspenseful | `final/bite-deep-pull.mp3` | 74865533338533 |
| `reel-click` | sfx | 2 | yes | A fishing reel being wound quickly, steady mechanical ratchet clicking, close up, seamless loop | `final/reel-click.mp3` | 124139702532219 |
| `drag-zip` | sfx | 1.5 |  | A fishing reel drag screaming as a fish runs: fast zipping line pulled off the spool, high pitched buzz | `final/drag-zip.mp3` | 131892656500430 |
| `line-strain` | sfx | 2 |  | A taut fishing line and bent fishing rod creaking and straining under heavy tension, about to snap, close and tense | `final/line-strain.mp3` | 128212235558095 |
| `thrash-splash` | sfx | 2 |  | A fish thrashing violently at the surface of a lake, frantic splashing water | `final/thrash-splash.mp3` | 100088064761803 |
| `splash-small` | sfx | 1 |  | A small fish lifted out of the water with a light splash and drips | `final/splash-small.mp3` | 125799618702788 |
| `splash-big` | sfx | 1.5 |  | A big heavy fish hauled out of the water with a large splash and a cascade of falling water | `final/splash-big.mp3` | 84379040677203 |
| `sting-common` | sfx | 1.2 |  | A soft single acoustic guitar pluck, warm and gentle, a small happy note, short | `final/sting-common.mp3` | 94330783579661 |
| `sting-uncommon` | sfx | 1.5 |  | A short cheerful two-note marimba flourish, bright and friendly | `final/sting-uncommon.mp3` | 80260553499530 |
| `sting-rare` | sfx | 2 |  | A sparkling rising harp glissando with a soft chime at the top, magical and bright, short reward sound | `final/sting-rare.mp3` | 140324306594399 |
| `sting-epic` | sfx | 2.5 |  | A rich orchestral reward stinger: rising strings and a bell chord, exciting, short | `final/sting-epic.mp3` | 136953225890121 |
| `sting-legendary` | sfx | 3 |  | A triumphant brass and timpani fanfare swell with shimmering cymbals, heroic, short | `final/sting-legendary.mp3` | 91099343832765 |
| `sting-mythic` | sfx | 3.5 |  | A mysterious epic stinger: deep taiko drum hit, ethereal choir swell and shimmering high strings, awe-inspiring | `final/sting-mythic.mp3` | 88524387075648 |
| `sting-godlike` | sfx | 4 |  | A massive heavenly full choir swell with a huge orchestral chord, bells and rising shimmer, overwhelming wonder, cinematic | `final/sting-godlike.mp3` | 80444017499358 |
| `sting-new-species` | sfx | 2 |  | A curious bright discovery chime with a soft ascending xylophone run, a little wonder, short | `final/sting-new-species.mp3` | 140661394861736 |
| `theme-lake` | music | 60 |  | Calm, warm acoustic fingerpicked guitar and soft piano, peaceful lakeside morning, slow tempo, gentle and nostalgic, instrumental, sparse, loopable | `final/theme-lake.mp3` | 76895844343949 |
| `theme-creek` | music | 60 |  | Light, flowing instrumental with plucked mandolin, soft flute and gentle strings, a sunlit forest stream, playful but calm, sparse, loopable | `final/theme-creek.mp3` | 119583899918145 |
| `tension-fight` | music | 45 |  | Tense, driving instrumental fight layer: low pulsing strings, steady soft percussion, rising suspense without melody, loopable, cinematic but restrained | `final/tension-fight.mp3` | 131247988401466 |
