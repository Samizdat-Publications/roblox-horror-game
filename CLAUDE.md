# Don't Wave Back (code name Dead Calm): a co-op Roblox horror game

Night shift on Blackwater Lake. One to four players share a rowboat, fill the bait shop's quota before dawn, and follow the Lake Rules. Built by Claude for Stewart and his son. This folder is its own project and its own git repo (private GitHub: `Samizdat-Publications/roblox-horror-game`). It sits inside the fishing game's folder only for convenience.

## This file wins here

A session opened in this folder also loads `C:\Users\stewa\Documents\Claude\Roblox\CLAUDE.md`, which describes the FISHING game. While working on this project, ignore that file's read-first list, its `src/` layout and its sync method. Never edit, commit or push anything in the fishing repo. Reading or copying from it is fine.

## Read first, in order

1. `PROGRESS.md`: where the run stands and exactly how to resume.
2. `docs/PLAN.md`: the plan Stewart approved on 11/26/2026, with milestones.
3. `docs/DESIGN.md`: the game, its rules, its look and its sound.
4. `docs/ARCHITECTURE.md`: the contracts every module honors.
5. `docs/ROUTING.md`: which model does which work.
6. `DECISIONS.md` and `HUMAN_TODO.md`.

## Owner rulings (Stewart, 11/26/2026)

- Fable 5.2 has full creative control of the game and orchestrates the build.
- Sound and ambience matter most. Be liberal with ElevenLabs. Try Gemini music as an alternative for music beds.
- Uploading generated sounds and models to Stewart's Roblox account as private assets is approved. Never publish the game, never buy anything, never create Developer Products or Game Passes.
- The PC is on a phone hotspot and goes offline at times. The local session does Studio, sound and visuals; one cloud helper builds the pure logic in `src/shared/Core`, `tests` and `tools/sim` on `claude/` branches.
- Later on 11/26/2026: the local session was switched to Opus 5.5 (high effort, auto mode). It leads; items tagged [fable] in the plan go to the `fable-advisor` agent with a self-contained brief. Do as much as possible in the cloud: a second cloud session builds the server, client and UI (`docs/CLOUD-SHELL-BRIEF.md`). Local keeps what needs this PC: Studio, sound generation and upload, critics, captures.
- Gemini 4 Neon is the main critic: it consults on the design and watches playthrough video to list issues. Hydrogen is the cheap screener. Evaluate what they say; do not follow it blindly.
- A style board for Liam (graphic styles mocked up with Gemini image generation) is wanted. Do not wait for his choice; keep building on the current look.
- The run is autonomous. Do not stop to ask questions. Make the call, write one line in `DECISIONS.md`, keep going. Human-only steps go in `HUMAN_TODO.md` with exact steps.

## How we work

- **Gate before every commit.** It runs lint, format check, tests, the pacing sim, lints and a clean build:

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\check.ps1"
```

- **Functional core, thin shell.** Everything under `src/shared/Core` is pure Luau: no services, no Instances, no `task`, no `os.clock`, no `math.random`. Time comes in as `dt`, randomness from `Core.Rng`. The server and the Lune simulator both drive `Core.Night.step`, so the tests cover what ships.
- **Server authority.** Clients send intents only. Every remote goes through `Net` (type check, rate limit, distance check). Catches, quota and deaths are decided on the server.
- **No invented asset ids.** Every id lives in `SoundRegistry` or `AssetRegistry` and must appear in `audio/ids.json` or `art/ids.json` with its upload or Creator Store source. Id `0` means skip silently.
- **One Studio lane.** Only the main session drives Roblox Studio, in a window it launched itself and tracks by process id. Never close or touch a Studio window this project did not open. Drive playtests with the Studio-only `DebugDriver` and `DebugBot` scenarios, not simulated mouse and keyboard.
- **Roblox APIs change.** Check current docs or the Studio MCP skills (`list_roblox_skills`, then `get_roblox_skill`) before using an API. Do not trust memory.
- **Evidence.** No milestone is done without the test, score, still or clip that shows it. Checkpoints go in `docs/checkpoints/CP-0x.md`. Fable looks at every capture itself.
- **Resumable.** Commit and push at every milestone. Keep `PROGRESS.md` current: done, next, known issues, how to resume.

## House rules

- No em dashes in anything a person reads (docs, UI strings, commit messages). Use a comma, colon or period.
- Dates as MM/DD/YYYY.
- Content: no blood, gore, injury detail or bodies. Deaths are a fade to black and a sound. Scary, not disturbing. No real people, no other games' monsters or names.
- Keys live in the ignored `.env` (`ELEVENLABS_API_KEY`, `GEMINI_API_KEY`). Never print or commit them.
- Commands written for Stewart are Windows PowerShell 5.1 one-liners with full absolute paths.
