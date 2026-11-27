# Critic consult: finale-v7 (gemini-4-neon)

Date: 11/27/2026. Files shown: finale_v7a.mp4, finale_v7b.mp4. Finish: STOP.

## Question

﻿Watch and listen to this clip from a co-op Roblox horror fishing game (ages 10 and up, often on phones). It is the finale of a five-night run. The design: on the last night the owner wants one special fish from the deep water by the sunken steeple. At 4 AM the dock bell rings by itself and every water sound stops. The rule says: go home, lights on, do not stop. The lantern locks on and its oil starts running out. On the way home, strange boats with lanterns and false beacon lights appear, and stopping too long gets someone taken. Reaching the dock light with the fish ends the run at dawn.

In this clip a test bot already has the fish and runs home. Score each point 0 to 10, then overall. Quote timestamps. Be blunt, no em dashes, under 600 words.

1. the_turn: does the bell and the silence land as a big, unmistakable moment?
2. urgency: does the run home feel like a chase? Can you see the hazards?
3. readability: can a phone player tell where home is and how much oil is left?
4. the_ending: does reaching home at dawn feel like a payoff?
5. ui: does anything on screen get in the way (cards, prompts)?
6. clip_worthy: would five seconds of this make a good short video?
7. broken_or_ugly.

Then the top five concrete fixes in order of impact, each with the moment and exactly what to change.


Note: this time there are two clips, played back to back: the first ends partway through the run home and the second picks up from there to dawn. A test bot drives straight home without steering.

## Answer

**Scores**

1. **the_turn: 7/10.** The sudden silence at Clip 1 00:13 and the booming bell at 00:15 genuinely land. The audio drop creates instant dread. It loses points because the camera snaps stiffly to the seat at 00:14, "Line in." lingers in the way until 00:15, and the oil bar weirdly refills when turning red at 00:13.
2. **urgency: 3/10.** From Clip 1 00:15 to 00:29, this feels like a slow evening cruise, not a finale escape. There is no motor rumble, speed sensation, or escalating tension until a brief horn at 00:27. The hazards are unreadable: just tiny yellow specks on the horizon (00:20 to 00:29) and one light passing left at 00:26. No visible strange boats threaten the player.
3. **readability: 4/10.** On a phone screen, the top-left HUD text will be microscopic. Worse, during Clip 1 00:20 to 00:29, players cannot tell which yellow dot is home versus a false beacon. The bow lantern at 00:15 sits dead center, blocking the exact horizon line where you steer. The red draining oil bar is the only clear signal.
4. **the_ending: 4/10.** The warm sunrise and acoustic guitar in Clip 2 00:00 are a nice tonal shift, and the dry owner line works. However, dumping a tiny white text box over the screen while the boat bobs in place for 29 seconds feels flat. There is no docking arrival, no fish handoff, and no visual relief.
5. **ui: 3/10.** Cluttered and buggy. Clip 1 displays PC keybinds ("Book R, Guide G") that waste space on phones. Clip 2 00:03 brings the gameplay HUD right back on top of the victory screen. The summary box (Clip 2 00:00) sits directly over the dock with tiny, cramped text.
6. **clip_worthy: 3/10.** The bell at Clip 1 00:15 and horn at 00:27 have audio potential, but visually it is a boxy boat gliding across flat darkness. There is no close call, monster silhouette, or panic moment worth a 5-second short.
7. **broken_or_ugly: 4/10** (polish score; several glaring issues). Clip 1 00:13 jumps oil from roughly 75% orange to full red. Clip 1 00:16 to 00:29 shows ugly flat green streaks sliding across the water. Clip 2 00:00 prints "Quota cleared: 0 of 5 nights" on the finale clear screen, and the HUD reappears at 00:03.

**Overall: 4/10.** The bell audio sells the turn, then the actual chase and payoff completely deflate.

**Top 5 Concrete Fixes**

1. **Make the chase visibly terrifying (Clip 1, 00:18 to 00:29):** Replace distant specks with large dark boat silhouettes that cross near your bow, rocking with dim lanterns and emitting creaking wood or whispers as you pass. Add slight camera bob, rising engine throb, and flickering lantern light as oil drops.
2. **Separate home from false beacons and clear the sightline (Clip 1, 00:15 to 00:29):** Offset or lower the bow lantern so it stops blocking center view. Give the real dock a distinct visual tell (like a tall sweeping beam or steady double light) while false beacons flicker off-color or drift sideways.
3. **Fix mobile UI and HUD bugs (Clip 1, 00:00 to 00:13; Clip 2, 00:00 to 00:03):** Double HUD and summary font sizes for phones, hide PC key prompts on touch devices, keep the gameplay HUD hidden during the Clip 2 ending, and stop the oil bar from jumping to 100% at Clip 1 00:13.
4. **Replace ugly water lines and the camera snap (Clip 1, 00:14 to 00:29):** Delete the flat green streaks on the water and add soft foam wakes behind the stern. Replace the instant seat teleport at 00:14 with a fast 0.4-second camera swing forward.
5. **Give dawn a real payoff (Clip 2, 00:00 to 00:10):** Delay the summary card by 3 seconds so players watch the boat glide into the sunny dock, show the owner or special fish on deck, and fix the broken "0 of 5 nights" stat text.

## Action taken

Score 4/10, up from 3. The turn (silence, then the bell) now lands at 7/10. Taken into polish round 2: the oil bar eases at the bell instead of snapping; each strange boat lights its own dark hull and a still figure with its lantern, sways, and creaks as you pass; the bright streaks on the water replaced by soft foam; the HUD stays hidden under every end card; the run-cleared card waits 3 s so the player sees the dock at dawn; end-card text phone-sized; the motor stays audible on the run home; the bow lantern lowered below the horizon line. Not taken: hazards closer (Core spacing keeps the run fair and the sims at 100 percent Normal), a docking cutscene, camera shake. The "0 of 5 nights" stat is the debug scenario starting at night 5, not a bug in a real run. The camera snap at 00:14 is the debug bot being re-seated.
