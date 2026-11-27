# Progress

Last updated 11/26/2026, late night, by the local session (Opus 5.5, orchestrating; Fable 5.2 designed it).

## Morning summary for Stewart

(Filled in at the end of the overnight run.)

## How to resume

1. Read `CLAUDE.md`, then this file, then `docs/PLAN.md`.
2. Run the gate. If it fails, fix that first.
3. `git status`: uncommitted files belong to a builder that was cut off. Read "In progress" below for whose they are, and finish them rather than start over.
4. Take the first unchecked item under "Next".

## Done

- **M0 setup.** Repo (public since 11/26/2026), Rokit toolchain, the 11-step gate, CI, the Studio launch and close scripts. Studio loop proven.
- **Design and docs.** DESIGN, ARCHITECTURE, DECISIONS, HUMAN_TODO, MATURITY_NOTES, the cloud briefs, Neon's design consult (taken and rejected ideas in DECISIONS).
- **Liam's style board:** https://claude.ai/artifact/5jPTuiWZoUpbFAozsNgzQN (build stays on Lantern Noir until he picks).
- **Making-of build log:** https://claude.ai/artifact/GQrZM4KSA6mkBg4XUWYN7T (update after every milestone; steps in CLAUDE.md).
- **Rules engine complete (Core M1 to M5, M7).** 198 specs. Director property tests: 2,500 nights, 0 violations. Rule-following bot clears a Normal run in 100 percent of 300 seeds at every crew size, Nightmare 98 to 100 percent; rule-blind bot dead by night 2 in 100 percent. Pacing: all 20 night and crew cells on target. Details in `docs/CLOUD-PROGRESS.md`.
- **Shell S1 to S3.** The lake, boat, lighting, fishing, the night service, HUD, all five Lake Rules on screen, fake-outs, death cards that teach the counter, the drowned spectate view, callouts, the tally card. Studio-verified: a full quiet night clears; every `<rule>_pass` and `<rule>_fail` scenario reports correctly.
- **Look:** three lighting passes, a moonlight rim so the boat reads with the lantern out.
- **Sound:** 71 sounds and tapes uploaded and wired; 11 Roblox library stand-ins; 28 derived sounds built in-engine from uploaded ones. Uploads are capped until about 12/26/2026 or until Stewart ID-verifies (HUMAN_TODO 6a); priority list in `audio/UPLOAD-PRIORITY.md`.
- **Neon video reviews:** Hum fail 3.5 then 4.5 out of 10; derived-sound listening test found the mix buries the cues.

## In progress

- Builder: Shell S4 (title, lobby, rulebook, Field Guide page, five-night flow via Core.Run, finale presentation in `fx/Finale.luau`, phone buttons). Owns LobbyService, NightService, ui Title/Rulebook/FieldGuide/MobileButtons/NightCards, Input, Main.client.
- Builder: Scare polish 2 (`docs/SCARE-POLISH-2.md`): the mix first, then a longer visible capsize, motor audible, a mid-range hum layer, a tighter silence-to-hum gap, a phone-sized death card, clean state after death. Owns AudioDirector, fx (not Finale), BoatFx, WorldFx, Drowned, DeathCard, DeathTexts, HUD, Prompt, DebugBot, Look, SoundRegistry volumes.

## Next

- [ ] Commit S4 and polish 2 when they land; Studio check (`full_run`, `finale`, `title`, `rulebook`); re-record the listening test and the Hum fail for Neon (target 6/10 or better).
- [ ] Re-record every rule's pass and fail for a Neon pass; fix what it finds.
- [ ] Shell S5 (saves through Core.Profile with a store adapter, cosmetics, Endless, the leaderboard stub, Game Pass stubs) and S6 (PLAYTEST_GUIDE, SOUNDS_NEEDED, README).
- [ ] Phone check in the Device Simulator at 705 by 338.
- [ ] M8 polish; update MATURITY_NOTES; the final self-review against the original brief (every requirement Done, Partial or Not done).
- [ ] When Stewart says "verified" or "credits are topped up": upload per `audio/UPLOAD-PRIORITY.md`; generate the 18 sounds still missing.

## Known issues

- The cloud sessions were never started (the app refused while Stewart was on Remote Control); everything is built locally.
- `tools/critic/critic.py consult` returns empty answers on Neon; use `tools/critic/ask.py` (streaming) instead. Studio video capture stops at 30 s per recording.
- Screenshots of end cards show the Roblox account name: never commit those (the repo is public).
- ElevenLabs credits are out (18 sounds left to generate).

## Notes for the next session

- The PC is on a hotspot at times. Network steps can fail: wait and retry. Builders cut off by a drop can be resumed with SendMessage.
- Uploads (when open) go through the Fishing Game Studio window's Open Cloud permission, `open_cloud_invoke` only. Coordinate with the "Roblox fishing game roadmap" session, which works in that place.
- A repeating wake-up runs at 17 and 47 past each hour while this session lives.
