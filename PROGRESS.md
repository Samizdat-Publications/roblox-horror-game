# Progress

Last updated 11/26/2026 by the local session (Fable 5.2).

## How to resume

1. Read `CLAUDE.md`, then this file, then `docs/PLAN.md`.
2. Run the gate. If it fails, fix that first.
3. Check for cloud helper work: `gh pr list --repo Samizdat-Publications/roblox-horror-game` and `docs/CLOUD-PROGRESS.md` on any `claude/core-*` branch. Review, run the gate on the branch, merge what passes.
4. Take the first unchecked item under "Next" below.

## Done

- Plan approved by Stewart on 11/26/2026 (`docs/PLAN.md`).
- Folder and repo created. The fishing repo ignores this folder through its local `.git/info/exclude`.
- Toolchain installed with Rokit 1.2.0: Rojo 7.7.1, Selene 0.32.0, StyLua 2.6.0, Lune 0.11.1, luau-lsp 1.70.1.
- Pipelines copied from the fishing repo (critic, ElevenLabs, capture, Blender scripts, test runner). Keys copied into the ignored `.env`.
- Design, architecture, cloud brief and the contracts (`Types.luau`, `Config.luau`) written.

- M0 skeleton, gate (11 steps) and CI built, committed and pushed to `Samizdat-Publications/roblox-horror-game`.
- Spike 1 (Studio loop) PASSED once on 11/26/2026: `tools\studio\launch.ps1` opened a copy of the place (pid in `artifacts\studio.pid`), the Studio MCP attached, Play, `DeadCalmDebug:Invoke("hello")` returned, console clean, screenshot taken, Stop. Studio opens a copy under `artifacts\studio\` so rebuilds never hit its file lock.
- Style board for Liam published: https://claude.ai/artifact/5jPTuiWZoUpbFAozsNgzQN (source `art\style-board\`, images from `gemini-nano-banana-2.1`). Build stays on Lantern Noir until he picks.
- Sound batch m1: 86 variants generated, winners ranked into `audio\final\`.
- The session was switched to Opus 5.5 high on 11/26/2026; [fable] items go to the `fable-advisor` agent.

- Core M1 and M2 committed (94 specs, pacing on target). Shell S1 committed and verified in Studio on 11/26/2026: player auto-seats in the helm facing the lake, `row_to_steeple` arrives in 23.5 s with the motor via the client path, `tour` has zero drift, console clean, 1,618 world parts.
- Look passes 1 to 3 (lighting, water, lantern, beacon, trees, steeple, dock props) with stills in `docs\checkpoints\stills\`. Neon look review: `docs\critic\11-26-2026-look-s1-neon.md` (2.5/10 before the passes).
- Neon design consult evaluated; taken and rejected ideas in DECISIONS.md and the shell brief.
- 53 sounds uploaded through the Fishing Game window's Open Cloud permission (Stewart approved), ids in `audio\ids.json` and `SoundRegistry.luau`. Owner's voice "Tull (Dont Wave Back)" made in ElevenLabs; 10 tapes generated.

## In progress

- Local builder: Core chunks M3 and M4 plus the Neon design changes (Neighbor rework, 6-minute nights, visible wrong-fish tells, no supplies, night tallies). It was cut off once by a network drop and resumed.
- Local grunt: regenerate 4 rejected sounds (frog-bull-b, owl-hoot, line-creak, ghost-bell), upload them plus ghost-loop and the 10 tapes, add the single frog calls to SoundRegistry.

## Next

- [ ] Review, gate, commit and push the M3 and M4 work.
- [ ] Prove an uploaded sound actually plays in the local place (check `Sound.IsLoaded` and `TimeLength` in Studio); moderation was "Reviewing" at upload.
- [ ] Shell S2 (fishing and the night on screen) once Core M3 lands, if the cloud shell session has not done it.
- [ ] Core M3 to M5 and M7, Shell S2 to S6 (cloud sessions if Stewart started them, else local builders, one chunk at a time).
- [ ] M8 polish and docs, final self-review, per `docs/PLAN.md`.

## Known issues

- **Cloud sessions could not be started by the local session** (the app refuses while Stewart is on Remote Control). He has the two prompts in HUMAN_TODO.md item 3. Check `gh pr list` and for `claude/*` branches before assigning a chunk to a local builder.
- Uploads use the Fishing Game Studio window (Stewart approved 11/26/2026). If that window is closed, uploads wait; never run Luau or play in it.
- `tools\critic\critic.py consult` returns an empty answer with its JSON schema on Gemini 4 Neon; calling the model directly in plain text works. `review` and `rank` modes are unverified here.

## Notes for the next session

- This PC is on a phone hotspot. Network steps can fail for no other reason: wait and retry.
- A repeating wake-up runs in the original session at 17 and 47 past each hour. It only exists while that session lives.
