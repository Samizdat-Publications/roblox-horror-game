# Critic consult: design-consult (gemini-4-neon)

Date: 11/26/2026. Files shown: DESIGN.md. Finish: MAX_TOKENS.

## Question

You are reviewing a game design before it is built. It is a 1 to 4 player co-op Roblox horror fishing game for ages 10 and up, played mostly on phones, often without voice chat, built from simple blocky parts. The design document follows. Answer five things, bluntly and specifically, with no praise and no preamble. Use plain markdown headings numbered 1 to 5. Keep the whole answer under 900 words. Do not use em dashes.

1. The three biggest risks that it is not fun or not scary in practice, each with one concrete change.
2. The weakest of the six rules (Hum, Wrong Catch, Neighbor, Knocking, Watcher, Finale) and exactly how to fix it.
3. What cheap addition is missing compared with the best co-op horror games on Roblox and Steam.
4. What to cut.
5. You can watch gameplay video with sound. Where in the build process would your review help most, and what exactly should each clip show (length, camera, what happens)?

## Answer

## 1. Three biggest risks and one concrete change each

**Risk 1: "Sound is the HUD" breaks on phones.**
Ten-year-olds on Roblox mobile frequently play muted, at low volume, or on phone speakers that cannot reproduce a low sub-bass "Hum" or subtle frog chorus thinning. Without audible warning, players die to invisible timers and quit thinking the game is unfair.
*Change:* Pair every audio tier with a diegetic visual tell inside the boat. Tie firefly density and water ripples around the hull to the frog chorus so everything freezes dead when frogs stop, and visibly vibrate the lantern flame and floorboards during the Hum build.

**Risk 2: Unreadable blocky anomalies and mobile UI gridlock.**
Checking "five bars" or "four saddles" on simple code-built fish in dim lantern light on a 6-inch screen, while a book blocks the viewport and a 13-phrase callout wheel fights touch controls, turns tension into squinting and menu fumble.
*Change:* Cut subtle stripe-counting anomalies. Restrict Wrong Catch tells to unmistakable silhouettes or behaviors (glowing third eye, blinking, upside-down fins, twitching jaw), and render the Field Guide as a quick-toggle half-screen card beside the held fish so players compare them without losing sight of the boat.

**Risk 3: Dead travel time and passive seats kill pacing.**
Nine-minute nights with slow oars and one steering seat leave three players sitting idle during long trips to the Steeple. Night 1, featuring only the Hum, will drag for mobile attention spans.
*Change:* Shorten nights to 5 to 6 minutes, give non-helm seats a simple tap-to-row rhythm that boosts quiet speed (creating noisy splashes if mistimed), and introduce Wrong Catch on Night 1 so the greed loop starts immediately.

## 2. Weakest rule and exact fix

**Weakest rule: The Neighbor.**
Once players read Rule 3, the waving rowboat has zero mechanical teeth. It drifts up, waits 30 seconds, and leaves if ignored. No player will open a 13-option callout menu to deliberately press "Wave" when the rulebook forbids it. The false beacon variant is also trivial: staring at it for two seconds confirms whether it blinks twice.

**Exact fix:**
Delete the "Wave" button trap. Make the Neighbor actively hunt your lantern light: when its oarlock creaks, it drifts steadily toward your boat and boards you unless the crew kills the lantern and holds still for 10 seconds while it passes, or rows away from it (risking losing their spot or hitting shore). While it lingers in the fog, have it emit fake overhead callout tags using a living or drowned crewmate's name ("Lantern on", "Go home") to trick players into breaking silence or steering toward a false beacon. This turns the Neighbor from a passive "don't press self-destruct" check into active pressure on light, movement, and crew trust.

## 3. Cheap missing addition from top co-op horror games

**Visible crewmate body language, death aftermath, and post-night blame.**
Games like Lethal Company, Content Warning, and Roblox Doors generate most of their scares and laughs from watching teammates panic, make dumb mistakes, and vanish. Locking players into outward-facing first-person seats turns co-op into four isolated solo screens.

Cheaply add three things using existing blocky avatars and UI:
1. Unlock full 360-degree head-look while seated and replicate head rotation to other clients so players physically see friends whip around toward noises or stare awkwardly at the Watcher.
2. When a player is taken, leave their Roblox hat floating on the water and drop their rod clattering into the bottom of the boat so teammates discover a death visually.
3. Add a 10-second end-of-night tally card with dry stats ("Broke silence twice", "Kept 2 cursed fish", "Bailed 40 gallons") to give non-voice-chat crews shared comedy between nights.

## 4. What to cut

* **Between-night pay envelope (8 upgrades):** Adds host-only menu friction and balance work without making the core horror better.
*

## Action taken

(fill in: what we changed, or why we did not)
