# Don't Wave Back (code name Dead Calm)

A co-op Roblox horror game. Night shift on Blackwater Lake: one to four players share a rowboat, fill the bait shop's quota before dawn, and follow the Lake Rules. Scary, not disturbing. Built by Claude for Stewart and his son Liam.

## The gate

Run before every commit (Windows PowerShell 5.1):

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\check.ps1"
```

It runs Selene, the StyLua check, the Lune specs, the fast pacing sim, the lints (em dash, asset ids, secrets, Core purity, UI words), `rojo build -o DeadCalm.rbxl` and a smoke test of the built place. It ends with `GATE PASS` or `GATE FAIL`.

See `CLAUDE.md` and `docs/ARCHITECTURE.md` for how the project is built.
