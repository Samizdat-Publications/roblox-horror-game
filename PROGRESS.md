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

## In progress

- M0: skeleton, gate and CI (builder).

## Next

- [ ] M0: commit, create the private GitHub repo, push.
- [ ] M0 spike 1: Studio loop (build, launch, attach, play, capture, close) three times.
- [ ] M0 spike 2: one sound generated, uploaded, proven to load in the local place.
- [ ] M0 spike 3: start the cloud helper with `docs/CLOUD-BRIEF.md`.
- [ ] M1 to M8, then the final self-review, per `docs/PLAN.md`.

## Known issues

- None yet.

## Notes for the next session

- This PC is on a phone hotspot. Network steps can fail for no other reason: wait and retry.
- A repeating wake-up runs in the original session at 17 and 47 past each hour. It only exists while that session lives.
