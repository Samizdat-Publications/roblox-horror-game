# Things only Stewart can do

Nothing here blocks the build. Each item says why it matters and the exact steps.

## Before or during the run

1. **Keep this PC on and online when you can.** The local half of the build only moves while the hotspot is home. If the session looks idle after you reconnect, type `continue` in it.
2. **Upload folder.** In Roblox Studio: Assistant panel, the "..." menu, Settings, MCP Permissions. Make sure `C:\Users\stewa\Documents\Claude\Roblox` is in the approved upload folders. If uploads from the new folder are refused, also add `C:\Users\stewa\Documents\Claude\Roblox\dead-calm`.

3. **Start the two cloud sessions (the app would not let the local session start them over Remote Control).** In the Claude desktop app or at claude.ai/code, start a new cloud session on the repository `Samizdat-Publications/roblox-horror-game` (default environment) and paste this as the whole prompt:

   `Read docs/CLOUD-BRIEF.md in this repository and carry it out in full without stopping to ask questions.`

   Then start a second cloud session on the same repository with:

   `Read docs/CLOUD-SHELL-BRIEF.md in this repository and carry it out in full without stopping to ask questions.`

   Until you do, the local session builds the same work itself whenever the PC is online.

4a. **Keep the Fishing Game open in Roblox Studio (11/26/2026, evening).** Sound uploads go through that window (you approved it). It closed when the laptop lid shut, so 15 uploads are waiting: 4 redone sounds, ghost-loop and the 10 owner's tapes. Open Roblox Studio, open "Fishing Game" from your experiences, and leave it open. Claude does not touch anything in that place; it only uses the window to upload.

4. **(Resolved: Stewart chose "use the fishing window".) Sound uploads were blocked until a permission was granted (found 11/26/2026).** The Studio window that has the horror game open (title starts with `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\artifacts\studio\DeadCalm-play`) refuses uploads: "Scope 'asset:read' has not been granted". In THAT window: Assistant panel, the "..." menu, Settings, MCP Permissions. Grant the asset read and asset write permissions (the same ones the Fishing Game window has), and check the approved upload folders include `C:\Users\stewa\Documents\Claude\Roblox`. If that window offers no such setting because the place is a local file, tell Claude "upload through the fishing window": the upload goes to your account either way and changes nothing in the fishing place. Until then the game builds silent, with every chosen sound waiting in `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\audio\final`.

5. **ElevenLabs is out of credits (11/26/2026, night).** 18 sounds are still to generate: finale-bed, title-theme, dawn-cue, run-cleared, night-failed-sting, lake-groan and night-cleared-sting (partial), and 8 UI sounds. Top up credits on elevenlabs.io (you said you can), then tell Claude "credits are topped up". Until then the game uses Roblox's free library sounds for those.
6. **The Roblox account's audio upload limit is used up until about 12/26/2026** (100 audio uploads per 30 days, shared by the fishing game and this game). About 30 of this game's sounds are generated but cannot be uploaded until then; free Roblox library sounds stand in for them (`audio/library-standins.md`). Nothing to do now. After 12/26, tell Claude "uploads reset" and it will swap our own sounds in, packing several short ones into one file to stretch the limit.

## After the run

3. **Play it solo.** Double-click `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\DeadCalm.rbxl`, then press Play in Studio. To rebuild the file first:

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; & "$env:USERPROFILE\.rokit\bin\rojo.exe" build -o "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\DeadCalm.rbxl"
```

4. **Play it with Liam on two devices.** That needs the game on Roblox, which only you may do. In Studio with `DeadCalm.rbxl` open: File, Publish to Roblox As, create a new experience named "Don't Wave Back", keep it Private. Then in Game Settings, Security, turn on "Enable Studio Access to API Services" so saves work. Invite Liam's account under Game Settings, Permissions (Play). The maturity questionnaire answers are in `MATURITY_NOTES.md`.
5. **Sound permissions after publishing.** Sounds uploaded by your account play in your own experiences. If any sound is silent in the published game, open the experience on create.roblox.com, Configure, Permissions, Assets, and grant the ids listed in `audio/ids.json`.

More items are added below as the run finds them.
