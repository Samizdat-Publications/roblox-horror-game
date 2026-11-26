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

## In progress

- Local builder: Core chunks M1 and M2 (`docs\CLOUD-BRIEF.md`).
- Local builder: Shell chunk S1 (`docs\CLOUD-SHELL-BRIEF.md`).
- Neon design consult (direct API call, output to `docs\critic\11-26-2026-design-consult-neon.md`).

## Next

- [ ] Review, gate, commit and push the two builders' work.
- [ ] Verify S1 in Studio (scenarios `state`, `tour`, `row_to_steeple`, `camera`), capture the three key shots, tune `Look.luau`, Neon look review.
- [ ] Evaluate the Neon consult; log taken and rejected ideas in DECISIONS.md.
- [ ] Sound uploads (blocked, see Known issues). When unblocked: upload `audio\final\*.mp3` once each in priority order (beds, chorus, boat, dock), log to `audio\ids.json`, set ids in `SoundRegistry.luau`, prove one loads in the local place.
- [ ] Core M3 to M5 and M7, Shell S2 to S6 (cloud sessions if Stewart started them, else local builders, one chunk at a time).
- [ ] M8 polish and docs, final self-review, per `docs/PLAN.md`.

## Known issues

- **Cloud sessions could not be started by the local session** (the app refuses while Stewart is on Remote Control). He has the two prompts in HUMAN_TODO.md item 3. Check `gh pr list` and for `claude/*` branches before assigning a chunk to a local builder.
- **Sound uploads are blocked:** Open Cloud scopes `asset:read` and `asset:write` are not granted for the local-file Studio window (HUMAN_TODO.md item 4). Do not route uploads through the Fishing Game window unless Stewart says so.
- `tools\critic\critic.py consult` returns an empty answer with its JSON schema on Gemini 4 Neon; calling the model directly in plain text works. `review` and `rank` modes are unverified here.

## Notes for the next session

- This PC is on a phone hotspot. Network steps can fail for no other reason: wait and retry.
- A repeating wake-up runs in the original session at 17 and 47 past each hour. It only exists while that session lives.
