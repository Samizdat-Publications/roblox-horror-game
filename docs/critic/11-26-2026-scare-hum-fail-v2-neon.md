# Critic consult: scare-hum-fail-v2 (gemini-4-neon)

Date: 11/26/2026. Files shown: hum_fail_v2.mp4. Finish: STOP.

## Question

Watch and listen to this clip from a co-op Roblox horror fishing game (ages 10 and up, often played on phones). It shows the rule called the Hum, played wrong on purpose.

The rule: the whole frog chorus stops at once, then a deep hum rises from under the boat. The crew must stop reeling, cut the outboard motor, put out the lantern and hold still until the frogs sing again. In this clip the player leaves the motor running, so they should fail: the boat is thrown, the catch goes over the side, the player is pulled under (fade to black, a splash or drag sound), and a paper death card should name the rule ("You left the motor running..." style).

Use this rubric. Score each point 0 to 10, then overall. Quote timestamps for everything. Be blunt, no praise paragraphs, no em dashes, under 600 words.

1. cue_clarity: can you hear the frogs stop and the hum rise? Is it unmistakable, and does it arrive before any danger?
2. learnable: after seeing this once, could a 12 year old say what they should have done?
3. time_to_react: enough time between cue and consequence?
4. payoff: is the fail moment readable and startling rather than confusing? Can you SEE anything happen?
5. relief_or_ending: is there a clear end (death card, fade, sound)?
6. clip_worthy: would five seconds of this make a good short video with no explanation?
7. tone: scary but not disturbing, no gore.
8. broken_or_ugly: anything that undercuts it (black screen, missing sound, glitch, timing).

Then list, in order of impact, the top five concrete fixes, each naming the moment and exactly what to change.

## Answer

**Rubric Scores**

1. **cue_clarity: 4/10**
The frogs cut out abruptly at 00:01, leaving over four seconds of plain water lapping before the hum starts at 00:06. From 00:06 to 00:11, the hum is pure low sub-bass that disappears on phone speakers, with zero visual feedback (no water ripples, no hull shake). Worse, when "Motor: on" appears at 00:04, there is almost no audible motor chug to warn the player it is running.

2. **learnable: 5/10**
The paper death card at 00:16 spells out the rule clearly, which saves this from failing completely. However, the card is small, uses thin text that will be hard for a 12-year-old to read on a phone, and vanishes after 3.5 seconds (00:19). Because the motor is nearly silent from 00:04 to 00:11, a player may not realize they left it on until the card tells them.

3. **time_to_react: 7/10**
About 10 seconds pass from frog silence (00:01) and 6 seconds from hum start (00:06) to impact at 00:12. That is enough time to react, though the four-second gap between silence and hum muddies when the timer actually begins.

4. **payoff: 3/10**
At 00:12, the boat snaps left for half a second in near-total darkness, a wood crack and splash play (00:12 to 00:14), and the screen cuts to flat dark teal (00:13) then black (00:14). You cannot see the boat thrown, no catch goes overboard (quota is 0/7 anyway), and there is no drag-under sensation. It reads like a camera glitch.

5. **relief_or_ending: 6/10**
The fade to black (00:14), bass stinger, and death card (00:16 to 00:19) create a clear endpoint. Two things undercut it: a stray frog croaks during the black screen at 00:15 before the card appears, and the cut at 00:20 to a calm, upright boat feels abrupt.

6. **clip_worthy: 2/10**
No one is clipping five seconds of a pitch-dark screen snapping sideways for half a second into black (00:09 to 00:14). There is nothing visible to react to and no physical chaos.

7. **tone: 7/10**
Fits ages 10+ well. Quiet dread, no gore, and the paper note aesthetic (00:16) works. The problem is lack of visibility, not tone.

8. **broken_or_ugly: 4/10**
Once the lantern dies at 00:01, the frame is nearly black on a phone screen. The "Hold to cast" prompt stays stuck on screen from 00:00 to 00:12. At 00:20, the boat sits upright and undamaged, the notepad still reads "Motor: on", and a random glowing blue orb floats beside the hull while the prompt says "Ring the bell" with no bell visible.

**Overall: 4.5/10**

---

**Top 5 Fixes (In Order of Impact)**

1. **Make the fail payoff readable (00:12 to 00:14):** Raise ambient moonlight slightly so the boat and water edge stay visible with the lantern out. Extend the capsize to 1.2 seconds with a violent roll, white foam burst, and loose gear or fish flying over the gunwale, then plunge the camera underwater with bubbles and a muffled drag-down sound before fading to black.
2. **Add phone-friendly hum and motor cues (00:04 to 00:11):** Give the outboard motor an unmistakable puttering loop and faint stern vibration whenever "Motor: on" is active (00:04). Layer mid-range hull resonance (150 to 400 Hz) over the sub-bass hum (00:06 to 00:11), plus subtle camera rattle and expanding water rings around the boat.
3. **Resize and hold the death card (00:15 to 00:19):** Mute the premature frog croak at 00:15. Scale the paper card up to fill ~70% of screen width with thicker, higher-contrast text for phones, and hold it for 5 seconds or until tapped.
4. **Tighten silence-to-hum timing (00:01 to 00:06):** Cut the dead gap between the frogs stopping (00:01) and the hum rising (00:06) down to 1.5 seconds so players immediately link the silence to the hum.
5. **Fix post-death state and HUD leaks (00:12, 00:20 to 00:22):** Hide the casting prompt on impact (00:12), clear "Motor: on" from the notepad after death, show the boat capsized or rocking hard at 00:20, and remove or explain the floating blue orb.

## Action taken

All five accepted and queued in docs/SCARE-POLISH-2.md, to run after the derived-sounds work (same files). The "floating blue orb" is the drowned player's own ghost light; it gets a "You" label.
