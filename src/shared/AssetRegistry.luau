--!strict
-- Every uploaded or Creator Store asset (meshes, textures, decals, models), by name.
-- Id 0 means "not available yet": the shell skips it silently. Every nonzero id must be
-- listed in art/ids.json with its source, or the gate fails (tools/lint/asset_ids.py).
--
-- Hero models (M9, 11/27/2026): Blender meshes laid over the part-built versions by
-- server/HeroModels.luau. `id` is the uploaded Model asset, `meshId` the mesh inside it
-- (both logged in art/ids.json). `center` is where the mesh's bounding-box centre sits in the
-- frame the model was authored in, and `size` its bounds in studs, both from
-- art/models/manifest.json (tools/blender/*.py). With id 0 (or a load that fails) the
-- part-built version stays exactly as it was.

export type AssetEntry = {
	id: number,
	kind: string?, -- "Mesh", "Texture", "Decal", "Model"
	meshId: number?, -- hero models: the MeshPart's mesh asset
	center: { number }?, -- hero models: { x, y, z } in the authoring frame
	size: { number }?, -- hero models: { x, y, z } studs
}

local AssetRegistry = {}

AssetRegistry.entries = {
	-- The rowboat, in BoatHull's frame (hull centre at the waterline, bow along -z).
	BoatShell = {
		id = 85052587790802,
		meshId = 122134959308734,
		kind = "Model",
		center = { 0, 1.123, -1.536 },
		size = { 5.745, 2.966, 15.971 },
	},
	BoatInterior = {
		id = 107547718043490,
		meshId = 84143708456113,
		kind = "Model",
		center = { 0, 0.978, -1.711 },
		size = { 5.76, 3.435, 16.271 },
	},
	Lantern = {
		id = 86351086974813,
		meshId = 106626381604242,
		kind = "Model",
		center = { 0.048, 1.989, -8.118 },
		size = { 1.085, 3.582, 1.855 },
	},
	-- The Watcher, in the figure's root frame (feet at the origin, facing -z).
	Watcher = {
		id = 79014766812859,
		meshId = 89883759138855,
		kind = "Model",
		center = { 0, 6.14, -0.053 },
		size = { 1.693, 12.28, 0.874 },
	},
	-- The sunken steeple, in Landmarks' tower frame (the foot, +y up the leaning axis).
	Steeple = {
		id = 107228756629568,
		meshId = 104411145568116,
		kind = "Model",
		center = { 0, 28.565, 0 },
		size = { 13, 57.13, 13 },
	},
	-- The bait shack, in Dock's shack frame (floor top centre, the lake side +z).
	Shack = {
		id = 131734055152778,
		meshId = 126214794933057,
		kind = "Model",
		center = { 0, 5.668, 0.545 },
		size = { 18.22, 18.337, 15.509 },
	},
	-- Dead shoreline trees, 40 studs tall from the trunk base; scaled per tree.
	DeadTreeA = {
		id = 130969346436761,
		meshId = 111957785113100,
		kind = "Model",
		center = { 1.891, 19.552, 1.321 },
		size = { 11.638, 40.638, 7.945 },
	},
	DeadTreeB = {
		id = 88112243394590,
		meshId = 123714846350356,
		kind = "Model",
		center = { 2.454, 20.101, 0.202 },
		size = { 11.985, 41.817, 12.186 },
	},
} :: { [string]: AssetEntry }

function AssetRegistry.get(name: string): AssetEntry?
	return AssetRegistry.entries[name]
end

return AssetRegistry
