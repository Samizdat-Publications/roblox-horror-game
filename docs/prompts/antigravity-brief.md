# Brief for a Gemini review pass in Antigravity (11/27/2026)

You are a guest reviewer and builder on "Don't Wave Back", a co-op Roblox horror game. Claude (Anthropic) built it and will take your work back afterward. Stewart, the owner, wants three things from you: honest feedback, any work you can finish and prove, and one package Claude can merge.

## What this is

Night shift on Blackwater Lake. One to four players share a rowboat, fill the bait shop's fish quota before dawn and follow the Lake Rules (a rulebook of five creatures, each with a sound cue and a counter). Rojo project, strict Luau. Pure game logic lives in `src/shared/Core` and is tested with Lune; the server and client are a thin shell over it.

Read in this order: `README.md`, `PROGRESS.md`, `docs/DESIGN.md`, `docs/ARCHITECTURE.md`, `DECISIONS.md`. `CLAUDE.md` holds the house rules; skip its parts about Claude subagents, the making-of artifact and the Studio lane.

## Rules you must keep

- Work only inside this folder. Do not push to GitHub, do not touch any other folder on this PC (the fishing game in the parent folder is a separate project), and do not close or use any Roblox Studio window you did not open yourself.
- Never publish the game, upload assets, buy anything or create Developer Products or Game Passes. Never invent an asset id: every id must already be in `audio/ids.json` or `art/ids.json`.
- There are no API keys here and you need none. Do not add any.
- `src/shared/Core` stays pure: no services, no Instances, no `task`, no `os.clock`, no `math.random`. Time comes in as `dt`, randomness from `Core.Rng`.
- Server authority: clients send intents only, through `Net`. Catches, quota and deaths are decided on the server.
- No em dashes in anything a person reads (docs, UI text, your report). Use a comma, colon or period. Dates as MM/DD/YYYY.
- Content: scary, not disturbing. No blood, gore, injury or bodies. Deaths are a fade to black and a sound.
- The repo is public: never write a child's age, a Roblox account name or an email anywhere.

## The work, in priority order

1. **Feedback.** Read the design and the code as a senior Roblox developer and a horror designer. What is strong, what is weak, what would you cut, what is risky for players on phones, what is missing before a first two-player test. Be specific: file and line where it helps.
2. **Fix the two bugs from Stewart's first hands-on play (11/27/2026).**
   - The oars stay still while the boat rows forward.
   - Pressing Space to cast shows no line or bobber, yet the game treats the line as in the water (the "press X to reel" prompt appears).
   Both look like missing client visuals, not broken rules. A likely cause: milestone M9 laid Blender hero meshes over the part-built boat (`src/server/HeroModels.luau`, `src/shared/HeroLook.luau`), which may have hidden or orphaned the parts the oar animation and the fishing line attach to. Start with `src/client/BoatFx.luau`, `src/server/world/BoatHull.luau`, `src/server/FishingService.luau` and `src/server/HeroModels.luau`. Find the real cause before changing anything, and explain it in your report.
3. **Anything else you can finish and prove** without uploads: items under "Known issues" in `PROGRESS.md`, weak spots you found in step 1, missing tests. Prefer small, verified changes over big rewrites.

## Proving your work

- Run the gate after every change set. It needs the Rokit tools already installed on this PC:

```powershell
cd "<this folder>"; powershell -ExecutionPolicy Bypass -File ".\tools\check.ps1"
```

- If you can drive Roblox Studio, build the place with `rojo build -o DeadCalm.rbxl`, open that file in a new Studio window, and check your fixes in Play mode. If you cannot, say so plainly; do not claim a visual fix works without seeing it.

## The package to hand back

1. Before you change anything, make a baseline commit so your work can be diffed: `git init`, `git add -A`, `git commit -m "Baseline from Claude"`. (`BASE_COMMIT.txt` names the matching commit in Claude's repo.)
2. Commit your work in small commits with clear messages.
3. Write `GEMINI-REPORT.md` in the folder root with these sections: Feedback; Changes made (file by file, and why); How each change was verified (gate output, Studio checks); Not done, and why; Suggestions for Claude.
4. Zip the whole folder, including the `.git` folder, as `dont-wave-back-from-gemini.zip` and tell Stewart where it is.
