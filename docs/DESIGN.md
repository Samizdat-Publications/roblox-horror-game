# Design: Don't Wave Back

Code name Dead Calm. Design by Fable 5.2 with full creative control from Stewart (11/26/2026). Numbers live in `src/shared/Config.luau`; this file says what they are for. Liam is the creative director once he plays it: his rulings will outrank this file.

## The promise

In the first 60 seconds you row out of the dock light into fog, the frogs are loud, a tape of the owner's tired voice reads Rule 1, and you realize the frogs are the only thing telling you that you are safe.

## Audience and platform

Roblox, phones first, 1 to 4 players per server, ages 10 and up. Many players have no voice chat, so the game never depends on it.

## Pillars

1. **Sound is the HUD.** The frog chorus thins as danger builds and dies when the Hum comes. No danger meter on screen. No scare without a sound cue.
2. **Every death teaches a rule.** Cue, counter, fail, then a death card naming the rule. No random jump scares. No instant deaths.
3. **Five verbs, hard choices.** Light, noise, motion, gaze, the book. No new button per monster, no combat, no inventory.
4. **Greed is the real monster.** Bigger fish are farther from the dock. The wrong fish pays triple. The crew chooses its own risk.
5. **One boat, different eyes.** Seats face different ways, some cues reach one player, the drowned see more than the living.
6. **Scary, not disturbing, and funny in the gaps.** No blood, gore, bodies or injury. The owner is dry and practical.

## The night

- 10 PM to 5 AM in about 9 real minutes. Five nights make a run. Clearing a run unlocks Endless Nights.
- The crew fills a quota of fish **points** (small fish 1, medium 2, large 3) for Tull's Bait and Tackle. Only fish banked in the dock cooler count.
- Clear the night: quota banked and at least one player alive at 5 AM. Fail: the whole crew is gone, the boat sinks, or the quota is short at 5 AM. A failed night restarts.

### The boat

One rowboat, four seats, each facing a different way: bow looks ahead, two side seats look out port and starboard, the helm at the stern steers. First-person view is locked while seated. Oars are slow and quiet. The outboard motor is nearly three times faster and loud: it hides most of the frog chorus, so the crew cannot hear trouble coming, and it must be off for the Hum. The boat must be nearly still to cast.

Rule 0: stay in the boat. A swimmer outside the dock light hears bubbles and a pull after two seconds and is taken at six.

### The dock

The beacon's light around the end of the dock is the one safe place: no real rule starts or advances there, and attention drains fast. The beacon blinks twice, slowly; that double blink is how you tell it from a false light. The cooler banks the hold. One oil can per night refills the lantern. A small radio plays old tunes: it is the sound of being safe, and you can hear it fade as you row out.

### Fishing

Cast, wait for the bobber tap, start reeling inside the bite window, then hold and release to keep the tension inside a band that wanders. Bigger fish have a narrower, faster band. Too tight for too long snaps the line; too slack loses the fish. Reeling is noise. When the Hum comes mid-fight, you must let go and probably lose the fish.

Every catch is held up to the lantern for a keep or throw back choice. If the lantern is out, the fish is hard to see.

Zones: Shallows near the dock (small fish), the Reeds along the east shore (pickerel, bullhead), the Narrows in the northwest (walleye, Old Plank), open water, and the Steeple in the deep north (the best fish, the farthest from home).

### The Field Guide

Eight species, each a page with a drawing and three or four facts you can check: eye count, back fins, bars, whiskers, tail shape. One deliberate trap: the Walleye's eyes shine in lantern light, and the page says so ("That is normal. Only for this one."). Nothing in the book glows. Nothing in the book blinks.

| Fish | Points | Tell it by |
|---|---|---|
| Pumpkinseed | 1 | Small, round, one back fin, no bars |
| Yellow Perch | 1 | Five bars, two back fins |
| Bullhead | 1 | Four whiskers, square tail |
| Papermouth | 2 | Silver, speckled, one tall back fin, no bars |
| Chain Pickerel | 2 | Long, green, one back fin, round tail |
| Walleye | 2 | Four saddles, two back fins, eyes shine |
| Old Plank (lake sturgeon) | 3 | Armored, four whiskers, uneven tail |
| Steeple Cat | 3 | Eight whiskers, forked tail, only by the steeple after 3 AM |

### Light

The lantern is the crew's main light and it burns oil. A full lantern left on lasts about 80 percent of a night, so the crew must spend some of the night dark or go home for the one refill.

### The book

The rulebook is taped inside the boat. Opening it or the Field Guide covers most of your view and stops your hands. One reads while the others watch.

### Callouts

A wheel of fixed phrases with a short voiceless sound and a speech tag over the head: Frogs stopped, Lantern out, Lantern on, Hold still, Knock once, Knock twice, Don't knock, Don't wave, Don't look, Look at it, Throw it back, Go home, and Wave. Wave is a friendly wave. It is also how the Neighbor gets you. The default Roblox emote menu is off in this game so that our Wave is the only wave.

