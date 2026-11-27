# Don't Wave Back (code name Dead Calm)

Night shift on Blackwater Lake. One to four players share a rowboat, fill the bait shop's cooler before 5 AM, and follow the Lake Rules taped inside the boat. The frogs are your only warning: when they stop all at once, something is coming, and every rule is a way to live through it. Hold still for the Hum, throw back the fish that are not in the book, never wave back at the other boat, answer the knocking, keep the thing on the shore at the edge of your eye, and on the fifth night bring the owner his fish when the bell rings by itself. Five nights make a run; clear one and Endless Nights opens, where any rule can come any night. Co-op horror for families: scary, not disturbing, no blood, no bodies, and funny in the gaps.

## Open it

Build the place file, then open it in Studio and press Play (Windows PowerShell 5.1, one line each):

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; & "$env:USERPROFILE\.rokit\bin\rojo.exe" build -o "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\DeadCalm.rbxl"
```

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\studio\launch.ps1"
```

The full guide (two players, what to test each night, the report-back checklist) is `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\PLAYTEST_GUIDE.md`.

## Controls

| Do | Keyboard and mouse | Gamepad | Phone or tablet |
|---|---|---|---|
| Row and steer | W A S D | Left stick | Thumbstick |
| Motor, lantern | M, F | X, Y | Motor, Light buttons |
| Cast (hold, let go), reel (hold) | Left click or Space | R2 | Cast button |
| Keep, bank, refill | E | A | Use button |
| Throw back | X | B | Throw back on the card |
| Knock | Q | L1 | Knock button |
| Callouts (Wave is in it) | C | D-pad up | Call button |
| Bail | Hold E | Hold A | Hold Bail |
| Rulebook, Field Guide | R, G | D-pad left, right | Book, Guide buttons |
| Locker (title screen) | K | R1 | Locker button |

## Tune it

Every gameplay number is in `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\src\shared\Config.luau`, each with a comment: night length (`Config.Night.realSeconds`), quotas per night (`Config.Nights`), crew size and difficulty scaling (`Config.Scaling`, `Config.Difficulty`, including tries per run), each rule's warning and timing (`Config.Rules`), Endless growth (`Config.Endless`), save retries (`Config.Save`) and the cosmetics list (`Config.Cosmetics`). Look and sound mix values are in `src\shared\Look.luau`; sound ids in `src\shared\SoundRegistry.luau` (see `SOUNDS_NEEDED.md`).

Change a number, then run the gate. Its pacing simulator plays thousands of nights with bots and says whether the nights still feel right (scares per night, quiet gaps, clear rates); a MISS names the night and crew size that drifted.

## The gate

Run before every commit:

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\check.ps1"
```

It runs Selene, the StyLua check, the Lune specs, the fast pacing sim, the lints (em dash, asset ids, secrets, Core purity, UI words), `rojo build -o DeadCalm.rbxl` and a smoke test of the built place. It ends with `GATE PASS` or `GATE FAIL`.

How the code is laid out: `CLAUDE.md` and `docs/ARCHITECTURE.md`.

## Credits

- Built by Claude (Anthropic), for Stewart and his son Liam.
- Sound: generated with ElevenLabs, plus a few stand-ins from Roblox's licensed Creator Store audio library (listed in `audio/library-standins.md`).
- Critiques of stills, clips and sound: Gemini.
- Made with Roblox Studio, Rojo, Luau, Selene, StyLua and Lune.
