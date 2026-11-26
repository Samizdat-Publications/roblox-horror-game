# Art: our own models

Made overnight 2026-11-26 by script in Blender 5.1.2 (the `bpy` module, headless, in the cloud). **Not yet imported or seen in Studio**: tomorrow's session does that. Every model can be rebuilt and tweaked from its script.

![Contact sheet](previews/contact-sheet.png)

## Roblox's import rules (read 2026-11-26)

| Rule | What we do | Source |
|---|---|---|
| At most 20,000 triangles per mesh; meshes should be closed and have some thickness | Every model is one mesh, the biggest about 1,400 triangles; nothing is paper thin (fins and lily pads are thin boxes) | https://create.roblox.com/docs/art/modeling/specifications |
| One material per mesh; textures up to 4096 px, one UV set inside 0 to 1 | No textures at all: each part's flat colour is baked into vertex colours, and all parts are joined into one mesh with one material | https://create.roblox.com/docs/art/modeling/texture-specifications |
| The 3D Importer takes .fbx, .obj and .gltf/.glb, with vertex colours | Each model ships as `.glb` and `.fbx`; try `.glb` first (Roblox's Blender page says glTF needs no extra scaling setup) | https://create.roblox.com/docs/studio/importer and https://create.roblox.com/docs/art/blender |
| 1 stud = 28 cm; in Blender set Unit System to None so 1 Blender unit = 1 stud; FBX export with Apply Scalings = FBX Unit Scale; Importer Scale Unit = Stud | Built in studs with Unit System None; FBX uses FBX Unit Scale, Y up, Z forward | https://create.roblox.com/docs/physics/units and https://create.roblox.com/docs/art/blender |
| Parts can be 0.001 to 2048 studs a side | Biggest is the dock, 46 studs long | https://create.roblox.com/docs/reference/engine/classes/BasePart |
| Collision fidelity: Box, Hull, Default, PreciseConvexDecomposition | See "Importing" below | https://create.roblox.com/docs/parts/meshes |

Unconfirmed: whether Studio shows the baked vertex colours exactly as in the previews (the Importer has an "Ignore Vertex Colors" option, so it reads them; check the first import).

## House style (decided 2026-11-26)

Duet's chunky low-poly, flat-colour, vertex-coloured look is the house style for everything in the game.

- **Blender by script** (`art/scripts/`) is the main tool for all props, environment, fish, rods and boats. Every script takes its colours from `art/scripts/palette.py`; add a colour there before using it.
- **Meshy** only for one-off complex organic shapes a script can't make well. Always decimate and recolour it in Blender to the same palette before import.
- **UI icons** (journal fish, bait, rods, boats) are rendered from the same Blender models, so the UI matches the world.
- **PixelLab and CadQuery are not used** for in-game art, to keep one consistent look.

## Conventions

- **Units:** 1 Blender unit = 1 stud. Blender is Z up; the exports are Y up, so the model's height is Roblox Y.
- **Pivot:** bottom centre of each model's bounding box.
- **Look:** low-poly, chunky, flat colours with light shading, readable on a phone. One shared palette in `scripts/palette.py`.
- **Fish scale:** 1 stud = 12 cm, the same scale the catch on the line uses (`FishingService.showCatch`: length in studs = cm / 12). Each fish is built at its species' average length; scale it by caught cm / average cm. Heads point along +X.

## Rebuild

```
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" -b -P "C:\Users\stewa\Documents\Claude\Roblox\art\scripts\build_all.py"
```

(That's Blender's default install folder; adjust if yours differs. Unverified on Stewart's PC.) One model: the same with `art\scripts\dock.py`; one fish: add `-- Walleye` at the end of the line for `fish.py`. In the cloud it ran as plain Python with `pip install bpy==5.1.2` (plus Pillow for the small previews and the contact sheet). `ART_SAMPLES` sets render quality (48 by default). Each run writes `models/<Name>.glb`, `models/<Name>.fbx`, `previews/<Name>.png` (1024 px) and updates `models/manifest.json` (sizes, triangles, what it replaces). `scripts/contact_sheet.py` rebuilds the sheet.

## Importing (for tomorrow's session)

1. Studio, 3D Importer (File, Import 3D), pick the `.glb`. Scale Unit **Stud**, keep vertex colours, **Merge Meshes** on.
2. "Upload to Roblox" creates the asset on Stewart's account. Turn it off while trying things, on for the version that stays.
3. Collisions: keep the existing gray-box parts as the invisible collision and cast-check shapes (set `Transparency = 1`), and set the new MeshParts to `CanCollide = false`, `CanQuery = false`. Then nothing about walking, casting or the zones changes. Small props (reeds, lily pads, fish, rods, bobber) never collide.
4. Place each model where its gray-box part was, using the notes in the table.

## The models

The table is generated from `models/manifest.json`. Sizes are studs as X x Y (up) x Z.

| Model | Size (studs) | Triangles | Replaces | Notes |
|---|---|---|---|---|
| [Dock](previews/Dock.png) | 16.7 x 18.2 x 46.3 | 1372 | Workspace.Lake.Dock (Deck, EndDeck, Posts) and the two dock-end lamp posts | Deck top is 9 studs above the model base; place the base at y = -7.5 so the deck top sits at y = 1.5. |
| [FishBuyerStand](previews/FishBuyerStand.png) | 12.05 x 12.8 x 6.11 | 772 | Workspace.Lake.SellStand (Counter, PostL, PostR, Roof); keep the SellPrompt and sign on an invisible counter part | Open front faces the lake. Base sits on the ground (y = 1). |
| [BaitShopStand](previews/BaitShopStand.png) | 14.32 x 11.9 x 6.11 | 1100 | Workspace.Lake.ShopStand (Counter, PostL, PostR, Roof); keep the ShopPrompt and sign on an invisible counter part | Open front faces the lake. Base sits on the ground (y = 1). |
| [PondRim](previews/PondRim.png) | 25.0 x 1.81 x 16.73 | 1328 | Workspace.Lake.HomePond RimN, RimS, RimW, RimE | Centre it on the pond (50, 1, 106 in the gray box); base on the ground. |
| [Log1](previews/Log1.png) | 22.16 x 2.81 x 3.49 | 188 | Workspace.Lake.Logs.Log1 to Log5 (mix the variants) | Lies along X. The gray box sinks logs 0.4 to 1.6 studs; keep that. |
| [Log2](previews/Log2.png) | 15.26 x 2.89 x 3.29 | 192 | Workspace.Lake.Logs.Log1 to Log5 (mix the variants) | Lies along X. The gray box sinks logs 0.4 to 1.6 studs; keep that. |
| [Log3](previews/Log3.png) | 18.42 x 4.29 x 5.14 | 292 | Workspace.Lake.Logs.Log1 to Log5 (mix the variants) | Lies along X. The gray box sinks logs 0.4 to 1.6 studs; keep that. |
| [Buoy](previews/Buoy.png) | 1.8 x 3.37 x 1.8 | 230 | Workspace.Lake.DeepHoleBuoy | Base at the water line minus about 0.6 so it floats. |
| [Reeds](previews/Reeds.png) | 3.9 x 7.29 x 3.7 | 428 | Workspace.Lake.WeedBed Weed sticks (scatter clumps over the weed bed) | Base at the water line; about 7 studs tall. |
| [LilyPads](previews/LilyPads.png) | 5.64 x 0.83 x 5.75 | 532 | Nothing yet: new dressing for the weed bed and pond | Sits on the water surface. |
| [PineTall](previews/PineTall.png) | 7.82 x 17.31 x 8.15 | 80 | Cedar Creek Trunk and Crown pairs | About 16 studs, like the gray box. |
| [PineShort](previews/PineShort.png) | 7.96 x 11.73 x 7.64 | 80 | Cedar Creek Trunk and Crown pairs (mix with PineTall) | About 11 studs. |
| [LeafyTree](previews/LeafyTree.png) | 9.49 x 15.67 x 8.88 | 176 | Nothing yet: new dressing for the lake shore | About 15 studs. |
| [RockSmall](previews/RockSmall.png) | 1.79 x 1.13 x 1.64 | 80 | Cedar Creek Boulder1-5 and Pebble1-14 (pick the size that fits) | About 1.6 studs across. |
| [RockMedium](previews/RockMedium.png) | 5.27 x 3.22 x 4.16 | 100 | Cedar Creek Boulder1-5 and Pebble1-14 (pick the size that fits) | About 4 studs across. |
| [RockLarge](previews/RockLarge.png) | 9.07 x 5.73 x 6.62 | 120 | Cedar Creek Boulder1-5 and Pebble1-14 (pick the size that fits) | About 7 studs across. |
| [Bluegill](previews/Bluegill.png) | 1.79 x 1.05 x 0.41 | 924 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 18.5 cm = 1.54 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [Pumpkinseed](previews/Pumpkinseed.png) | 1.55 x 0.87 x 0.34 | 924 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 16.0 cm = 1.33 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [YellowPerch](previews/YellowPerch.png) | 2.27 x 0.74 x 0.3 | 924 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 23.5 cm = 1.96 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [BlackCrappie](previews/BlackCrappie.png) | 2.42 x 1.3 x 0.51 | 924 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 25.0 cm = 2.08 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [LargemouthBass](previews/LargemouthBass.png) | 4.11 x 1.48 x 0.59 | 908 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 42.5 cm = 3.54 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [ChannelCatfish](previews/ChannelCatfish.png) | 6.14 x 1.45 x 1.03 | 964 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 62.5 cm = 5.21 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [CommonCarp](previews/CommonCarp.png) | 5.61 x 2.13 x 0.85 | 932 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 57.5 cm = 4.79 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [NorthernPike](previews/NorthernPike.png) | 8.62 x 1.49 x 0.87 | 908 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 77.5 cm = 6.46 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [RainbowTrout](previews/RainbowTrout.png) | 3.38 x 1.01 x 0.43 | 916 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 35.0 cm = 2.92 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [SmallmouthBass](previews/SmallmouthBass.png) | 3.38 x 1.22 x 0.49 | 908 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 35.0 cm = 2.92 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [Walleye](previews/Walleye.png) | 5.07 x 1.25 x 0.65 | 924 | FishShadows blobs and the catch held on the line (FishingService.showCatch) | Built at the species' average length, 52.5 cm = 4.38 studs (1 stud = 12 cm). Scale by caught cm / average cm. Head along +X. |
| [WillowRod](previews/WillowRod.png) | 0.67 x 1.06 x 6.0 | 644 | the gray-box rod part from RodService (Willow) | 6.0 studs long along Z, tip toward -Z (as RodService points it). Put the RodTip attachment at the tip. |
| [FiberglassRod](previews/FiberglassRod.png) | 0.67 x 1.06 x 6.6 | 604 | the gray-box rod part from RodService (Fiberglass) | 6.6 studs long along Z, tip toward -Z (as RodService points it). Put the RodTip attachment at the tip. |
| [GraphiteRod](previews/GraphiteRod.png) | 0.67 x 1.06 x 7.2 | 604 | the gray-box rod part from RodService (Graphite) | 7.2 studs long along Z, tip toward -Z (as RodService points it). Put the RodTip attachment at the tip. |
| [Bobber](previews/Bobber.png) | 0.84 x 1.38 x 0.84 | 304 | the ball Bobber and its Top from FishingService.makeBobber | 0.8 studs across like the gray box; the base is the line eye. |
| [JonBoat](previews/JonBoat.png) | 6.05 x 3.6 x 14.8 | 392 | Nothing yet: the boat from the boat plan (gray box in Task 2, this model after) | Hull 14 x 6 studs; floor at about 0.35 studs above the base. Bow toward -Z. |

Total: 32 models. Every one is a single mesh well under the 20,000 triangle limit; the biggest is the dock at 1372.
