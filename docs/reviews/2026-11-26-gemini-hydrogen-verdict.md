# Verdict on Gemini Hydrogen's repo review (11/26/2026)

Source: `2026-11-26-gemini-hydrogen-review.md` (Stewart ran it on the repo about 40 minutes before this verdict). Each point checked against the current code.

| # | Point | Verdict | Where |
|---|---|---|---|
| 1 | Dock-light cheese: fish at the edge of the light, dodge threats | **Take.** True in part: rules keep timing in the dock light, so rowing into the light can run a scare out. Rules pause (not pass) in the light; bite rates fall off near the dock so the quota forces the crew out. | Core builder now |
| 2 | Ghost agency: give the drowned a spotter role | **Take, partly.** The drowned already see outlines and ring a bell. Add: the bell sends a directional ripple the living can see, and the drowned can tell the real beacon from a false one. | Shell, after S4 |
| 3 | Boat feel: slide along the shore, damp turning while stopped | **Take.** Cheap and good. | Shell, after S4 |
| 4 | Deciding timeout silently keeps a maybe-wrong fish | **Take.** A timeout now throws the fish back, and the hold shows a visible countdown (the fish thrashes harder). | Core builder now (rule), shell later (look) |
| 5 | Solo Neighbor has no crewmate to impersonate | **Take, simplest form:** in solo, no fake callouts. A radio or tape voice can come once uploads reopen. | Core builder now |
| 6 | Watcher on touch: widen the edge cone, add feedback | **Take.** About 15 degrees wider for touch players; the vignette and tone already exist. | Core and shell |
| 7 | Look: Future lighting, terrain water, smaller lantern, darker ambient, overcast sky, waterline mist, depth of field | **Mixed.** A smaller lantern and darker ambient are **rejected**: Neon scored phone readability 2/10 before we lifted them. Depth of field rejected for phones. Future lighting, terrain water, a wake, waterline mist and an overcast sky go into the M8 look pass, judged by stills and Neon, with a phone performance check. (`Lighting.Technology` cannot be set from a script; it goes in the Rojo project file.) | M8 |
| 8 | Finale and Rulebook missing; dead `supplies`; duplicate WrongCatch name | Finale and Rulebook were **already done** after the snapshot. **Take** the cleanup: remove `supplies`, rename `Core/WrongCatch.luau` to `FishMutations.luau`. | Core builder now |
| 9 | Upload the pending sounds | Blocked by the account cap until ID verification; stand-ins stay, as planned. | Waiting on Stewart |