## The Lake Rules

The text below is the in-game text. The owner wrote it.

> **Rule 0.** Stay in the boat. The water is not yours at night.
>
> **Rule 1.** When the frogs stop all at once, stop reeling, cut the motor, put out the lantern, and hold still until they sing again.
>
> **Rule 2.** Check every catch against the Field Guide. If it is not in the book, throw it back. I do not care what it weighs.
>
> **Rule 3.** There are no other boats on Blackwater Lake. If you see one, you did not. Never wave back. Never row toward a light that is not the dock beacon. Ours blinks twice.
>
> **Rule 4.** If something knocks three times on the hull, answer with two. Not one. Not three.
>
> **Rule 5.** Do not stare at the shore. Do not turn your back on it either. Keep it at the edge of your eye.
>
> **Rule 6.** If the bell rings by itself, go home. Lights on. Do not stop. Bring my fish.

### How each one plays

**The Hum (night 1).** The whole chorus stops at once. A beat of dead quiet, then a low hum rises from under the hull and the boards buzz. From the first note the crew has a few seconds to comply, then must hold for 10 to 15 seconds: nobody reeling, motor off, lantern out, boat still. A little noise is forgiven. Pass: the hum sinks away and one frog starts, then the rest. Fail: the boat is thrown, the hold goes over the side, and whoever made the most noise is pulled under.

**Wrong Catch (night 2).** Some catches are almost right: a third eye, a second back fin, a wrong tail, a faint glow, a blink. Obvious on night 2, down to one bar too many by night 5. Throw it back and nothing happens. Keep it and it counts triple, the lake's attention jumps and cannot fall all the way back that night, and some time after it is banked the cooler knocks from inside and two banked fish are gone. The server never tells a client which fish are wrong; the player has to look.

**The Neighbor (night 3).** A slow oarlock creak with nobody rowing. Then a second lantern in the fog and a rowboat drifting closer, a figure in it, one arm raised, waving. It drifts to a polite distance, lingers about half a minute, and drifts away. Wave back, or close the distance, and your lantern is snuffed, a silhouette is sitting in your boat, and the one who waved or steered is gone. Sometimes it comes as a false beacon instead: a steady light where the dock is not. The real beacon blinks twice.

**The Knocking (night 4).** Three slow knocks from under the hull. Any living player answers with the knock button: exactly two knocks inside the window. Get it wrong and it knocks again, harder, with a shorter window. Wrong again and water comes in. The crew bails (no fishing while bailing) or the boat sinks and takes everyone.

**The Watcher on the Shore (night 4).** Near a shore, one player notices a tall still figure among the trees. Stare straight at it and a thin tone rises in your ears; stare too long and it lunges closer. Let everyone look away and it steps closer. Keep it at the edge of one player's sight and it holds. After a while it is simply not there. If it reaches the waterline every lantern dies and it takes the nearest player. Rowing well away from the shore also loses it.

**The Lake Wakes (night 5).** The owner wants one Steeple Cat, and they only bite by the steeple after 3 AM, so the crew is in the deepest water when, at 4 AM, the dock bell rings by itself and every water sound stops. The lantern locks on and its oil starts running out. Go home. Neighbors drift across the way, false beacons burn, and if the boat sits still for more than a few seconds the lake takes someone. Reaching the dock light with the Steeple Cat aboard or banked ends the run at dawn.

### Amendments

The owner amends his own rules in a different ink. The cue never changes; the answer does. Players learn to recognize the thing, then check tonight's page. On Normal the first run is by the book and one amendment appears on night 5. On Nightmare and Endless any rule may be amended on any night, drawn from the run seed. A new amendment is shown on the page at night start and the tape mentions that "the book changed".

| Rule | As printed | Amended |
|---|---|---|
| Hum | "put out the lantern" | "LEAVE THE LANTERN LIT. It hates the dark now." |
| Knocking | "answer with two" | "ONE. Just one." or "DO NOT ANSWER. Let it knock." |
| Watcher | "keep it at the edge of your eye" | "STARE AT IT. Someone must. Do not look away first." |
| Neighbor | "never wave back" | adds "And put the lantern out until it is gone." |

### Fake-outs

Harmless, budgeted, never within a few seconds of a real cue: a loon that sounds like a scream, a branch snapping on shore, a fish jumping at the gunwale, one knock (not three), the chorus dipping for two seconds, a buoy clank that is nearly a bell, a lantern flicker, a far light that turns out to be fireflies. About a third go to one player only.

### Fairness

A real cue shown to only one player must be one that player can answer alone, or must leave at least 12 seconds to tell the crew. Every fail is preceded by its cue by at least the warning time. Solo players get longer warnings.

## The director

Each night the director cycles calm, build and peak. After a real scare resolves it guarantees a quiet gap. It has a budget of real scares and fake-outs for the night. The night's new rule always appears once, early, with a long teaching window. The lake's hidden attention (motor, light, splashing, a kept wrong fish) shortens the calm phases and can add one scare. The crew hears all of this as the chorus: full, thin, sparse, silent. Everything is drawn from a logged seed.

