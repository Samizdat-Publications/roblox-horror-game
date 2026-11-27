# M8 polish list (11/27/2026, after midnight)

Collected from Neon's latest reviews (`docs/critic/11-26-2026-finale-v6-neon.md`, `11-26-2026-scare-hum-fail-v3-neon.md`) and the orchestrator's own Studio checks. Scores at this point: Hum fail 5/10 (from 3.5), finale 3/10 (from 1.5). The phone layout passes on the Galaxy A06.

## Hum fail
1. **The capsize debris looks like placeholders** (a yellow block, plain white and blue spheres). Use real things: the bucket as a bucket shape, the held fish models, an oar; spray as a short ParticleEmitter burst of small soft droplets, not spheres. Keep it brief and readable.
2. **The cyan rings look sci-fi.** Make them murky: low-contrast dark ripples with a faint pale edge, slower, closer to the hull.
3. **The motor is not recognizable over the hum** (measured: it does play, at volume 1.4 in the Boat group). Raise it so a phone speaker hears a clear putter (try +6 dB for the loop only), add a faint stern vibration while it runs, and keep the HUD's "Motor: on".
4. **The lantern glow stays orange when the lantern is out.** When off, the glow part goes dark (no Neon, a dull brass colour), and the PointLight and SpotLight are off.
5. **The drowned character clips under the boat** after the death card. Hide the drowned player's character (or park it out of view) while they spectate.

## Finale
6. **Ease the dawn in over 3 seconds** as the boat enters the dock light, instead of a one-frame change: warm the horizon, lift and thin the fog, then the banner.
7. **Keep the Steeple Cat in the boat at dawn** (it vanished when banked). Lay it on the floor, clear of the rods.
8. **Hide the HUD under the dawn banner** (they overlapped).
9. **The oil bar shows its real level from the start** of night 5 (it read empty, then snapped to full red at 4 AM).
10. **Bring the nearest hazards a little closer** for the run home: one boat crossing ahead at 40 to 60 studs off the path line, still never on the path and never within kill distance plus 15 studs. Rerun the full-run sim; Normal must stay at least 95 percent, Nightmare at least 70 percent.
11. **The "Line in." text is microscopic**; make prompts at least 16 px on every screen.

## General
12. Hold at least 3 seconds of full frog chorus before any Hum cue in the Studio scenarios (so a clip shows the change), not only in real play.
