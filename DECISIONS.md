# Decisions

One line each: the call, then why. Newest at the bottom.

## 11/26/2026

- **Display title is "Don't Wave Back"; Dead Calm stays as the code name.** Dead Calm is a 1989 film title; the new title is a rule from the book and no game by that name turned up on Roblox or Steam. One constant in Config.
- **Fable 5.2 orchestrates; Opus builds; Sonnet does mechanical work; one cloud helper builds the pure logic.** Unattended run with judgment-heavy look and sound calls; the PC goes offline with the hotspot.
- **The folder is `Roblox\dead-calm` with its own repo, ignored by the fishing repo through `.git/info/exclude`.** A nested repo must not be swallowed by the fishing repo, and no tracked fishing file may change.
- **Rojo build is the source of the place; nothing is edited only in Studio.** The whole world is built by code, so the place file is a build artifact.
- **Core requires use `script.Parent` and the Lune runner fakes `script`.** That runner is already proven on this machine in both Lune and Studio; string requires were not worth the risk.
- **Our own seeded Rng instead of Roblox Random.** Identical draws in Lune and Roblox, so a logged seed replays a run and sims match the game.
- **The server owns the reel bar; the client only sends "reel held".** Never trust the client for catches.
- **Gaze is client reported and range checked.** The server cannot see a camera; a cheater can only make a co-op game easier for their own crew.
- **Quota is counted in points (fish size), not fish.** It makes deep water worth the trip.
- **Wrong Catch counts triple if kept.** Turns a rule into a temptation the crew argues about.
- **The motor hides the frog chorus.** Speed costs you your hearing; ties a verb to the sound pillar.
- **Rules can be amended per run; the cue never changes.** Keeps the rulebook worth reading on the tenth run without breaking learn-by-dying.
- **Night 5 needs a Steeple Cat, which only bites after 3 AM at the steeple.** Puts the crew in the deepest water when the bell rings.
- **Fixed-phrase callouts, no free text, default emote menu off.** Works without voice chat (Liam is under the voice age) and makes our Wave the only wave.
- **Installed Rokit 1.2.0 from its official GitHub release** and pinned Rojo 7.7.1, Selene 0.32.0, StyLua 2.6.0, Lune 0.11.1, luau-lsp 1.70.1 in `rokit.toml`.
- **A repeating wake-up (cron, 17 and 47 past the hour) nudges the local session to continue.** The hotspot drops; the job dies with the session and is deleted when the run ends.
- **Uploads of sounds and models go to Stewart's Roblox account as private assets through Open Cloud.** Approved by Stewart on 11/26/2026. Nothing is published as a game.
- **Uploads go through the Fishing Game Studio window's Open Cloud permission.** Stewart said "use the fishing window" on 11/26/2026; the local-file window has no asset scopes. Only `open_cloud_invoke` runs there; nothing in the fishing place is touched.
- **The frog chorus is the full loop plus single calls scheduled from the shore.** The generated "thin" and "sparse" loops were too busy to read as thinning.
- **Night lighting lifted twice in Studio.** The design palette's near-black water and fog rendered pure black; Neon's look review scored phone readability 2/10. Values live in `Look.luau`.
- **Taken from Neon's design consult (`docs/critic/11-26-2026-design-consult-neon.md`):** every audio cue gets a visual tell (lantern flame shiver and floorboard buzz in the Hum, fireflies freeze when the frogs stop); wrong fish use tells visible at a glance, never a count of stripes; the Field Guide is a half-screen card beside the held fish; nights are 6 minutes instead of 9; the Neighbor hunts lantern light and fakes crewmate callouts; a taken player's hat floats and their rod clatters into the boat; an end-of-night tally card; free head-look with head turns replicated; the supply pick is cut.
- **Rejected from the consult:** Wrong Catch on night 1 (one new rule per night is how players learn). Deferred: tap-to-row for passenger seats.
