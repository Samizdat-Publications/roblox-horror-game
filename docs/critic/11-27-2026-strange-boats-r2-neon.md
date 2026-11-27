# Critic consult: strange-boats-r2 (gemini-4-neon)

Date: 11/27/2026. Files shown: 35-boats-before-near.jpg, 36-boats-before-far.jpg, 37-boats-after-near.jpg, 38-boats-after-far.jpg, 39-boats-fisherman-close.jpg. Finish: STOP.

## Question

These four stills are from a co-op Roblox horror fishing game (ages 10 and up, often on phones). On the last night, strange boats appear on the water during the run home. The rule: there are no other boats on this lake, never wave back, never row toward them. Images 1 and 2 are BEFORE (one boat at about 50 studs, then a boat at about 85 studs beside a false beacon on a pole). Images 3 and 4 are AFTER the same two views, and image 5 is a close crop of image 3: the strange boat now lies turned side-on, a tall dark figure in a long coat and a wide brimmed hat stands in it with pinprick eyes, and its lantern hangs on a pole just behind him inside a soft glow.

Score 0 to 10, BEFORE and AFTER, for each:
1. reads_as_boat: at a glance on a phone, is it clearly a boat with someone in it?
2. distinct_from_beacon: can you tell it apart from the false beacon light on a pole (image 2 and 4)?
3. creepy: does it feel wrong and threatening, not silly?
4. art_fit: does the glow look like part of the world or like a UI sticker?
Then list the three most useful changes, blunt, under 350 words, no em dashes.

## Answer

**Scores (BEFORE to AFTER)**

1. **reads_as_boat:** 2/10 to 6/10. Huge readability jump for phones, since the figure is now unmistakable. It still loses points because the hull reads like a flat wooden raft or plank, and he looks like he is standing on top of it rather than inside it.
2. **distinct_from_beacon:** 2/10 to 9/10. Before, it blended right into the false beacon at 85 studs. After, the wide silhouette and soft backlit glow separate them immediately.
3. **creepy:** 3/10 to 5/10. Effective at 85 studs, where the dark hat silhouette feels tense. Up close, the blocky proportions, big bright eyes, and giant halo veer into goofy territory.
4. **art_fit:** 6/10 to 3/10. Before matched the game's simple lighting. After looks like a banded 2D sticker pasted behind him because the light has no visible source in the world.

**Three Most Useful Changes**

1. **Offset the lantern and tame the glow.** Putting the pole dead center behind his torso hides the lantern completely, making the glow look like a saint's halo instead of mist around a lamp. Move the pole to the bow or stern so players actually see the hanging light source. Shrink the glow sprite, lower its opacity, and dither the texture to kill that harsh circular banding.
2. **Make the hull read as a boat, not a slab.** Side-on, the boat is just a flat brown rectangle. Add a tapered bow, slightly raised sides, and a resting oar to sell the rowboat silhouette on small screens. Sink his legs inside the hull so he looks like a passenger instead of a figurine glued to a brick.
3. **Fix the eyes and stiff pose.** Those are bright square blocks, not pinpricks, and they look cartoonish up close. Shrink them down, dim them, or only fade them in if the player drifts too close. Break his rigid symmetry with a slight head tilt or a subtly raised arm hinting at a wave so he feels wrong rather than silly.

## Action taken

Round 2 scored 6, 9, 5, 3. Taken: the lantern moved beside his shoulder so its source shows, taller sides and a pointed bow, dimmer eyes, a smaller glow.
