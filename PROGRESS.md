# Progress

Last updated 11/27/2026, early morning, by the local session (Opus 5.5, orchestrating; Fable 5.2 designed it).

## Morning summary for Stewart

The overnight run is finished: M0 to M8 are built, and the final self-review and its audit are done (`docs/SELF-REVIEW.md`, `docs/AUDIT-11-27-2026.md`). Everything is committed and pushed. The build log has the pictures: https://claude.ai/artifact/GQrZM4KSA6mkBg4XUWYN7T

**What works (checked in Studio, not just in tests)**
- A full five-night run from the title to dawn: fishing, the quota, banking at the dock, the owner's tapes, all five Lake Rules, fake-outs, the death cards that teach the rule, the drowned view and its bell, the run home and the dawn.
- The phone layout on the smallest phone Roblox offers.
- Saves (in memory while the place is unpublished), Endless Nights, cosmetics.
- 212 automated tests. A bot that follows the rules clears Normal every time and Nightmare about 95 percent of the time; a bot that ignores them is dead by night 2.

**What is stubbed or rough**
- About 30 of our own sounds wait on disk because the Roblox upload cap is used up; free Roblox library sounds stand in. 18 more sounds need ElevenLabs credits.
- The strange boats on the run home still read as small lights more than boats.
- Real DataStores and a two-player test need the game published privately (HUMAN_TODO).
- The critic (Gemini Neon) scores the two big moments 5 out of 10. It started at 1.5 and 3.5. It is harsh, and it judges a test bot that drives straight.

**Three things for you and Liam to try first**
1. Night 1, the Hum: when every frog stops at once, cut the motor, put the lantern out, hold still. Then try it wrong on purpose to see the death card.
2. Night 3, the Neighbor: someone waves from a boat in the fog. Don't wave back.
3. Read the rulebook (R on a PC, the book button on a phone) and find the line the owner crossed out.

To play: double-click `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\DeadCalm.rbxl`, then press Play in Studio.

**Top five next builds**
1. Make the strange boats on the run home read as boats: a silhouette you can see, closer passes that stay fair.
2. Upload our own sounds when the cap allows (ID verification or after 12/26/2026) and generate the 18 missing ones.
3. Publish privately and run a two-device test with Liam: real saves, two players in one boat, cues that go to one player only.
4. Liam's style pick from the style board (https://claude.ai/artifact/5jPTuiWZoUpbFAozsNgzQN), then a look pass in that style.
5. Hero models (the boat, the lantern, the Watcher) from Blender, laid over the block versions (plan item M9).

## How to resume

1. Read `CLAUDE.md`, then this file, then `docs/PLAN.md`.
2. Run the gate. If it fails, fix that first.
3. `git status`: uncommitted files belong to a builder that was cut off. Check `docs/SHELL-DECISIONS.md` (newest lines at the bottom) for what it was doing, and finish it rather than start over.
4. Take the first item under "Next".

## Done

- **M0 setup.** Repo (public since 11/26/2026), Rokit toolchain, the 11-step gate, CI, the Studio launch and close scripts.
- **Design and docs.** DESIGN, ARCHITECTURE, DECISIONS, HUMAN_TODO, MATURITY_NOTES, PLAYTEST_GUIDE, SOUNDS_NEEDED, README, the style board for Liam, the making-of log.
- **Rules engine (Core).** 212 specs. Director property tests: 2,500 nights, 0 violations. Rule contract sim: 8,308 checks, 0 violations; every player a rule takes had heard its cue (794 deaths, 0 violations).
- **Shell S1 to S6.** World, boat, lighting, fishing, the night service, every Lake Rule on screen, fake-outs, death cards, the drowned, callouts, title, lobby, rulebook, Field Guide, five-night flow, finale, phone buttons, saves, cosmetics, Endless, leaderboard and Game Pass stubs.
- **M8 polish.** Three rounds from Neon's video reviews and Studio checks (`docs/M8-POLISH.md`, `docs/SHELL-DECISIONS.md`, `docs/critic/`).
- **Final self-review and audit (11/27/2026).** One real fairness hole found (a solo Watcher could take someone who never saw it) and fixed; Net now uses the tested validator; a player who leaves no longer keeps a lost night alive.

## Next

- [ ] The top five next builds above.
- [ ] When Stewart says "verified" or "credits are topped up": upload per `audio/UPLOAD-PRIORITY.md`; generate the 18 missing sounds.

## Known issues

- The strange boats on the run home are hard to see (next build 1).
- `tools/critic/critic.py consult` returns empty answers on Neon; use `tools/critic/ask.py` (streaming). Studio video capture stops at 30 s per recording; start recordings after a scenario's reset.
- Screenshots of some end cards show the Roblox account name: never commit those (the repo is public).
- luau-lsp type analysis is not run (no Roblox definitions file); selene and the specs cover the rest.

## Notes for the next session

- The PC is on a hotspot at times. Network steps can fail: wait and retry. Builders cut off by a drop can be resumed with SendMessage.
- Uploads (when open) go through the Fishing Game Studio window's Open Cloud permission, `open_cloud_invoke` only. Coordinate with the "Roblox fishing game roadmap" session, which works in that place.