## Death and the drowned

Death is a fade to black, a splash or a drag sound, then a card:

> **You kept reeling while the frogs were quiet.** Rule 1.

The drowned float near the boat as a dim light. They see outlines the living cannot (the shape under the hull, where the Watcher really is) and can ring a faint bell every 15 seconds. Everyone returns at the next night. If the whole crew is gone the night restarts.

## Between nights

The owner's pay envelope: pick one of three supplies for the rest of the run (Spare Oil Can, Waxed Oars, Second Stringer, Lucky Lure, Owner's Spectacles, Brass Bell, Trimmed Wick, Thermos). The host picks. This is the first thing cut if time is short.

## The owner's tapes

One designed voice: an older man, tired, kind, dry, recorded on a cheap cassette. Each night opens with a click and a tape.

1. "Night one. Quota's on the cooler. Rules are taped in the boat. Read them. Mostly it's just frogs out there. If the frogs quit, you quit too. That's all. Coffee's in the shack."
2. "Night two. You'll pull up things that look almost right. Almost is the problem. Count the eyes. Use the book. I don't pay for what isn't in the book. Officially."
3. "Night three. There's nobody else on this lake. I've held the only license since the dam went in. So if somebody waves at you, be rude."
4. "Night four. Two things. If it knocks, answer short. And don't go staring into my trees. Don't ignore them, neither. You'll work it out."
5. "Last night. I need one fish from over the steeple. They bite after three. And if you hear the bell, it isn't me ringing it. Come home. Don't stop for anything in that book."
- Amendment line: "One more thing. I changed the book. Read it again."
- Night failed: "Rough night. Lake gives you one back. It doesn't do that forever."
- Run cleared: "Huh. You're still here. Pay's in the envelope. Same time tomorrow?"

## Progress and cosmetics

Saved per player: nights cleared, runs cleared, best Endless night, fish banked, scares survived, cosmetics. Cosmetics are earned by playing, never bought: lantern colors (Amber, Bone White for clearing a run, Marsh Green for Nightmare night 3, Blue Hour for Endless night 5), boat paint (Bare Wood, Oxblood for 100 fish banked, Hull Black for 25 scares survived, Robin Egg for a solo run), hats (Bucket Hat for night 1, Sou'wester for a run). Game Pass hooks exist as clearly marked stubs with no ids.

## Look

- **Palette:** water `#0B1418`, fog `#1B2A2E`, lantern `#FFB45A`, beacon `#FFE2A8`, wrong-glow `#8CFFC1`, silhouettes `#050607`, pin eyes `#E8F4FF`, paper `#E9DFC3`, ink `#2A2118`, amendment ink `#7A2E1E`, dawn `#F2B98A`.
- **Light:** midnight, heavy fog, very low ambient. The lantern is a warm pool about two boat lengths wide. The beacon is a far warm double blink. Never pure black: a phone in daylight must still read the boat, the water line and the fog edge.
- **Shapes:** parts built by code. Chunky, readable, slightly crooked. The steeple leans. The dock sags.
- **Monsters:** silhouettes. Height, stillness, eyes, wrongness. The Watcher is too tall and too narrow. The Neighbor's wave is a little too slow.
- **Camera:** first person in the boat, a slow bob with the water. Nothing moves fast except a fail.
- **UI:** paper and ink. Handwriting for the rules, typewriter for the Field Guide. Second person, short, practical. The HUD is four small things: night, clock, quota, oil.

## Sound

Sound is built before visuals and judged first. About 90 named sounds:

- **Beds:** hull lap, open-water air, wind in the trees.
- **Chorus:** frogs in three densities, crickets, single loons and owls at real positions on shore.
- **Boat:** oar strokes, oarlock, hull creak, motor start, idle and stop, lantern squeak and flame.
- **Fishing:** cast, plop, bobber tap, reel click, line creak, splashes by size, cooler lid.
- **Rules:** for each, a cue, a build, a pass and a fail. The Hum is a sub drone and a buzz in the boards. The Neighbor is an oarlock with nobody rowing. The Knocking is knuckles on wet wood. The Watcher is a thin tone that is not quite tinnitus. The finale is a bell heard through water.
- **Fake-outs:** loon scream, branch snap, big fish jump, single knock, buoy clank.
- **UI:** page turn, tape click, pencil scratch, stamp, envelope.
- **Music with a job:** the dock radio's old tunes mean safe. Title theme, dawn, finale bed, death sting, run cleared.
- **Voice:** the owner's tapes.

Mix rules: the chorus density follows the director; the motor ducks the chorus; rule cues duck everything else; silence is used on purpose.

## Never

Blood, gore, bodies, injury detail, shrieking faces held on screen, real people, real tragedies, other games' monsters or names, free-text chat, anything bought with Robux, pay to win.
