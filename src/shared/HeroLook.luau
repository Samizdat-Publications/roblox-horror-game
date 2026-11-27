--!strict
-- Look constants for the M9 hero models (server/HeroModels.luau and the Watcher in
-- client/fx/Watcher.luau). Kept apart from Look.luau on purpose. No requires.
--
-- `hide` lists the part-built pieces each hero mesh covers. They are made see-through
-- (Transparency 1) and keep their collision, queries, attachments and lights, so nothing
-- about walking, casting, seats or the rules changes. When a mesh does not load, nothing is
-- hidden and the part-built version is the game, exactly as before M9.

local HeroLook = {}

-- ReplicatedStorage folder holding one loaded copy of each hero mesh (the client clones the
-- Watcher from it).
HeroLook.FOLDER = "DeadCalmHero"

-- Name prefix of every placed hero MeshPart.
HeroLook.PREFIX = "Hero"

-- Roblox brings a glTF mesh in turned half a turn about its vertical axis (seen in Studio on
-- 11/27/2026: the shack's stovepipe landed front left instead of back right, the lantern cage
-- sat behind its glow). Every placed mesh gets this turn about its own centre.
HeroLook.MESH_TURN = CFrame.Angles(0, math.pi, 0)

-- Attribute set on each part-built piece a hero mesh hides.
HeroLook.HIDDEN_ATTR = "HeroHidden"

-- Surface material per hero mesh (vertex colours carry the palette; the material adds grain).
HeroLook.Material = {
	BoatShell = Enum.Material.Wood,
	BoatInterior = Enum.Material.Wood,
	Lantern = Enum.Material.SmoothPlastic,
	Watcher = Enum.Material.SmoothPlastic,
	Steeple = Enum.Material.Slate,
	Shack = Enum.Material.WoodPlanks,
	DeadTreeA = Enum.Material.Wood,
	DeadTreeB = Enum.Material.Wood,
} :: { [string]: Enum.Material }

-- The boat paint cosmetic colours this mesh (it has no vertex colours). Cosmetics lists it.
HeroLook.SHELL_PART = "HeroBoatShell"

HeroLook.hide = {
	BoatShell = { "Hull", "SidePort", "SideStarboard", "Transom", "BowPort", "BowStarboard", "BowFloor" },
	BoatInterior = {
		"GunwalePort",
		"GunwaleStarboard",
		"Keel",
		"ThwartStern",
		"ThwartMid",
		"ThwartBow",
		"HelmSeat",
		"BowSeat",
		"PortSeat",
		"StarboardSeat",
	},
	Lantern = { "LanternPost", "LanternArm", "LanternCap" },
	Shack = {
		"Floor",
		"WallSouth",
		"WallWest",
		"WallEast",
		"WallNorthA",
		"Door",
		"WallNorthB",
		"WallNorthC",
		"WallNorthBelow",
		"WallNorthAbove",
		"WallNorthD",
		"RoofNorth",
		"RoofSouth",
		"GableEast",
		"GableWest",
		"Step",
	},
} :: { [string]: { string } }

-- Steeple pieces that stay visible (the bell rings in the finale; the anchor is invisible).
HeroLook.steepleKeep = { Bell = true, BellLip = true, SteepleAnchor = true } :: { [string]: boolean }

-- Dead trees: the mesh is this tall at scale 1 (studs from the trunk base).
HeroLook.TREE_HEIGHT = 40
HeroLook.TREE_VARIANTS = { "DeadTreeA", "DeadTreeB" }

return HeroLook
