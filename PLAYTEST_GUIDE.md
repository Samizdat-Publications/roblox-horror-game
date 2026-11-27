# Playtest guide

How Stewart and Liam open Don't Wave Back, play it, and report back. Updated 11/26/2026. Every command below is one line for Windows PowerShell 5.1: open Windows Terminal, paste it, press Enter.

## 1. Open it

**Build the place file** (only needed after code changes; the gate also builds it):

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; & "$env:USERPROFILE\.rokit\bin\rojo.exe" build -o "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\DeadCalm.rbxl"
```

**Open it in Studio** (the project's own launcher, which remembers the Studio window it opened):

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\studio\launch.ps1"
```

Or double-click `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\DeadCalm.rbxl`. Then press **Play** in Studio.

**Close the Studio window the launcher opened** (and only that one):

```powershell
cd "C:\Users\stewa\Documents\Claude\Roblox\dead-calm"; powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\studio\close.ps1"
```

**Two players on one PC:** in Studio, the Test tab, set Clients to 2 and press Start. Each window is a player.

**Two devices (Stewart and Liam together):** the game has to be published privately first. Only Stewart does that; the steps are in `C:\Users\stewa\Documents\Claude\Roblox\dead-calm\HUMAN_TODO.md` (item 4). After publishing, turn on Game Settings, Security, "Enable Studio Access to API Services" so saves are real.

**Saves:** in the unpublished place, saves live only while the server runs. The output says so once: `[DeadCalm] saves are in memory this session`. That is expected. In a published place with API access on, what you earn stays.

## 2. Controls

| Do | Keyboard and mouse | Gamepad | Phone or tablet |
|---|---|---|---|
| Row and steer (at the helm) | W A S D | Left stick | Thumbstick |
| Look around | Move the mouse | Right stick | Drag on the screen |
| Motor on or off | M | X | Motor button |
| Lantern on or off | F | Y | Light button |
| Cast: hold, then let go | Left click or Space | R2 | Cast button |
| Reel: hold to reel, let go to ease off | Left click or Space | R2 | Cast button |
| Keep the fish, bank at the dock, refill oil at the dock | E | A | Use button |
| Throw the fish back, or reel in | X | B | Throw back on the card |
| Knock on the hull | Q | L1 | Knock button |
| Callout wheel (Wave is in it) | C, then click a phrase | D-pad up, then A | Call button |
| Bail while there is water in the boat | Hold E | Hold A | Hold Bail |
| Rulebook | R, the Book button, or click the paper on the stern bench | D-pad left | Book button |
| Field Guide | G or the Guide button | D-pad right | Guide button |
| Turn Field Guide pages | Left and Right, or A and D | L1 and R1 | Tap a species |
| Shut the book or the Locker | Escape, Close, or click outside | B | Close |
| Ring the bell when drowned | Left click or Space | R2 | Bell button |

On the title screen:

| Do | Keyboard and mouse | Gamepad | Phone or tablet |
|---|---|---|---|
| Play (host only) | Click Play, or Enter | A | Tap Play |
| Difficulty (host only) | Click it, or N | X | Tap it |
| The Lake Rules | Click it, or L | Y | Tap it |
| Endless Nights (host only, after a cleared run) | Click it | Select it, A | Tap it |
| Locker | Click it, or K | R1 | Tap it |

The book covers most of the view and stops your hands: no casting, steering, lantern, motor, knocking or bailing while it is open.

## 3. What to test, night by night

The first player in is the host. A run is five nights of about 6 minutes each. A failed night comes back while the run has tries left (Normal 3, Nightmare 2).

**Title screen**
1. The lake from the dock, the owner's title tape, the paper menu on the left, the Locker and the "Longest Endless nights" list on the right.
2. Open the Locker. Amber, Bare Wood and No hat are yours from the start; the rest say how to earn them. Pick something you have: the card gets a dark red border and says "Wearing".
3. Read the Lake Rules. Pick a difficulty. Press Play.

**Night 1: fishing and the Hum.** Row out of the beacon light (fish do not bite in it), cast, set the hook when the bobber dips, keep the ink mark in the band. Hold the fish up to the Field Guide card: keep it or throw it back. Bank at the dock end with E. When the frogs stop all at once: stop reeling, motor off, lantern out, hold still until they sing again.

**Night 2: wrong fish.** Look hard at every catch next to the Field Guide. Glow, a third eye, a wrong tail, an extra fin, blinking lids, an eye looking the wrong way, a fin on the wrong side: throw it back.

**Night 3: the Neighbor.** Another rowboat in the fog, someone waving. Do not wave back. Lantern out and row away. A crewmate's callout might not be your crewmate.

**Night 4: the knocking and the Watcher.** Three knocks on the hull: answer with two (Q), not one, not three. If water comes in, bail (hold E). Something tall on the shore: keep it at the edge of your eye, never stare, never turn your back on it.

**Night 5: the special order.** Every rule so far, and the owner has changed one of them: read the book again (R). Catch the owner's fish by the steeple after 3 AM; at 4 AM the dock bell rings by itself, the lantern locks on and its oil is your clock. Go home without stopping, and avoid any boat or light that does not blink twice.

**After a cleared run: Endless Nights.** Back on the title, the host now has an Endless Nights button. Endless starts at night 6, any rule any night, one try. The paper tag says "Endless night 6". When it ends, your best night goes on the list (display names only).

**Each time:** check what you earned. Clearing night 1 gives the Bucket Hat. Clearing a run gives Bone White and the Sou'wester. The host's lantern color and boat paint show on the boat; your hat shows on your head and floats on the water if the lake takes you.

## 4. Report back

Copy this list and fill it in:

- [ ] Anything in the Output window other than the `[DeadCalm] server up`, `[DeadCalm] client up` and `saves are in memory` lines (a screenshot is fine).
- [ ] Which night you reached, on which difficulty, solo or with how many.
- [ ] Each night: cleared or failed, and if failed, what the death card said.
- [ ] Did each rule's warning come through? Name any you missed (sound off or on?).
- [ ] Was reeling fair (too fast, too slow, band too narrow)?
- [ ] Was a wrong fish obvious next to the Field Guide?
- [ ] Anything too dark to see, or too bright.
- [ ] Was it scary? Which moment was the scariest, and was anything too much?
- [ ] Locker: did picking a color change the boat (host) and your hat? Did a locked item stay locked?
- [ ] Endless: did the button appear after a cleared run, and did the night number show?
- [ ] On a phone: were the buttons big enough, and did any text spill off the paper?
- [ ] Anything that felt broken, slow or confusing, in your own words.
