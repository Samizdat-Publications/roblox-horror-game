# Critic consult: finale-v3 (gemini-4-neon)

Date: 11/26/2026. Files shown: finale_v3.mp4. Finish: STOP.

## Question

Watch and listen to this clip from a co-op Roblox horror fishing game (ages 10 and up, often on phones). It is the finale of a five-night run. The design: on the last night the owner wants one special fish from the deep water by the sunken steeple. At 4 AM the dock bell rings by itself and every water sound stops. The rule says: go home, lights on, do not stop. The lantern locks on and its oil starts running out. On the way home, strange boats with lanterns and false beacon lights appear, and stopping too long gets someone taken. Reaching the dock light with the fish ends the run at dawn.

In this clip a test bot already has the fish and runs home. Score each point 0 to 10, then overall. Quote timestamps. Be blunt, no em dashes, under 600 words.

1. the_turn: does the bell and the silence land as a big, unmistakable moment?
2. urgency: does the run home feel like a chase? Can you see the hazards?
3. readability: can a phone player tell where home is and how much oil is left?
4. the_ending: does reaching home at dawn feel like a payoff?
5. ui: does anything on screen get in the way (cards, prompts)?
6. clip_worthy: would five seconds of this make a good short video?
7. broken_or_ugly.

Then the top five concrete fixes in order of impact, each with the moment and exactly what to change.

## Answer

**Scores (0 to 10, higher is better)**

1. **the_turn: 4/10**
At 00:09 to 00:10, cutting the water audio works, and the three bell chimes (00:12, 00:14, 00:17) are loud and clear. However, "The bell. Go home." pops up at 00:11 before the bell even rings, ruining the surprise. Worse, nothing visually changes at 00:10 when the lantern supposedly locks on: no light beam snaps on, no flash, no camera jolt.

2. **urgency: 2/10**
This feels like drifting through black soup, not a finale chase. From 00:19 to 00:29, speed is barely perceptible, and the panting loop (00:21, 00:23, 00:25, 00:27, 00:29) gets repetitive fast. Hazards are unreadable: at 00:26 to 00:29 a dark pole sweeps across the left and a tiny yellow dot sits on the horizon, with zero clarity on whether either is a threat, false beacon, or dock.

3. **readability: 1/10**
Phone players are blind here. From 00:18 to 00:29, you cannot tell where home is. Worse, the oil gauge breaks at 00:10: the full bar disappears and turns into "Oil: locked on" next to a microscopic red square that shrinks to a hairline sliver by 00:29. Nobody on mobile will read that as remaining oil.

4. **the_ending: 0/10**
There is no ending. The clip cuts off at 00:29 (4:22 AM) in pitch-black water with no dock, no dawn, and no payoff.

5. **ui: 3/10**
The top-left card looks rough, clips text ("Owner's fish: aboa" from 00:00 to 00:29), shows irrelevant "Quota 0 / 3" on Night 5, displays PC-only prompts ("Book R", "Guide G", "X Reel in" at 00:00), and blocks the horizon light at 00:26 to 00:27. "The bell. Go home." (00:11 to 00:16) sits center screen too long, and "Line in." (00:10) is tiny.

6. **clip_worthy: 1/10**
No five-second slice works for Shorts or TikTok. On a phone feed it reads as a black screen with a beige box in the corner. No visible monster, no near miss, no lighting payoff.

7. **broken_or_ugly: 2/10** (very broken/ugly)
Clipped HUD text, microscopic red-square oil meter (00:10 to 00:29), crushed black lighting, missing lantern beam, unexplained pole sliding across frame (00:26 to 00:28), abrupt contextless voice line at 00:00 ("Change the book, read it again"), and a missing ending.

**Overall: 2/10**

---

**Top 5 Fixes (In Order of Impact)**

1. **Add a real lantern beam and silhouette contrast (00:10 to 00:29):** Snap on a bright forward spotlight cone at 00:10 so the player actually sees the locked-on lantern. Lift fog contrast so strange boats read as clear silhouettes, and make the real dock beacon taller, brighter, and distinct in color from smaller flickering false lights.

2. **Rebuild the oil bar and clean up mobile HUD (00:00 to 00:29):** At 00:10, keep a wide, bright oil bar that visibly drains and pulses below 25% instead of shrinking into a tiny red square. Fix the "Owner's fish: aboa" clipping, hide "Quota 0 / 3" on Night 5, and swap "R/G/X" key prompts for touch buttons on phones.

3. **Fix the 4 AM turn timing (00:09 to 00:16):** Remove the early text at 00:11. Let silence drop at 00:10, hit the first bell chime at 00:11 with an audible lantern click and light snap-on, then flash a short reminder ("Go home. Do not stop.") after the chime lands.

4. **Make hazards and chase tension legible (00:20 to 00:29):** Put readable lantern-lit hazard boats crossing the light cone so players actively steer around them. Replace the 2-second breathing loop (00:21 to 00:29) with rising tension audio and stronger water-wake speed cues, and clarify what the pole at 00:26 to 00:28 is.

5. **Deliver the dawn arrival payoff (after 00:29):** Fix the run so players reach the dock, then trigger an unmistakable shift: cut the horror drone, flood the sky and water with warm sunrise light, pull smoothly into the lit pier, and show a clear five-night survival finale screen.

## Action taken

(fill in: what we changed, or why we did not)
